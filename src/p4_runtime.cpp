#include "p4_runtime.h"

#include <Arduino.h>

#include "esp_heap_caps.h"

#include "p4_gif.h"
#include "p4_show_player.h"
#include "p4_storage.h"
#include "p4_upload_ui.h"

namespace p4runtime {
namespace {

uint8_t *active_gif = nullptr;
uint8_t *active_show = nullptr;
bool fallback_visible = false;

void release_active_data() {
  if (active_gif != nullptr) {
    heap_caps_free(active_gif);
    active_gif = nullptr;
  }
  if (active_show != nullptr) {
    heap_caps_free(active_show);
    active_show = nullptr;
  }
}

void show_fallback() {
  p4uploadui::show_fallback();
  fallback_visible = true;
  Serial.println("FALLBACK: built-in safe splash");
}

}  // namespace

void stop() {
  p4gif::stop();
  p4showplayer::stop();
  release_active_data();
  fallback_visible = false;
}

bool play_gif(const char *name) {
  stop();
  size_t size = 0;
  uint8_t *data = p4storage::load_gif(name, &size);
  if (data == nullptr) {
    Serial.printf("GIF ERROR: cannot load %s\n", name);
    show_fallback();
    return false;
  }
  p4gif::Info info = {};
  if (!p4gif::start(data, size, 0, &info)) {
    heap_caps_free(data);
    show_fallback();
    return false;
  }
  active_gif = data;
  Serial.printf("PLAYING GIF: %s, %ux%u, %u bytes\n", name, info.width,
                info.height, static_cast<unsigned>(info.byte_size));
  return true;
}

bool play_show() {
  stop();
  size_t size = 0;
  uint8_t *data = p4storage::load_show(&size);
  if (data == nullptr) {
    Serial.println("SHOW REJECTED: cannot load package");
    show_fallback();
    return false;
  }
  if (!p4showplayer::start(data, size)) {
    heap_caps_free(data);
    show_fallback();
    return false;
  }
  active_show = data;
  Serial.printf("PLAYING SHOW: %u bytes\n", static_cast<unsigned>(size));
  return true;
}

void play_startup_media() {
  if (p4storage::show_exists()) {
    play_show();
    return;
  }
  char startup_gif[64] = {};
  if (p4storage::first_gif(startup_gif, sizeof(startup_gif))) {
    play_gif(startup_gif);
    return;
  }
  show_fallback();
}

void poll() {
  if (active_show != nullptr && !p4showplayer::running() &&
      p4showplayer::failed() && !fallback_visible) {
    stop();
    show_fallback();
  }
  if (active_gif != nullptr && !p4gif::running() && !fallback_visible) {
    stop();
    show_fallback();
  }
}

bool show_running() {
  return active_show != nullptr && p4showplayer::running();
}

bool fallback_active() { return fallback_visible; }

}  // namespace p4runtime
