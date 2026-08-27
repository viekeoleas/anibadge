import 'dart:typed_data';

const int maxShowBytes = 23 * 1024 * 1024;

class ShowPackageInfo {
  const ShowPackageInfo({
    required this.frameCount,
    required this.fps,
    required this.byteSize,
  });

  final int frameCount;
  final int fps;
  final int byteSize;
}

class ShowPackageException implements Exception {
  const ShowPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

ShowPackageInfo inspectShowPackage(Uint8List bytes) {
  if (bytes.length < 64) {
    throw const ShowPackageException('Файл обрезан: заголовок ZSHOW неполный');
  }
  if (bytes.length > maxShowBytes) {
    throw const ShowPackageException('ZSHOW должен быть не больше 23 МБ');
  }

  const magic = <int>[0x5A, 0x53, 0x48, 0x4F, 0x57, 0x56, 0x31, 0x00];
  for (var index = 0; index < magic.length; index++) {
    if (bytes[index] != magic[index]) {
      throw const ShowPackageException('Это не пакет ZSHOW v1');
    }
  }

  final header = ByteData.sublistView(bytes, 0, 64);
  final version = header.getUint16(8, Endian.little);
  if (version != 1) {
    throw ShowPackageException('Версия ZSHOW $version пока не поддерживается');
  }
  if (header.getUint16(10, Endian.little) != 64) {
    throw const ShowPackageException('Неподдерживаемый заголовок ZSHOW');
  }
  if (header.getUint32(12, Endian.little) != bytes.length) {
    throw const ShowPackageException('Размер пакета не совпадает с заголовком');
  }
  if (header.getUint16(16, Endian.little) != 800 ||
      header.getUint16(18, Endian.little) != 800) {
    throw const ShowPackageException('Пакет должен быть размером 800 × 800');
  }

  final fps = header.getUint16(20, Endian.little);
  final frameCount = header.getUint32(24, Endian.little);
  if (fps < 1 || fps > 60 || frameCount < 1) {
    throw const ShowPackageException('В пакете некорректные тайминги');
  }
  return ShowPackageInfo(
    frameCount: frameCount,
    fps: fps,
    byteSize: bytes.length,
  );
}
