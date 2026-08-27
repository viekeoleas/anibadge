#include "p4_storage.h"

#include <Arduino.h>
#include <LittleFS.h>

#include "esp_heap_caps.h"
#include "esp_partition.h"

#include "p4_gif.h"
#include "p4_show_format.h"

namespace p4storage {
namespace {

constexpr char kMediaDir[] = "/media";
constexpr char kCurrentPath[] = "/media/current.gif";
constexpr char kUploadTemp[] = "/media/.upload.tmp";
constexpr char kRawShowPartitionLabel[] = "show";
constexpr size_t kRawShowDataOffset = 4096U;
constexpr size_t kRawEraseChunkBytes = 64U * 1024U;
constexpr size_t kRawWriteChunkBytes = 256U * 1024U;
constexpr uint8_t kRawShowMagic[8] = {'Z', 'S', 'R', 'A', 'W', 'V', '1', 0};

struct RawShowHeader {
  uint8_t magic[8];
  uint32_t size;
  uint32_t reserved;
};

static_assert(sizeof(RawShowHeader) == 16, "Unexpected raw show header size");

enum class UploadType : uint8_t { kNone, kGif, kShow };

File upload_file;
size_t upload_expected = 0;
size_t upload_received = 0;
UploadType upload_type = UploadType::kNone;
const char *show_upload_error = "none";
uint8_t *show_upload_buffer = nullptr;
uint8_t *installed_show_data = nullptr;
size_t installed_show_size = 0;
const esp_partition_t *show_partition = nullptr;

portMUX_TYPE request_mux = portMUX_INITIALIZER_UNLOCKED;
volatile bool request_pending = false;
volatile bool show_request_pending = false;

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

size_t align_up(size_t value, size_t alignment) {
  return ((value + alignment - 1U) / alignment) * alignment;
}

size_t raw_show_size() {
  if (show_partition == nullptr) return 0;
  RawShowHeader header = {};
  if (esp_partition_read(show_partition, 0, &header, sizeof(header)) != ESP_OK ||
      memcmp(header.magic, kRawShowMagic, sizeof(kRawShowMagic)) != 0 ||
      header.reserved != 0 || header.size < p4show::kHeaderBytes ||
      header.size > p4show::kMaxPackageBytes ||
      kRawShowDataOffset + header.size > show_partition->size) {
    return 0;
  }
  return header.size;
}

bool invalidate_raw_show() {
  return show_partition != nullptr &&
         esp_partition_erase_range(show_partition, 0,
                                   show_partition->erase_size) == ESP_OK;
}

bool erase_raw_show_for_upload(size_t package_size) {
  if (show_partition == nullptr ||
      kRawShowDataOffset + package_size > show_partition->size) {
    return false;
  }
  const size_t erase_bytes = align_up(package_size, show_partition->erase_size);
  size_t erased = 0;
  while (erased < erase_bytes) {
    const size_t remaining = erase_bytes - erased;
    const size_t chunk = remaining < kRawEraseChunkBytes
                             ? remaining
                             : kRawEraseChunkBytes;
    if (esp_partition_erase_range(show_partition,
                                  kRawShowDataOffset + erased,
                                  chunk) != ESP_OK) {
      return false;
    }
    erased += chunk;
    // Let the idle task feed the watchdog during a multi-megabyte erase.
    delay(1);
  }
  return true;
}

bool write_raw_show(const uint8_t *data, size_t size) {
  if (show_partition == nullptr || data == nullptr ||
      kRawShowDataOffset + size > show_partition->size) {
    return false;
  }
  size_t written = 0;
  while (written < size) {
    const size_t remaining = size - written;
    const size_t chunk = remaining < kRawWriteChunkBytes
                             ? remaining
                             : kRawWriteChunkBytes;
    if (esp_partition_write(show_partition,
                            kRawShowDataOffset + written,
                            data + written, chunk) != ESP_OK) {
      return false;
    }
    written += chunk;
    delay(1);
  }
  return true;
}

uint8_t *read_raw_show(size_t size) {
  if (show_partition == nullptr || size < p4show::kHeaderBytes ||
      size > p4show::kMaxPackageBytes ||
      kRawShowDataOffset + size > show_partition->size) {
    return nullptr;
  }
  uint8_t *data = static_cast<uint8_t *>(heap_caps_malloc(
      size, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
  if (data == nullptr) return nullptr;
  if (esp_partition_read(show_partition, kRawShowDataOffset, data, size) !=
      ESP_OK) {
    heap_caps_free(data);
    return nullptr;
  }
  return data;
}

bool commit_raw_show(size_t size) {
  if (show_partition == nullptr) return false;
  RawShowHeader header = {};
  memcpy(header.magic, kRawShowMagic, sizeof(kRawShowMagic));
  header.size = static_cast<uint32_t>(size);
  return esp_partition_write(show_partition, 0, &header, sizeof(header)) ==
         ESP_OK;
}

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
        if (name != kCurrentGif) {
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
  show_partition = esp_partition_find_first(
      ESP_PARTITION_TYPE_DATA, static_cast<esp_partition_subtype_t>(0x40),
      kRawShowPartitionLabel);
  if (show_partition == nullptr ||
      show_partition->size < kRawShowDataOffset + p4show::kMaxPackageBytes) {
    Serial.println("STORAGE ERROR: raw show partition unavailable");
    return false;
  }
  if (!LittleFS.begin(true)) return false;
  if (!LittleFS.exists(kMediaDir) && !LittleFS.mkdir(kMediaDir)) return false;
  LittleFS.remove(kUploadTemp);
  migrate_to_single_gif();
  Serial.printf("STORAGE READY: %u/%u LittleFS bytes, raw show %u bytes\n",
                static_cast<unsigned>(LittleFS.usedBytes()),
                static_cast<unsigned>(LittleFS.totalBytes()),
                static_cast<unsigned>(show_partition->size));
  return true;
}

uint8_t *load_gif(const char *name, size_t *size_out) {
  if (size_out != nullptr) *size_out = 0;
  if (name == nullptr || strcmp(name, kCurrentGif) != 0) return nullptr;
  return load_file(kCurrentPath, p4gif::kMaxFileBytes, size_out);
}

uint8_t *load_show(size_t *size_out) {
  if (size_out != nullptr) *size_out = 0;
  if (installed_show_data != nullptr) {
    uint8_t *data = installed_show_data;
    const size_t size = installed_show_size;
    installed_show_data = nullptr;
    installed_show_size = 0;
    if (size_out != nullptr) *size_out = size;
    return data;
  }
  const size_t size = raw_show_size();
  if (size == 0) return nullptr;
  uint8_t *data = read_raw_show(size);
  if (data != nullptr && size_out != nullptr) *size_out = size;
  return data;
}

bool show_exists() { return raw_show_size() != 0; }

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
  invalidate_raw_show();
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
  if (upload_type == UploadType::kShow) {
    if (show_upload_buffer == nullptr) {
      return false;
    }
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
  bool installed = complete && LittleFS.rename(kUploadTemp, kCurrentPath);
  if (installed && !invalidate_raw_show()) installed = false;
  if (!installed) LittleFS.remove(kUploadTemp);
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
  upload_expected = 0;
  upload_received = 0;
  upload_type = UploadType::kNone;
}

bool clear_media() {
  abort_stream_upload();
  release_installed_show_handoff();
  bool ok = invalidate_raw_show();
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
      expected_size > p4show::kMaxPackageBytes ||
      show_partition == nullptr ||
      kRawShowDataOffset + expected_size > show_partition->size) {
    show_upload_error = "invalid-request";
    return false;
  }
  release_installed_show_handoff();
  LittleFS.remove(kCurrentPath);
  const size_t free_psram_before = ESP.getFreePsram();
  show_upload_buffer = static_cast<uint8_t *>(heap_caps_malloc(
      expected_size,
      MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
  if (show_upload_buffer == nullptr) {
    show_upload_error = "storage-memory";
    return false;
  }
  // Remove the old commit marker before accepting the new package. The data
  // sectors are erased only after the fast PSRAM receive and validation pass,
  // so flash operations cannot throttle the HTTP request body.
  if (!invalidate_raw_show()) {
    release_show_upload_buffer();
    show_upload_error = "storage-erase";
    return false;
  }
  Serial.printf("SHOW UPLOAD: PSRAM buffer %u bytes, free %u -> %u\n",
                static_cast<unsigned>(expected_size),
                static_cast<unsigned>(free_psram_before),
                static_cast<unsigned>(ESP.getFreePsram()));
  upload_type = UploadType::kShow;
  upload_expected = expected_size;
  upload_received = 0;
  return true;
}

bool finish_show_stream_upload() {
  if (upload_type != UploadType::kShow || show_partition == nullptr ||
      show_upload_buffer == nullptr) {
    show_upload_error = "upload-state";
    return false;
  }
  bool installed = false;
  bool handoff_ready = false;
  p4show::Error validation = p4show::Error::kPackageSize;
  uint32_t validate_ms = 0;
  uint32_t erase_ms = 0;
  uint32_t write_ms = 0;
  uint32_t commit_ms = 0;
  if (upload_received == upload_expected) {
    Serial.printf("SHOW FINALIZE: validating %u bytes\n",
                  static_cast<unsigned>(upload_received));
    const uint32_t validate_start = millis();
    validation = p4show::validate(show_upload_buffer, upload_received);
    validate_ms = millis() - validate_start;
    if (validation == p4show::Error::kOk) {
      Serial.println("SHOW FINALIZE: erasing raw data range");
      Serial.flush();
      const uint32_t erase_start = millis();
      const bool erased = erase_raw_show_for_upload(upload_received);
      erase_ms = millis() - erase_start;
      if (!erased) {
        show_upload_error = "storage-erase";
      } else {
        Serial.println("SHOW FINALIZE: writing raw data range");
        Serial.flush();
        const uint32_t write_start = millis();
        const bool written =
            write_raw_show(show_upload_buffer, upload_received);
        write_ms = millis() - write_start;
        if (!written) {
          show_upload_error = "install-failed";
        } else {
          Serial.println("SHOW FINALIZE: committing header");
          const uint32_t commit_start = millis();
          installed = commit_raw_show(upload_received);
          commit_ms = millis() - commit_start;
        }
      }
    }
    if (installed) {
      release_installed_show_handoff();
      installed_show_data = show_upload_buffer;
      installed_show_size = upload_received;
      show_upload_buffer = nullptr;
      handoff_ready = true;
    }
  }
  release_show_upload_buffer();
  if (!installed) invalidate_raw_show();
  if (installed) {
    show_upload_error = "none";
  } else if (validation != p4show::Error::kOk) {
    show_upload_error = p4show::error_name(validation);
  } else if (strcmp(show_upload_error, "storage-erase") != 0) {
    show_upload_error = "install-failed";
  }
  Serial.printf(
      "SHOW UPLOAD: %u/%u bytes, validation=%s, %s, validate %u ms, "
      "erase %u ms, write %u ms, commit %u ms, %s\n",
      static_cast<unsigned>(upload_received),
      static_cast<unsigned>(upload_expected), p4show::error_name(validation),
      installed ? "installed" : "rejected", static_cast<unsigned>(validate_ms),
      static_cast<unsigned>(erase_ms), static_cast<unsigned>(write_ms),
      static_cast<unsigned>(commit_ms),
      handoff_ready ? "ram-handoff" : "no-handoff");
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
