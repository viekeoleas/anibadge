#include "p4_show_contract_test.h"

#include <Arduino.h>
#include <Preferences.h>

#include "esp_heap_caps.h"

#include "p4_show_contract_fixture.h"
#include "p4_show_format.h"
#include "p4_show_player.h"
#include "p4_storage.h"
#include "p4_upload_ui.h"

namespace p4showcontract {
namespace {

constexpr char kPreferencesNamespace[] = "zshow-contract";
constexpr char kStageKey[] = "stage";

bool stream_package(const uint8_t *data, size_t size, bool expect_success) {
  if (!p4storage::begin_show_stream_upload("contract.zshow", size)) {
    Serial.println("CONTRACT FAIL: cannot begin package stream");
    return false;
  }
  constexpr size_t kChunkBytes = 4096;
  for (size_t offset = 0; offset < size; offset += kChunkBytes) {
    const size_t chunk = min(kChunkBytes, size - offset);
    if (!p4storage::write_stream_upload(data + offset, chunk)) {
      p4storage::abort_stream_upload();
      Serial.println("CONTRACT FAIL: package stream write");
      return false;
    }
  }
  const bool installed = p4storage::finish_show_stream_upload();
  if (installed != expect_success) {
    Serial.printf("CONTRACT FAIL: install=%u expected=%u\n", installed,
                  expect_success);
    return false;
  }
  return true;
}

bool expect_rejected(const char *case_name, const uint8_t *data, size_t size,
                     p4show::Error expected_error) {
  const p4show::Error actual = p4show::validate(data, size);
  const bool parser_rejected = actual == expected_error;
  const bool player_rejected = !p4showplayer::start(data, size);
  p4showplayer::stop();
  Serial.printf(
      "CONTRACT NEGATIVE: case=%s parser=%s player_started=%u result=%s\n",
      case_name, p4show::error_name(actual), !player_rejected,
      parser_rejected && player_rejected ? "PASS" : "FAIL");
  return parser_rejected && player_rejected;
}

bool run_negative_contracts(uint8_t *scratch) {
  bool ok = true;
  ok = expect_rejected("truncated", kGoldenPackage, kGoldenPackageSize - 31,
                       p4show::Error::kPackageSize) &&
       ok;

  memcpy(scratch, kGoldenPackage, kGoldenPackageSize);
  scratch[8] = 2;
  scratch[9] = 0;
  ok = expect_rejected("unsupported-v2", scratch, kGoldenPackageSize,
                       p4show::Error::kUnsupportedVersion) &&
       ok;

  memcpy(scratch, kGoldenPackage, kGoldenPackageSize);
  scratch[kGoldenPackageSize - 17] ^= 0x80;
  ok = expect_rejected("payload-corrupt", scratch, kGoldenPackageSize,
                       p4show::Error::kPayloadCrc) &&
       ok;
  ok = stream_package(scratch, kGoldenPackageSize, false) && ok;
  return ok;
}

}  // namespace

void prepare() {
  Preferences preferences;
  if (!preferences.begin(kPreferencesNamespace, false)) {
    Serial.println("CONTRACT FAIL: Preferences unavailable");
    return;
  }
  const uint8_t stage = preferences.getUChar(kStageKey, 0);
  if (stage == 0) {
    Serial.println("CONTRACT STAGE 0: negative cases and golden install");
    uint8_t *scratch = static_cast<uint8_t *>(heap_caps_malloc(
        kGoldenPackageSize,
        MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT | MALLOC_CAP_CACHE_ALIGNED));
    if (scratch == nullptr) {
      Serial.println("CONTRACT FAIL: scratch allocation");
      preferences.end();
      return;
    }
    const bool negatives_ok = run_negative_contracts(scratch);
    heap_caps_free(scratch);
    p4uploadui::show_fallback();
    delay(800);
    const bool golden_ok =
        stream_package(kGoldenPackage, kGoldenPackageSize, true);
    if (!negatives_ok || !golden_ok) {
      Serial.println("CONTRACT FAIL: stage 0");
      preferences.end();
      return;
    }
    preferences.putUChar(kStageKey, 1);
    preferences.end();
    Serial.println("CONTRACT STAGE 0 PASS: rebooting for boot proof");
    delay(500);
    ESP.restart();
    return;
  }

  size_t stored_size = 0;
  uint8_t *stored = p4storage::load_show(&stored_size);
  const p4show::Error validation =
      stored == nullptr ? p4show::Error::kNullData
                        : p4show::validate(stored, stored_size);
  const bool identical = stored != nullptr &&
                         stored_size == kGoldenPackageSize &&
                         memcmp(stored, kGoldenPackage, stored_size) == 0;
  if (stored != nullptr) heap_caps_free(stored);
  Serial.printf(
      "CONTRACT BOOT PROOF: validation=%s identical=%u result=%s\n",
      p4show::error_name(validation), identical,
      validation == p4show::Error::kOk && identical ? "PASS" : "FAIL");
  preferences.putUChar(kStageKey, 2);
  preferences.end();
}

}  // namespace p4showcontract
