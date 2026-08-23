#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4showplayer {

// The caller owns package_data and keeps it alive until stop().
bool start(const uint8_t *package_data, size_t package_size);
void stop();
bool running();
bool failed();
uint32_t completed_cycles();
uint32_t current_frame_index();
uint32_t frame_count();
uint32_t decode_error_count();

}  // namespace p4showplayer
