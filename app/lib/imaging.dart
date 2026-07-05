import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Размер дисплея и константы формата (должны совпадать с прошивкой).
const int kSize = 480;
const int kStillJpegQuality = 100;
const int kAnimJpegQuality = 80;             // конфиг «крутой» версии; цвет чинит RGB-конверсия
const int kMaxUploadBytes = 4 * 1024 * 1024; // лимит GIF_MAX_FILE в прошивке
const int kMjpgMaxFrames = 200;              // длинные ролики идут стримом из PSRAM
const int kMinFrameDelayMs = 45;             // стрим (полу-декод в буфер панели) ~40мс/кадр

/// cover-crop в квадрат -> ресайз 480x480 -> круглая маска (вне круга — чёрный).
img.Image _fit(img.Image src) {
  final s = min(src.width, src.height);
  final cx = (src.width - s) ~/ 2;
  final cy = (src.height - s) ~/ 2;
  var im = img.copyCrop(src, x: cx, y: cy, width: s, height: s);
  im = img.copyResize(im,
      width: kSize, height: kSize, interpolation: img.Interpolation.average);
  const c = kSize / 2;
  final r2 = (c - 1) * (c - 1);
  for (int y = 0; y < kSize; y++) {
    final dy = y - c;
    for (int x = 0; x < kSize; x++) {
      final dx = x - c;
      if (dx * dx + dy * dy > r2) im.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  return im;
}

/// Результат конвертации: имя файла на устройстве + байты для заливки.
class Converted {
  final String name;
  final Uint8List bytes;
  Converted(this.name, this.bytes);
}

/// Статичная картинка -> .jpg (480x480, круглая маска, JPEG q100).
/// JPEG в ~10 раз меньше сырого RGB565 -> во столько же быстрее заливка по BLE.
/// Устройство декодирует JPEG в кадровый буфер (JPEGDEC).
Converted convertStill(Uint8List fileBytes, String baseName) {
  final src = img.decodeImage(fileBytes);
  if (src == null) throw Exception('не удалось прочитать изображение');
  final jpg = img.encodeJpg(_fit(src), quality: kStillJpegQuality);
  return Converted('$baseName.jpg', jpg);
}

/// Анимированный GIF -> .mjpg (motion-JPEG): телефон разбирает GIF на кадры,
/// каждый вписывает в круг 480x480 и жмёт в JPEG (полный цвет). Плата декодирует
/// проверенным JPEGDEC: если кадры влезли в PSRAM-кэш — играет идеально плавно
/// на родном fps; иначе стримит с точным тактом ~12fps (без рывков).
/// Кадры прореживаются так, чтобы интервал был ≥85мс (скорость декода платы),
/// общая длительность анимации сохраняется.
/// Формат: "MJP1" + nframes(u16 LE) + delay(u16 LE) + таблица размеров (u32 LE
/// на кадр) + JPEG-кадры подряд.
Converted convertGif(Uint8List fileBytes, String baseName) {
  final anim = img.decodeGif(fileBytes);
  if (anim == null) throw Exception('не удалось прочитать GIF');
  final frames = anim.frames;
  if (frames.length <= 1) return convertStill(fileBytes, baseName);

  // суммарная длительность GIF (мс); кадры без задержки считаем как 100мс
  int totalMs = 0;
  for (final fr in frames) {
    totalMs += fr.frameDuration > 0 ? fr.frameDuration : 100;
  }

  // сколько кадров оставить: интервал не мельче kMinFrameDelayMs и лимит прошивки
  int n = frames.length;
  final maxByDelay = max(1, totalMs ~/ kMinFrameDelayMs);
  n = min(n, min(maxByDelay, kMjpgMaxFrames));

  // равномерная выборка кадров + JPEG каждого.
  // ВАЖНО: кадры GIF палитровые — сначала конвертируем в честный RGB,
  // иначе ресайз усредняет индексы палитры и портит цвета.
  List<Uint8List> encodeAll(int quality) {
    final out = <Uint8List>[];
    for (int i = 0; i < n; i++) {
      var src = frames[(i * frames.length) ~/ n];
      if (src.hasPalette) {
        src = src.convert(format: img.Format.uint8, numChannels: 3);
      }
      out.add(Uint8List.fromList(img.encodeJpg(_fit(src), quality: quality)));
    }
    return out;
  }

  int sizeOf(List<Uint8List> js) =>
      8 + 4 * js.length + js.fold<int>(0, (a, b) => a + b.length);

  // авто-подгонка под лимит платы: q80 -> q65 -> равномерное прореживание
  var jpegs = encodeAll(kAnimJpegQuality);
  if (sizeOf(jpegs) > kMaxUploadBytes) {
    jpegs = encodeAll(65);
  }
  if (sizeOf(jpegs) > kMaxUploadBytes) {
    final avg = jpegs.fold<int>(0, (a, b) => a + b.length) / jpegs.length;
    int m = ((kMaxUploadBytes - 8) / (avg + 4)).floor();
    m = m.clamp(1, jpegs.length);
    final thinned = <Uint8List>[
      for (int i = 0; i < m; i++) jpegs[(i * jpegs.length) ~/ m]
    ];
    jpegs = thinned;
  }
  n = jpegs.length;
  final delay = (totalMs / n).round().clamp(kMinFrameDelayMs, 65535);

  final out = Uint8List(sizeOf(jpegs));
  out[0] = 0x4D; out[1] = 0x4A; out[2] = 0x50; out[3] = 0x31; // "MJP1"
  out[4] = n & 0xFF; out[5] = (n >> 8) & 0xFF;
  out[6] = delay & 0xFF; out[7] = (delay >> 8) & 0xFF;
  for (int i = 0; i < n; i++) {
    final sz = jpegs[i].length;
    final o = 8 + i * 4;
    out[o] = sz & 0xFF;
    out[o + 1] = (sz >> 8) & 0xFF;
    out[o + 2] = (sz >> 16) & 0xFF;
    out[o + 3] = (sz >> 24) & 0xFF;
  }
  int off = 8 + 4 * n;
  for (final j in jpegs) {
    out.setRange(off, off + j.length, j);
    off += j.length;
  }
  return Converted('$baseName.mjpg', out);
}
