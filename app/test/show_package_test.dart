import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:znachok_bmw/show_package.dart';

void main() {
  test('accepts a structurally valid ZSHOW v1 header', () {
    final bytes = _packageHeader();
    final info = inspectShowPackage(bytes);

    expect(info.frameCount, 2);
    expect(info.fps, 60);
    expect(info.byteSize, 64);
  });

  test('rejects unsupported version before upload', () {
    final bytes = _packageHeader();
    bytes.buffer.asByteData().setUint16(8, 2, Endian.little);

    expect(
      () => inspectShowPackage(bytes),
      throwsA(isA<ShowPackageException>()),
    );
  });
}

Uint8List _packageHeader() {
  final bytes = Uint8List(64);
  bytes.setAll(0, [0x5A, 0x53, 0x48, 0x4F, 0x57, 0x56, 0x31, 0]);
  final header = bytes.buffer.asByteData();
  header.setUint16(8, 1, Endian.little);
  header.setUint16(10, 64, Endian.little);
  header.setUint32(12, 64, Endian.little);
  header.setUint16(16, 800, Endian.little);
  header.setUint16(18, 800, Endian.little);
  header.setUint16(20, 60, Endian.little);
  header.setUint32(24, 2, Endian.little);
  return bytes;
}
