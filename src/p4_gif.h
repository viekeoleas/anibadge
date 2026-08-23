#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4gif {

constexpr size_t kMaxFileBytes = 16U * 1024U * 1024U;

struct Info {
  uint16_t width;
  uint16_t height;
  size_t byte_size;
};

// The caller keeps ownership of data and must keep it alive until stop().
bool start(const uint8_t *data, size_t size, uint16_t loops = 0,
           Info *info = nullptr);
void stop();
bool running();
uint32_t completed_cycles();

}  // namespace p4gif
