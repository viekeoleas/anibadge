#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4display {

constexpr int kWidth = 800;
constexpr int kHeight = 800;
constexpr size_t kPixelCount = static_cast<size_t>(kWidth) * kHeight;
constexpr size_t kFrameBytes = kPixelCount * sizeof(uint16_t);

bool begin();
bool present(const uint16_t *pixels, uint32_t timeout_ms = 100);
void set_brightness(uint8_t percent);
uint16_t *framebuffer(uint8_t index);
uint16_t *back_buffer();
uint16_t *front_buffer();

}  // namespace p4display
