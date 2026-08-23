#include "p4_gif.h"

#include <AnimatedGIF.h>
#include <Arduino.h>

#include <limits.h>

#include "driver/ppa.h"
#include "esp_cache.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "p4_display.h"

namespace p4gif {
namespace {

AnimatedGIF decoder;
const uint8_t *gif_data = nullptr;
size_t gif_size = 0;
uint8_t *decoder_frame_buffer = nullptr;
size_t decoder_frame_buffer_size = 0;
ppa_client_handle_t ppa_client = nullptr;
int canvas_width = 0;
int canvas_height = 0;
int offset_x = 0;
int offset_y = 0;
uint16_t requested_loops = 0;
bool decoder_open = false;
volatile bool task_running = false;
volatile bool task_stop = false;
volatile uint32_t cycles_done = 0;
TaskHandle_t task_handle = nullptr;

bool has_gif_signature(const uint8_t *data, size_t size) {
  return data != nullptr && size >= 6 &&
         (memcmp(data, "GIF87a", 6) == 0 || memcmp(data, "GIF89a", 6) == 0);
}

bool copy_composited_frame(uint16_t *destination) {
  if (decoder_frame_buffer == nullptr || destination == nullptr ||
      ppa_client == nullptr) {
    return false;
  }

  // COOKED mode without a draw callback stores an indexed compositing canvas
  // first and a complete RGB565 canvas immediately after it. Using the full
  // cooked canvas avoids stale pixels from the reusable one-line callback
  // buffer when a GIF contains transparent pixels.
  const size_t canvas_pixels =
      static_cast<size_t>(canvas_width) * canvas_height;
  const uint16_t *decoded = reinterpret_cast<const uint16_t *>(
      decoder_frame_buffer + canvas_pixels);

  const int source_x = offset_x < 0 ? -offset_x : 0;
  const int source_y = offset_y < 0 ? -offset_y : 0;
  const int destination_x = offset_x > 0 ? offset_x : 0;
  const int destination_y = offset_y > 0 ? offset_y : 0;
  const int copy_width =
      min(canvas_width - source_x, p4display::kWidth - destination_x);
  const int copy_height =
      min(canvas_height - source_y, p4display::kHeight - destination_y);
  if (copy_width <= 0 || copy_height <= 0) return false;

  // The PPA owns a DMA2D path on ESP32-P4. It crops directly from the full
  // decoded canvas into the display's back buffer, avoiding two ~1.2 MB CPU
  // copies through PSRAM for every frame.
  if (esp_cache_msync(const_cast<uint16_t *>(decoded), canvas_pixels * 2,
                      ESP_CACHE_MSYNC_FLAG_DIR_C2M) != ESP_OK) {
    return false;
  }
  const ppa_srm_oper_config_t operation = {
      .in =
          {
              .buffer = decoded,
              .pic_w = static_cast<uint32_t>(canvas_width),
              .pic_h = static_cast<uint32_t>(canvas_height),
              .block_w = static_cast<uint32_t>(copy_width),
              .block_h = static_cast<uint32_t>(copy_height),
              .block_offset_x = static_cast<uint32_t>(source_x),
              .block_offset_y = static_cast<uint32_t>(source_y),
              .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
          },
      .out =
          {
              .buffer = destination,
              .buffer_size = p4display::kFrameBytes,
              .pic_w = p4display::kWidth,
              .pic_h = p4display::kHeight,
              .block_offset_x = static_cast<uint32_t>(destination_x),
              .block_offset_y = static_cast<uint32_t>(destination_y),
              .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
          },
      .rotation_angle = PPA_SRM_ROTATION_ANGLE_0,
      .scale_x = 1.0f,
      .scale_y = 1.0f,
      .mirror_x = false,
      .mirror_y = false,
      .rgb_swap = false,
      .byte_swap = false,
      .alpha_update_mode = PPA_ALPHA_NO_CHANGE,
      .mode = PPA_TRANS_MODE_BLOCKING,
  };
  return ppa_do_scale_rotate_mirror(ppa_client, &operation) == ESP_OK;
}

void playback_task(void *) {
  uint32_t stats_frames = 0;
  uint64_t stats_source_delay_ms = 0;
  uint64_t stats_decode_us = 0;
  uint64_t stats_copy_us = 0;
  uint64_t stats_present_us = 0;
  uint32_t stats_min_delay_ms = UINT32_MAX;
  uint32_t stats_max_delay_ms = 0;
  uint32_t stats_max_work_us = 0;
  int64_t stats_started_us = esp_timer_get_time();
  cycles_done = 0;

  while (!task_stop) {
    const int64_t frame_started_us = esp_timer_get_time();
    int delay_ms = 100;
    const int result = decoder.playFrame(false, &delay_ms, nullptr);
    if (result < 0) {
      Serial.printf("GIF ERROR: decode failed, code=%d\n", decoder.getLastError());
      break;
    }
    const int64_t decoded_us = esp_timer_get_time();
    uint16_t *back_buffer = p4display::back_buffer();
    if (!copy_composited_frame(back_buffer)) {
      Serial.println("GIF ERROR: PPA frame copy failed");
      break;
    }
    const int64_t copied_us = esp_timer_get_time();
    if (!p4display::present(back_buffer)) {
      Serial.println("GIF ERROR: display present failed");
      break;
    }
    const int64_t presented_us = esp_timer_get_time();
    ++stats_frames;
    const uint32_t source_delay_ms = delay_ms > 0 ? delay_ms : 0;
    stats_source_delay_ms += source_delay_ms;
    stats_min_delay_ms = min(stats_min_delay_ms, source_delay_ms);
    stats_max_delay_ms = max(stats_max_delay_ms, source_delay_ms);
    stats_decode_us += decoded_us - frame_started_us;
    stats_copy_us += copied_us - decoded_us;
    stats_present_us += presented_us - copied_us;
    stats_max_work_us = max(
        stats_max_work_us,
        static_cast<uint32_t>(presented_us - frame_started_us));

    if (result == 0) {
      cycles_done = cycles_done + 1;
      if (requested_loops != 0 && cycles_done >= requested_loops) break;
      decoder.reset();
      memset(decoder_frame_buffer, 0, decoder_frame_buffer_size);
    }

    const int64_t now_us = esp_timer_get_time();
    if (now_us - stats_started_us >= 2000000) {
      const float seconds = (now_us - stats_started_us) / 1000000.0f;
      const float source_fps = stats_source_delay_ms == 0
                                   ? 0.0f
                                   : stats_frames * 1000.0f /
                                         stats_source_delay_ms;
      Serial.printf(
          "GIF FPS: %.1f actual / %.1f source, delay %u..%u ms, "
          "work avg %.1f ms (decode %.1f + copy %.1f + present %.1f), "
          "max %.1f ms, cycle %u, free PSRAM %u\n",
          stats_frames / seconds, source_fps,
          static_cast<unsigned>(stats_min_delay_ms),
          static_cast<unsigned>(stats_max_delay_ms),
          (stats_decode_us + stats_copy_us + stats_present_us) /
              (stats_frames * 1000.0f),
          stats_decode_us / (stats_frames * 1000.0f),
          stats_copy_us / (stats_frames * 1000.0f),
          stats_present_us / (stats_frames * 1000.0f),
          stats_max_work_us / 1000.0f, static_cast<unsigned>(cycles_done),
          ESP.getFreePsram());
      stats_frames = 0;
      stats_source_delay_ms = 0;
      stats_decode_us = 0;
      stats_copy_us = 0;
      stats_present_us = 0;
      stats_min_delay_ms = UINT32_MAX;
      stats_max_delay_ms = 0;
      stats_max_work_us = 0;
      stats_started_us = now_us;
    }

    // GIF delays have 10 ms granularity. A 60 FPS source typically alternates
    // 10 and 20 ms frame delays, so a 20 ms floor would cap it at 50 FPS.
    if (delay_ms < 1) delay_ms = 1;
    const int64_t elapsed_us = esp_timer_get_time() - frame_started_us;
    const int64_t wait_us = static_cast<int64_t>(delay_ms) * 1000 - elapsed_us;
    if (wait_us > 2000) {
      vTaskDelay(pdMS_TO_TICKS(static_cast<uint32_t>(wait_us / 1000)));
    } else {
      taskYIELD();
    }
  }

  task_running = false;
  task_handle = nullptr;
  vTaskDelete(nullptr);
}

void release_decoder() {
  if (decoder_open) {
    decoder.close();
    decoder_open = false;
  }
  if (decoder_frame_buffer != nullptr) {
    heap_caps_free(decoder_frame_buffer);
    decoder_frame_buffer = nullptr;
  }
  if (ppa_client != nullptr) {
    ppa_unregister_client(ppa_client);
    ppa_client = nullptr;
  }
  decoder_frame_buffer_size = 0;
  gif_data = nullptr;
  gif_size = 0;
  canvas_width = 0;
  canvas_height = 0;
  offset_x = 0;
  offset_y = 0;
  requested_loops = 0;
}

}  // namespace

bool start(const uint8_t *data, size_t size, uint16_t loops, Info *info) {
  stop();
  if (!has_gif_signature(data, size) || size > kMaxFileBytes ||
      size > static_cast<size_t>(INT_MAX)) {
    Serial.printf("GIF ERROR: invalid file or unsupported size (%u bytes)\n",
                  static_cast<unsigned>(size));
    return false;
  }

  gif_data = data;
  gif_size = size;
  if (size >= 10) {
    const uint16_t header_width = static_cast<uint16_t>(data[6]) |
                                  (static_cast<uint16_t>(data[7]) << 8);
    const uint16_t header_height = static_cast<uint16_t>(data[8]) |
                                   (static_cast<uint16_t>(data[9]) << 8);
    Serial.printf("GIF INPUT: %ux%u, %u bytes\n", header_width,
                  header_height, static_cast<unsigned>(size));
  }
  decoder.begin(GIF_PALETTE_RGB565_LE);
  if (!decoder.open(const_cast<uint8_t *>(data), static_cast<int>(size),
                    nullptr)) {
    Serial.printf("GIF ERROR: open failed, code=%d\n", decoder.getLastError());
    release_decoder();
    return false;
  }
  decoder_open = true;
  canvas_width = decoder.getCanvasWidth();
  canvas_height = decoder.getCanvasHeight();
  if (canvas_width <= 0 || canvas_height <= 0 || canvas_width > 4096 ||
      canvas_height > 4096) {
    Serial.printf("GIF ERROR: invalid canvas %dx%d\n", canvas_width,
                  canvas_height);
    release_decoder();
    return false;
  }

  const size_t canvas_pixels =
      static_cast<size_t>(canvas_width) * canvas_height;
  decoder_frame_buffer_size = canvas_pixels * 3;
  decoder_frame_buffer = static_cast<uint8_t *>(heap_caps_malloc(
      decoder_frame_buffer_size,
      MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
  if (decoder_frame_buffer == nullptr) {
    Serial.printf("GIF ERROR: PSRAM allocation failed (%u bytes)\n",
                  static_cast<unsigned>(decoder_frame_buffer_size));
    release_decoder();
    return false;
  }
  memset(decoder_frame_buffer, 0, decoder_frame_buffer_size);
  const ppa_client_config_t ppa_config = {
      .oper_type = PPA_OPERATION_SRM,
      .max_pending_trans_num = 1,
      .data_burst_length = PPA_DATA_BURST_LENGTH_128,
  };
  if (ppa_register_client(&ppa_config, &ppa_client) != ESP_OK) {
    Serial.println("GIF ERROR: PPA client allocation failed");
    release_decoder();
    return false;
  }
  for (uint8_t index = 0; index < 2; ++index) {
    uint16_t *display_buffer = p4display::framebuffer(index);
    memset(display_buffer, 0, p4display::kFrameBytes);
    esp_cache_msync(display_buffer, p4display::kFrameBytes,
                    ESP_CACHE_MSYNC_FLAG_DIR_C2M);
  }
  decoder.setFrameBuf(decoder_frame_buffer);
  decoder.setDrawType(GIF_DRAW_COOKED);
  offset_x = (p4display::kWidth - canvas_width) / 2;
  offset_y = (p4display::kHeight - canvas_height) / 2;
  requested_loops = loops;
  cycles_done = 0;
  task_stop = false;
  task_running = true;
  const BaseType_t created = xTaskCreatePinnedToCore(
      playback_task, "gif-player", 12288, nullptr, 3, &task_handle, 1);
  if (created != pdPASS) {
    Serial.println("GIF ERROR: playback task creation failed");
    task_running = false;
    release_decoder();
    return false;
  }

  if (info != nullptr) {
    info->width = static_cast<uint16_t>(canvas_width);
    info->height = static_cast<uint16_t>(canvas_height);
    info->byte_size = size;
  }
  Serial.printf(
      "GIF START: %dx%d, %u bytes, decoder %u bytes, offset %d,%d, loops=%u\n",
      canvas_width, canvas_height, static_cast<unsigned>(gif_size),
      static_cast<unsigned>(decoder_frame_buffer_size), offset_x, offset_y,
      loops);
  return true;
}

void stop() {
  if (task_running) {
    task_stop = true;
    while (task_running) delay(2);
  }
  task_stop = false;
  release_decoder();
}

bool running() { return task_running; }

uint32_t completed_cycles() { return cycles_done; }

}  // namespace p4gif
