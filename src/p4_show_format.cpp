#include "p4_show_format.h"

#include <string.h>

#include "p4_display.h"

namespace p4show {
namespace {

constexpr uint8_t kMagic[8] = {'Z', 'S', 'H', 'O', 'W', 'V', '1', 0};
constexpr size_t kManifestCrcOffset = 44;

uint16_t read_u16(const uint8_t *data) {
  return static_cast<uint16_t>(data[0]) |
         (static_cast<uint16_t>(data[1]) << 8);
}

uint32_t read_u32(const uint8_t *data) {
  return static_cast<uint32_t>(data[0]) |
         (static_cast<uint32_t>(data[1]) << 8) |
         (static_cast<uint32_t>(data[2]) << 16) |
         (static_cast<uint32_t>(data[3]) << 24);
}

uint32_t crc32_update(uint32_t state, const uint8_t *data, size_t size) {
  for (size_t index = 0; index < size; ++index) {
    state ^= data[index];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      state = (state >> 1) ^
              ((state & 1U) != 0 ? 0xEDB88320U : 0U);
    }
  }
  return state;
}

uint32_t crc32(const uint8_t *data, size_t size) {
  return crc32_update(0xFFFFFFFFU, data, size) ^ 0xFFFFFFFFU;
}

uint32_t manifest_crc32(const uint8_t *data, size_t index_end) {
  uint32_t state = crc32_update(0xFFFFFFFFU, data, kManifestCrcOffset);
  constexpr uint8_t zeros[4] = {};
  state = crc32_update(state, zeros, sizeof(zeros));
  state = crc32_update(state, data + kManifestCrcOffset + sizeof(zeros),
                       kHeaderBytes - kManifestCrcOffset - sizeof(zeros));
  state = crc32_update(state, data + kHeaderBytes, index_end - kHeaderBytes);
  return state ^ 0xFFFFFFFFU;
}

bool baseline_jpeg_dimensions(const uint8_t *jpeg, size_t size,
                              uint16_t *width, uint16_t *height) {
  if (jpeg == nullptr || size < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    return false;
  }
  size_t cursor = 2;
  while (cursor + 4 <= size) {
    if (jpeg[cursor] != 0xFF) return false;
    while (cursor < size && jpeg[cursor] == 0xFF) ++cursor;
    if (cursor >= size) return false;
    const uint8_t marker = jpeg[cursor++];
    if (marker == 0x01 || marker == 0xD8 || marker == 0xD9) continue;
    if (cursor + 2 > size) return false;
    const uint16_t segment_size =
        (static_cast<uint16_t>(jpeg[cursor]) << 8) | jpeg[cursor + 1];
    if (segment_size < 2 || cursor + segment_size > size) return false;
    if (marker == 0xC0) {
      if (segment_size < 8) return false;
      *height = (static_cast<uint16_t>(jpeg[cursor + 3]) << 8) |
                jpeg[cursor + 4];
      *width = (static_cast<uint16_t>(jpeg[cursor + 5]) << 8) |
               jpeg[cursor + 6];
      return true;
    }
    if ((marker >= 0xC1 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF)) {
      return false;
    }
    cursor += segment_size;
  }
  return false;
}

}  // namespace

Error validate(const uint8_t *data, size_t size, PackageView *view) {
  if (data == nullptr) return Error::kNullData;
  if (size < kHeaderBytes) return Error::kTruncatedHeader;
  if (memcmp(data, kMagic, sizeof(kMagic)) != 0) return Error::kBadMagic;

  const uint16_t version = read_u16(data + 8);
  const uint16_t header_size = read_u16(data + 10);
  const uint32_t package_size = read_u32(data + 12);
  const uint16_t width = read_u16(data + 16);
  const uint16_t height = read_u16(data + 18);
  const uint16_t fps = read_u16(data + 20);
  const uint16_t flags = read_u16(data + 22);
  const uint32_t frame_count = read_u32(data + 24);
  const uint32_t index_offset = read_u32(data + 28);
  const uint32_t index_size = read_u32(data + 32);
  const uint32_t payload_offset = read_u32(data + 36);
  const uint32_t payload_size = read_u32(data + 40);
  const uint32_t expected_manifest_crc = read_u32(data + 44);
  const uint32_t expected_payload_crc = read_u32(data + 48);
  const uint16_t player_api = read_u16(data + 52);
  const uint16_t target_board = read_u16(data + 54);
  const uint32_t codec = read_u32(data + 56);
  const uint32_t reserved = read_u32(data + 60);

  if (version != kFormatVersion) return Error::kUnsupportedVersion;
  if (header_size != kHeaderBytes) return Error::kUnsupportedHeader;
  if (package_size != size || size > kMaxPackageBytes) {
    return Error::kPackageSize;
  }
  if (width != p4display::kWidth || height != p4display::kHeight) {
    return Error::kCanvas;
  }
  if (fps == 0 || fps > 60) return Error::kFps;
  if (flags != kLoopFlag) return Error::kPackageFlags;
  if (frame_count == 0 || frame_count > kMaxFrames) {
    return Error::kFrameCount;
  }
  if (index_offset != kHeaderBytes ||
      index_size != frame_count * kFrameEntryBytes ||
      index_offset + index_size < index_offset ||
      index_offset + index_size > size) {
    return Error::kIndex;
  }
  if (payload_offset != index_offset + index_size ||
      payload_offset > size || payload_size != size - payload_offset) {
    return Error::kPayload;
  }
  if (player_api > kPlayerApiVersion) return Error::kPlayerApi;
  if (target_board != kTargetWaveshare31523) return Error::kTargetBoard;
  if (codec != kCodecBaselineJpeg) return Error::kCodec;
  if (reserved != 0) return Error::kReserved;
  if (manifest_crc32(data, payload_offset) != expected_manifest_crc) {
    return Error::kManifestCrc;
  }
  if (crc32(data + payload_offset, payload_size) != expected_payload_crc) {
    return Error::kPayloadCrc;
  }

  uint32_t expected_offset = 0;
  for (uint32_t index = 0; index < frame_count; ++index) {
    const uint8_t *entry = data + index_offset + index * kFrameEntryBytes;
    const uint32_t offset = read_u32(entry);
    const uint32_t jpeg_size = read_u32(entry + 4);
    const uint32_t duration_us = read_u32(entry + 8);
    const uint32_t frame_flags = read_u32(entry + 12);
    if (offset != expected_offset) return Error::kFrameOffset;
    if (jpeg_size == 0 || jpeg_size > kMaxJpegBytes ||
        offset + jpeg_size < offset || offset + jpeg_size > payload_size) {
      return Error::kFrameSize;
    }
    if (duration_us < 1000 || duration_us > 10000000) {
      return Error::kFrameDuration;
    }
    if (frame_flags != 0) return Error::kFrameFlags;
    uint16_t jpeg_width = 0;
    uint16_t jpeg_height = 0;
    if (!baseline_jpeg_dimensions(data + payload_offset + offset, jpeg_size,
                                  &jpeg_width, &jpeg_height)) {
      return Error::kJpeg;
    }
    if (jpeg_width != width || jpeg_height != height) {
      return Error::kJpegDimensions;
    }
    expected_offset += jpeg_size;
  }
  if (expected_offset != payload_size) return Error::kPayload;

  if (view != nullptr) {
    *view = {
        .data = data,
        .size = size,
        .width = width,
        .height = height,
        .fps = fps,
        .frame_count = frame_count,
        .payload_offset = payload_offset,
        .payload_size = payload_size,
    };
  }
  return Error::kOk;
}

bool frame(const PackageView &package, uint32_t index, FrameView *frame_out) {
  if (package.data == nullptr || frame_out == nullptr ||
      index >= package.frame_count) {
    return false;
  }
  const uint8_t *entry =
      package.data + kHeaderBytes + index * kFrameEntryBytes;
  const uint32_t offset = read_u32(entry);
  *frame_out = {
      .jpeg = package.data + package.payload_offset + offset,
      .jpeg_size = read_u32(entry + 4),
      .duration_us = read_u32(entry + 8),
  };
  return true;
}

const char *error_name(Error error) {
  switch (error) {
    case Error::kOk: return "ok";
    case Error::kNullData: return "null-data";
    case Error::kTruncatedHeader: return "truncated-header";
    case Error::kBadMagic: return "bad-magic";
    case Error::kUnsupportedVersion: return "unsupported-version";
    case Error::kUnsupportedHeader: return "unsupported-header";
    case Error::kPackageSize: return "package-size";
    case Error::kCanvas: return "canvas";
    case Error::kFps: return "fps";
    case Error::kPackageFlags: return "package-flags";
    case Error::kFrameCount: return "frame-count";
    case Error::kIndex: return "index";
    case Error::kPayload: return "payload";
    case Error::kPlayerApi: return "player-api";
    case Error::kTargetBoard: return "target-board";
    case Error::kCodec: return "codec";
    case Error::kReserved: return "reserved";
    case Error::kManifestCrc: return "manifest-crc";
    case Error::kPayloadCrc: return "payload-crc";
    case Error::kFrameOffset: return "frame-offset";
    case Error::kFrameSize: return "frame-size";
    case Error::kFrameDuration: return "frame-duration";
    case Error::kFrameFlags: return "frame-flags";
    case Error::kJpeg: return "jpeg";
    case Error::kJpegDimensions: return "jpeg-dimensions";
  }
  return "unknown";
}

}  // namespace p4show
