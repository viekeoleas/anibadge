#pragma once

#include <stdint.h>

namespace p4uploadui {

void show_progress(uint8_t percent);
void show_complete();
void show_show_progress(uint8_t percent);
void show_show_complete();
void show_error();
void show_fallback();

}  // namespace p4uploadui
