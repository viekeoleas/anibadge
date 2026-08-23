#include "p4_display.h"

#include <Arduino.h>

#include "esp_cache.h"
#include "esp_err.h"
#include "esp_lcd_mipi_dsi.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_ldo_regulator.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "p4_jd9365_init.h"

namespace p4display {
namespace {

constexpr int kResetPin = 27;
constexpr int kBacklightPin = 26;
// 46 MHz with the configured 860 x 840 total timing gives the scheduler a
// small amount of scan headroom above 60 Hz. The package timeline, rather than
// the panel scan clock, remains the source of truth for 60 FPS playback.
constexpr float kPixelClockMhz = 46.0f;

esp_ldo_channel_handle_t ldo_handle = nullptr;
esp_lcd_dsi_bus_handle_t dsi_bus = nullptr;
esp_lcd_panel_io_handle_t panel_io = nullptr;
esp_lcd_panel_handle_t panel = nullptr;
uint16_t *framebuffers[2] = {nullptr, nullptr};
uint8_t back_index = 0;
SemaphoreHandle_t refresh_done = nullptr;
SemaphoreHandle_t present_lock = nullptr;

bool check(esp_err_t result, const char *operation) {
  if (result == ESP_OK) {
    Serial.printf("OK: %s\n", operation);
    return true;
  }
  Serial.printf("ERROR: %s: %s (0x%x)\n", operation,
                esp_err_to_name(result), static_cast<unsigned>(result));
  return false;
}

bool on_refresh_done(esp_lcd_panel_handle_t,
                     esp_lcd_dpi_panel_event_data_t *, void *) {
  BaseType_t need_yield = pdFALSE;
  xSemaphoreGiveFromISR(refresh_done, &need_yield);
  return need_yield == pdTRUE;
}

void reset_panel() {
  pinMode(kResetPin, OUTPUT);
  digitalWrite(kResetPin, HIGH);
  delay(5);
  digitalWrite(kResetPin, LOW);
  delay(10);
  digitalWrite(kResetPin, HIGH);
  delay(120);
}

}  // namespace

void set_brightness(uint8_t percent) {
  if (percent > 100) percent = 100;
  // The board's backlight is active-low.
  const uint32_t duty =
      255U - (static_cast<uint32_t>(percent) * 255U / 100U);
  ledcWrite(kBacklightPin, duty);
}

uint16_t *framebuffer(uint8_t index) {
  return index < 2 ? framebuffers[index] : nullptr;
}

uint16_t *back_buffer() { return framebuffers[back_index]; }

uint16_t *front_buffer() { return framebuffers[back_index ^ 1U]; }

bool begin() {
  if (!ledcAttach(kBacklightPin, 20000, 8)) {
    Serial.println("ERROR: backlight PWM attach");
    return false;
  }
  set_brightness(0);

  const esp_ldo_channel_config_t ldo_config = {
      .chan_id = 3,
      .voltage_mv = 2500,
  };
  if (!check(esp_ldo_acquire_channel(&ldo_config, &ldo_handle),
             "MIPI PHY LDO 2.5V")) {
    return false;
  }

  const esp_lcd_dsi_bus_config_t bus_config = {
      .bus_id = 0,
      .num_data_lanes = 2,
      .phy_clk_src = MIPI_DSI_PHY_CLK_SRC_DEFAULT,
      .lane_bit_rate_mbps = 1500.0f,
  };
  if (!check(esp_lcd_new_dsi_bus(&bus_config, &dsi_bus), "DSI bus")) {
    return false;
  }

  const esp_lcd_dbi_io_config_t io_config = {
      .virtual_channel = 0,
      .lcd_cmd_bits = 8,
      .lcd_param_bits = 8,
  };
  if (!check(esp_lcd_new_panel_io_dbi(dsi_bus, &io_config, &panel_io),
             "DSI command IO")) {
    return false;
  }

  const esp_lcd_dpi_panel_config_t dpi_config = {
      .virtual_channel = 0,
      .dpi_clk_src = MIPI_DSI_DPI_CLK_SRC_DEFAULT,
      .dpi_clock_freq_mhz = kPixelClockMhz,
      .pixel_format = LCD_COLOR_PIXEL_FORMAT_RGB565,
      .num_fbs = 2,
      .video_timing = {
          .h_size = kWidth,
          .v_size = kHeight,
          .hsync_pulse_width = 20,
          .hsync_back_porch = 20,
          .hsync_front_porch = 40,
          .vsync_pulse_width = 4,
          .vsync_back_porch = 12,
          .vsync_front_porch = 24,
      },
      .flags = {
          .use_dma2d = true,
      },
  };
  if (!check(esp_lcd_new_panel_dpi(dsi_bus, &dpi_config, &panel),
             "800x800 DPI panel")) {
    return false;
  }

  reset_panel();
  Serial.printf("Sending %u JD9365 init commands...\n",
                static_cast<unsigned>(kP4LcdInitCommandCount));
  for (const auto &entry : kP4LcdInitCommands) {
    const esp_err_t result = esp_lcd_panel_io_tx_param(
        panel_io, entry.command, &entry.parameter, 1);
    if (result != ESP_OK) {
      Serial.printf("ERROR: JD9365 command 0x%02x: %s\n", entry.command,
                    esp_err_to_name(result));
      return false;
    }
    if (entry.delay_ms != 0) delay(entry.delay_ms);
  }
  Serial.println("OK: JD9365 init sequence");

  if (!check(esp_lcd_panel_init(panel), "DPI panel start")) return false;
  if (!check(esp_lcd_dpi_panel_get_frame_buffer(
                 panel, 2, reinterpret_cast<void **>(&framebuffers[0]),
                 reinterpret_cast<void **>(&framebuffers[1])),
             "two DPI framebuffers")) {
    return false;
  }

  refresh_done = xSemaphoreCreateBinary();
  present_lock = xSemaphoreCreateMutex();
  if (refresh_done == nullptr || present_lock == nullptr) {
    Serial.println("ERROR: framebuffer synchronization objects");
    return false;
  }
  const esp_lcd_dpi_panel_event_callbacks_t callbacks = {
      .on_color_trans_done = nullptr,
      .on_refresh_done = on_refresh_done,
  };
  if (!check(esp_lcd_dpi_panel_register_event_callbacks(
                 panel, &callbacks, nullptr),
             "DPI vsync callback")) {
    return false;
  }
  if (!check(esp_lcd_dpi_panel_set_pattern(panel, MIPI_DSI_PATTERN_NONE),
             "disable test pattern")) {
    return false;
  }

  memset(framebuffers[0], 0, kFrameBytes);
  memset(framebuffers[1], 0, kFrameBytes);
  esp_cache_msync(framebuffers[0], kFrameBytes, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
  esp_cache_msync(framebuffers[1], kFrameBytes, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
  set_brightness(100);
  Serial.printf("DISPLAY READY: two 800x800 RGB565 buffers at %p / %p\n",
                framebuffers[0], framebuffers[1]);
  return true;
}

bool present(const uint16_t *pixels, uint32_t timeout_ms) {
  if (panel == nullptr || pixels == nullptr || present_lock == nullptr) {
    return false;
  }
  if (xSemaphoreTake(present_lock, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
    Serial.println("ERROR: present lock timeout");
    return false;
  }

  uint16_t *back = framebuffers[back_index];
  if (pixels != back) memcpy(back, pixels, kFrameBytes);
  esp_err_t result =
      esp_cache_msync(back, kFrameBytes, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
  if (result == ESP_OK) {
    result = esp_lcd_panel_draw_bitmap(panel, 0, 0, kWidth, kHeight, back);
  }
  if (result == ESP_OK) {
    xSemaphoreTake(refresh_done, 0);
    if (xSemaphoreTake(refresh_done, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
      Serial.println("ERROR: display refresh timeout");
      result = ESP_ERR_TIMEOUT;
    }
  }
  if (result == ESP_OK) back_index ^= 1U;
  xSemaphoreGive(present_lock);
  return result == ESP_OK;
}

}  // namespace p4display
