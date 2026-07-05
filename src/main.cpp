#include <Arduino.h>
#include <Wire.h>
#include <lvgl.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include <JPEGDEC.h>
#include <AnimatedGIF.h>
#include <vector>
#include "esp_timer.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_rgb.h"
#include "driver/spi_master.h"

// ---- Bluetooth (BLE) / хранилище ----
#define BLE_NAME   "Znachok-BMW"
#define MEDIA_DIR  "/media"
#define SHOW_FILE  "show.zpl"
#define IMG_BYTES  (LCD_W * LCD_H * 2)   // 460800, сырой RGB565
#define MJPG_MAX_FRAMES 200
#define SHOW_MAX_SCENES 24
#define TRANSITION_MS 420
// UUID сервиса/характеристик (custom)
#define SVC_UUID   "a1b20000-1111-2222-3333-444455556666"
#define CTRL_UUID  "a1b20001-1111-2222-3333-444455556666"  // write + notify: команды/ответы
#define DATA_UUID  "a1b20002-1111-2222-3333-444455556666"  // write: байты картинки

// ============================================================================
// Спринт 1: фундамент графики на LVGL + статичный логотип.
// Waveshare ESP32-S3-Touch-LCD-2.1/2.1B (ST7701 480x480 RGB, расширитель TCA9554).
// Рендер: LVGL v8.3 full_refresh -> рисует прямо в 2 буфера панели (zero-copy).
// ============================================================================

// ---- I2C / расширитель TCA9554 ----
#define I2C_SDA 15
#define I2C_SCL 7
#define TCA9554_ADDR        0x20
#define TCA9554_OUTPUT_REG  0x01
#define TCA9554_CONFIG_REG  0x03
#define EXIO_LCD_RST 1    // EXIO1 -> reset панели
#define EXIO_LCD_CS  3    // EXIO3 -> CS для 3-wire SPI init

// ---- 3-wire SPI инициализации ST7701 ----
#define LCD_MOSI_PIN 1
#define LCD_CLK_PIN  2
#define LCD_BL_PIN   6    // подсветка (PWM)

#define LCD_W 480
#define LCD_H 480

static spi_device_handle_t g_spi = nullptr;
static esp_lcd_panel_handle_t g_panel = nullptr;

// ---- плеер / BLE ----
static lv_obj_t  *g_img = nullptr;       // объект LVGL, показывающий текущий кадр
static lv_img_dsc_t g_cur_dsc = {};      // дескриптор для присланных картинок
static uint16_t  *g_imgbuf = nullptr;    // PSRAM-буфер кадра (RGB565)
static uint16_t  *g_frombuf = nullptr;   // кадр A для переходов
static uint16_t  *g_tobuf = nullptr;     // кадр B для переходов
static File       g_upf;                 // открытый файл при заливке по BLE
static char       g_show_name[64] = {0}; // запрос «показать файл» из BLE-потока
static char       g_del_name[64] = {0};  // запрос «удалить файл» из BLE-потока
static volatile bool g_show_dirty = false;
static volatile bool g_del_dirty = false;
static volatile bool g_list_dirty = false;
static std::vector<String> g_playlist;   // имена файлов для слайдшоу
static size_t     g_play_idx = 0;
static uint32_t   g_last_switch = 0;
static const uint32_t SLIDE_MS = 8000;   // длительность кадра в слайдшоу
static bool       g_manual = false;      // выбрана картинка вручную -> не листать

struct ShowScene {
  String file;
  String fx_img;                         // картинка-значок для FX-сцены ("" = вшитый BMW)
  uint16_t duration_ms;                  // для статики (мс); 0 у динамики
  uint8_t loops;                         // для анимаций/FX: полных циклов (0 = бесконечно)
  uint8_t transition;                    // 0 none, 1 fade, 2 push, 3 circle, 4 wipe, 5 zoom, 6 blinds, 7 split
  uint8_t fx;                            // 0 media file, 6..15 процедурная сцена
};
static std::vector<ShowScene> g_show;
static bool       g_show_loaded = false;
static volatile bool g_script_dirty = false;
static size_t     g_scene_idx = 0;
static bool       g_transition_active = false;
static uint32_t   g_transition_start = 0;
static uint32_t   g_scene_started = 0;
static uint8_t    g_transition_type = 0;
static uint32_t   g_fx_last_frame = 0;
static bool       g_scene_anim_active = false;  // сцена-анимация играет своим плеером
static uint32_t   g_scene_anim_end = 0;         // millis конца её циклов

// JPEG-декодер (для сжатых картинок .jpg)
static JPEGDEC g_jpeg;
static uint8_t *g_jpegbuf = nullptr;
static size_t   g_jpegbuf_cap = 0;
static uint16_t *g_jpeg_target = nullptr;

// BLE
static NimBLECharacteristic *g_ctrl = nullptr;   // команды/ответы (notify)
static bool       g_upf_open = false;            // идёт ли приём файла
static size_t     g_rx_total = 0, g_rx_got = 0;  // ожидаемый/принятый размер

// проигрывание анимации .anm (заголовок 8 байт + кадры RGB565)
static File       g_anim_file;
static bool       g_anim_active = false;
static bool       g_anim_mjpg = false;
static uint16_t   g_anim_nframes = 0, g_anim_delay = 100, g_anim_idx = 0;
static uint32_t   g_anim_last = 0;
static uint32_t   g_mjpg_sizes[MJPG_MAX_FRAMES] = {0};
static size_t     g_mjpg_data_start = 0;
static uint8_t   *g_mjpg_data = nullptr;   // весь .mjpg-файл в PSRAM
static uint16_t  *g_halfbuf = nullptr;     // 240x240 для стрим-декода в полразрешения
static uint16_t  *g_anim_cache = nullptr;
static uint16_t   g_anim_cached_frames = 0;
static bool       g_anim_cache_half = false;  // кэш в 240x240 (длинные анимации)

// ---- прямое представление кадров (мимо LVGL): двойной буфер панели ----
static uint16_t  *g_fbs[2] = {nullptr, nullptr};  // кадровые буферы RGB-панели
static int        g_backfb = 0;                   // индекс заднего (рисуем в него)

// ---- анимационная задача: владеет экраном, пока крутится ----
enum AnimKind : uint8_t { ANIM_NONE = 0, ANIM_RAW, ANIM_GIF };
static volatile bool g_task_running = false;      // задача жива
static volatile bool g_task_stop = false;         // просьба остановиться
static AnimKind   g_anim_kind = ANIM_NONE;

// ---- нативный GIF (AnimatedGIF): файл целиком в PSRAM, дельта-кадры ----
static AnimatedGIF g_gif;
static uint8_t   *g_gif_data = nullptr;
static uint8_t   *g_gif_framebuf = nullptr;
static bool       g_gif_open = false;
static int        g_gif_ox = 0, g_gif_oy = 0;     // центрирование канвы GIF
#define GIF_MAX_FILE (4u * 1024u * 1024u)

// ---------- TCA9554 ----------
static void tca_write(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(TCA9554_ADDR);
  Wire.write(reg); Wire.write(val);
  Wire.endTransmission();
}
static uint8_t tca_read(uint8_t reg) {
  Wire.beginTransmission(TCA9554_ADDR);
  Wire.write(reg); Wire.endTransmission();
  Wire.requestFrom((int)TCA9554_ADDR, 1);
  return Wire.available() ? Wire.read() : 0;
}
static void tca_set(uint8_t pin, bool high) {
  uint8_t s = tca_read(TCA9554_OUTPUT_REG);
  if (high) s |= (1 << (pin - 1)); else s &= ~(1 << (pin - 1));
  tca_write(TCA9554_OUTPUT_REG, s);
}

// ---------- ST7701 init по SPI ----------
static void st_cmd(uint8_t c) { spi_transaction_t t = {}; t.cmd = 0; t.addr = c; spi_device_transmit(g_spi, &t); }
static void st_dat(uint8_t d) { spi_transaction_t t = {}; t.cmd = 1; t.addr = d; spi_device_transmit(g_spi, &t); }

static void st7701_init() {
  spi_bus_config_t buscfg = {};
  buscfg.mosi_io_num = LCD_MOSI_PIN; buscfg.miso_io_num = -1; buscfg.sclk_io_num = LCD_CLK_PIN;
  buscfg.quadwp_io_num = -1; buscfg.quadhd_io_num = -1; buscfg.max_transfer_sz = 64;
  spi_bus_initialize(SPI2_HOST, &buscfg, SPI_DMA_CH_AUTO);

  spi_device_interface_config_t devcfg = {};
  devcfg.command_bits = 1; devcfg.address_bits = 8; devcfg.mode = 0;
  devcfg.clock_speed_hz = 40 * 1000 * 1000; devcfg.spics_io_num = -1; devcfg.queue_size = 1;
  spi_bus_add_device(SPI2_HOST, &devcfg, &g_spi);

  tca_set(EXIO_LCD_CS, false); delay(10);

  st_cmd(0xFF); st_dat(0x77); st_dat(0x01); st_dat(0x00); st_dat(0x00); st_dat(0x10);
  st_cmd(0xC0); st_dat(0x3B); st_dat(0x00);
  st_cmd(0xC1); st_dat(0x0B); st_dat(0x02);
  st_cmd(0xC2); st_dat(0x07); st_dat(0x02);
  st_cmd(0xCC); st_dat(0x10);
  st_cmd(0xCD); st_dat(0x08);
  st_cmd(0xB0); st_dat(0x00); st_dat(0x11); st_dat(0x16); st_dat(0x0e); st_dat(0x11);
                st_dat(0x06); st_dat(0x05); st_dat(0x09); st_dat(0x08); st_dat(0x21);
                st_dat(0x06); st_dat(0x13); st_dat(0x10); st_dat(0x29); st_dat(0x31); st_dat(0x18);
  st_cmd(0xB1); st_dat(0x00); st_dat(0x11); st_dat(0x16); st_dat(0x0e); st_dat(0x11);
                st_dat(0x07); st_dat(0x05); st_dat(0x09); st_dat(0x09); st_dat(0x21);
                st_dat(0x05); st_dat(0x13); st_dat(0x11); st_dat(0x2a); st_dat(0x31); st_dat(0x18);
  st_cmd(0xFF); st_dat(0x77); st_dat(0x01); st_dat(0x00); st_dat(0x00); st_dat(0x11);
  st_cmd(0xB0); st_dat(0x6d);
  st_cmd(0xB1); st_dat(0x37);
  st_cmd(0xB2); st_dat(0x81);
  st_cmd(0xB3); st_dat(0x80);
  st_cmd(0xB5); st_dat(0x43);
  st_cmd(0xB7); st_dat(0x85);
  st_cmd(0xB8); st_dat(0x20);
  st_cmd(0xC1); st_dat(0x78);
  st_cmd(0xC2); st_dat(0x78);
  st_cmd(0xD0); st_dat(0x88);
  st_cmd(0xE0); st_dat(0x00); st_dat(0x00); st_dat(0x02);
  st_cmd(0xE1); st_dat(0x03); st_dat(0xA0); st_dat(0x00); st_dat(0x00); st_dat(0x04);
                st_dat(0xA0); st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x20); st_dat(0x20);
  st_cmd(0xE2); for (int i = 0; i < 13; i++) st_dat(0x00);
  st_cmd(0xE3); st_dat(0x00); st_dat(0x00); st_dat(0x11); st_dat(0x00);
  st_cmd(0xE4); st_dat(0x22); st_dat(0x00);
  st_cmd(0xE5); st_dat(0x05); st_dat(0xEC); st_dat(0xA0); st_dat(0xA0); st_dat(0x07);
                st_dat(0xEE); st_dat(0xA0); st_dat(0xA0); st_dat(0x00); st_dat(0x00);
                st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00);
  st_cmd(0xE6); st_dat(0x00); st_dat(0x00); st_dat(0x11); st_dat(0x00);
  st_cmd(0xE7); st_dat(0x22); st_dat(0x00);
  st_cmd(0xE8); st_dat(0x06); st_dat(0xED); st_dat(0xA0); st_dat(0xA0); st_dat(0x08);
                st_dat(0xEF); st_dat(0xA0); st_dat(0xA0); st_dat(0x00); st_dat(0x00);
                st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00); st_dat(0x00);
  st_cmd(0xEB); st_dat(0x00); st_dat(0x00); st_dat(0x40); st_dat(0x40); st_dat(0x00);
                st_dat(0x00); st_dat(0x00);
  st_cmd(0xED); st_dat(0xFF); st_dat(0xFF); st_dat(0xFF); st_dat(0xBA); st_dat(0x0A);
                st_dat(0xBF); st_dat(0x45); st_dat(0xFF); st_dat(0xFF); st_dat(0x54);
                st_dat(0xFB); st_dat(0xA0); st_dat(0xAB); st_dat(0xFF); st_dat(0xFF); st_dat(0xFF);
  st_cmd(0xEF); st_dat(0x10); st_dat(0x0D); st_dat(0x04); st_dat(0x08); st_dat(0x3F); st_dat(0x1F);
  st_cmd(0xFF); st_dat(0x77); st_dat(0x01); st_dat(0x00); st_dat(0x00); st_dat(0x13);
  st_cmd(0xEF); st_dat(0x08);
  st_cmd(0xFF); st_dat(0x77); st_dat(0x01); st_dat(0x00); st_dat(0x00); st_dat(0x00);
  st_cmd(0x36); st_dat(0x00);
  st_cmd(0x3A); st_dat(0x66);
  st_cmd(0x11); delay(120);
  st_cmd(0x29); delay(20);

  tca_set(EXIO_LCD_CS, true);
}

static void rgb_panel_init() {
  esp_lcd_rgb_panel_config_t cfg = {};
  cfg.clk_src = LCD_CLK_SRC_DEFAULT;
  cfg.timings.pclk_hz = 16 * 1000 * 1000;
  cfg.timings.h_res = LCD_W; cfg.timings.v_res = LCD_H;
  cfg.timings.hsync_pulse_width = 8;  cfg.timings.hsync_back_porch = 10; cfg.timings.hsync_front_porch = 50;
  cfg.timings.vsync_pulse_width = 3;  cfg.timings.vsync_back_porch = 8;  cfg.timings.vsync_front_porch = 8;
  cfg.data_width = 16; cfg.bits_per_pixel = 16; cfg.num_fbs = 2;
  cfg.bounce_buffer_size_px = 10 * LCD_W; cfg.psram_trans_align = 64;
  cfg.hsync_gpio_num = 38; cfg.vsync_gpio_num = 39; cfg.de_gpio_num = 40; cfg.pclk_gpio_num = 41;
  cfg.disp_gpio_num = -1;
  int dp[16] = {5,45,48,47,21, 14,13,12,11,10,9, 46,3,8,18,17};
  for (int i = 0; i < 16; i++) cfg.data_gpio_nums[i] = dp[i];
  cfg.flags.fb_in_psram = 1;
  esp_lcd_new_rgb_panel(&cfg, &g_panel);
  esp_lcd_panel_reset(g_panel);
  esp_lcd_panel_init(g_panel);
}

// ---------- LVGL glue ----------
static lv_disp_draw_buf_t g_draw_buf;
static lv_disp_drv_t      g_disp_drv;

static void lvgl_flush(lv_disp_drv_t *drv, const lv_area_t *area, lv_color_t *color_p) {
  esp_lcd_panel_draw_bitmap(g_panel, area->x1, area->y1, area->x2 + 1, area->y2 + 1, color_p);
  lv_disp_flush_ready(drv);
}
static void lvgl_tick_cb(void *arg) { lv_tick_inc(2); }

static void lvgl_init() {
  lv_init();
  void *fb0 = nullptr, *fb1 = nullptr;
  esp_lcd_rgb_panel_get_frame_buffer(g_panel, 2, &fb0, &fb1);
  g_fbs[0] = (uint16_t *)fb0;               // для прямого вывода анимаций мимо LVGL
  g_fbs[1] = (uint16_t *)fb1;
  lv_disp_draw_buf_init(&g_draw_buf, fb0, fb1, LCD_W * LCD_H);

  lv_disp_drv_init(&g_disp_drv);
  g_disp_drv.hor_res = LCD_W;
  g_disp_drv.ver_res = LCD_H;
  g_disp_drv.flush_cb = lvgl_flush;
  g_disp_drv.full_refresh = 1;             // RGB-панель: всегда перерисовываем весь экран
  g_disp_drv.draw_buf = &g_draw_buf;
  lv_disp_drv_register(&g_disp_drv);

  const esp_timer_create_args_t targs = { .callback = &lvgl_tick_cb, .name = "lv_tick" };
  esp_timer_handle_t th = nullptr;
  esp_timer_create(&targs, &th);
  esp_timer_start_periodic(th, 2 * 1000);  // 2 ms
}

static void set_brightness(uint8_t pct) {            // 0..100
  if (pct > 100) pct = 100;
  ledcWrite(LCD_BL_PIN, (uint32_t)pct * 1023 / 100);
}

// ---------- картинка на экране ----------
extern const lv_img_dsc_t bmw_logo;       // вшитый логотип (src/bmw_logo.c)

static void build_screen() {
  lv_obj_t *scr = lv_scr_act();
  lv_obj_set_style_bg_color(scr, lv_color_black(), 0);
  lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

  g_img = lv_img_create(scr);
  lv_img_set_src(g_img, &bmw_logo);        // по умолчанию — логотип
  lv_obj_center(g_img);
}

// отдать содержимое g_imgbuf в объект LVGL
static void blit_buffer() {
  g_cur_dsc.header.cf = LV_IMG_CF_TRUE_COLOR;
  g_cur_dsc.header.always_zero = 0;
  g_cur_dsc.header.w = LCD_W;
  g_cur_dsc.header.h = LCD_H;
  g_cur_dsc.data_size = IMG_BYTES;
  g_cur_dsc.data = (const uint8_t *)g_imgbuf;
  lv_img_set_src(g_img, &g_cur_dsc);
  lv_obj_center(g_img);
  lv_obj_invalidate(g_img);
}

// Показать g_imgbuf без LVGL: копия в ЗАДНИЙ буфер панели + флип по vsync.
// draw_bitmap с указателем, равным одному из буферов панели, не копирует,
// а просто переключает активный буфер на следующем vsync -> нет разрывов.
static void present_buffer_fast() {
  uint16_t *fb = g_fbs[g_backfb];
  memcpy(fb, g_imgbuf, IMG_BYTES);
  esp_lcd_panel_draw_bitmap(g_panel, 0, 0, LCD_W, LCD_H, fb);
  g_backfb ^= 1;
}

// ---------- нативный GIF + анимационная задача ----------
static bool anim_read_frame(uint16_t idx);        // fwd
static bool mjpg_stream_show(uint16_t idx);       // fwd

static void *gif_alloc(uint32_t sz) { return heap_caps_malloc(sz, MALLOC_CAP_SPIRAM); }
static void gif_free_cb(void *p) { heap_caps_free(p); }

// COOKED-строки кадра -> RGB565-канва g_imgbuf (содержимое сохраняется между
// кадрами, поэтому дельта-кадры GIF ложатся поверх правильно)
static void gif_draw_cb(GIFDRAW *d) {
  int y = g_gif_oy + d->iY + d->y;
  if (y < 0 || y >= LCD_H) return;
  int x = g_gif_ox + d->iX;
  int w = d->iWidth;
  const uint16_t *src = (const uint16_t *)d->pPixels;
  if (x < 0) { src += -x; w += x; x = 0; }
  if (x + w > LCD_W) w = LCD_W - x;
  if (w > 0) memcpy(g_imgbuf + (size_t)y * LCD_W + x, src, (size_t)w * 2);
}

static void gif_unload() {
  if (g_gif_open) { g_gif.close(); g_gif_open = false; }
  if (g_gif_framebuf) { heap_caps_free(g_gif_framebuf); g_gif_framebuf = nullptr; }
  if (g_gif_data) { heap_caps_free(g_gif_data); g_gif_data = nullptr; }
}

// Задача воспроизведения: декод кадра -> флип буфера, такт с компенсацией
// времени декода. Работает на ядре 1; BLE (NimBLE) живёт на ядре 0.
static void anim_task_fn(void *) {
  bool first = true;
  uint32_t t_start = millis();
  int last_frame = -1;
  uint32_t render_ema = 0;   // скользящее среднее времени рендера кадра
  while (!g_task_stop) {
    if (g_anim_kind == ANIM_GIF) {
      uint32_t t0 = millis();
      int delay_ms = 100;
      int rc = g_gif.playFrame(false, &delay_ms, nullptr);  // строки лягут в g_imgbuf
      if (first) { Serial.printf("gif playFrame rc=%d err=%d delay=%d\n",
                                 rc, g_gif.getLastError(), delay_ms); first = false; }
      if (rc < 0) break;
      if (rc == 0) g_gif.reset();                           // конец -> зациклить
      if (delay_ms < 20) delay_ms = 20;
      present_buffer_fast();
      int wait = delay_ms - (int)(millis() - t0);
      vTaskDelay(pdMS_TO_TICKS(wait < 2 ? 2 : wait));
      continue;
    }
    // .anm/.mjpg: такт по настенным часам + СТАБИЛЬНЫЙ каденс.
    // Скорость анимации всегда правильная. Если рендер кадра медленнее
    // интервала — показываем каждый stride-й кадр строго равномерно
    // (ровный ритм; пляшущие пропуски глаз видит как рваность).
    uint32_t delay_ms = g_anim_delay < 20 ? 20 : g_anim_delay;
    uint32_t stride = render_ema ? (render_ema + delay_ms - 1) / delay_ms : 1;
    if (stride < 1) stride = 1;
    if (stride > g_anim_nframes) stride = g_anim_nframes;
    uint32_t period = stride * delay_ms;
    uint32_t elapsed = millis() - t_start;
    uint32_t step = elapsed / period;
    int want = (int)((step * stride) % g_anim_nframes);
    if (want != last_frame) {
      uint32_t t0 = millis();
      if (g_anim_mjpg && !g_anim_cache) {
        mjpg_stream_show((uint16_t)want);   // длинные: полу-декод прямо в буфер панели
      } else if (anim_read_frame((uint16_t)want)) {
        present_buffer_fast();
      }
      uint32_t rt = millis() - t0;                          // реальное время рендера
      render_ema = render_ema ? (render_ema * 3 + rt) / 4 : rt;
      last_frame = want;
    }
    elapsed = millis() - t_start;
    uint32_t next_ms = (step + 1) * period;                 // граница следующего такта
    int wait = (int)((int64_t)next_ms - (int64_t)elapsed);
    vTaskDelay(pdMS_TO_TICKS(wait < 2 ? 2 : wait));
  }
  g_task_running = false;
  vTaskDelete(nullptr);
}

static void anim_task_start(AnimKind kind) {
  g_anim_kind = kind;
  g_task_stop = false;
  g_task_running = true;
  BaseType_t ok = xTaskCreatePinnedToCore(anim_task_fn, "anim", 12288, nullptr, 2, nullptr, 1);
  if (ok != pdPASS) {
    Serial.println("anim task: create FAIL");
    g_task_running = false;
    g_anim_kind = ANIM_NONE;
  }
}

// Остановить задачу и вернуть экран LVGL (только из главного потока!)
static void anim_task_stop_sync() {
  if (g_task_running) {
    g_task_stop = true;
    while (g_task_running) delay(2);
  }
  g_task_stop = false;
  gif_unload();
  g_anim_kind = ANIM_NONE;
  lv_obj_invalidate(lv_scr_act());        // LVGL перерисует экран поверх анимации
}

static void anim_cache_free() {
  if (g_anim_cache) {
    heap_caps_free(g_anim_cache);
    g_anim_cache = nullptr;
  }
  g_anim_cached_frames = 0;
  g_anim_cache_half = false;
}

static void anim_stop() {
  anim_task_stop_sync();                  // сначала гасим задачу воспроизведения
  if (g_anim_active) { g_anim_file.close(); g_anim_active = false; }
  g_anim_mjpg = false;
  if (g_mjpg_data) { heap_caps_free(g_mjpg_data); g_mjpg_data = nullptr; }
  if (g_halfbuf) { heap_caps_free(g_halfbuf); g_halfbuf = nullptr; }
  anim_cache_free();
}

// callback JPEGDEC: блок MCU -> в целевой буфер (stride настраивается,
// чтобы уметь декодить и полный кадр 480, и половинный 240)
static int g_jpeg_stride = LCD_W;
static int g_jpeg_maxh = LCD_H;
static int jpeg_draw(JPEGDRAW *p) {
  for (int row = 0; row < p->iHeight; row++) {
    int y = p->y + row;
    if (y < 0 || y >= g_jpeg_maxh) continue;
    int x = p->x;
    int w = p->iWidth;
    if (x < 0) { w += x; x = 0; }
    if (x + w > g_jpeg_stride) w = g_jpeg_stride - x;
    if (w > 0)
      memcpy(g_jpeg_target + (size_t)y * g_jpeg_stride + x,
             p->pPixels + row * p->iWidth, (size_t)w * 2);
  }
  return 1;
}

static bool ensure_jpeg_buf(size_t sz) {
  if (sz <= g_jpegbuf_cap) return true;
  if (g_jpegbuf) heap_caps_free(g_jpegbuf);
  g_jpegbuf = (uint8_t *)heap_caps_malloc(sz, MALLOC_CAP_SPIRAM);
  g_jpegbuf_cap = g_jpegbuf ? sz : 0;
  return g_jpegbuf != nullptr;
}

static bool decode_jpeg_ram_ex(uint8_t *buf, size_t sz, uint16_t *target,
                               int stride, int maxh, int opts) {
  g_jpeg_target = target;
  g_jpeg_stride = stride;
  g_jpeg_maxh = maxh;
  bool ok = false;
  if (g_jpeg.openRAM(buf, sz, jpeg_draw)) {
    g_jpeg.setPixelType(RGB565_LITTLE_ENDIAN);
    ok = g_jpeg.decode(0, 0, opts) == 1;
    g_jpeg.close();
  }
  g_jpeg_stride = LCD_W;
  g_jpeg_maxh = LCD_H;
  return ok;
}

static bool decode_jpeg_ram(uint8_t *buf, size_t sz, uint16_t *target = nullptr) {
  return decode_jpeg_ram_ex(buf, sz, target ? target : g_imgbuf, LCD_W, LCD_H, 0);
}

// быстрый целочисленный апскейл 240x240 -> 480x480 (дублирование пикселей/строк)
static void upscale2x_240(const uint16_t *src, uint16_t *dst) {
  static uint16_t row[LCD_W];
  for (int y = 0; y < 240; y++) {
    const uint16_t *s = src + (size_t)y * 240;
    for (int x = 0; x < 240; x++) { row[2 * x] = s[x]; row[2 * x + 1] = s[x]; }
    memcpy(dst + (size_t)(2 * y) * LCD_W, row, sizeof(row));
    memcpy(dst + (size_t)(2 * y + 1) * LCD_W, row, sizeof(row));
  }
}

// декодировать .jpg-файл (480x480) в target/g_imgbuf
static bool decode_jpeg(const char *path, uint16_t *target = nullptr) {
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  size_t sz = f.size();
  if (!ensure_jpeg_buf(sz)) { f.close(); return false; }
  bool rd = f.read(g_jpegbuf, sz) == sz;
  f.close();
  return rd && decode_jpeg_ram(g_jpegbuf, sz, target);
}

static bool load_media_to_buffer(const char *name, uint16_t *target) {
  char path[96];
  snprintf(path, sizeof(path), MEDIA_DIR "/%s", name);
  size_t n = strlen(name);
  bool is_jpg = (n > 4 && strcmp(name + n - 4, ".jpg") == 0);
  bool is_bin = (n > 4 && strcmp(name + n - 4, ".bin") == 0);
  if (is_jpg) return decode_jpeg(path, target);
  if (is_bin) {
    File f = LittleFS.open(path, "r");
    if (!f || f.size() != IMG_BYTES) { if (f) f.close(); return false; }
    bool ok = f.read((uint8_t *)target, IMG_BYTES) == IMG_BYTES;
    f.close();
    return ok;
  }
  return false;
}

// показать вшитый логотип
static void show_logo() {
  anim_stop();
  lv_img_set_src(g_img, &bmw_logo);
  lv_obj_center(g_img);
}

static uint16_t blend565(uint16_t a, uint16_t b, uint8_t t) {
  uint8_t ar = (a >> 11) & 0x1F, ag = (a >> 5) & 0x3F, ab = a & 0x1F;
  uint8_t br = (b >> 11) & 0x1F, bg = (b >> 5) & 0x3F, bb = b & 0x1F;
  uint8_t r = ar + (((int)br - ar) * t >> 8);
  uint8_t g = ag + (((int)bg - ag) * t >> 8);
  uint8_t bl = ab + (((int)bb - ab) * t >> 8);
  return (r << 11) | (g << 5) | bl;
}

static uint8_t ease_cubic(uint8_t t) {
  uint16_t x = t;
  uint32_t y = (uint32_t)x * x * (768 - 2 * x);
  return (uint8_t)(y >> 16);
}

static void compose_transition(uint8_t type, uint8_t progress) {
  progress = ease_cubic(progress);
  if (type == 0 || progress >= 255) {
    memcpy(g_imgbuf, g_tobuf, IMG_BYTES);
    return;
  }
  if (type == 1) { // fade
    for (size_t i = 0; i < LCD_W * LCD_H; i++) g_imgbuf[i] = blend565(g_frombuf[i], g_tobuf[i], progress);
    return;
  }
  if (type == 2) { // push from right
    int shift = (LCD_W * (255 - progress)) / 255;
    for (int y = 0; y < LCD_H; y++) {
      for (int x = 0; x < LCD_W; x++) {
        int src_to = x - shift;
        int src_from = x + (LCD_W - shift);
        if (src_to >= 0) g_imgbuf[y * LCD_W + x] = g_tobuf[y * LCD_W + src_to];
        else g_imgbuf[y * LCD_W + x] = g_frombuf[y * LCD_W + src_from];
      }
    }
    return;
  }
  if (type == 3) { // circular reveal
    int cx = LCD_W / 2, cy = LCD_H / 2;
    int r = (340 * progress) / 255;
    int soft = 20;
    int r0 = r - soft;
    int r2 = r * r;
    int r02 = r0 * r0;
    for (int y = 0; y < LCD_H; y++) {
      int dy = y - cy;
      for (int x = 0; x < LCD_W; x++) {
        int dx = x - cx;
        size_t i = y * LCD_W + x;
        int d2 = dx * dx + dy * dy;
        if (d2 <= r02) g_imgbuf[i] = g_tobuf[i];
        else if (d2 >= r2) g_imgbuf[i] = g_frombuf[i];
        else {
          uint8_t t = (uint8_t)((r2 - d2) * 255 / max(1, r2 - r02));
          g_imgbuf[i] = blend565(g_frombuf[i], g_tobuf[i], t);
        }
      }
    }
    return;
  }
  if (type == 4) { // soft wipe
    int edge = (LCD_W * progress) / 255;
    const int soft = 56;
    for (int y = 0; y < LCD_H; y++) {
      for (int x = 0; x < LCD_W; x++) {
        size_t i = y * LCD_W + x;
        int d = edge - x;
        if (d >= soft) g_imgbuf[i] = g_tobuf[i];
        else if (d <= 0) g_imgbuf[i] = g_frombuf[i];
        else g_imgbuf[i] = blend565(g_frombuf[i], g_tobuf[i], (uint8_t)(d * 255 / soft));
      }
    }
    return;
  }
  if (type == 5) { // zoom fade
    uint8_t fade = progress < 36 ? 0 : (uint8_t)((progress - 36) * 255 / 219);
    int scale = 236 + (19 * progress) / 255; // 92.5% -> 100%
    int cx = LCD_W / 2, cy = LCD_H / 2;
    for (int y = 0; y < LCD_H; y++) {
      int sy = cy + ((y - cy) * 255) / scale;
      if (sy < 0) sy = 0;
      if (sy >= LCD_H) sy = LCD_H - 1;
      for (int x = 0; x < LCD_W; x++) {
        int sx = cx + ((x - cx) * 255) / scale;
        if (sx < 0) sx = 0;
        if (sx >= LCD_W) sx = LCD_W - 1;
        size_t i = y * LCD_W + x;
        g_imgbuf[i] = blend565(g_frombuf[i], g_tobuf[sy * LCD_W + sx], fade);
      }
    }
    return;
  }
  if (type == 6) { // vertical blinds
    const int stripe = 40;
    int open = (stripe * progress) / 255;
    for (int y = 0; y < LCD_H; y++) {
      for (int x = 0; x < LCD_W; x++) {
        size_t i = y * LCD_W + x;
        int local = x % stripe;
        g_imgbuf[i] = (local < open) ? g_tobuf[i] : g_frombuf[i];
      }
    }
    return;
  }
  if (type == 7) { // split from center
    int half = (LCD_W / 2 * progress) / 255;
    int left = LCD_W / 2 - half;
    int right = LCD_W / 2 + half;
    for (int y = 0; y < LCD_H; y++) {
      for (int x = 0; x < LCD_W; x++) {
        size_t i = y * LCD_W + x;
        g_imgbuf[i] = (x >= left && x <= right) ? g_tobuf[i] : g_frombuf[i];
      }
    }
  }
}

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

// ============================================================================
// FX-движок: срежиссированные сцены поверх ЛЮБОГО значка.
// Значок = картинка с платы (.jpg/.bin) или вшитый BMW-логотип (по умолчанию).
// fx_prepare() грузит картинку в слой g_fxlogo и один раз анализирует её:
// яркие точки (для частиц) и внешний контур-силуэт (для кометы).
// Сцена в сценарии: "FX:<эффект>" или "FX:<эффект>:<файл-картинки>".
// ============================================================================
extern const lv_img_dsc_t bmw_logo;

static uint16_t *g_fxlogo = nullptr;         // слой значка 480x480 (PSRAM)
static String    g_fx_loaded = "\x01";       // что загружено (невалидно -> перезагрузка)
static uint8_t   g_fx_vlogo_sel = 0;         // выбранный векторный логотип (0=@bmw,1=@toyota)

struct PfxTarget { uint16_t x, y, c; };
#define PFX_N 1400
static PfxTarget *g_pfx = nullptr;
static int g_pfx_n = 0;

#define CT_N 720                              // контур: точка на каждые 0.5 градуса
static int16_t g_ct_x[CT_N], g_ct_y[CT_N];    // -1 = на этом луче контура нет

static inline const uint16_t *fx_logo_px() {
  return g_fxlogo ? g_fxlogo : (const uint16_t *)bmw_logo.data;
}

static inline uint16_t scale565(uint16_t c, uint8_t k) {  // яркость 0..255
  uint32_t r = ((c >> 11) & 31) * k / 255;
  uint32_t g = ((c >> 5) & 63) * k / 255;
  uint32_t b = (c & 31) * k / 255;
  return (uint16_t)((r << 11) | (g << 5) | b);
}
static inline int bright565(uint16_t c) {     // «яркость» 0..187
  return ((c >> 11) & 31) * 2 + ((c >> 5) & 63) + (c & 31) * 2;
}
static inline uint32_t fxrand(uint32_t s) { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return s; }

// --- анализ 1: яркие точки значка (reservoir sampling для равномерности) ---
static void pfx_build() {
  if (!g_pfx)
    g_pfx = (PfxTarget *)heap_caps_malloc(PFX_N * sizeof(PfxTarget), MALLOC_CAP_SPIRAM);
  g_pfx_n = 0;
  if (!g_pfx) return;
  const uint16_t *px = fx_logo_px();
  uint32_t rnd = 0xA5F15EED;
  int seen = 0;
  for (int y = 0; y < LCD_H; y += 3) {
    for (int x = 0; x < LCD_W; x += 3) {
      uint16_t c = px[(size_t)y * LCD_W + x];
      if (bright565(c) < 34) continue;         // фон/чёрное пропускаем
      seen++;
      rnd = rnd * 1664525u + 1013904223u;
      if (g_pfx_n < PFX_N) {
        g_pfx[g_pfx_n++] = { (uint16_t)x, (uint16_t)y, c };
      } else {
        uint32_t j = rnd % (uint32_t)seen;
        if (j < PFX_N) g_pfx[j] = { (uint16_t)x, (uint16_t)y, c };
      }
    }
  }
}

// --- анализ 2: внешний контур-силуэт (луч из центра на каждый угол) ---
static void contour_build() {
  const uint16_t *px = fx_logo_px();
  for (int a = 0; a < CT_N; a++) {
    float th = (float)a * (6.2831853f / CT_N);
    float cs = cosf(th), sn = sinf(th);
    g_ct_x[a] = -1; g_ct_y[a] = -1;
    for (int r = 236; r >= 8; r--) {           // снаружи внутрь до первой яркой точки
      int x = 240 + (int)(cs * (float)r), y = 240 + (int)(sn * (float)r);
      if (bright565(px[(size_t)y * LCD_W + x]) >= 34) {
        g_ct_x[a] = (int16_t)x; g_ct_y[a] = (int16_t)y;
        break;
      }
    }
  }
}

// загрузить значок сцены + проанализировать (один раз на смену картинки)
static void fx_prepare(const String &img) {
  if (img.startsWith("@")) {                 // векторный логотип: битмап не нужен
    if (img == "@toyota") g_fx_vlogo_sel = 1;
    else if (img == "@audi") g_fx_vlogo_sel = 2;
    else if (img == "@mercedes") g_fx_vlogo_sel = 3;
    else if (img == "@tesla") g_fx_vlogo_sel = 4;
    else g_fx_vlogo_sel = 0;
    return;
  }
  if (img == g_fx_loaded && g_fxlogo) return;
  if (!g_fxlogo)
    g_fxlogo = (uint16_t *)heap_caps_malloc(IMG_BYTES, MALLOC_CAP_SPIRAM);
  if (g_fxlogo) {
    bool ok = false;
    if (img.length()) ok = load_media_to_buffer(img.c_str(), g_fxlogo);
    if (!ok) memcpy(g_fxlogo, bmw_logo.data, IMG_BYTES);  // фолбэк: вшитый BMW
  }
  g_fx_loaded = img;
  pfx_build();
  contour_build();
  Serial.printf("fx prepare: '%s' -> %d точек\n", img.c_str(), g_pfx_n);
}

static uint8_t fx_id(const String &s) {
  String n = s;
  n.toLowerCase();
  if (n == "comet") return 7;
  if (n == "holo" || n == "hologram") return 8;
  if (n == "vdraw") return 9;                  // векторное рисование
  if (n == "vkin") return 10;                  // кинетическая сборка
  if (n == "vportal") return 11;
  if (n == "vblade") return 12;
  if (n == "vneon") return 13;
  if (n == "vorbit") return 14;
  if (n == "vprism") return 15;
  return 6;                                    // particles и все старые имена
}

static inline void pfx_dot(uint16_t *dst, int X, int Y, uint16_t c) {
  if (X < 1 || X >= LCD_W - 1 || Y < 1 || Y >= LCD_H - 1) return;
  size_t i = (size_t)Y * LCD_W + X;
  dst[i] = c; dst[i + 1] = c;
  dst[i + LCD_W] = c; dst[i + LCD_W + 1] = c;
  uint16_t halo = scale565(c, 90);               // лёгкое свечение по краям
  dst[i - 1] = halo; dst[i + 2] = halo;
  dst[i - LCD_W] = halo; dst[i + LCD_W * 2] = halo;
}

// ---------- сцена 6: частицы собираются в значок ----------
static void render_fx_particles(uint32_t age_ms, uint16_t *dst) {
  if (!g_fxlogo) fx_prepare("");
  const uint16_t *logo = fx_logo_px();
  if (!g_pfx_n) { memcpy(dst, logo, IMG_BYTES); return; }

  const uint32_t T = 7000;                       // цикл: сборка/фейд/лого/взрыв
  uint32_t t = age_ms % T;
  const float cx = 240.f, cy = 240.f;

  if (t < 3300) {
    // 0..2800 вихрь-сборка, 2800..3300 проявление настоящего лого
    memset(dst, 0, IMG_BYTES);
    float e = t < 2800 ? (float)t / 2800.f : 1.f;
    e = e * e * (3.f - 2.f * e);                 // smoothstep
    float inv = 1.f - e;
    for (int i = 0; i < g_pfx_n; i++) {
      uint32_t h = (uint32_t)(i + 1) * 2654435761u;
      float th0  = (float)(h & 1023) * 0.0061359f;          // 0..2pi
      float r0   = 252.f + (float)((h >> 10) & 255) * 0.42f; // спавн за краем
      float spin = 2.0f + (float)((h >> 18) & 127) * 0.011f; // личная закрутка
      float dxT = (float)g_pfx[i].x - cx, dyT = (float)g_pfx[i].y - cy;
      float rt  = sqrtf(dxT * dxT + dyT * dyT);
      float tht = atan2f(dyT, dxT);
      float th  = tht + inv * (th0 - tht) + spin * inv * inv;
      float r   = rt + (r0 - rt) * inv;
      int X = (int)(cx + cosf(th) * r);
      int Y = (int)(cy + sinf(th) * r);
      pfx_dot(dst, X, Y, scale565(g_pfx[i].c, (uint8_t)(90 + 165 * e)));
    }
    if (t >= 2800) {                             // кроссфейд в полный логотип
      uint8_t a = (uint8_t)((t - 2800) * 255 / 500);
      const size_t n = (size_t)LCD_W * LCD_H;
      for (size_t k = 0; k < n; k++) dst[k] = blend565(dst[k], logo[k], a);
    }
  } else if (t < 5300) {
    memcpy(dst, logo, IMG_BYTES);                // держим эмблему
  } else {
    // взрыв: лого быстро тает, частицы разлетаются с закруткой
    memset(dst, 0, IMG_BYTES);
    float e = (float)(t - 5300) / 1700.f;
    e = e * e * (3.f - 2.f * e);
    uint8_t fade = (uint8_t)(255.f * (1.f - e));
    for (int i = 0; i < g_pfx_n; i++) {
      uint32_t h = (uint32_t)(i + 1) * 2654435761u;
      float r0 = 300.f + (float)((h >> 10) & 255) * 0.5f;
      float dxT = (float)g_pfx[i].x - cx, dyT = (float)g_pfx[i].y - cy;
      float rt  = sqrtf(dxT * dxT + dyT * dyT);
      float tht = atan2f(dyT, dxT);
      float th  = tht + 1.7f * e * e;
      float r   = rt + (r0 - rt) * e * e;
      int X = (int)(cx + cosf(th) * r);
      int Y = (int)(cy + sinf(th) * r);
      pfx_dot(dst, X, Y, scale565(g_pfx[i].c, fade));
    }
    if (t < 5300 + 350) {                        // первые мгновения — лого тает
      uint8_t a = (uint8_t)(255 - (t - 5300) * 255 / 350);
      const size_t n = (size_t)LCD_W * LCD_H;
      for (size_t k = 0; k < n; k++) dst[k] = blend565(dst[k], logo[k], a);
    }
  }
}

// ---------- сцена 7: неоновая комета обводит контур значка ----------
static void render_fx_comet(uint32_t age_ms, uint16_t *dst) {
  if (!g_fxlogo) fx_prepare("");
  const uint16_t *logo = fx_logo_px();
  const uint32_t T = 7000;
  uint32_t t = age_ms % T;
  const uint16_t NEON  = rgb565(70, 190, 255);   // электрик-синий
  const uint16_t NEON2 = rgb565(170, 235, 255);  // почти белое ядро
  const size_t NPX = (size_t)LCD_W * LCD_H;

  if (t < 3400) {
    // комета бежит по контуру, оставляя неоновый след
    memset(dst, 0, IMG_BYTES);
    float e = (float)t / 3400.f;
    e = e * e * (3.f - 2.f * e);
    int head = (int)(e * CT_N);
    for (int k = 0; k < head; k++) {
      if (g_ct_x[k] < 0) continue;
      int back = head - k;                       // насколько давно прорисовано
      uint8_t br = back < 70 ? (uint8_t)(255 - back) : 175;
      pfx_dot(dst, g_ct_x[k], g_ct_y[k], scale565(NEON, br));
    }
    int hi = head - 1;
    if (hi >= 0 && g_ct_x[hi] >= 0) {            // светящаяся голова
      int X = g_ct_x[hi], Y = g_ct_y[hi];
      for (int dy = -3; dy <= 3; dy++)
        for (int dx = -3; dx <= 3; dx++) {
          int d2 = dx * dx + dy * dy;
          if (d2 > 10) continue;
          int xx = X + dx, yy = Y + dy;
          if (xx < 0 || xx >= LCD_W || yy < 0 || yy >= LCD_H) continue;
          dst[(size_t)yy * LCD_W + xx] = d2 <= 2 ? 0xFFFF : NEON2;
        }
    }
  } else if (t < 3900) {
    // контур замкнулся: вспышка и проявление значка
    uint8_t a = (uint8_t)((t - 3400) * 255 / 500);
    for (size_t k = 0; k < NPX; k++) dst[k] = scale565(logo[k], a);
    if (t < 3560) {                              // короткая белая вспышка
      uint8_t w = (uint8_t)((3560 - t) * 190 / 160);
      for (size_t k = 0; k < NPX; k++) dst[k] = blend565(dst[k], 0xFFFF, w);
    }
    uint8_t cb = (uint8_t)(255 - a);             // неон догорает
    for (int k = 0; k < CT_N; k++)
      if (g_ct_x[k] >= 0) pfx_dot(dst, g_ct_x[k], g_ct_y[k], scale565(NEON, cb));
  } else if (t < 5900) {
    memcpy(dst, logo, IMG_BYTES);                // держим значок
  } else {
    uint8_t f = (uint8_t)(255 - (t - 5900) * 255 / 1100);
    for (size_t k = 0; k < NPX; k++) dst[k] = scale565(logo[k], f);
  }
}

// ---------- сцена 8: голограмма (скан-материализация с глитчем) ----------
static void render_fx_holo(uint32_t age_ms, uint16_t *dst) {
  if (!g_fxlogo) fx_prepare("");
  const uint16_t *logo = fx_logo_px();
  const uint32_t T = 6500;
  uint32_t t = age_ms % T;
  const uint16_t CYAN = rgb565(90, 230, 255);
  uint32_t seed = t * 2654435761u;

  // строка значка со сдвигом и яркостью (сдвиг — «дрожание голограммы»)
  auto row_copy = [&](int y, int shift, uint8_t br) {
    uint16_t *d = dst + (size_t)y * LCD_W;
    const uint16_t *s = logo + (size_t)y * LCD_W;
    if (shift == 0 && br == 255) { memcpy(d, s, LCD_W * 2); return; }
    for (int x = 0; x < LCD_W; x++) {
      int sx = x - shift;
      d[x] = (sx >= 0 && sx < LCD_W)
                 ? (br == 255 ? s[sx] : scale565(s[sx], br)) : 0;
    }
  };
  auto black_row_sparks = [&](int y) {
    memset(dst + (size_t)y * LCD_W, 0, LCD_W * 2);
    uint32_t r = fxrand(seed ^ (uint32_t)(y * 0x9E3779B9));
    if ((r & 0xFF) < 10) {                       // редкие «искры» над сканлайном
      int x = (int)(r >> 8) % LCD_W;
      dst[(size_t)y * LCD_W + x] = scale565(CYAN, 120 + (r & 63));
    }
  };
  auto glow_line = [&](int sl) {
    for (int y = sl - 4; y <= sl + 4; y++) {
      if (y < 0 || y >= LCD_H) continue;
      uint8_t k = (uint8_t)(255 - abs(y - sl) * 52);
      uint16_t c = scale565(CYAN, k);
      uint16_t *d = dst + (size_t)y * LCD_W;
      for (int x = 0; x < LCD_W; x++) d[x] = c;
    }
  };

  if (t < 2600) {
    // материализация снизу вверх
    float e = (float)t / 2600.f;
    e = e * e * (3.f - 2.f * e);
    int sl = LCD_H - 1 - (int)(e * (LCD_H - 1));
    for (int y = 0; y < LCD_H; y++) {
      if (y > sl + 4) {
        int dist = y - sl;
        int amp = dist < 70 ? (70 - dist) / 14 : 0;    // дрожь гаснет вниз
        int shift = amp ? ((int)(fxrand(seed + y * 31) & 7) - 3) * amp / 3 : 0;
        uint8_t br = dist < 40 ? (uint8_t)(200 + dist) : 255;
        row_copy(y, shift, br > 255 ? 255 : br);
      } else if (y >= sl - 4) {
        // glow_line нарисует
      } else {
        black_row_sparks(y);
      }
    }
    glow_line(sl);
  } else if (t < 4800) {
    // значок держится, изредка «глитчует»
    memcpy(dst, logo, IMG_BYTES);
    uint32_t g = (t - 2600) % 750;
    if (g < 90) {                                 // короткий глитч-бёрст
      uint32_t burst = fxrand((uint32_t)((t - 2600) / 750) * 0x85EBCA6B + 7u);
      int y0 = (int)(burst % (LCD_H - 60));
      for (int y = y0; y < y0 + 50; y++) {
        int shift = ((int)(fxrand(burst + y) & 15) - 7);
        row_copy(y, shift, 235);
      }
    }
  } else {
    // растворение сверху вниз
    float e = (float)(t - 4800) / 1700.f;
    e = e * e * (3.f - 2.f * e);
    int sl = (int)(e * (LCD_H - 1));
    for (int y = 0; y < LCD_H; y++) {
      if (y < sl - 4) black_row_sparks(y);
      else if (y > sl + 4) row_copy(y, 0, 255);
    }
    glow_line(sl);
  }
}

// ============================================================================
// Векторный движок: логотип = список форм, анимации двигают формы по-отдельности.
// Рендер скан-спанами (аналитические пересечения строк) — быстро и без лесенки
// на горизонтальных краях (дробные концы спанов сглаживаются).
// ============================================================================
#define C565(r, g, b) ((uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | ((b) >> 3)))

enum : uint8_t { VS_RING = 0, VS_PIE = 1, VS_ELLR = 2, VS_LINE = 3, VS_CQUAD = 4, VS_POLY = 5 };
struct VShape {
  uint8_t type;
  int16_t cx, cy;      // центр формы
  int16_t p0, p1, p2;  // RING: rout,rin,-  PIE: r,-,-  ELLR: rx,ry,толщина
  int16_t a0, span;    // PIE: старт/размах в градусах
  uint16_t color;
};

// Toyota из пользовательского SVG: единый even-odd силуэт официальной эмблемы
static const VShape VL_TOYOTA[] = {
  { VS_POLY, 240, 240, 9, 0, 0, 0, 0, C565(214, 30, 40) },
};
struct VLogo { const VShape *s; uint8_t n; };

// произвольные контуры (из SVG через tools/svg_to_vlogo.py)
#include "vlogo_data.h"
struct VPoly { const int16_t *pts; const uint16_t *ends; uint8_t ncont; uint16_t npts; };
static const VPoly VPOLYS[] = {
  { VP_TESLA_pts, VP_TESLA_ends, 10, 282 },        // 0: Tesla T + надпись
  { VP_MB_STAR_pts, VP_MB_STAR_ends, 1, 6 },       // 1: звезда Mercedes
  { VP_BMW_RIMOUT_pts, VP_BMW_RIMOUT_ends, 2, 196 }, // 2: BMW внешний обод
  { VP_BMW_BODY_pts, VP_BMW_BODY_ends, 2, 154 },     // 3: BMW тонкое тёмное кольцо
  { VP_BMW_RIMIN_pts, VP_BMW_RIMIN_ends, 2, 112 },   // 4: BMW тёмная полоса
  { VP_BMW_DISC_pts, VP_BMW_DISC_ends, 1, 56 },      // 5: BMW диск (синяя основа)
  { VP_BMW_QUADS_pts, VP_BMW_QUADS_ends, 2, 36 },    // 6: BMW белые сектора
  { VP_BMW_TEXT_pts, VP_BMW_TEXT_ends, 3, 105 },     // 7: BMW буквы
  { VP_BMW_HOLES_pts, VP_BMW_HOLES_ends, 2, 36 },    // 8: BMW дырки буквы B
  { VP_TOYOTA_pts, VP_TOYOTA_ends, 6, 374 },         // 9: Toyota (цельный силуэт)
};
#define POLY_MAX_PTS 400
// BMW из пользовательского SVG: настоящий роундел С БУКВАМИ, 7 деталей
static const VShape VL_BMW[] = {
  { VS_POLY, 240, 240, 2, 0, 0, 0, 0, C565(206, 210, 218) },  // внешний обод
  { VS_POLY, 240, 240, 3, 0, 0, 0, 0, C565(30, 33, 39) },     // тонкое кольцо
  { VS_POLY, 240, 240, 4, 0, 0, 0, 0, C565(30, 33, 39) },     // полоса с буквами
  { VS_POLY, 240, 240, 5, 0, 0, 0, 0, C565(60, 140, 210) },   // диск (синяя основа)
  { VS_POLY, 240, 240, 6, 0, 0, 0, 0, C565(245, 247, 250) },  // белые сектора
  { VS_POLY, 240, 240, 7, 0, 0, 0, 0, C565(222, 226, 233) },  // буквы BMW
  { VS_POLY, 240, 240, 8, 0, 0, 0, 0, C565(30, 33, 39) },     // дырки буквы B
};
static const VShape VL_AUDI[] = {         // кольца Audi — КРУГИ, перекрываются
  { VS_ELLR, 123, 240, 60, 60, 12, 0, 0, C565(220, 224, 230) },
  { VS_ELLR, 201, 240, 60, 60, 12, 0, 0, C565(220, 224, 230) },
  { VS_ELLR, 279, 240, 60, 60, 12, 0, 0, C565(220, 224, 230) },
  { VS_ELLR, 357, 240, 60, 60, 12, 0, 0, C565(220, 224, 230) },
};
static const VShape VL_MERCEDES[] = {     // кольцо + точная трёхлучевая звезда
  { VS_RING, 240, 240, 206, 188, 0, 0, 0, C565(220, 224, 230) },
  { VS_POLY, 240, 240, 1, 0, 0, 0, 0, C565(220, 224, 230) },     // p0 = индекс в VPOLYS
};
static const VShape VL_TESLA[] = {        // настоящий T + надпись из офиц. SVG
  { VS_POLY, 240, 240, 0, 0, 0, 0, 0, C565(226, 26, 44) },
};
static const VLogo VLOGOS[] = {
  { VL_BMW, 7 },
  { VL_TOYOTA, 1 },
  { VL_AUDI, 4 },
  { VL_MERCEDES, 2 },
  { VL_TESLA, 1 },
};

// трансформация формы в кадре анимации
struct VX { float dx, dy, rot, scale; uint8_t alpha; float sweep; };

// спан с дробными концами (горизонтальное сглаживание) и угловой маской
static void vspan(uint16_t *dst, int y, float xa, float xb, uint16_t color,
                  uint8_t alpha, bool ang_mask, float scx, float scy,
                  float aa0, float alim) {
  if (xb <= xa || y < 0 || y >= LCD_H) return;
  if (xa < 0) xa = 0;
  if (xb > LCD_W) xb = LCD_W;
  uint16_t *row = dst + (size_t)y * LCD_W;
  int ia = (int)ceilf(xa), ib = (int)floorf(xb);
  auto put = [&](int x, uint8_t a) {
    if (x < 0 || x >= LCD_W || !a) return;
    if (ang_mask) {
      float ang = atan2f((float)y - scy, (float)x - scx) - aa0;
      while (ang < 0) ang += 6.2831853f;
      if (ang > alim) return;
    }
    row[x] = a >= 250 ? color : blend565(row[x], color, a);
  };
  if (ia > 0 && ia - 1 >= (int)xa)
    put(ia - 1, (uint8_t)((float)ia - xa) * 0 + (uint8_t)(((float)ia - xa) * alpha));
  for (int x = ia; x < ib; x++) put(x, alpha);
  if (ib < LCD_W && (float)ib < xb)
    put(ib, (uint8_t)((xb - (float)ib) * alpha));
}

// пересечение строки с половиной плоскости (луч клина сектора)
static inline void vclip_halfplane(float nx, float ny, float py, float &xa, float &xb) {
  // n·(x,py) >= 0
  if (fabsf(nx) < 1e-5f) {
    if (ny * py < 0) { xb = xa - 1; }        // вся строка мимо
    return;
  }
  float xi = -ny * py / nx;
  if (nx > 0) { if (xi > xa) xa = xi; }
  else        { if (xi < xb) xb = xi; }
}

static void vshape_render(uint16_t *dst, const VShape &s, const VX &vx) {
  if (vx.alpha == 0 || vx.sweep <= 0.001f) return;
  float sc = vx.scale <= 0.f ? 1.f : vx.scale;
  float cx = (float)s.cx + vx.dx, cy = (float)s.cy + vx.dy;
  float sweep_rad = vx.sweep * 6.2831853f;
  bool part = vx.sweep < 0.999f;

  if (s.type == VS_POLY) {
    // произвольный контур: скан-заливка even-odd (дырки работают сами)
    const VPoly &P = VPOLYS[s.p0];
    if (P.npts > POLY_MAX_PTS) return;
    static float txp[POLY_MAX_PTS * 2];
    float c = cosf(vx.rot), sn = sinf(vx.rot);
    float miny = 1e9f, maxy = -1e9f;
    for (int i = 0; i < P.npts; i++) {
      float px = ((float)P.pts[i * 2] - (float)s.cx) * sc;
      float py = ((float)P.pts[i * 2 + 1] - (float)s.cy) * sc;
      float X = cx + px * c - py * sn;
      float Y = cy + px * sn + py * c;
      txp[i * 2] = X; txp[i * 2 + 1] = Y;
      if (Y < miny) miny = Y;
      if (Y > maxy) maxy = Y;
    }
    int y0 = miny < 0.f ? 0 : (int)miny;
    int y1 = maxy >= (float)LCD_H ? LCD_H - 1 : (int)ceilf(maxy);
    float xs[24];
    for (int y = y0; y <= y1; y++) {
      float fy = (float)y + 0.5f;
      int nx = 0, start = 0;
      for (int ci = 0; ci < P.ncont; ci++) {
        int end = P.ends[ci];
        for (int i = start; i < end; i++) {
          int j = (i + 1 == end) ? start : i + 1;
          float ya = txp[i * 2 + 1], yb = txp[j * 2 + 1];
          if ((ya <= fy) == (yb <= fy)) continue;
          float t = (fy - ya) / (yb - ya);
          if (nx < 24) xs[nx++] = txp[i * 2] + (txp[j * 2] - txp[i * 2]) * t;
        }
        start = end;
      }
      for (int i = 1; i < nx; i++) {                     // сортировка вставками
        float v = xs[i]; int j = i - 1;
        while (j >= 0 && xs[j] > v) { xs[j + 1] = xs[j]; j--; }
        xs[j + 1] = v;
      }
      // угловая обводка от «12 часов» — как у колец (шторка сверху выглядела криво)
      for (int i = 0; i + 1 < nx; i += 2)
        vspan(dst, y, xs[i], xs[i + 1], s.color, vx.alpha, part, cx, cy,
              -1.5707963f + vx.rot, sweep_rad);
    }
    return;
  }

  if (s.type == VS_LINE) {
    float x0 = (float)s.cx, y0 = (float)s.cy;
    float x1 = (float)s.p0, y1 = (float)s.p1;
    float mx = (x0 + x1) * 0.5f, my = (y0 + y1) * 0.5f;
    auto tx = [&](float x, float y, float &ox, float &oy) {
      float px = (x - mx) * sc, py = (y - my) * sc;
      float c = cosf(vx.rot), sn = sinf(vx.rot);
      ox = mx + px * c - py * sn + vx.dx;
      oy = my + px * sn + py * c + vx.dy;
    };
    tx(x0, y0, x0, y0);
    tx(x1, y1, x1, y1);
    if (part) {
      x1 = x0 + (x1 - x0) * vx.sweep;
      y1 = y0 + (y1 - y0) * vx.sweep;
    }
    float dx = x1 - x0, dy = y1 - y0;
    float len2 = dx * dx + dy * dy;
    if (len2 < 0.01f) return;
    float r = (float)s.p2 * sc * 0.5f;
    int xmin = (int)floorf((x0 < x1 ? x0 : x1) - r - 1.f);
    int xmax = (int)ceilf ((x0 > x1 ? x0 : x1) + r + 1.f);
    int ymin = (int)floorf((y0 < y1 ? y0 : y1) - r - 1.f);
    int ymax = (int)ceilf ((y0 > y1 ? y0 : y1) + r + 1.f);
    if (xmin < 0) xmin = 0; if (xmax >= LCD_W) xmax = LCD_W - 1;
    if (ymin < 0) ymin = 0; if (ymax >= LCD_H) ymax = LCD_H - 1;
    for (int y = ymin; y <= ymax; y++) {
      uint16_t *row = dst + (size_t)y * LCD_W;
      for (int x = xmin; x <= xmax; x++) {
        float px = (float)x - x0, py = (float)y - y0;
        float u = (px * dx + py * dy) / len2;
        if (u < 0.f) u = 0.f; else if (u > 1.f) u = 1.f;
        float qx = x0 + dx * u, qy = y0 + dy * u;
        float dist = sqrtf(((float)x - qx) * ((float)x - qx) + ((float)y - qy) * ((float)y - qy));
        float cov = r + 0.75f - dist;
        if (cov <= 0.f) continue;
        uint8_t a = cov >= 1.f ? vx.alpha : (uint8_t)(cov * (float)vx.alpha);
        row[x] = a >= 250 ? s.color : blend565(row[x], s.color, a);
      }
    }
    return;
  }

  if (s.type == VS_CQUAD) {
    float r = (float)s.p0 * sc;
    uint8_t qid = (uint8_t)s.p1;             // 0=top-left, 1=top-right, 2=bottom-left, 3=bottom-right
    bool right = (qid == 1 || qid == 3);
    bool bottom = (qid == 2 || qid == 3);
    int y0 = bottom ? (int)floorf(cy) : (int)floorf(cy - r);
    int y1 = bottom ? (int)ceilf(cy + r) : (int)ceilf(cy);
    if (part) {
      if (bottom) y1 = (int)ceilf(cy + r * vx.sweep);
      else y0 = (int)floorf(cy - r * vx.sweep);
    }
    for (int y = y0; y <= y1; y++) {
      float py = (float)y - cy;
      float qq = r * r - py * py;
      if (qq <= 0.f) continue;
      float half = sqrtf(qq);
      float xa = right ? cx : cx - half;
      float xb = right ? cx + half : cx;
      vspan(dst, y, xa, xb, s.color, vx.alpha, false, 0, 0, 0, 0);
    }
    return;
  }

  if (s.type == VS_RING || s.type == VS_PIE) {
    float ro = (float)s.p0 * sc;
    float ri = (s.type == VS_RING) ? (float)s.p1 * sc : 0.f;
    int y0 = (int)(cy - ro), y1 = (int)(cy + ro);
    // клин сектора (для PIE всегда, для RING при частичной обводке — углы от «верха»)
    float a0 = (s.type == VS_PIE) ? ((float)s.a0 * 0.0174533f + vx.rot) : (-1.5707963f + vx.rot);
    float alim = (s.type == VS_PIE) ? ((float)s.span * 0.0174533f * vx.sweep) : sweep_rad;
    bool wedge = (s.type == VS_PIE);
    float n1x = 0, n1y = 0, n2x = 0, n2y = 0;
    if (wedge) {                             // границы клина: два луча
      n1x = -sinf(a0);        n1y = cosf(a0);          // слева от первого луча
      float a2 = a0 + alim;
      n2x = sinf(a2);         n2y = -cosf(a2);         // справа от второго
    }
    for (int y = y0; y <= y1; y++) {
      float py = (float)y - cy;
      float q = ro * ro - py * py;
      if (q <= 0) continue;
      float half = sqrtf(q);
      float oxa = cx - half, oxb = cx + half;
      float ixa = 1.f, ixb = 0.f;
      if (ri > 0.f) {
        float qi = ri * ri - py * py;
        if (qi > 0) { float h2 = sqrtf(qi); ixa = cx - h2; ixb = cx + h2; }
      }
      auto emit = [&](float xa, float xb) {
        if (xb <= xa) return;
        if (wedge) {
          float lim = alim;
          if (lim >= 6.28f) { /* полный круг */ }
          else if (lim <= 3.1416f) {          // клин = пересечение полуплоскостей
            vclip_halfplane(n1x, n1y, py, xa, xb);
            vclip_halfplane(n2x, n2y, py, xa, xb);
            vspan(dst, y, xa, xb, s.color, vx.alpha, false, 0, 0, 0, 0);
            return;
          }
          // >180°: рисуем с угловой маской по пикселям
          vspan(dst, y, xa, xb, s.color, vx.alpha, true, cx, cy, a0, lim);
          return;
        }
        vspan(dst, y, xa, xb, s.color, vx.alpha, part, cx, cy, a0, sweep_rad);
      };
      if (ixb > ixa) {                       // кольцо: два спана вокруг дырки
        emit(oxa, ixa);
        emit(ixb, oxb);
      } else {
        emit(oxa, oxb);
      }
    }
  } else {                                   // VS_ELLR — эллипс-кольцо (с поворотом)
    float rx = (float)s.p0 * sc, ry = (float)s.p1 * sc;
    float rix = rx - (float)s.p2 * sc, riy = ry - (float)s.p2 * sc;
    float c = cosf(vx.rot), sn = sinf(vx.rot);
    // коэффициенты конік для внешнего и внутреннего эллипсов
    auto conic = [&](float RX, float RY, float &A, float &B, float &C) {
      A = c * c / (RX * RX) + sn * sn / (RY * RY);
      B = 2.f * c * sn * (1.f / (RX * RX) - 1.f / (RY * RY));
      C = sn * sn / (RX * RX) + c * c / (RY * RY);
    };
    float Ao, Bo, Co, Ai, Bi, Ci;
    conic(rx, ry, Ao, Bo, Co);
    conic(rix, riy, Ai, Bi, Ci);
    float R = rx > ry ? rx : ry;
    int y0 = (int)(cy - R), y1 = (int)(cy + R);
    float a0 = -1.5707963f;                  // обводка от «верха»
    for (int y = y0; y <= y1; y++) {
      float py = (float)y - cy;
      auto solve = [&](float A, float B, float C, float &xa, float &xb) -> bool {
        float b = B * py, cc = C * py * py - 1.f;
        float D = b * b - 4.f * A * cc;
        if (D <= 0) return false;
        float sd = sqrtf(D);
        xa = cx + (-b - sd) / (2.f * A);
        xb = cx + (-b + sd) / (2.f * A);
        return true;
      };
      float oxa, oxb, ixa2, ixb2;
      if (!solve(Ao, Bo, Co, oxa, oxb)) continue;
      bool inner = solve(Ai, Bi, Ci, ixa2, ixb2);
      auto emit = [&](float xa, float xb) {
        vspan(dst, y, xa, xb, s.color, vx.alpha, part, cx, cy, a0, sweep_rad);
      };
      if (inner) { emit(oxa, ixa2); emit(ixb2, oxb); }
      else emit(oxa, oxb);
    }
  }
}

static float ease_smooth01(float x) {
  if (x < 0) x = 0; if (x > 1) x = 1;
  return x * x * (3.f - 2.f * x);
}
static float ease_backout(float x) {         // с «пружинкой» в конце
  if (x < 0) x = 0; if (x > 1) x = 1;
  float c = 1.70158f, u = x - 1.f;
  return 1.f + u * u * ((c + 1.f) * u + c);
}

// ---------- сцена 9: векторное рисование (draw-on) ----------
static void render_fx_vdraw(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 7000;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  VX vx = { 0, 0, 0, 1, 255, 1 };
  if (t < 3400) {
    for (int i = 0; i < L.n; i++) {
      float st = (float)i * (2000.f / (float)L.n);   // формы включаются по очереди
      float e = ease_smooth01(((float)t - st) / 1400.f);
      if (e <= 0.f) continue;
      vx.sweep = e;
      vshape_render(dst, L.s[i], vx);
    }
  } else if (t < 5700) {
    for (int i = 0; i < L.n; i++) vshape_render(dst, L.s[i], vx);
  } else {
    vx.alpha = (uint8_t)(255 - (t - 5700) * 255 / 1300);
    for (int i = 0; i < L.n; i++) vshape_render(dst, L.s[i], vx);
  }
}

// ---------- сцена 10: кинетическая сборка ----------
static void render_fx_vkin(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 7000;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  for (int i = 0; i < L.n; i++) {
    uint32_t h = (uint32_t)(i + 1) * 2654435761u;
    float dirA = (float)(h & 255) * 0.0245437f;                  // откуда влетает
    float rotA = (((h >> 8) & 1) ? 1.f : -1.f) *
                 (1.5f + (float)((h >> 9) & 127) * 0.008f);      // своя закрутка
    VX vx = { 0, 0, 0, 1, 255, 1 };
    if (t < 2900) {
      float st = (float)i * 300.f;                               // стаггер деталей
      float e = ((float)t - st) / 1500.f;
      if (e <= 0.f) continue;
      float k = ease_backout(e);                                 // с овершутом
      float inv = 1.f - k;
      vx.dx = cosf(dirA) * 470.f * inv;
      vx.dy = sinf(dirA) * 470.f * inv;
      vx.rot = rotA * inv;
      vx.alpha = e < 0.12f ? (uint8_t)(e * 2100.f) : 255;
    } else if (t >= 5200) {
      float e = ease_smooth01((float)(t - 5200) / 1800.f);       // разлёт
      vx.dx = cosf(dirA) * 520.f * e * e;
      vx.dy = sinf(dirA) * 520.f * e * e;
      vx.rot = rotA * e;
      vx.alpha = (uint8_t)(255.f * (1.f - e));
    }
    vshape_render(dst, L.s[i], vx);
  }
}

static void vlogo_render(uint16_t *dst, const VLogo &L, uint8_t alpha,
                         float scale, float rot, float dx, float dy, float sweep = 1.f) {
  VX vx = { dx, dy, rot, scale, alpha, sweep };
  for (int i = 0; i < L.n; i++) vshape_render(dst, L.s[i], vx);
}

static void vglow_ring(uint16_t *dst, float r, uint16_t color, uint8_t alpha, float sweep, float rot = 0.f) {
  VShape ring = { VS_RING, 240, 240, (int16_t)r, (int16_t)(r - 4.f), 0, 0, 0, color };
  VX vx = { 0, 0, rot, 1, alpha, sweep };
  vshape_render(dst, ring, vx);
}

// луч: узкая полоса через экран. Спанами по строкам — трогаем только
// пиксели самой полосы (~7К), а не весь экран (230К). Было главной причиной лагов.
static void vbeam(uint16_t *dst, float ang, float off, uint16_t color, uint8_t alpha) {
  float ca = cosf(ang), sa = sinf(ang);
  float nx = -sa, ny = ca;
  const float thick = 7.f;
  for (int y = 0; y < LCD_H; y++) {
    float py = (float)y - 240.f;
    if (fabsf(nx) < 1e-4f) {                       // почти горизонтальный луч
      float d = fabsf(ny * py - off);
      if (d <= thick)
        vspan(dst, y, 0, LCD_W, color,
              (uint8_t)((1.f - d / thick) * (float)alpha), false, 0, 0, 0, 0);
      continue;
    }
    float xA = 240.f + (off - ny * py - thick) / nx;
    float xB = 240.f + (off - ny * py + thick) / nx;
    if (xB < xA) { float tmp = xA; xA = xB; xB = tmp; }
    float w = xB - xA;
    // мягкий край: широкий слабый спан + узкое яркое ядро
    vspan(dst, y, xA, xB, color, alpha / 3, false, 0, 0, 0, 0);
    vspan(dst, y, xA + w * 0.3f, xB - w * 0.3f, color, alpha, false, 0, 0, 0, 0);
  }
}

static void render_fx_vportal(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 6400;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  float u = (float)t / (float)T;
  const uint16_t blue = rgb565(80, 190, 255);
  const uint16_t white = rgb565(245, 250, 255);

  float spin = u * 6.2831853f * 2.1f;
  uint8_t portal = (uint8_t)(120 + 80 * (0.5f + 0.5f * sinf(u * 6.2831853f * 4.f)));
  vglow_ring(dst, 72.f + 10.f * sinf(spin), blue, 80, 0.72f, spin);
  vglow_ring(dst, 162.f, blue, portal, 0.82f, -spin * 0.45f);
  vglow_ring(dst, 206.f, white, 85, 0.55f, spin * 0.3f);

  float e;
  uint8_t alpha;
  float scale;
  float rot;
  if (t < 1800) {
    e = ease_backout((float)t / 1800.f);
    alpha = (uint8_t)(255.f * e);
    scale = 0.22f + 0.86f * e;
    rot = (1.f - e) * 2.2f;
  } else if (t < 5000) {
    e = (float)(t - 1800) / 3200.f;
    alpha = 255;
    scale = 1.f + 0.018f * sinf(e * 6.2831853f * 2.f);
    rot = 0.f;
  } else {
    e = ease_smooth01((float)(t - 5000) / 1400.f);
    alpha = (uint8_t)(255.f * (1.f - e));
    scale = 1.f - 0.78f * e;
    rot = -1.4f * e;
  }
  vlogo_render(dst, L, alpha, scale, rot, 0, 0);   // один рендер за кадр (был + призрак)

  if (t > 1550 && t < 2250) {
    uint8_t flash = (uint8_t)(180.f * (1.f - fabsf((float)t - 1900.f) / 350.f));
    if (flash > 0) vglow_ring(dst, 222.f, white, flash, 1.f, 0.f);
  }
}

static void render_fx_vblade(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 5600;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  const uint16_t blade = rgb565(210, 245, 255);
  const uint16_t blue = rgb565(50, 170, 255);

  for (int b = 0; b < 3; b++) {
    int bt = (int)t - 360 - b * 430;
    if (bt >= 0 && bt < 620) {
      float e = (float)bt / 620.f;
      float off = -330.f + 660.f * e;
      vbeam(dst, -0.72f + b * 0.32f, off, b == 1 ? blue : blade, (uint8_t)(180.f * (1.f - e)));
    }
  }

  for (int i = 0; i < L.n; i++) {
    uint32_t h = (uint32_t)(i + 7) * 2246822519u;
    float st = (float)i * (1700.f / (float)L.n);
    float eIn = ease_backout(((float)t - st) / 1250.f);
    VX vx = { 0, 0, 0, 1, 255, 1 };
    if (t < 3000) {
      if (eIn <= 0.f) continue;
      float inv = 1.f - eIn;
      float side = (h & 1) ? 1.f : -1.f;
      vx.dx = side * 380.f * inv;
      vx.dy = (((h >> 2) & 1) ? -1.f : 1.f) * 160.f * inv;
      vx.rot = side * inv * 0.9f;
      vx.alpha = eIn < 0.08f ? (uint8_t)(eIn * 3200.f) : 255;
      vx.sweep = eIn;
    } else if (t < 4550) {
      vx.alpha = 255;
    } else {
      float e = ease_smooth01((float)(t - 4550) / 1050.f);
      float side = (h & 1) ? -1.f : 1.f;
      vx.dx = side * 260.f * e * e;
      vx.dy = -260.f * e;
      vx.rot = side * 0.8f * e;
      vx.alpha = (uint8_t)(255.f * (1.f - e));
    }
    vshape_render(dst, L.s[i], vx);
  }
}

static void render_fx_vneon(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 5200;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  float u = (float)t / (float)T;
  float beat = 0.5f + 0.5f * sinf(u * 6.2831853f * 3.f);
  uint8_t glow = (uint8_t)(55 + 95 * beat);
  const uint16_t cyan = rgb565(75, 210, 255);
  const uint16_t white = rgb565(245, 250, 255);

  (void)glow;
  // неоновый пульс альфой одного рендера (двойной рендер лагал)
  vlogo_render(dst, L, (uint8_t)(190 + 65.f * beat), 1.f, 0, 0, 0);

  float a = u * 6.2831853f;
  for (int k = 0; k < 18; k++) {
    float kk = (float)k / 18.f;
    float th = a - kk * 0.55f;
    float r = 224.f - kk * 1.4f;
    int x = (int)(240.f + cosf(th) * r);
    int y = (int)(240.f + sinf(th) * r);
    uint8_t br = (uint8_t)(220.f * (1.f - kk));
    pfx_dot(dst, x, y, scale565(k < 4 ? white : cyan, br));
  }

  if ((t % 1700) < 240) {
    float e = (float)(t % 1700) / 240.f;
    vglow_ring(dst, 132.f + 90.f * e, cyan, (uint8_t)(150.f * (1.f - e)), 1.f, 0.f);
  }
}

static void render_fx_vorbit(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 6200;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  float u = (float)t / (float)T;
  const uint16_t cyan = rgb565(65, 205, 255);
  const uint16_t white = rgb565(245, 250, 255);

  for (int k = 0; k < 5; k++) {
    float th = u * 6.2831853f * (1.15f + k * 0.13f) + k * 1.2566f;
    float r = 118.f + k * 22.f + 8.f * sinf(u * 6.2831853f * 2.f + k);
    int x = (int)(240.f + cosf(th) * r);
    int y = (int)(240.f + sinf(th) * r);
    pfx_dot(dst, x, y, k & 1 ? white : cyan);
    vglow_ring(dst, r, k & 1 ? white : cyan, 28, 0.18f, th);
  }

  for (int i = 0; i < L.n; i++) {
    float st = (float)i * (1900.f / (float)L.n);
    float e = ease_backout(((float)t - st) / 1300.f);
    VX vx = { 0, 0, 0, 1, 255, 1 };
    if (t < 2800) {
      if (e <= 0.f) continue;
      float inv = 1.f - e;
      float th = (float)i * 2.39996f + u * 6.2831853f * 1.6f;
      vx.dx = cosf(th) * 170.f * inv;
      vx.dy = sinf(th) * 170.f * inv;
      vx.alpha = e < 0.1f ? (uint8_t)(e * 2550.f) : 255;
      vx.sweep = e;
    } else if (t > 5000) {
      float e2 = ease_smooth01((float)(t - 5000) / 1200.f);
      float th = (float)i * 2.39996f + e2 * 2.2f;
      vx.dx = cosf(th) * 210.f * e2;
      vx.dy = sinf(th) * 210.f * e2;
      vx.alpha = (uint8_t)(255.f * (1.f - e2));
      vx.sweep = 1.f - e2 * 0.55f;
    }
    vshape_render(dst, L.s[i], vx);
  }
}

static void render_fx_vprism(uint32_t age_ms, uint16_t *dst) {
  const VLogo &L = VLOGOS[g_fx_vlogo_sel];
  const uint32_t T = 5800;
  uint32_t t = age_ms % T;
  memset(dst, 0, IMG_BYTES);
  float u = (float)t / (float)T;
  const uint16_t cyan = rgb565(50, 190, 255);
  const uint16_t mag = rgb565(255, 70, 170);
  const uint16_t white = rgb565(245, 250, 255);

  for (int b = 0; b < 4; b++) {
    float phase = fmodf(u * 1.35f + b * 0.25f, 1.f);
    float off = -360.f + phase * 720.f;
    vbeam(dst, 0.55f + b * 0.38f, off, (b & 1) ? mag : cyan, 110);
  }

  if (t < 1800) {
    // вход: один призрак + основной (было три рендера — лагало)
    float e = ease_smooth01((float)t / 1800.f);
    vlogo_render(dst, L, (uint8_t)(110.f * e), 1.03f, 0, 8.f * (1.f - e), 0, e);
    vlogo_render(dst, L, (uint8_t)(255.f * e), 1.f, 0, 0, 0, e);
  } else if (t < 4550) {
    // держим: обычно ОДИН рендер; двойники — короткими глитч-вспышками
    uint32_t gph = (t - 1800) % 1400;
    if (gph < 220) {
      float wob = 1.f - (float)gph / 220.f;
      vlogo_render(dst, L, (uint8_t)(90.f * wob), 1.f, 0, -6.f * wob, 0);
      vlogo_render(dst, L, (uint8_t)(90.f * wob), 1.f, 0,  6.f * wob, 0);
    }
    vlogo_render(dst, L, 255, 1.f, 0, 0, 0);
  } else {
    // выход: один уходящий призрак + основной
    float e = ease_smooth01((float)(t - 4550) / 1250.f);
    vlogo_render(dst, L, (uint8_t)(110.f * (1.f - e)), 1.f, 0, 28.f * e, 0);
    vlogo_render(dst, L, (uint8_t)(255.f * (1.f - e)), 1.f, 0, 0, 0, 1.f - e * 0.25f);
    vglow_ring(dst, 160.f + 80.f * e, white, (uint8_t)(120.f * (1.f - e)), 1.f, 0);
  }
}

static void render_fx_frame(uint8_t fx, uint32_t age_ms, uint16_t *dst) {
  if (fx == 7) { render_fx_comet(age_ms, dst); return; }
  if (fx == 8) { render_fx_holo(age_ms, dst); return; }
  if (fx == 9) { render_fx_vdraw(age_ms, dst); return; }
  if (fx == 10) { render_fx_vkin(age_ms, dst); return; }
  if (fx == 11) { render_fx_vportal(age_ms, dst); return; }
  if (fx == 12) { render_fx_vblade(age_ms, dst); return; }
  if (fx == 13) { render_fx_vneon(age_ms, dst); return; }
  if (fx == 14) { render_fx_vorbit(age_ms, dst); return; }
  if (fx == 15) { render_fx_vprism(age_ms, dst); return; }
  render_fx_particles(age_ms, dst);
}

static uint8_t transition_id(const String &s) {
  if (s == "fade") return 1;
  if (s == "push") return 2;
  if (s == "slide") return 2;
  if (s == "circle") return 3;
  if (s == "wipe") return 4;
  if (s == "zoom") return 5;
  if (s == "blinds") return 6;
  if (s == "split") return 7;
  return 0;
}

static bool load_show_script() {
  g_show.clear();
  File f = LittleFS.open(MEDIA_DIR "/" SHOW_FILE, "r");
  if (!f) { g_show_loaded = false; return false; }
  String header = f.readStringUntil('\n');
  header.trim();
  if (header != "ZPL1") { f.close(); g_show_loaded = false; return false; }
  while (f.available() && g_show.size() < SHOW_MAX_SCENES) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (!line.length()) continue;
    int p1 = line.indexOf('|');
    int p2 = line.indexOf('|', p1 + 1);
    if (p1 <= 0 || p2 <= p1) continue;
    ShowScene sc;
    sc.file = line.substring(0, p1);
    // 2-е поле: <10 = число циклов динамики (0 = бесконечно), иначе мс статики
    uint32_t rawd = (uint32_t)line.substring(p1 + 1, p2).toInt();
    if (rawd < 10) {
      sc.loops = (uint8_t)rawd;
      sc.duration_ms = 0;
    } else {
      sc.loops = 1;
      sc.duration_ms = (uint16_t)(rawd < 500 ? 500 : (rawd > 60000 ? 60000 : rawd));
    }
    sc.transition = transition_id(line.substring(p2 + 1));
    sc.fx = 0;
    if (sc.file.startsWith("FX:") || sc.file.startsWith("fx:")) {
      // "FX:<эффект>" или "FX:<эффект>:<файл-значка>"
      String spec = sc.file.substring(3);
      int c = spec.indexOf(':');
      sc.fx = fx_id(c >= 0 ? spec.substring(0, c) : spec);
      sc.fx_img = c >= 0 ? spec.substring(c + 1) : "";
    }
    g_show.push_back(sc);
  }
  f.close();
  g_scene_idx = 0;
  g_show_loaded = !g_show.empty();
  g_transition_active = false;
  Serial.printf("show script: %u scene(s)\n", (unsigned)g_show.size());
  return g_show_loaded;
}

// длина одного цикла FX-сцены (мс) — для семантики «1 полный цикл -> некст»
static uint32_t fx_cycle_ms(uint8_t fx) {
  switch (fx) {
    case 6: return 7000;  case 7: return 7000;  case 8: return 6500;
    case 9: return 7000;  case 10: return 7000; case 11: return 6400;
    case 12: return 5600; case 13: return 5200; case 14: return 6200;
    case 15: return 5800;
  }
  return 6000;
}

// сколько сцена живёт на экране (статика — таймер, FX — циклы, 0x7FFFFFFF = «вечно»)
static uint32_t scene_len_ms(const ShowScene &sc) {
  if (sc.fx) {
    uint32_t c = fx_cycle_ms(sc.fx);
    return sc.loops ? (uint32_t)sc.loops * c : 0x7FFFFFFF;
  }
  return sc.duration_ms ? sc.duration_ms : 3000;
}

// первый кадр .mjpg-файла в буфер (для стартового кадра и переходов)
static bool mjpg_first_frame(const char *name, uint16_t *target) {
  char path[96];
  snprintf(path, sizeof(path), MEDIA_DIR "/%s", name);
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  uint8_t h[8];
  if (f.read(h, 8) != 8 || memcmp(h, "MJP1", 4) != 0) { f.close(); return false; }
  uint16_t n = h[4] | (h[5] << 8);
  uint8_t s4[4];
  if (!n || n > MJPG_MAX_FRAMES || f.read(s4, 4) != 4) { f.close(); return false; }
  uint32_t sz0 = (uint32_t)s4[0] | ((uint32_t)s4[1] << 8) |
                 ((uint32_t)s4[2] << 16) | ((uint32_t)s4[3] << 24);
  if (!sz0 || !ensure_jpeg_buf(sz0)) { f.close(); return false; }
  f.seek(8 + (size_t)n * 4);
  bool ok = f.read(g_jpegbuf, sz0) == sz0;
  f.close();
  return ok && decode_jpeg_ram_ex(g_jpegbuf, sz0, target, LCD_W, LCD_H, 0);
}

static bool show_file(const char *name);   // fwd (определена ниже)

// сцена появилась на экране: если это анимация — запустить её плеер и
// засечь конец N полных циклов (обрезанных циклов не бывает)
static void scene_launch_dynamic(size_t idx) {
  g_scene_anim_active = false;
  if (idx >= g_show.size()) return;
  ShowScene &sc = g_show[idx];
  if (sc.fx || !sc.file.endsWith(".mjpg")) return;   // FX/статика — по scene_len_ms
  if (show_file(sc.file.c_str())) {
    uint32_t d = g_anim_delay < 20 ? 20 : g_anim_delay;
    uint32_t cyc = (uint32_t)g_anim_nframes * d;
    if (cyc < 200) cyc = 200;
    g_scene_anim_active = true;
    g_scene_anim_end = sc.loops ? millis() + (uint32_t)sc.loops * cyc : 0xFFFFFFFFu;
  }
}

static bool start_scene(size_t idx, bool first) {
  if (!g_show_loaded || idx >= g_show.size()) return false;
  uint16_t *target = first ? g_imgbuf : g_tobuf;
  if (g_show[idx].fx) {
    fx_prepare(g_show[idx].fx_img);      // загрузить+проанализировать значок сцены
    render_fx_frame(g_show[idx].fx, 0, target);
  } else if (g_show[idx].file.endsWith(".mjpg")) {
    if (!mjpg_first_frame(g_show[idx].file.c_str(), target)) return false;
  } else if (!load_media_to_buffer(g_show[idx].file.c_str(), target)) {
    return false;
  }
  if (first) {
    blit_buffer();
    g_scene_started = millis();
    g_fx_last_frame = 0;
    scene_launch_dynamic(idx);
    return true;
  }
  memcpy(g_frombuf, g_imgbuf, IMG_BYTES);
  g_transition_type = g_show[idx].transition;
  g_transition_start = millis();
  g_transition_active = true;
  return true;
}

static uint32_t u32le(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static size_t mjpg_frame_offset(uint16_t idx) {
  size_t off = g_mjpg_data_start;
  for (uint16_t i = 0; i < idx; i++) off += g_mjpg_sizes[i];
  return off;
}

// Все mjpg-операции идут из g_mjpg_data (файл целиком в PSRAM, без FS).
// ГЛАВНЫЙ ПРИНЦИП: во время воспроизведения декода НЕТ. Все кадры
// распаковываются один раз здесь; плейбек — только копирование в экран.
static bool mjpg_preload_frames() {
  anim_cache_free();
  // 1) короткая анимация -> кэш в полном 480x480 (максимум качества)
  size_t total = (size_t)g_anim_nframes * IMG_BYTES;
  g_anim_cache = (uint16_t *)heap_caps_malloc(total, MALLOC_CAP_SPIRAM);
  if (g_anim_cache) {
    for (uint16_t i = 0; i < g_anim_nframes; i++) {
      uint16_t *dst = g_anim_cache + (size_t)i * LCD_W * LCD_H;
      memset(dst, 0, IMG_BYTES);
      if (!decode_jpeg_ram(g_mjpg_data + mjpg_frame_offset(i), g_mjpg_sizes[i], dst)) {
        anim_cache_free();
        return false;
      }
    }
    g_anim_cached_frames = g_anim_nframes;
    Serial.printf("mjpg: кэш FULL %u кадр(ов), %u байт\n",
                  (unsigned)g_anim_cached_frames, (unsigned)total);
    return true;
  }
  // 2) длинная -> кэш в 240x240 (влезает ~40 кадров), апскейл 2x при показе.
  //    Для GIF-контента потери незаметны: исходники обычно мельче 480.
  total = (size_t)g_anim_nframes * (240 * 240 * 2);
  g_anim_cache = (uint16_t *)heap_caps_malloc(total, MALLOC_CAP_SPIRAM);
  if (!g_anim_cache) {
    Serial.printf("mjpg: кэш не влез даже в 240 (%u кадров) -> стриминг\n",
                  (unsigned)g_anim_nframes);
    return false;
  }
  for (uint16_t i = 0; i < g_anim_nframes; i++) {
    uint16_t *dst = g_anim_cache + (size_t)i * 240 * 240;
    memset(dst, 0, 240 * 240 * 2);
    if (!decode_jpeg_ram_ex(g_mjpg_data + mjpg_frame_offset(i), g_mjpg_sizes[i],
                            dst, 240, 240, JPEG_SCALE_HALF)) {
      anim_cache_free();
      return false;
    }
  }
  g_anim_cache_half = true;
  g_anim_cached_frames = g_anim_nframes;
  Serial.printf("mjpg: кэш HALF %u кадр(ов), %u байт\n",
                (unsigned)g_anim_cached_frames, (unsigned)total);
  return true;
}

static bool mjpg_read_frame(uint16_t idx) {
  // кэш обрабатывается в anim_read_frame; здесь только стрим-фолбэк
  if (!g_mjpg_data || idx >= g_anim_nframes) return false;
  return decode_jpeg_ram(g_mjpg_data + mjpg_frame_offset(idx), g_mjpg_sizes[idx]);
}

// Быстрый стрим-показ для длинных анимаций (кэш не влез): полу-декод 240x240
// (в 2-3 раза быстрее полного) + 2x апскейл ПРЯМО в задний буфер панели +
// vsync-флип. Минус одно полное копирование против обычного пути -> ~20fps.
static bool mjpg_stream_show(uint16_t idx) {
  if (!g_mjpg_data || idx >= g_anim_nframes) return false;
  uint8_t *p = g_mjpg_data + mjpg_frame_offset(idx);
  size_t sz = g_mjpg_sizes[idx];
  if (!g_halfbuf)
    g_halfbuf = (uint16_t *)heap_caps_malloc(240 * 240 * 2, MALLOC_CAP_SPIRAM);
  uint16_t *fb = g_fbs[g_backfb];
  if (g_halfbuf &&
      decode_jpeg_ram_ex(p, sz, g_halfbuf, 240, 240, JPEG_SCALE_HALF)) {
    upscale2x_240(g_halfbuf, fb);
  } else if (!decode_jpeg_ram_ex(p, sz, fb, LCD_W, LCD_H, 0)) {
    return false;                        // фолбэк: полный декод сразу в буфер
  }
  esp_lcd_panel_draw_bitmap(g_panel, 0, 0, LCD_W, LCD_H, fb);
  g_backfb ^= 1;
  return true;
}

static bool anm_preload_frames() {
  anim_cache_free();
  size_t total = (size_t)g_anim_nframes * IMG_BYTES;
  g_anim_cache = (uint16_t *)heap_caps_malloc(total, MALLOC_CAP_SPIRAM);
  if (!g_anim_cache) {
    Serial.printf("anm cache: not enough PSRAM for %u frames (%u bytes)\n",
                  (unsigned)g_anim_nframes, (unsigned)total);
    return false;
  }
  g_anim_file.seek(8);
  bool ok = g_anim_file.read((uint8_t *)g_anim_cache, total) == total;
  if (!ok) {
    anim_cache_free();
    return false;
  }
  g_anim_cached_frames = g_anim_nframes;
  Serial.printf("anm cache: %u frame(s), %u bytes\n",
                (unsigned)g_anim_cached_frames, (unsigned)total);
  return true;
}

// прочитать кадр idx анимации в буфер (кэш в PSRAM — основной путь, без декода)
static bool anim_read_frame(uint16_t idx) {
  if (g_anim_cache && idx < g_anim_cached_frames) {
    if (g_anim_cache_half)
      upscale2x_240(g_anim_cache + (size_t)idx * 240 * 240, g_imgbuf);  // ~9мс
    else
      memcpy(g_imgbuf, g_anim_cache + (size_t)idx * LCD_W * LCD_H, IMG_BYTES);
    return true;
  }
  if (g_anim_mjpg) return mjpg_read_frame(idx);  // стрим из PSRAM, файл не нужен
  if (!g_anim_file) return false;
  g_anim_file.seek(8 + (size_t)idx * IMG_BYTES);
  return g_anim_file.read((uint8_t *)g_imgbuf, IMG_BYTES) == IMG_BYTES;
}

// показать присланный файл (.jpg/.bin — картинка, .mjpg/.anm — анимация).
// Вызывать только из главного потока (LVGL не потокобезопасен).
static bool show_file(const char *name) {
  char path[96];
  snprintf(path, sizeof(path), MEDIA_DIR "/%s", name);
  anim_stop();
  Serial.printf("show_file: %s\n", name);

  size_t n = strlen(name);
  bool is_anim = (n > 4 && strcmp(name + n - 4, ".anm") == 0);
  bool is_mjpg = (n > 5 && strcmp(name + n - 5, ".mjpg") == 0);
  bool is_jpg  = (n > 4 && strcmp(name + n - 4, ".jpg") == 0);
  bool is_gif  = (n > 4 && strcmp(name + n - 4, ".gif") == 0);

  if (is_jpg) {                          // сжатая картинка
    if (!decode_jpeg(path)) return false;
    blit_buffer();
    return true;
  }

  if (is_gif) {                          // нативный GIF: файл в PSRAM, декод в задаче
    File f = LittleFS.open(path, "r");
    if (!f) { Serial.println("gif: open file FAIL"); return false; }
    size_t sz = f.size();
    if (sz == 0 || sz > GIF_MAX_FILE) { Serial.printf("gif: bad size %u\n", (unsigned)sz); f.close(); return false; }
    g_gif_data = (uint8_t *)heap_caps_malloc(sz, MALLOC_CAP_SPIRAM);
    if (!g_gif_data) { Serial.println("gif: malloc FAIL"); f.close(); return false; }
    bool rd = f.read(g_gif_data, sz) == sz;
    f.close();
    if (!rd) { Serial.println("gif: read FAIL"); gif_unload(); return false; }
    Serial.printf("gif: file %u bytes, hdr %c%c%c%c%c%c\n", (unsigned)sz,
                  g_gif_data[0], g_gif_data[1], g_gif_data[2],
                  g_gif_data[3], g_gif_data[4], g_gif_data[5]);
    g_gif.begin(GIF_PALETTE_RGB565_LE);  // панель ест RGB565 little-endian
    if (!g_gif.open(g_gif_data, (int)sz, gif_draw_cb)) {
      Serial.printf("gif: open() FAIL, err=%d\n", g_gif.getLastError());
      gif_unload(); return false;
    }
    g_gif_open = true;
    size_t canvas_px = (size_t)g_gif.getCanvasWidth() * (size_t)g_gif.getCanvasHeight();
    size_t fb_sz = canvas_px * 3 + (size_t)g_gif.getCanvasWidth() * 2;
    g_gif_framebuf = (uint8_t *)heap_caps_malloc(fb_sz, MALLOC_CAP_SPIRAM);
    if (!g_gif_framebuf) {
      Serial.printf("gif: framebuf malloc FAIL (%u bytes)\n", (unsigned)fb_sz);
      gif_unload(); return false;
    }
    memset(g_gif_framebuf, 0, fb_sz);
    g_gif.setFrameBuf(g_gif_framebuf);
    g_gif.setDrawType(GIF_DRAW_COOKED);  // ...потом COOKED (порядок важен)
    g_gif_ox = (LCD_W - g_gif.getCanvasWidth()) / 2;
    g_gif_oy = (LCD_H - g_gif.getCanvasHeight()) / 2;
    memset(g_imgbuf, 0, IMG_BYTES);      // чёрная канва под первым кадром
    g_anim_active = true;                // блокирует слайдшоу/переходы, как раньше
    Serial.printf("gif: OK, canvas %dx%d, offset %d,%d -> task\n",
                  g_gif.getCanvasWidth(), g_gif.getCanvasHeight(), g_gif_ox, g_gif_oy);
    anim_task_start(ANIM_GIF);
    return true;
  }

  if (is_mjpg) {                         // motion-JPEG: основной формат анимаций
    File f = LittleFS.open(path, "r");
    if (!f) { Serial.println("mjpg: open FAIL"); return false; }
    size_t fsz = f.size();
    if (fsz < 12 || fsz > GIF_MAX_FILE) { Serial.printf("mjpg: bad size %u\n", (unsigned)fsz); f.close(); return false; }
    g_mjpg_data = (uint8_t *)heap_caps_malloc(fsz, MALLOC_CAP_SPIRAM);
    if (!g_mjpg_data) { Serial.println("mjpg: malloc FAIL"); f.close(); return false; }
    bool rd = f.read(g_mjpg_data, fsz) == fsz;
    f.close();
    if (!rd || memcmp(g_mjpg_data, "MJP1", 4) != 0) {
      Serial.println("mjpg: read/hdr FAIL");
      heap_caps_free(g_mjpg_data); g_mjpg_data = nullptr;
      return false;
    }
    g_anim_nframes = g_mjpg_data[4] | (g_mjpg_data[5] << 8);
    g_anim_delay   = g_mjpg_data[6] | (g_mjpg_data[7] << 8);
    g_mjpg_data_start = 8 + (size_t)g_anim_nframes * 4;
    if (g_anim_nframes == 0 || g_anim_nframes > MJPG_MAX_FRAMES ||
        g_mjpg_data_start > fsz) {
      Serial.printf("mjpg: bad header (n=%u)\n", (unsigned)g_anim_nframes);
      heap_caps_free(g_mjpg_data); g_mjpg_data = nullptr;
      return false;
    }
    size_t sum = g_mjpg_data_start;             // валидация таблицы размеров
    for (uint16_t i = 0; i < g_anim_nframes; i++) {
      g_mjpg_sizes[i] = u32le(g_mjpg_data + 8 + (size_t)i * 4);
      sum += g_mjpg_sizes[i];
    }
    if (sum > fsz) {
      Serial.println("mjpg: size table overflow");
      heap_caps_free(g_mjpg_data); g_mjpg_data = nullptr;
      return false;
    }
    g_anim_mjpg = true;
    bool cached = mjpg_preload_frames();        // кэш = идеально плавно
    if (cached) { heap_caps_free(g_mjpg_data); g_mjpg_data = nullptr; }
    // не влезло в кэш -> стриминг из PSRAM (~12fps, точный такт, без рывков)
    g_anim_idx = 0; g_anim_active = true;
    if (!anim_read_frame(0)) { anim_stop(); return false; }
    present_buffer_fast();
    Serial.printf("mjpg: %u frames, delay %u ms, %s\n", (unsigned)g_anim_nframes,
                  (unsigned)g_anim_delay, cached ? "cached" : "stream");
    anim_task_start(ANIM_RAW);
    return true;
  }

  if (is_anim) {
    g_anim_file = LittleFS.open(path, "r");
    if (!g_anim_file) return false;
    uint8_t h[8];
    if (g_anim_file.read(h, 8) != 8 || h[0] != 'A' || h[1] != 'N' || h[2] != 'M' || h[3] != '1') {
      g_anim_file.close(); return false;
    }
    g_anim_nframes = h[4] | (h[5] << 8);
    g_anim_delay   = h[6] | (h[7] << 8);
    if (g_anim_nframes == 0) { g_anim_file.close(); return false; }
    bool cached = anm_preload_frames();
    if (!cached) { g_anim_file.close(); return false; }  // без кэша плавно не будет
    g_anim_file.close();
    g_anim_idx = 0; g_anim_active = true;
    if (!anim_read_frame(0)) { anim_stop(); return false; }
    present_buffer_fast();
    anim_task_start(ANIM_RAW);
    return true;
  }

  // статичная картинка
  File f = LittleFS.open(path, "r");
  if (!f || f.size() != IMG_BYTES) { if (f) f.close(); return false; }
  size_t rd = f.read((uint8_t *)g_imgbuf, IMG_BYTES);
  f.close();
  if (rd != IMG_BYTES) return false;
  blit_buffer();
  return true;
}

// ---------- хранилище ----------
static void rebuild_playlist() {
  g_playlist.clear();
  File dir = LittleFS.open(MEDIA_DIR);
  if (dir && dir.isDirectory()) {
    for (File e = dir.openNextFile(); e; e = dir.openNextFile()) {
      if (!e.isDirectory()) {
        String n = e.name();
        int sl = n.lastIndexOf('/');
        if (sl >= 0) n = n.substring(sl + 1);
        g_playlist.push_back(n);
      }
      e.close();
    }
  }
  if (g_play_idx >= g_playlist.size()) g_play_idx = 0;
}

static void storage_init() {
  if (!LittleFS.begin(true)) { Serial.println("LittleFS mount FAILED"); return; }
  if (!LittleFS.exists(MEDIA_DIR)) LittleFS.mkdir(MEDIA_DIR);
  rebuild_playlist();
  load_show_script();
  Serial.printf("storage ok, %u image(s)\n", (unsigned)g_playlist.size());
}

// ---------- BLE ----------
// Протокол (текст в CTRL):  BEGIN:<имя>:<размер> | END | SHOW:<имя> | DEL:<имя> | LIST
// Байты картинки шлются в DATA. Ответы — нотификации CTRL: OK / DONE / ERR / LIST:a,b,c
static void ctrl_notify(const char *s) {
  if (g_ctrl) { g_ctrl->setValue((const uint8_t *)s, strlen(s)); g_ctrl->notify(); }
}

class CtrlCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &) override {
    NimBLEAttValue v = c->getValue();
    String cmd((const char *)v.data(), v.length());

    if (cmd.startsWith("BEGIN:")) {
      int p2 = cmd.lastIndexOf(':');
      String name = cmd.substring(6, p2);
      g_rx_total = cmd.substring(p2 + 1).toInt();
      g_rx_got = 0;
      g_upf = LittleFS.open(String(MEDIA_DIR "/") + name, "w");
      g_upf_open = (bool)g_upf;
      strncpy(g_show_name, name.c_str(), sizeof(g_show_name) - 1);
      g_show_name[sizeof(g_show_name) - 1] = 0;
      ctrl_notify(g_upf_open ? "OK" : "ERR");
    } else if (cmd == "END") {
      if (g_upf) g_upf.close();
      g_upf_open = false;
      bool ok = (g_rx_total == 0) || (g_rx_got == g_rx_total);
      g_list_dirty = true;
      bool is_script = strcmp(g_show_name, SHOW_FILE) == 0;
      if (ok && is_script) { g_manual = false; g_script_dirty = true; }
      else if (ok) { g_manual = true; g_show_dirty = true; }
      ctrl_notify(ok ? "DONE" : "ERR");
    } else if (cmd.startsWith("SHOW:")) {
      strncpy(g_show_name, cmd.substring(5).c_str(), sizeof(g_show_name) - 1);
      g_show_name[sizeof(g_show_name) - 1] = 0;
      g_manual = true; g_show_dirty = true;
      ctrl_notify("OK");
    } else if (cmd.startsWith("DEL:")) {
      strncpy(g_del_name, cmd.substring(4).c_str(), sizeof(g_del_name) - 1);
      g_del_name[sizeof(g_del_name) - 1] = 0;
      g_del_dirty = true;
      ctrl_notify("OK");
    } else if (cmd == "LIST") {
      String j = "LIST:";
      for (size_t i = 0; i < g_playlist.size(); i++) { if (i) j += ","; j += g_playlist[i]; }
      ctrl_notify(j.c_str());
    }
  }
};

class DataCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic *c, NimBLEConnInfo &) override {
    if (!g_upf_open) return;
    NimBLEAttValue v = c->getValue();
    g_upf.write(v.data(), v.length());
    g_rx_got += v.length();
  }
};

static void ble_init() {
  NimBLEDevice::init(BLE_NAME);
  NimBLEDevice::setMTU(517);                       // максимальный пакет
  NimBLEServer *srv = NimBLEDevice::createServer();
  NimBLEService *svc = srv->createService(SVC_UUID);

  g_ctrl = svc->createCharacteristic(CTRL_UUID,
             NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
  g_ctrl->setCallbacks(new CtrlCb());

  NimBLECharacteristic *data = svc->createCharacteristic(DATA_UUID,
             NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  data->setCallbacks(new DataCb());

  svc->start();
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  // ВАЖНО: 128-битный UUID + имя не влезают в 31 байт основного пакета,
  // из-за чего сканер не находил плату. Имя — в основной пакет (влезает),
  // UUID сервиса — в scan response (отдельные 31 байт). Ищем по имени.
  adv->setName(BLE_NAME);
  NimBLEAdvertisementData scanResp;
  scanResp.addServiceUUID(SVC_UUID);
  adv->setScanResponseData(scanResp);
  adv->enableScanResponse(true);
  adv->start();
  Serial.println("BLE: реклама как \"" BLE_NAME "\"");
}

// слайдшоу + анимация + применение запросов из BLE-потока (всё в главном потоке)
static void player_tick() {
  if (g_upf_open) return;                 // во время приёма файла файловую систему не трогаем

  if (g_del_dirty) {
    g_del_dirty = false;
    anim_stop();                          // закрыть текущий файл, если удаляют открытую анимацию
    g_scene_anim_active = false;
    char path[96];
    snprintf(path, sizeof(path), MEDIA_DIR "/%s", g_del_name);
    bool ok = LittleFS.remove(path);
    Serial.printf("delete %s: %s\n", path, ok ? "ok" : "fail");
    if (strcmp(g_del_name, SHOW_FILE) == 0) { g_show.clear(); g_show_loaded = false; }
    g_manual = false;
    g_list_dirty = true;
  }

  if (g_list_dirty) { g_list_dirty = false; rebuild_playlist(); }
  if (g_script_dirty) {
    g_script_dirty = false;
    load_show_script();
    if (g_show_loaded) start_scene(0, true);
  }

  if (g_show_dirty) {
    g_show_dirty = false;
    g_scene_anim_active = false;          // ручной показ прерывает сцену шоу
    if (show_file(g_show_name)) g_last_switch = millis();
  }

  // сцена-анимация играет своим плеером: ждём конца её полных циклов -> некст
  if (!g_manual && g_show_loaded && g_scene_anim_active) {
    if (!g_task_running || millis() >= g_scene_anim_end) {
      anim_stop();                         // последний кадр анимации остаётся в g_imgbuf
      g_scene_anim_active = false;
      g_scene_idx = (g_scene_idx + 1) % g_show.size();
      if (!start_scene(g_scene_idx, false)) g_scene_started = millis();
    }
    return;
  }

  if (!g_manual && g_show_loaded && !g_anim_active) {
    if (!g_transition_active && g_scene_started == 0) {
      start_scene(g_scene_idx, true);
    }
    if (g_transition_active) {
      uint32_t elapsed = millis() - g_transition_start;
      uint8_t p = elapsed >= TRANSITION_MS ? 255 : (uint8_t)(elapsed * 255 / TRANSITION_MS);
      compose_transition(g_transition_type, p);
      present_buffer_fast();
      if (elapsed >= TRANSITION_MS) {
        g_transition_active = false;
        blit_buffer();
        g_scene_started = millis();
        g_fx_last_frame = 0;
        scene_launch_dynamic(g_scene_idx);  // сцена-анимация стартует после перехода
      }
    } else if (millis() - g_scene_started >= scene_len_ms(g_show[g_scene_idx])) {
      g_scene_idx = (g_scene_idx + 1) % g_show.size();
      if (!start_scene(g_scene_idx, false)) g_scene_started = millis();
    } else if (g_show[g_scene_idx].fx && millis() - g_fx_last_frame >= 33) {
      g_fx_last_frame = millis();
      render_fx_frame(g_show[g_scene_idx].fx, g_fx_last_frame - g_scene_started, g_imgbuf);
      present_buffer_fast();
    }
    return;
  }

  // авто-листание коллекции
  if (!g_manual && g_playlist.size() >= 1 && millis() - g_last_switch > SLIDE_MS) {
    g_last_switch = millis();
    if (show_file(g_playlist[g_play_idx].c_str()))
      g_play_idx = (g_play_idx + 1) % g_playlist.size();
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== Znachok BMW (BLE) ===");

  Wire.begin(I2C_SDA, I2C_SCL, 400000);
  // ВАЖНО: выставить выходы LOW ДО перевода в режим выхода.
  // По умолчанию регистр выходов TCA9554 = 0xFF -> все EXIO в HIGH, а на EXIO8
  // висит зуммер -> громкий постоянный писк. Сначала 0x00, потом включаем выходы.
  tca_write(TCA9554_OUTPUT_REG, 0x00);          // все выходы LOW (зуммер EXIO8 молчит)
  tca_write(TCA9554_CONFIG_REG, 0x00);          // все EXIO на выход
  tca_set(EXIO_LCD_RST, false); delay(10);
  tca_set(EXIO_LCD_RST, true);  delay(50);

  st7701_init();
  rgb_panel_init();

  ledcAttach(LCD_BL_PIN, 20000, 10);
  set_brightness(0);                            // включим после первой отрисовки (без вспышки)

  g_imgbuf = (uint16_t *)heap_caps_malloc(IMG_BYTES, MALLOC_CAP_SPIRAM);
  g_frombuf = (uint16_t *)heap_caps_malloc(IMG_BYTES, MALLOC_CAP_SPIRAM);
  g_tobuf = (uint16_t *)heap_caps_malloc(IMG_BYTES, MALLOC_CAP_SPIRAM);

  lvgl_init();
  build_screen();
  lv_timer_handler();                           // первый кадр (логотип)
  set_brightness(90);

  storage_init();

  ble_init();

  // если в памяти уже есть картинки — стартуем слайдшоу, иначе остаётся логотип
  g_last_switch = millis();
  Serial.printf("ready. PSRAM free=%u\n", ESP.getFreePsram());
}

void loop() {
  if (!g_task_running) lv_timer_handler();  // во время анимации экраном владеет задача
  player_tick();
  delay(2);
}
