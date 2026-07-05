# Znachok BMW — полная документация проекта

DIY «умный логотип» на задний бампер авто: круглый дисплей показывает логотип,
картинки и анимации; новые картинки заливаются с телефона по **Bluetooth (BLE)**.

> Файл — рабочая память по проекту. Держать в актуальном состоянии при изменениях
> прошивки/протокола/тулчейна.

---

## 1. Железо

**Плата:** Waveshare ESP32-S3-Touch-LCD-2.1B
- ESP32-S3, 8 МБ OPI PSRAM, 16 МБ Flash, WiFi/BT(BLE).
- Круглый IPS 2.1″, **480×480**, контроллер **ST7701**, интерфейс **RGB** (16-бит параллель).
- Ёмкостный тач CST820 (НЕ используется).
- USB-C для прошивки через мост **CH343** → порт **COM6**.

**Подтверждено I2C-сканом (SDA=15, SCL=7):**
| Адрес | Чип | Назначение |
|------|------|-----------|
| 0x20 | **TCA9554** | IO-расширитель (НЕ CH422G, несмотря на маркировку «2.1B»!) |
| 0x15 | CST820 | тач (не используется) |
| 0x51 | PCF85063 | RTC |
| 0x6B | QMI8658 | гироскоп/акселерометр |

**Распиновка дисплея (выверено офиц. демо Waveshare):**
- 3-wire SPI инициализации ST7701: `MOSI=GPIO1`, `CLK=GPIO2`.
- Подсветка: `GPIO6` (PWM, ledc).
- Управление через TCA9554: `EXIO1 = LCD_RST`, `EXIO3 = LCD_CS`.
- RGB-данные: `{5,45,48,47,21, 14,13,12,11,10,9, 46,3,8,18,17}`.
- Синхро: `DE=40, VSYNC=39, HSYNC=38, PCLK=41`.
- Тайминги: pclk 16 МГц, HPW8/HBP10/HFP50, VPW3/VBP8/VFP8.

Источник истины по init/драйверам: `C:\Users\maybe\Downloads\WS-2.1-Demo`
(скачан с files.waveshare.com — демо для 2.1, совпадает с этим железом).

---

## 2. Тулчейн и сборка прошивки

- **PlatformIO Core** в `C:\Users\maybe\.platformio\penv\` (CLI: `...\Scripts\platformio.exe`).
- Платформа — **pioarduino** (форк, даёт arduino-esp32 **3.x / IDF 5.x**; нужно для
  `esp_lcd` RGB API `num_fbs` и `ledcAttach`). Официальный espressif32 застрял на 2.0.17 — НЕ годится.
- Конфиг — `platformio.ini`: board `esp32-s3-devkitc-1`, `qio_opi` (OPI PSRAM),
  flash 16MB, partitions `partitions_16MB.csv`, filesystem `littlefs`.

**Команды (из PowerShell):**
```powershell
$env:PYTHONIOENCODING="utf-8"   # иначе консоль cp1251 роняет вывод pio на эмодзи
$pio="C:\Users\maybe\.platformio\penv\Scripts\platformio.exe"
& $pio run -d "d:\znachok_dima_bmw"            # сборка
& $pio run -d "d:\znachok_dima_bmw" -t upload  # прошивка на COM6
```

**Чтение Serial (порт COM6, 115200), со сбросом в рабочий режим:**
```python
# python из penv. Сброс: DTR=False (BOOT high), пульс RTS (EN)
import serial,time
s=serial.Serial('COM6',115200,timeout=1)
s.setDTR(False); s.setRTS(True); time.sleep(0.15); s.setRTS(False)
# читать s.readline() в цикле
```

**Подводные камни тулчейна:**
- `-DARDUINO_USB_CDC_ON_BOOT=0` обязателен — иначе `Serial` уходит в нативный USB, COM6 пустой.
- Дважды попадались битые dist-info в penv (`pyelftools`, `bottle`) → лечить
  `pip install --force-reinstall` или удалить папку `*.dist-info` и переустановить.
- Для APK-сборки Flutter нужен JDK 17/21 (НЕ 25) — взят `E:\Android Studio\jbr` (JDK 21).

---

## 3. Прошивка (`src/`)

| Файл | Что |
|------|-----|
| `src/main.cpp` | всё: init дисплея, LVGL, плеер, BLE |
| `src/bmw_logo.c` | вшитый логотип 480×480 RGB565 (LVGL `lv_img_dsc_t bmw_logo`) |
| `include/lv_conf.h` | конфиг LVGL v8.3.10 (color depth 16, swap 0, montserrat_28 вкл) |
| `partitions_16MB.csv` | разделы: 2×3MB OTA app + раздел `spiffs` (~9.8MB littlefs) + coredump |
| `tools/png_to_lvgl.py` | конвертер PNG → C-массив RGB565 для вшитого логотипа |

**Зависимости (`platformio.ini` lib_deps):** `lvgl@8.3.10`, `h2zero/NimBLE-Arduino@^2.2.3`.

**Графический стек:** LVGL v8.3, режим `full_refresh`, рисует прямо в 2 кадровых буфера
RGB-панели (zero-copy через `esp_lcd_rgb_panel_get_frame_buffer` + `draw_bitmap`),
тик через `esp_timer` (2 мс). LVGL не потокобезопасен → всё рисование только в главном потоке.

**Порядок init (setup):** I2C → TCA9554 (все EXIO на выход) → reset панели (EXIO1) →
ST7701 по SPI (CS=EXIO3) → RGB-панель → подсветка (вкл после первого кадра, без вспышки) →
LVGL → логотип → LittleFS → BLE.

**Плеер (`player_tick`, главный поток):**
- по умолчанию показывает вшитый логотип;
- если в `/media` есть файлы — слайдшоу (8 с/кадр), пока не выбрана картинка вручную (`g_manual`);
- `.anm` проигрывается покадрово (стрим кадров из флеша);
- во время приёма файла по BLE (`g_upf_open`) файловые операции плеера на паузе.

---

## 4. BLE-протокол (устройство ↔ телефон)

NimBLE-Arduino 2.x. Имя устройства: **`Znachok-BMW`**.

| UUID | Характеристика | Свойства | Назначение |
|------|----------------|----------|-----------|
| `a1b20000-1111-2222-3333-444455556666` | Service | — | сервис знака |
| `a1b20001-...` | CTRL | write + notify | команды и ответы |
| `a1b20002-...` | DATA | write | байты файла |

**Команды (UTF-8 текст в CTRL):**
- `BEGIN:<имя>:<размер>` — начать приём файла (открыть `/media/<имя>`).
- `END` — завершить приём.
- `SHOW:<имя>` — показать файл.
- `DEL:<имя>` — удалить.
- `LIST` — запросить список.

**Ответы (notify на CTRL):** `OK`, `DONE`, `ERR`, `LIST:a,b,c`.

**Заливка:** `BEGIN` → ждать `OK` → слать DATA чанками (≈MTU-3, до 512 Б) → `END` → ждать `DONE`.
MTU запрашивается 517. Сейчас write-with-response (надёжно, но медленно: кадр ~460 КБ → 30–90 с).

---

## 5. Форматы файлов (в LittleFS `/media`)

- **`.gif`** — ОСНОВНОЙ формат анимаций: обычный GIF, прошивка играет его нативно
  (библиотека **AnimatedGIF** bitbank2). Файл целиком поднимается в PSRAM (лимит `GIF_MAX_FILE` = 4 МБ),
  декод дельта-кадров в COOKED-режиме (RGB565 LE) → канва `g_imgbuf` → задний буфер панели → vsync-флип.
  Все кадры, родные тайминги (кламп ≥20 мс), зацикливание через `gif.reset()`.
- **`.jpg`** — статичная картинка: 480×480 с круглой маской, JPEG; устройство декодирует через `JPEGDEC`.
- **`.mjpg`** — legacy JPEG-анимация: заголовок `MJP1` + таблица размеров + JPEG-кадры.
  Играет только если ВСЕ кадры влезли RGB565-кэшем в PSRAM (иначе отказ — стриминг из FS выпилен как рваный).
- **`.bin`** — сырой кадр RGB565 LE (460800 байт), legacy.
- **`.anm`** — legacy raw-анимация `ANM1` + RGB565-кадры; тоже только через полный PSRAM-кэш.

**Архитектура плавного воспроизведения (ключевое!):**
анимации крутит отдельная FreeRTOS-задача `anim_task_fn` (ядро 1, prio 2, стек 12К):
декод/выборка кадра → `present_buffer_fast()` = memcpy в ЗАДНИЙ буфер панели +
`esp_lcd_panel_draw_bitmap` тем же указателем (= тир-фри флип по vsync) → `vTaskDelay`
с компенсацией времени декода. **LVGL в это время от экрана отключён** (`loop()` не зовёт
`lv_timer_handler`, пока `g_task_running`). Остановка — только из главного потока:
`anim_task_stop_sync()` (ждёт задачу, чистит GIF, инвалидирует LVGL-экран).
Старый путь «кадр → lv_obj_invalidate → ждать тика LVGL» давал 2-15 FPS с джиттером — не возвращать!

**Конвертация — на стороне клиента (телефон), НЕ на устройстве** (ключевое решение:
без декодеров на ESP32). Пайплайн: cover-crop в квадрат → ресайз 480×480 →
круглая маска (вне круга чёрный) → RGB565 LE. GIF раскладывается на кадры.

---

## 6. Клиент — мобильная апка (Flutter, `app/`)

Кросс-платформенная (Android + iOS). Это единственный актуальный клиент проекта.

| Файл | Что |
|------|-----|
| `app/lib/main.dart` | UI: подключение, выбор фото/камера, прогресс, список ▶/🗑 |
| `app/lib/ble.dart` | BLE: поиск/коннект/MTU, протокол, заливка чанками |
| `app/lib/imaging.dart` | конвертация фото → `.jpg`, GIF → `.anm` lossless RGB565 (пакет `image`) |
| `app/pubspec.yaml` | deps: flutter_blue_plus, image, image_picker, permission_handler |
| `app/README.md` | пошаговая сборка + правки разрешений Android/iOS |

**Сборка (Flutter SDK на `D:\flutter`, кэши на D:):**
```powershell
$env:Path="D:\flutter\bin;$env:Path"; $env:PUB_CACHE="D:\.pub-cache"; $env:GRADLE_USER_HOME="D:\.gradle"
cd D:\znachok_dima_bmw\app
flutter pub get
flutter analyze            # 0 ошибок
flutter build apk --release
# результат: app\build\app\outputs\flutter-apk\app-release.apk (~46 МБ)
```
JDK для Gradle указан: `flutter config --jdk-dir "E:\Android Studio\jbr"` (JDK 21).
Android SDK: `C:\Users\maybe\AppData\Local\Android\Sdk` (build-tools 35/36, platform android-36).

Web-клиент удалён; актуальный клиент проекта — Flutter-апка.

---

## 7. Прогресс по спринтам

- **C0 — Bring-up ✅** тулчейн, дисплей ST7701 заведён.
- **C1 — LVGL + логотип ✅** реальный `bmw logo.png` вшит как RGB565.
- **C2+C3 — связь и заливка ✅** хранилище LittleFS, плеер, передача с телефона.
  Изначально сделано на WiFi (SoftAP+веб), затем **переведено на BLE** (выбор пользователя),
  WiFi полностью удалён.
- **Клиент ✅** Flutter-апка собрана в APK.

**Дальше (бэклог):**
- **RLE-сжатие** кадров (для логотипов с плоскими цветами — кратно быстрее заливка по BLE).
- Превью картинок в списке апки.
- OTA-обновление прошивки по BLE.
- Полировка плеера: порядок, длительность на кадр, переходы, настройки в NVS.

**Железный трек (вне софта):** питание 12В→5В от борта (на линию, гаснущую с зажиганием),
герметичный корпус (IP65+, виброразвязка), яркость IPS на солнце (компромисс платы),
юридический момент (внешние светящиеся экраны на авто — проверить ПДД региона).

---

## 8. Ограничения / важно помнить
- **Скорость BLE:** полноразмерный кадр шлётся как есть (~460 КБ) → 30–90 с. Решение — RLE.
- **iOS:** только Flutter-апка.
- **ESP32-S3 = только BLE**, классического Bluetooth (SPP) нет.
- LVGL — рисовать строго из главного потока; BLE-колбэки только ставят флаги/пишут файл.
