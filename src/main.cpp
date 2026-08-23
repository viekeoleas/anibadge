#include <Arduino.h>

#include "p4_display.h"
#include "p4_runtime.h"
#include "p4_storage.h"
#include "p4_web.h"

#ifdef ZNACHOK_JPEG_BENCHMARK
#include "p4_jpeg_benchmark.h"
#endif
#ifdef ZNACHOK_SHOW_CONTRACT_TEST
#include "p4_show_contract_test.h"
#endif

namespace {

void show_black_screen() {
  uint16_t *target = p4display::back_buffer();
  memset(target, 0, p4display::kFrameBytes);
  p4display::present(target);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(2500);
  Serial.println();
  Serial.println("Znachok Show Player");
  Serial.printf("ESP32-P4 rev %d, CPU %u MHz, flash %u MB, PSRAM %u MB\n",
                ESP.getChipRevision(), ESP.getCpuFreqMHz(),
                ESP.getFlashChipSize() / (1024U * 1024U),
                ESP.getPsramSize() / (1024U * 1024U));

  if (!p4storage::begin()) Serial.println("FATAL: storage unavailable");
  if (!p4web::begin()) Serial.println("FATAL: Wi-Fi upload unavailable");
  if (!p4display::begin()) {
    Serial.println("FATAL: display unavailable");
    return;
  }
  p4display::set_brightness(100);
  show_black_screen();

#ifdef ZNACHOK_JPEG_BENCHMARK
  if (!p4jpegbenchmark::run()) {
    Serial.println("BENCHMARK FATAL: run failed");
  }
#endif

#ifdef ZNACHOK_SHOW_CONTRACT_TEST
  p4showcontract::prepare();
#endif

  p4runtime::play_startup_media();
  Serial.println("READY: upload GIF or ZSHOW over Wi-Fi");
}

void loop() {
  p4web::poll();
  p4runtime::poll();
  if (p4storage::take_show_play_request()) {
    p4runtime::play_show();
  }
  char requested[64] = {};
  if (p4storage::take_play_request(requested, sizeof(requested))) {
    p4runtime::play_gif(requested);
  }
  delay(2);
}
