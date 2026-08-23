#pragma once

namespace p4runtime {

void stop();
bool play_gif(const char *name);
bool play_show();
void play_startup_media();
void poll();
bool show_running();
bool fallback_active();

}  // namespace p4runtime
