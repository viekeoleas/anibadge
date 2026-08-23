#include "p4_upload_ui.h"

#include <Arduino.h>

#include "p4_display.h"

namespace p4uploadui {
namespace {

constexpr uint16_t kBackground = 0x0844;
constexpr uint16_t kPanel = 0x10A6;
constexpr uint16_t kBlue = 0x0356;
constexpr uint16_t kBlueLight = 0x5D9F;
constexpr uint16_t kWhite = 0xFFFF;
constexpr uint16_t kMuted = 0xA534;
constexpr uint16_t kGreen = 0x3666;
constexpr uint16_t kRed = 0xE9C7;

uint8_t last_percent = 255;

const uint8_t *glyph(char value) {
  // Five columns, least-significant bit at the top. Only glyphs used by the
  // upload screen are kept here to avoid pulling a font library into firmware.
  static constexpr uint8_t kSpace[5] = {0, 0, 0, 0, 0};
  static constexpr uint8_t kPercent[5] = {0x63, 0x13, 0x08, 0x64, 0x63};
  static constexpr uint8_t kA[5] = {0x7E, 0x09, 0x09, 0x09, 0x7E};
  static constexpr uint8_t kD[5] = {0x7F, 0x41, 0x41, 0x22, 0x1C};
  static constexpr uint8_t kE[5] = {0x7F, 0x49, 0x49, 0x49, 0x41};
  static constexpr uint8_t kF[5] = {0x7F, 0x09, 0x09, 0x09, 0x01};
  static constexpr uint8_t kG[5] = {0x3E, 0x41, 0x49, 0x49, 0x7A};
  static constexpr uint8_t kH[5] = {0x7F, 0x08, 0x08, 0x08, 0x7F};
  static constexpr uint8_t kI[5] = {0x00, 0x41, 0x7F, 0x41, 0x00};
  static constexpr uint8_t kL[5] = {0x7F, 0x40, 0x40, 0x40, 0x40};
  static constexpr uint8_t kM[5] = {0x7F, 0x02, 0x0C, 0x02, 0x7F};
  static constexpr uint8_t kN[5] = {0x7F, 0x02, 0x0C, 0x10, 0x7F};
  static constexpr uint8_t kO[5] = {0x3E, 0x41, 0x41, 0x41, 0x3E};
  static constexpr uint8_t kP[5] = {0x7F, 0x09, 0x09, 0x09, 0x06};
  static constexpr uint8_t kR[5] = {0x7F, 0x09, 0x19, 0x29, 0x46};
  static constexpr uint8_t kS[5] = {0x46, 0x49, 0x49, 0x49, 0x31};
  static constexpr uint8_t kT[5] = {0x01, 0x01, 0x7F, 0x01, 0x01};
  static constexpr uint8_t kU[5] = {0x3F, 0x40, 0x40, 0x40, 0x3F};
  static constexpr uint8_t kV[5] = {0x1F, 0x20, 0x40, 0x20, 0x1F};
  static constexpr uint8_t kW[5] = {0x7F, 0x20, 0x18, 0x20, 0x7F};
  static constexpr uint8_t kY[5] = {0x03, 0x04, 0x78, 0x04, 0x03};
  static constexpr uint8_t k0[5] = {0x3E, 0x51, 0x49, 0x45, 0x3E};
  static constexpr uint8_t k1[5] = {0x00, 0x42, 0x7F, 0x40, 0x00};
  static constexpr uint8_t k2[5] = {0x42, 0x61, 0x51, 0x49, 0x46};
  static constexpr uint8_t k3[5] = {0x21, 0x41, 0x45, 0x4B, 0x31};
  static constexpr uint8_t k4[5] = {0x18, 0x14, 0x12, 0x7F, 0x10};
  static constexpr uint8_t k5[5] = {0x27, 0x45, 0x45, 0x45, 0x39};
  static constexpr uint8_t k6[5] = {0x3C, 0x4A, 0x49, 0x49, 0x30};
  static constexpr uint8_t k7[5] = {0x01, 0x71, 0x09, 0x05, 0x03};
  static constexpr uint8_t k8[5] = {0x36, 0x49, 0x49, 0x49, 0x36};
  static constexpr uint8_t k9[5] = {0x06, 0x49, 0x49, 0x29, 0x1E};

  switch (value) {
    case '%': return kPercent;
    case 'A': return kA;
    case 'D': return kD;
    case 'E': return kE;
    case 'F': return kF;
    case 'G': return kG;
    case 'H': return kH;
    case 'I': return kI;
    case 'L': return kL;
    case 'M': return kM;
    case 'N': return kN;
    case 'O': return kO;
    case 'P': return kP;
    case 'R': return kR;
    case 'S': return kS;
    case 'T': return kT;
    case 'U': return kU;
    case 'V': return kV;
    case 'W': return kW;
    case 'Y': return kY;
    case '0': return k0;
    case '1': return k1;
    case '2': return k2;
    case '3': return k3;
    case '4': return k4;
    case '5': return k5;
    case '6': return k6;
    case '7': return k7;
    case '8': return k8;
    case '9': return k9;
    default: return kSpace;
  }
}

void fill_rect(uint16_t *pixels, int x, int y, int width, int height,
               uint16_t color) {
  if (pixels == nullptr || width <= 0 || height <= 0) return;
  const int left = max(0, x);
  const int top = max(0, y);
  const int right = min(p4display::kWidth, x + width);
  const int bottom = min(p4display::kHeight, y + height);
  for (int row = top; row < bottom; ++row) {
    uint16_t *target = pixels + static_cast<size_t>(row) * p4display::kWidth;
    for (int column = left; column < right; ++column) target[column] = color;
  }
}

int text_width(const char *text, int scale) {
  if (text == nullptr || *text == '\0') return 0;
  return (static_cast<int>(strlen(text)) * 6 - 1) * scale;
}

void draw_text(uint16_t *pixels, int x, int y, const char *text, int scale,
               uint16_t color) {
  for (const char *cursor = text; cursor != nullptr && *cursor != '\0';
       ++cursor) {
    const uint8_t *columns = glyph(*cursor);
    for (int column = 0; column < 5; ++column) {
      for (int row = 0; row < 7; ++row) {
        if ((columns[column] & (1U << row)) != 0) {
          fill_rect(pixels, x + column * scale, y + row * scale, scale, scale,
                    color);
        }
      }
    }
    x += 6 * scale;
  }
}

void draw_centered(uint16_t *pixels, int y, const char *text, int scale,
                   uint16_t color) {
  draw_text(pixels, (p4display::kWidth - text_width(text, scale)) / 2, y,
            text, scale, color);
}

void draw_shell(uint16_t *pixels) {
  fill_rect(pixels, 0, 0, p4display::kWidth, p4display::kHeight, kBackground);
  fill_rect(pixels, 64, 140, 672, 520, kPanel);
  fill_rect(pixels, 64, 140, 672, 5, kBlueLight);
}

void present(uint16_t *pixels) {
  if (!p4display::present(pixels, 250)) {
    Serial.println("UPLOAD UI: display refresh failed");
  }
}

void render_progress(uint8_t percent, const char *label) {
  if (percent > 100) percent = 100;
  if (percent == last_percent) return;
  last_percent = percent;

  uint16_t *pixels = p4display::back_buffer();
  if (pixels == nullptr) return;
  draw_shell(pixels);
  draw_centered(pixels, 205, label, 7, kWhite);

  char percentage[5] = {};
  snprintf(percentage, sizeof(percentage), "%u%%",
           static_cast<unsigned>(percent));
  draw_centered(pixels, 315, percentage, 13, kWhite);

  constexpr int bar_x = 110;
  constexpr int bar_y = 475;
  constexpr int bar_width = 580;
  constexpr int bar_height = 54;
  constexpr int border = 5;
  fill_rect(pixels, bar_x, bar_y, bar_width, bar_height, kMuted);
  fill_rect(pixels, bar_x + border, bar_y + border,
            (bar_width - border * 2) * percent / 100,
            bar_height - border * 2, kBlue);
  draw_centered(pixels, 570, "PLEASE WAIT", 4, kMuted);
  present(pixels);
}

}  // namespace

void show_progress(uint8_t percent) {
  render_progress(percent, "LOADING GIF");
}

void show_show_progress(uint8_t percent) {
  render_progress(percent, "LOADING SHOW");
}

void show_complete() {
  last_percent = 255;
  uint16_t *pixels = p4display::back_buffer();
  if (pixels == nullptr) return;
  draw_shell(pixels);
  draw_centered(pixels, 270, "DONE", 14, kGreen);
  draw_centered(pixels, 430, "STARTING GIF", 5, kWhite);
  present(pixels);
}

void show_show_complete() {
  last_percent = 255;
  uint16_t *pixels = p4display::back_buffer();
  if (pixels == nullptr) return;
  draw_shell(pixels);
  draw_centered(pixels, 270, "DONE", 14, kGreen);
  draw_centered(pixels, 430, "SHOW READY", 5, kWhite);
  present(pixels);
}

void show_error() {
  last_percent = 255;
  uint16_t *pixels = p4display::back_buffer();
  if (pixels == nullptr) return;
  draw_shell(pixels);
  draw_centered(pixels, 260, "UPLOAD ERROR", 8, kRed);
  draw_centered(pixels, 430, "TRY AGAIN", 6, kWhite);
  present(pixels);
}

void show_fallback() {
  last_percent = 255;
  uint16_t *pixels = p4display::back_buffer();
  if (pixels == nullptr) return;
  draw_shell(pixels);
  draw_centered(pixels, 260, "SAFE MODE", 9, kBlueLight);
  draw_centered(pixels, 430, "NO VALID SHOW", 5, kWhite);
  present(pixels);
}

}  // namespace p4uploadui
