#include "p4_jpeg_benchmark.h"

#include <Arduino.h>
#include <LittleFS.h>

#include <algorithm>
#include <new>

#include "driver/jpeg_decode.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"

#include "p4_display.h"
#include "p4_jpeg_benchmark_assets.h"

#ifndef ZNACHOK_JPEG_BENCHMARK_FRAMES
#define ZNACHOK_JPEG_BENCHMARK_FRAMES 3600
#endif

#ifndef ZNACHOK_JPEG_BENCHMARK_MMAP
#define ZNACHOK_JPEG_BENCHMARK_MMAP 0
#endif

namespace p4jpegbenchmark {
namespace {

constexpr char kContainerPath[] = "/media/jpeg-benchmark.zjbm";
constexpr uint8_t kContainerMagic[8] = {'Z', 'J', 'B', 'M', '0', '0', '0', '1'};
constexpr uint32_t kTargetFrameUs = 1000000U / 60U;
constexpr uint32_t kHistogramBucketUs = 100;
constexpr size_t kHistogramBuckets = 2001;

struct ContainerHeader {
  uint8_t magic[sizeof(kContainerMagic)];
  uint32_t frame_count;
  uint32_t width;
  uint32_t height;
};

struct ContainerFrameHeader {
  uint32_t asset_index;
  uint32_t jpeg_size;
};

struct StoredFrame {
  uint32_t offset;
  uint32_t size;
};

struct Distribution {
  uint32_t histogram[kHistogramBuckets];
  uint64_t sum_us;
  uint32_t count;
  uint32_t maximum_us;
};

struct TimingStats {
  Distribution read;
  Distribution decode;
  Distribution present;
  Distribution total;
};

struct BenchmarkStats {
  TimingStats overall;
  TimingStats per_asset[1];
};

struct MemorySnapshot {
  size_t internal_free;
  size_t internal_largest;
  size_t psram_free;
  size_t psram_largest;
};

uint32_t elapsed_us(int64_t start_us, int64_t end_us) {
  const int64_t elapsed = end_us - start_us;
  if (elapsed <= 0) return 0;
  return elapsed > UINT32_MAX ? UINT32_MAX : static_cast<uint32_t>(elapsed);
}

void record(Distribution &distribution, uint32_t microseconds) {
  const size_t bucket = std::min<size_t>(
      microseconds / kHistogramBucketUs, kHistogramBuckets - 1);
  ++distribution.histogram[bucket];
  distribution.sum_us += microseconds;
  ++distribution.count;
  distribution.maximum_us =
      std::max(distribution.maximum_us, microseconds);
}

void record(TimingStats &stats, uint32_t read_us, uint32_t decode_us,
            uint32_t present_us, uint32_t total_us) {
  record(stats.read, read_us);
  record(stats.decode, decode_us);
  record(stats.present, present_us);
  record(stats.total, total_us);
}

uint32_t percentile(const Distribution &distribution, uint32_t numerator,
                    uint32_t denominator) {
  if (distribution.count == 0) return 0;
  const uint32_t target =
      (distribution.count * numerator + denominator - 1) / denominator;
  uint32_t accumulated = 0;
  for (size_t bucket = 0; bucket < kHistogramBuckets; ++bucket) {
    accumulated += distribution.histogram[bucket];
    if (accumulated >= target) {
      return static_cast<uint32_t>(bucket * kHistogramBucketUs);
    }
  }
  return distribution.maximum_us;
}

MemorySnapshot memory_snapshot() {
  return {
      .internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
      .internal_largest =
          heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
      .psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
      .psram_largest = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM),
  };
}

bool write_all(File &file, const void *data, size_t size) {
  return file.write(static_cast<const uint8_t *>(data), size) == size;
}

bool provision_container(StoredFrame *stored_frames, size_t capacity,
                         size_t *maximum_jpeg_size) {
  if (stored_frames == nullptr || capacity < kBenchmarkAssetCount ||
      maximum_jpeg_size == nullptr) {
    return false;
  }
  LittleFS.remove(kContainerPath);
  File file = LittleFS.open(kContainerPath, FILE_WRITE);
  if (!file) {
    Serial.println("BENCHMARK ERROR: cannot create flash payload");
    return false;
  }

  const ContainerHeader header = {
      .magic = {'Z', 'J', 'B', 'M', '0', '0', '0', '1'},
      .frame_count = static_cast<uint32_t>(kBenchmarkAssetCount),
      .width = p4display::kWidth,
      .height = p4display::kHeight,
  };
  bool ok = write_all(file, &header, sizeof(header));
  size_t largest = 0;
  for (size_t index = 0; ok && index < kBenchmarkAssetCount; ++index) {
    const BenchmarkAsset &asset = kBenchmarkAssets[index];
    const ContainerFrameHeader frame_header = {
        .asset_index = static_cast<uint32_t>(index),
        .jpeg_size = static_cast<uint32_t>(asset.size),
    };
    ok = write_all(file, &frame_header, sizeof(frame_header));
    stored_frames[index] = {
        .offset = static_cast<uint32_t>(file.position()),
        .size = static_cast<uint32_t>(asset.size),
    };
    ok = ok && write_all(file, asset.data, asset.size);
    largest = std::max(largest, asset.size);
  }
  file.flush();
  const size_t container_size = file.size();
  file.close();
  if (!ok) {
    LittleFS.remove(kContainerPath);
    Serial.println("BENCHMARK ERROR: incomplete flash payload");
    return false;
  }
  *maximum_jpeg_size = largest;
  Serial.printf("BENCHMARK PAYLOAD: %u frames, %u bytes in LittleFS\n",
                static_cast<unsigned>(kBenchmarkAssetCount),
                static_cast<unsigned>(container_size));
  for (size_t index = 0; index < kBenchmarkAssetCount; ++index) {
    Serial.printf("BENCHMARK ASSET: index=%u name=%s class=%s jpeg_bytes=%u\n",
                  static_cast<unsigned>(index), kBenchmarkAssets[index].name,
                  kBenchmarkAssets[index].content_class,
                  static_cast<unsigned>(kBenchmarkAssets[index].size));
  }
  return true;
}

bool validate_payload(File &file, const StoredFrame *stored_frames,
                      uint8_t *input_buffer, size_t input_capacity) {
  for (size_t index = 0; index < kBenchmarkAssetCount; ++index) {
    const StoredFrame &frame = stored_frames[index];
    if (frame.size > input_capacity || !file.seek(frame.offset, SeekSet) ||
        file.read(input_buffer, frame.size) != frame.size) {
      Serial.printf("BENCHMARK ERROR: cannot read asset %u\n",
                    static_cast<unsigned>(index));
      return false;
    }
    jpeg_decode_picture_info_t info = {};
    const esp_err_t result =
        jpeg_decoder_get_info(input_buffer, frame.size, &info);
    if (result != ESP_OK || info.width != p4display::kWidth ||
        info.height != p4display::kHeight) {
      Serial.printf(
          "BENCHMARK ERROR: invalid JPEG %u: result=%s dimensions=%ux%u\n",
          static_cast<unsigned>(index), esp_err_to_name(result),
          static_cast<unsigned>(info.width), static_cast<unsigned>(info.height));
      return false;
    }
  }
  return true;
}

void print_distribution(const char *scope, const char *metric,
                        const Distribution &distribution) {
  const uint32_t mean = distribution.count == 0
                            ? 0
                            : static_cast<uint32_t>(distribution.sum_us /
                                                    distribution.count);
  Serial.printf(
      "BENCHMARK METRIC: scope=%s metric=%s count=%u median_us=%u "
      "p95_us=%u max_us=%u mean_us=%u\n",
      scope, metric, static_cast<unsigned>(distribution.count),
      static_cast<unsigned>(percentile(distribution, 50, 100)),
      static_cast<unsigned>(percentile(distribution, 95, 100)),
      static_cast<unsigned>(distribution.maximum_us),
      static_cast<unsigned>(mean));
}

void print_timing_stats(const char *scope, const TimingStats &stats) {
  print_distribution(scope, "read", stats.read);
  print_distribution(scope, "decode", stats.decode);
  print_distribution(scope, "present", stats.present);
  print_distribution(scope, "total", stats.total);
}

}  // namespace

bool run() {
  Serial.println(
      "BENCHMARK START: internal flash -> HW JPEG -> RGB565 framebuffer -> vsync");
  Serial.printf(
      "BENCHMARK CONFIG: frames=%u target_fps=60 deadline_us=%u source=%s\n",
                static_cast<unsigned>(ZNACHOK_JPEG_BENCHMARK_FRAMES),
                static_cast<unsigned>(kTargetFrameUs),
                ZNACHOK_JPEG_BENCHMARK_MMAP ? "memory-mapped-flash"
                                           : "LittleFS");

  StoredFrame *stored_frames = static_cast<StoredFrame *>(heap_caps_calloc(
      kBenchmarkAssetCount, sizeof(StoredFrame), MALLOC_CAP_SPIRAM));
  const size_t stats_size = sizeof(BenchmarkStats) +
                            (kBenchmarkAssetCount - 1) * sizeof(TimingStats);
  BenchmarkStats *stats = static_cast<BenchmarkStats *>(
      heap_caps_calloc(1, stats_size, MALLOC_CAP_SPIRAM));
  if (stored_frames == nullptr || stats == nullptr) {
    Serial.println("BENCHMARK ERROR: statistics allocation failed");
    heap_caps_free(stored_frames);
    heap_caps_free(stats);
    return false;
  }

  size_t maximum_jpeg_size = 0;
  if (!provision_container(stored_frames, kBenchmarkAssetCount,
                           &maximum_jpeg_size)) {
    heap_caps_free(stored_frames);
    heap_caps_free(stats);
    return false;
  }

  const jpeg_decode_memory_alloc_cfg_t input_alloc_config = {
      .buffer_direction = JPEG_DEC_ALLOC_INPUT_BUFFER,
  };
  size_t input_capacity = 0;
  uint8_t *input_buffer = static_cast<uint8_t *>(jpeg_alloc_decoder_mem(
      maximum_jpeg_size, &input_alloc_config, &input_capacity));
  if (input_buffer == nullptr || input_capacity < maximum_jpeg_size) {
    Serial.printf("BENCHMARK ERROR: JPEG input allocation %u/%u bytes\n",
                  static_cast<unsigned>(input_capacity),
                  static_cast<unsigned>(maximum_jpeg_size));
    heap_caps_free(input_buffer);
    heap_caps_free(stored_frames);
    heap_caps_free(stats);
    return false;
  }

  File file = LittleFS.open(kContainerPath, FILE_READ);
  if (!file || !validate_payload(file, stored_frames, input_buffer,
                                 input_capacity)) {
    if (file) file.close();
    heap_caps_free(input_buffer);
    heap_caps_free(stored_frames);
    heap_caps_free(stats);
    return false;
  }

  const jpeg_decode_engine_cfg_t engine_config = {
      .intr_priority = 0,
      .timeout_ms = 100,
  };
  jpeg_decoder_handle_t decoder = nullptr;
  esp_err_t result = jpeg_new_decoder_engine(&engine_config, &decoder);
  if (result != ESP_OK) {
    Serial.printf("BENCHMARK ERROR: JPEG engine: %s\n",
                  esp_err_to_name(result));
    file.close();
    heap_caps_free(input_buffer);
    heap_caps_free(stored_frames);
    heap_caps_free(stats);
    return false;
  }
  const jpeg_decode_cfg_t decode_config = {
      .output_format = JPEG_DECODE_OUT_FORMAT_RGB565,
      .rgb_order = JPEG_DEC_RGB_ELEMENT_ORDER_BGR,
      .conv_std = JPEG_YUV_RGB_CONV_STD_BT601,
  };

  const MemorySnapshot memory_start = memory_snapshot();
  uint32_t dropped_frames = 0;
  uint32_t errors = 0;
  const int64_t run_start_us = esp_timer_get_time();
  for (uint32_t sequence = 0; sequence < ZNACHOK_JPEG_BENCHMARK_FRAMES;
       ++sequence) {
    const size_t asset_index = sequence % kBenchmarkAssetCount;
    const StoredFrame &frame = stored_frames[asset_index];
    const int64_t total_start_us = esp_timer_get_time();

    const int64_t read_start_us = total_start_us;
#if ZNACHOK_JPEG_BENCHMARK_MMAP
    memcpy(input_buffer, kBenchmarkAssets[asset_index].data, frame.size);
    const bool read_ok = true;
#else
    const bool read_ok = file.seek(frame.offset, SeekSet) &&
                         file.read(input_buffer, frame.size) == frame.size;
#endif
    const int64_t read_end_us = esp_timer_get_time();
    if (!read_ok) {
      Serial.printf("BENCHMARK ERROR: flash read failed at frame %u\n",
                    static_cast<unsigned>(sequence));
      ++errors;
      break;
    }

    uint16_t *output = p4display::back_buffer();
    uint32_t decoded_size = 0;
    const int64_t decode_start_us = esp_timer_get_time();
    result = jpeg_decoder_process(
        decoder, &decode_config, input_buffer, frame.size,
        reinterpret_cast<uint8_t *>(output), p4display::kFrameBytes,
        &decoded_size);
    const int64_t decode_end_us = esp_timer_get_time();
    if (result != ESP_OK || decoded_size != p4display::kFrameBytes) {
      Serial.printf(
          "BENCHMARK ERROR: decode frame=%u asset=%u result=%s bytes=%u\n",
          static_cast<unsigned>(sequence), static_cast<unsigned>(asset_index),
          esp_err_to_name(result), static_cast<unsigned>(decoded_size));
      ++errors;
      break;
    }

    const int64_t present_start_us = esp_timer_get_time();
    const bool present_ok = p4display::present(output);
    const int64_t present_end_us = esp_timer_get_time();
    if (!present_ok) {
      Serial.printf("BENCHMARK ERROR: present failed at frame %u\n",
                    static_cast<unsigned>(sequence));
      ++errors;
      break;
    }

    const uint32_t read_us = elapsed_us(read_start_us, read_end_us);
    const uint32_t decode_us = elapsed_us(decode_start_us, decode_end_us);
    const uint32_t present_us = elapsed_us(present_start_us, present_end_us);
    const uint32_t total_us = elapsed_us(total_start_us, present_end_us);
    record(stats->overall, read_us, decode_us, present_us, total_us);
    record(stats->per_asset[asset_index], read_us, decode_us, present_us,
           total_us);
    if (total_us > kTargetFrameUs) ++dropped_frames;

    if ((sequence + 1) % 300 == 0 ||
        sequence + 1 == ZNACHOK_JPEG_BENCHMARK_FRAMES) {
      const int64_t elapsed = esp_timer_get_time() - run_start_us;
      const float fps = elapsed > 0
                            ? (sequence + 1) * 1000000.0f / elapsed
                            : 0.0f;
      Serial.printf(
          "BENCHMARK PROGRESS: %u/%u fps=%.2f dropped=%u errors=%u\n",
          static_cast<unsigned>(sequence + 1),
          static_cast<unsigned>(ZNACHOK_JPEG_BENCHMARK_FRAMES), fps,
          static_cast<unsigned>(dropped_frames),
          static_cast<unsigned>(errors));
    }
  }
  const int64_t run_elapsed_us = esp_timer_get_time() - run_start_us;
  const MemorySnapshot memory_end = memory_snapshot();

  jpeg_del_decoder_engine(decoder);
  file.close();

  const uint32_t completed_frames = stats->overall.total.count;
  const float effective_fps = run_elapsed_us > 0
                                  ? completed_frames * 1000000.0f /
                                        run_elapsed_us
                                  : 0.0f;
  Serial.printf(
      "BENCHMARK RESULT: completed=%u requested=%u effective_fps=%.2f "
      "dropped_60fps=%u errors=%u elapsed_ms=%u\n",
      static_cast<unsigned>(completed_frames),
      static_cast<unsigned>(ZNACHOK_JPEG_BENCHMARK_FRAMES), effective_fps,
      static_cast<unsigned>(dropped_frames), static_cast<unsigned>(errors),
      static_cast<unsigned>(run_elapsed_us / 1000));
  print_timing_stats("overall", stats->overall);
  for (size_t index = 0; index < kBenchmarkAssetCount; ++index) {
    print_timing_stats(kBenchmarkAssets[index].name,
                       stats->per_asset[index]);
  }
  Serial.printf(
      "BENCHMARK MEMORY: start_internal_free=%u end_internal_free=%u "
      "minimum_internal_free=%u start_internal_largest=%u "
      "end_internal_largest=%u start_psram_free=%u end_psram_free=%u "
      "minimum_psram_free=%u start_psram_largest=%u end_psram_largest=%u\n",
      static_cast<unsigned>(memory_start.internal_free),
      static_cast<unsigned>(memory_end.internal_free),
      static_cast<unsigned>(
          heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL)),
      static_cast<unsigned>(memory_start.internal_largest),
      static_cast<unsigned>(memory_end.internal_largest),
      static_cast<unsigned>(memory_start.psram_free),
      static_cast<unsigned>(memory_end.psram_free),
      static_cast<unsigned>(
          heap_caps_get_minimum_free_size(MALLOC_CAP_SPIRAM)),
      static_cast<unsigned>(memory_start.psram_largest),
      static_cast<unsigned>(memory_end.psram_largest));
  Serial.println(errors == 0 && completed_frames == ZNACHOK_JPEG_BENCHMARK_FRAMES
                     ? "BENCHMARK PASS"
                     : "BENCHMARK FAIL");

  heap_caps_free(input_buffer);
  heap_caps_free(stored_frames);
  heap_caps_free(stats);
  return errors == 0 && completed_frames == ZNACHOK_JPEG_BENCHMARK_FRAMES;
}

}  // namespace p4jpegbenchmark
