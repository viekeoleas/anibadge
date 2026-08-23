#include "p4_show_player.h"

#include <Arduino.h>

#include "driver/jpeg_decode.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "p4_display.h"
#include "p4_show_format.h"

namespace p4showplayer {
namespace {

p4show::PackageView package = {};
jpeg_decoder_handle_t decoder = nullptr;
uint8_t *input_buffer = nullptr;
size_t input_capacity = 0;
volatile bool task_running = false;
volatile bool task_stop = false;
volatile bool task_failed = false;
volatile uint32_t cycles_done = 0;
volatile uint32_t current_frame = 0;
volatile uint32_t playback_frame_count = 0;
volatile uint32_t decode_errors = 0;
TaskHandle_t task_handle = nullptr;

void playback_task(void *) {
  const jpeg_decode_cfg_t decode_config = {
      .output_format = JPEG_DECODE_OUT_FORMAT_RGB565,
      .rgb_order = JPEG_DEC_RGB_ELEMENT_ORDER_BGR,
      .conv_std = JPEG_YUV_RGB_CONV_STD_BT601,
  };
  uint32_t frame_index = 0;
  uint32_t stats_frames = 0;
  uint32_t timing_resyncs = 0;
  uint64_t stats_copy_us = 0;
  uint64_t stats_decode_us = 0;
  uint64_t stats_present_us = 0;
  int64_t stats_started_us = esp_timer_get_time();
  int64_t next_deadline_us = stats_started_us;
  cycles_done = 0;
  current_frame = 0;
  decode_errors = 0;

  while (!task_stop) {
    current_frame = frame_index;
    p4show::FrameView frame = {};
    if (!p4show::frame(package, frame_index, &frame)) {
      Serial.println("SHOW ERROR: frame index rejected");
      task_failed = true;
      break;
    }

    const int64_t frame_started_us = esp_timer_get_time();
    memcpy(input_buffer, frame.jpeg, frame.jpeg_size);
    const int64_t copied_us = esp_timer_get_time();

    uint16_t *output = p4display::back_buffer();
    uint32_t decoded_size = 0;
    const esp_err_t decode_result = jpeg_decoder_process(
        decoder, &decode_config, input_buffer, frame.jpeg_size,
        reinterpret_cast<uint8_t *>(output), p4display::kFrameBytes,
        &decoded_size);
    const int64_t decoded_us = esp_timer_get_time();
    const bool decoded =
        decode_result == ESP_OK && decoded_size == p4display::kFrameBytes;
    if (!decoded) {
      decode_errors = decode_errors + 1;
      Serial.printf("SHOW ERROR: JPEG frame=%u result=%s bytes=%u\n",
                    static_cast<unsigned>(frame_index),
                    esp_err_to_name(decode_result),
                    static_cast<unsigned>(decoded_size));
    } else if (!p4display::present(output, 100)) {
      Serial.printf("SHOW ERROR: present frame=%u\n",
                    static_cast<unsigned>(frame_index));
      task_failed = true;
      break;
    }
    const int64_t presented_us = esp_timer_get_time();

    ++stats_frames;
    stats_copy_us += copied_us - frame_started_us;
    stats_decode_us += decoded_us - copied_us;
    if (decoded) stats_present_us += presented_us - decoded_us;
    next_deadline_us += frame.duration_us;
    // The panel refresh and package timeline use different clocks. Preserve
    // their normal phase drift so early refreshes compensate later refreshes
    // and the long-term rate remains the package rate. Rebase only after a
    // genuine external stall.
    if (presented_us - next_deadline_us > 1000000) {
      ++timing_resyncs;
      next_deadline_us = presented_us;
    }

    ++frame_index;
    if (frame_index == package.frame_count) {
      frame_index = 0;
      cycles_done = cycles_done + 1;
    }

    const int64_t now_us = esp_timer_get_time();
    if (now_us - stats_started_us >= 2000000) {
      const float seconds = (now_us - stats_started_us) / 1000000.0f;
      Serial.printf(
          "SHOW FPS: %.2f, work %.2f ms (copy %.2f + decode %.2f + "
          "present %.2f), timing_resyncs=%u cycles=%u free_psram=%u\n",
          stats_frames / seconds,
          (stats_copy_us + stats_decode_us + stats_present_us) /
              (stats_frames * 1000.0f),
          stats_copy_us / (stats_frames * 1000.0f),
          stats_decode_us / (stats_frames * 1000.0f),
          stats_present_us / (stats_frames * 1000.0f),
          static_cast<unsigned>(timing_resyncs),
          static_cast<unsigned>(cycles_done), ESP.getFreePsram());
      stats_frames = 0;
      timing_resyncs = 0;
      stats_copy_us = 0;
      stats_decode_us = 0;
      stats_present_us = 0;
      stats_started_us = now_us;
    }

    const int64_t wait_us = next_deadline_us - esp_timer_get_time();
    if (wait_us > 2000) {
      vTaskDelay(pdMS_TO_TICKS(static_cast<uint32_t>(wait_us / 1000)));
    } else if (wait_us > 0) {
      taskYIELD();
    } else if (wait_us < -1000000) {
      // Do not carry a stale deadline forever after an external stall.
      next_deadline_us = esp_timer_get_time();
    }
  }

  task_running = false;
  task_handle = nullptr;
  vTaskDelete(nullptr);
}

void release_resources() {
  if (decoder != nullptr) {
    jpeg_del_decoder_engine(decoder);
    decoder = nullptr;
  }
  if (input_buffer != nullptr) {
    heap_caps_free(input_buffer);
    input_buffer = nullptr;
  }
  input_capacity = 0;
  package = {};
}

}  // namespace

bool start(const uint8_t *package_data, size_t package_size) {
  stop();
  p4show::PackageView validated = {};
  const p4show::Error validation =
      p4show::validate(package_data, package_size, &validated);
  if (validation != p4show::Error::kOk) {
    Serial.printf("SHOW REJECTED: %s\n", p4show::error_name(validation));
    task_failed = true;
    return false;
  }

  size_t largest_frame = 0;
  for (uint32_t index = 0; index < validated.frame_count; ++index) {
    p4show::FrameView frame = {};
    if (!p4show::frame(validated, index, &frame)) return false;
    largest_frame = max(largest_frame, static_cast<size_t>(frame.jpeg_size));
  }
  const jpeg_decode_memory_alloc_cfg_t input_config = {
      .buffer_direction = JPEG_DEC_ALLOC_INPUT_BUFFER,
  };
  input_buffer = static_cast<uint8_t *>(jpeg_alloc_decoder_mem(
      largest_frame, &input_config, &input_capacity));
  if (input_buffer == nullptr || input_capacity < largest_frame) {
    Serial.println("SHOW ERROR: input buffer allocation failed");
    release_resources();
    task_failed = true;
    return false;
  }
  const jpeg_decode_engine_cfg_t engine_config = {
      .intr_priority = 0,
      // Transition frames can be substantially larger and more complex than
      // source GIF frames. A short timeout used to terminate the whole show at
      // the first expensive transition frame.
      .timeout_ms = 500,
  };
  const esp_err_t engine_result =
      jpeg_new_decoder_engine(&engine_config, &decoder);
  if (engine_result != ESP_OK) {
    Serial.printf("SHOW ERROR: JPEG engine: %s\n",
                  esp_err_to_name(engine_result));
    release_resources();
    task_failed = true;
    return false;
  }

  package = validated;
  playback_frame_count = validated.frame_count;
  task_stop = false;
  task_failed = false;
  task_running = true;
  cycles_done = 0;
  current_frame = 0;
  decode_errors = 0;
  const BaseType_t created = xTaskCreatePinnedToCore(
      playback_task, "show-player", 8192, nullptr, 4, &task_handle, 1);
  if (created != pdPASS) {
    Serial.println("SHOW ERROR: playback task creation failed");
    task_running = false;
    release_resources();
    task_failed = true;
    return false;
  }
  Serial.printf("SHOW START: v%u %ux%u, %u frames at %u FPS, %u bytes\n",
                p4show::kFormatVersion, validated.width, validated.height,
                static_cast<unsigned>(validated.frame_count), validated.fps,
                static_cast<unsigned>(package_size));
  return true;
}

void stop() {
  if (task_running) {
    task_stop = true;
    while (task_running) delay(2);
  }
  task_stop = false;
  release_resources();
}

bool running() { return task_running; }

bool failed() { return task_failed; }

uint32_t completed_cycles() { return cycles_done; }

uint32_t current_frame_index() { return current_frame; }

uint32_t frame_count() { return playback_frame_count; }

uint32_t decode_error_count() { return decode_errors; }

}  // namespace p4showplayer
