#pragma once

#include <stddef.h>
#include <stdint.h>

namespace p4storage {

constexpr char kCurrentGif[] = "current.gif";
constexpr char kCurrentShow[] = "current.zshow";

bool begin();
uint8_t *load_gif(const char *name, size_t *size_out);
bool first_gif(char *name, size_t capacity);
uint8_t *load_show(size_t *size_out);
bool show_exists();
bool clear_media();

bool begin_stream_upload(const char *name, size_t expected_size);
bool write_stream_upload(const uint8_t *data, size_t size);
bool finish_stream_upload();
void abort_stream_upload();

bool begin_show_stream_upload(const char *name, size_t expected_size);
bool finish_show_stream_upload();
const char *last_show_upload_error();

bool take_play_request(char *name, size_t capacity);
bool take_show_play_request();

}  // namespace p4storage
