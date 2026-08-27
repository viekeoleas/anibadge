#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4show {

constexpr uint16_t kFormatVersion = 1;
constexpr uint16_t kPlayerApiVersion = 1;
constexpr uint16_t kTargetWaveshare31523 = 1;
constexpr uint32_t kCodecBaselineJpeg = 1;
constexpr uint16_t kLoopFlag = 1;
constexpr size_t kHeaderBytes = 64;
constexpr size_t kFrameEntryBytes = 16;
constexpr size_t kMaxPackageBytes = 23U * 1024U * 1024U;
constexpr size_t kMaxJpegBytes = 212U * 1024U;
constexpr uint32_t kMaxFrames = 20000;

enum class Error : uint8_t {
  kOk = 0,
  kNullData,
  kTruncatedHeader,
  kBadMagic,
  kUnsupportedVersion,
  kUnsupportedHeader,
  kPackageSize,
  kCanvas,
  kFps,
  kPackageFlags,
  kFrameCount,
  kIndex,
  kPayload,
  kPlayerApi,
  kTargetBoard,
  kCodec,
  kReserved,
  kManifestCrc,
  kPayloadCrc,
  kFrameOffset,
  kFrameSize,
  kFrameDuration,
  kFrameFlags,
  kJpeg,
  kJpegDimensions,
};

struct FrameView {
  const uint8_t *jpeg;
  uint32_t jpeg_size;
  uint32_t duration_us;
};

struct PackageView {
  const uint8_t *data;
  size_t size;
  uint16_t width;
  uint16_t height;
  uint16_t fps;
  uint32_t frame_count;
  uint32_t payload_offset;
  uint32_t payload_size;
};

Error validate(const uint8_t *data, size_t size, PackageView *view = nullptr);
bool frame(const PackageView &package, uint32_t index, FrameView *frame_out);
const char *error_name(Error error);

}  // namespace p4show
