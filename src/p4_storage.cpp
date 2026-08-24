#include "p4_storage.h"

#include <Arduino.h>
#include <LittleFS.h>

#include "esp_heap_caps.h"

#include "p4_gif.h"
#include "p4_show_format.h"

namespace p4storage {
namespace {

constexpr char kMediaDir[] = "/media";
constexpr char kCurrentPath[] = "/media/current.gif";
constexpr char kUploadTemp[] = "/media/.upload.tmp";
constexpr char kCurrentShowPath[] = "/media/current.zshow";
constexpr char kShowUploadTemp[] = "/media/.show-upload.tmp";
constexpr char kShowBackup[] = "/media/.show-backup.tmp";

enum class UploadType : uint8_t { kNone, kGif, kShow };

File upload_file;
size_t upload_expected = 0;
size_t upload_received = 0;
UploadType upload_type = UploadType::kNone;
const char *show_upload_error = "none";

// Show uploads stream into PSRAM when it is available: the package is
// validated in RAM (no LittleFS read-back) and persisted afterwards in one
// sequential pass. The validated buffer is then handed to the player so the
// fresh package is not read back from flash either.
uint8_t *show_upload_buffer = nullptr;
uint8_t *installed_show_data = nullptr;
size_t installed_show_size = 0;
constexpr size_t kPersistChunkBytes = 256U * 1024U;

void release_show_upload_buffer() {
  if (show_upload_buffer != nullptr) {
    heap_caps_free(show_upload_buffer);
    show_upload_buffer = nullptr;
  }
}

void release_installed_show_handoff() {
  if (installed_show_data != nullptr) {
    heap_caps_free(installed_show_data);
    installed_show_data = nullptr;
  }
  installed_show_size = 0;
}

bool persist_show_buffer(const uint8_t *data, size_t size) {
  LittleFS.remove(kShowUploadTemp);
  File out = LittleFS.open(kShowUploadTemp, FILE_WRITE);
  if (!out) return false;
  size_t written = 0;
  while (written < size) {
    const size_t chunk =
        size - written < kPersistChunkBytes ? size - written : kPersistChunkBytes;
    if (out.write(data + written, chunk) != chunk) {
      out.close();
      LittleFS.remove(kShowUploadTemp);
      return false;
    }
    written += chunk;
  }
  out.close();
  return true;
}

portMUX_TYPE request_mux = portMUX_INITIALIZER_UNLOCKED;
volatile bool request_pending = false;
volatile bool show_request_pending = false;

bool is_gif_name(String name) {
  name.toLowerCase();
  return name.endsWith(".gif");
}

bool is_show_name(String name) {
  name.toLowerCase();
  return name.endsWith(".zshow");
}

String base_name(String path) {
  const int slash = path.lastIndexOf('/');
  return slash >= 0 ? path.substring(slash + 1) : path;
}

void request_play() {
  portENTER_CRITICAL(&request_mux);
  request_pending = true;
  portEXIT_CRITICAL(&request_mux);
}

void request_show_play() {
  portENTER_CRITICAL(&request_mux);
  show_request_pending = true;
  portEXIT_CRITICAL(&request_mux);
}

uint8_t *load_file(const char *path, size_t maximum_size, size_t *size_out) {
  if (size_out != nullptr) *size_out = 0;
  File file = LittleFS.open(path, FILE_READ);
  if (!file || file.isDirectory()) return nullptr;
  const size_t size = file.size();
  if (size == 0 || size > maximum_size) {
    file.close();
    return nullptr;
  }
  uint8_t *data = static_cast<uint8_t *>(heap_caps_malloc(
      size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
  if (data == nullptr) {
    file.close();
    return nullptr;
  }
  const bool ok = file.read(data, size) == size;
  file.close();
  if (!ok) {
    heap_caps_free(data);
    return nullptr;
  }
  if (size_out != nullptr) *size_out = size;
  return data;
}

void migrate_to_single_gif() {
  String gif_to_keep;
  File dir = LittleFS.open(kMediaDir);
  if (dir && dir.isDirectory()) {
    for (File entry = dir.openNextFile(); entry; entry = dir.openNextFile()) {
      if (!entry.isDirectory()) {
        const String name = base_name(entry.name());
        if (name == kCurrentGif) {
          gif_to_keep = name;
        } else if (gif_to_keep.isEmpty() && is_gif_name(name)) {
          gif_to_keep = name;
        }
      }
      entry.close();
    }
  }
  if (dir) dir.close();

  if (!gif_to_keep.isEmpty() && gif_to_keep != kCurrentGif) {
    LittleFS.remove(kCurrentPath);
    LittleFS.rename(String(kMediaDir) + "/" + gif_to_keep, kCurrentPath);
  }

  size_t removed_bytes = 0;
  dir = LittleFS.open(kMediaDir);
  if (dir && dir.isDirectory()) {
    for (File entry = dir.openNextFile(); entry; entry = dir.openNextFile()) {
      if (!entry.isDirectory()) {
        const String name = base_name(entry.name());
        if (name != kCurrentGif && name != kCurrentShow) {
          removed_bytes += entry.size();
          const String path = String(kMediaDir) + "/" + name;
          entry.close();
          LittleFS.remove(path);
          continue;
        }
      }
      entry.close();
    }
  }
  if (dir) dir.close();
  Serial.printf("STORAGE CLEANUP: removed %u legacy bytes\n",
                static_cast<unsigned>(removed_bytes));
}

}  // namespace

bool begin() {
  if (!LittleFS.begin(true)) return false;
  if (!LittleFS.exists(kMediaDir) && !LittleFS.mkdir(kMediaDir)) return false;
  LittleFS.remove(kUploadTemp);
  LittleFS.remove(kShowUploadTemp);
  LittleFS.remove(kShowBackup);
  migrate_to_single_gif();
  Serial.printf("STORAGE READY: %u/%u bytes used\n",
                static_cast<unsigned>(LittleFS.usedBytes()),
                static_cast<unsigned>(LittleFS.totalBytes()));
  return true;
}

uint8_t *load_gif(const char *name, size_t *size_out) {
  if (size_out != nullptr) *size_out = 0;
  if (name == nullptr || strcmp(name, kCurrentGif) != 0) return nullptr;
  return load_file(kCurrentPath, p4gif::kMaxFileBytes, size_out);
}

uint8_t *load_show(size_t *size_out) {
  if (installed_show_data != nullptr) {
    uint8_t *data = installed_show_data;
    const size_t size = installed_show_size;
    installed_show_data = nullptr;
    installed_show_size = 0;
    if (size_out != nullptr) *size_out = size;
    return data;
  }
  return load_file(kCurrentShowPath, p4show::kMaxPackageBytes, size_out);
}

bool show_exists() { return LittleFS.exists(kCurrentShowPath); }

bool first_gif(char *name, size_t capacity) {
  if (name == nullptr || capacity == 0 || !LittleFS.exists(kCurrentPath)) {
    return false;
  }
  strlcpy(name, kCurrentGif, capacity);
  return true;
}

bool begin_stream_upload(const char *name, size_t expected_size) {
  abort_stream_upload();
  if (name == nullptr || !is_gif_name(name) || expected_size == 0 ||
      expected_size > p4gif::kMaxFileBytes) {
    return false;
  }

  LittleFS.remove(kUploadTemp);
  LittleFS.remove(kCurrentPath);
  const size_t free_bytes = LittleFS.totalBytes() - LittleFS.usedBytes();
  if (expected_size > free_bytes) return false;

  upload_file = LittleFS.open(kUploadTemp, FILE_WRITE);
  if (!upload_file) return false;
  upload_type = UploadType::kGif;
  upload_expected = expected_size;
  upload_received = 0;
  return true;
}

bool write_stream_upload(const uint8_t *data, size_t size) {
  if (data == nullptr || size == 0 ||
      upload_received + size > upload_expected) {
    return false;
  }
  if (upload_type == UploadType::kShow && show_upload_buffer != nullptr) {
    memcpy(show_upload_buffer + upload_received, data, size);
    upload_received += size;
    return true;
  }
  if (!upload_file) return false;
  const size_t written = upload_file.write(data, size);
  upload_received += written;
  return written == size;
}

bool finish_stream_upload() {
  if (!upload_file || upload_type != UploadType::kGif) return false;
  upload_file.close();
  const bool complete = upload_received == upload_expected;
  const bool installed = complete && LittleFS.rename(kUploadTemp, kCurrentPath);
  if (!installed) LittleFS.remove(kUploadTemp);
  if (installed) LittleFS.remove(kCurrentShowPath);
  Serial.printf("GIF UPLOAD: %u/%u bytes, %s\n",
                static_cast<unsigned>(upload_received),
                static_cast<unsigned>(upload_expected),
                installed ? "installed" : "rejected");
  upload_expected = 0;
  upload_received = 0;
  upload_type = UploadType::kNone;
  if (installed) request_play();
  return installed;
}

void abort_stream_upload() {
  if (upload_file) upload_file.close();
  release_show_upload_buffer();
  LittleFS.remove(kUploadTemp);
  LittleFS.remove(kShowUploadTemp);
  upload_expected = 0;
  upload_received = 0;
  upload_type = UploadType::kNone;
}

bool clear_media() {
  abort_stream_upload();
  release_installed_show_handoff();
  bool ok = true;
  size_t removed_bytes = 0;
  File dir = LittleFS.open(kMediaDir);
  if (!dir || !dir.isDirectory()) return false;
  for (File entry = dir.openNextFile(); entry; entry = dir.openNextFile()) {
    if (entry.isDirectory()) {
      entry.close();
      continue;
    }
    const String name = base_name(entry.name());
    const size_t size = entry.size();
    const String path = String(kMediaDir) + "/" + name;
    entry.close();
    if (LittleFS.remove(path)) {
      removed_bytes += size;
    } else {
      ok = false;
    }
  }
  dir.close();
  portENTER_CRITICAL(&request_mux);
  request_pending = false;
  show_request_pending = false;
  portEXIT_CRITICAL(&request_mux);
  show_upload_error = "none";
  Serial.printf("STORAGE CLEAR: removed %u media bytes, %s\n",
                static_cast<unsigned>(removed_bytes), ok ? "ok" : "failed");
  return ok;
}

bool begin_show_stream_upload(const char *name, size_t expected_size) {
  abort_stream_upload();
  show_upload_error = "upload-start";
  if (name == nullptr || !is_show_name(name) ||
      expected_size < p4show::kHeaderBytes ||
      expected_size > p4show::kMaxPackageBytes) {
    show_upload_error = "invalid-request";
    return false;
  }
  LittleFS.remove(kShowUploadTemp);
  const size_t free_bytes = LittleFS.totalBytes() - LittleFS.usedBytes();
  if (expected_size > free_bytes) {
    show_upload_error = "storage-full";
    return false;
  }
  show_upload_buffer = static_cast<uint8_t *>(heap_caps_malloc(
      expected_size,
      MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
  if (show_upload_buffer == nullptr) {
    // Without PSRAM headroom fall back to streaming into the temp file.
    upload_file = LittleFS.open(kShowUploadTemp, FILE_WRITE);
    if (!upload_file) {
      show_upload_error = "storage-open";
      return false;
    }
  }
  upload_type = UploadType::kShow;
  upload_expected = expected_size;
  upload_received = 0;
  return true;
}

bool finish_show_stream_upload() {
  if (upload_type != UploadType::kShow ||
      (!upload_file && show_upload_buffer == nullptr)) {
    show_upload_error = "upload-state";
    return false;
  }
  if (upload_file) upload_file.close();
  bool installed = false;
  bool handoff_ready = false;
  p4show::Error validation = p4show::Error::kPackageSize;
  uint32_t validate_ms = 0;
  uint32_t persist_ms = 0;
  if (upload_received == upload_expected) {
    uint8_t *package_data = show_upload_buffer;
    size_t package_size = upload_received;
    if (package_data == nullptr) {
      package_data =
          load_file(kShowUploadTemp, p4show::kMaxPackageBytes, &package_size);
    }
    if (package_data != nullptr) {
      const uint32_t validate_start = millis();
      validation = p4show::validate(package_data, package_size);
      validate_ms = millis() - validate_start;
    }
    if (validation == p4show::Error::kOk) {
      const uint32_t persist_start = millis();
      bool persisted = true;
      if (show_upload_buffer != nullptr) {
        persisted = persist_show_buffer(package_data, package_size);
      }
      if (persisted) {
        LittleFS.remove(kShowBackup);
        const bool had_current = LittleFS.exists(kCurrentShowPath);
        const bool backed_up =
            !had_current || LittleFS.rename(kCurrentShowPath, kShowBackup);
        installed = backed_up &&
                    LittleFS.rename(kShowUploadTemp, kCurrentShowPath);
        if (installed) {
          LittleFS.remove(kShowBackup);
        } else if (had_current && LittleFS.exists(kShowBackup)) {
          LittleFS.rename(kShowBackup, kCurrentShowPath);
        }
      }
      persist_ms = millis() - persist_start;
    }
    if (installed && package_data != nullptr) {
      // The validated PSRAM copy becomes the player's package: playback does
      // not need to read the file it just wrote.
      release_installed_show_handoff();
      installed_show_data = package_data;
      installed_show_size = package_size;
      if (package_data == show_upload_buffer) show_upload_buffer = nullptr;
      handoff_ready = true;
    }
    if (package_data != nullptr && package_data != installed_show_data &&
        package_data != show_upload_buffer) {
      heap_caps_free(package_data);
    }
  }
  release_show_upload_buffer();
  if (!installed) LittleFS.remove(kShowUploadTemp);
  show_upload_error = installed
                          ? "none"
                          : validation == p4show::Error::kOk
                                ? "install-failed"
                                : p4show::error_name(validation);
  Serial.printf(
      "SHOW UPLOAD: %u/%u bytes, validation=%s, %s, validate %u ms, "
      "persist %u ms, %s\n",
      static_cast<unsigned>(upload_received),
      static_cast<unsigned>(upload_expected), p4show::error_name(validation),
      installed ? "installed" : "rejected", static_cast<unsigned>(validate_ms),
      static_cast<unsigned>(persist_ms),
      handoff_ready ? "ram-handoff" : "file-path");
  upload_expected = 0;
  upload_received = 0;
  upload_type = UploadType::kNone;
  if (installed) request_show_play();
  return installed;
}

const char *last_show_upload_error() { return show_upload_error; }

bool take_play_request(char *name, size_t capacity) {
  if (name == nullptr || capacity == 0 || !request_pending) return false;
  portENTER_CRITICAL(&request_mux);
  const bool pending = request_pending;
  request_pending = false;
  portEXIT_CRITICAL(&request_mux);
  if (pending) strlcpy(name, kCurrentGif, capacity);
  return pending;
}

bool take_show_play_request() {
  if (!show_request_pending) return false;
  portENTER_CRITICAL(&request_mux);
  const bool pending = show_request_pending;
  show_request_pending = false;
  portEXIT_CRITICAL(&request_mux);
  return pending;
}

}  // namespace p4storage
