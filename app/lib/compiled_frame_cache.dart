import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

const int _cacheMagic = 0x3143435A;
const int _cacheHeaderSize = 8;
const int _cacheEntrySize = 8;
const int _maximumCachedFrames = 20000;
const int _maximumCachedFrameBytes = 212 * 1024;
const int _maximumCacheBytes = 128 * 1024 * 1024;

class CachedFrameData {
  const CachedFrameData(this.jpeg, this.durationUs);

  final Uint8List jpeg;
  final int durationUs;
}

class CompiledFrameCache {
  CompiledFrameCache(String rootPath) : root = Directory(rootPath);

  final Directory root;
  int hits = 0;
  int misses = 0;

  static String digestText(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String digestBytes(Uint8List value) =>
      sha256.convert(value).toString();

  Future<List<CachedFrameData>?> read(String key) async {
    final file = File(path.join(root.path, '$key.zcc'));
    try {
      if (!await file.exists()) {
        misses++;
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < _cacheHeaderSize) throw const FormatException();
      final data = ByteData.sublistView(bytes);
      if (data.getUint32(0, Endian.little) != _cacheMagic) {
        throw const FormatException();
      }
      final count = data.getUint32(4, Endian.little);
      if (count == 0 || count > _maximumCachedFrames) {
        throw const FormatException();
      }
      var cursor = _cacheHeaderSize;
      final frames = <CachedFrameData>[];
      for (var index = 0; index < count; index++) {
        if (cursor + _cacheEntrySize > bytes.length) {
          throw const FormatException();
        }
        final durationUs = data.getUint32(cursor, Endian.little);
        final length = data.getUint32(cursor + 4, Endian.little);
        cursor += _cacheEntrySize;
        if (durationUs == 0 ||
            length == 0 ||
            length > _maximumCachedFrameBytes ||
            cursor + length > bytes.length) {
          throw const FormatException();
        }
        frames.add(CachedFrameData(
          Uint8List.sublistView(bytes, cursor, cursor + length),
          durationUs,
        ));
        cursor += length;
      }
      if (cursor != bytes.length) throw const FormatException();
      hits++;
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return frames;
    } catch (_) {
      misses++;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(
    String key,
    List<CachedFrameData> frames, {
    bool maintain = true,
  }) async {
    if (frames.isEmpty || frames.length > _maximumCachedFrames) return;
    await root.create(recursive: true);
    final target = File(path.join(root.path, '$key.zcc'));
    if (await target.exists()) return;
    final header = Uint8List(_cacheHeaderSize);
    ByteData.sublistView(header)
      ..setUint32(0, _cacheMagic, Endian.little)
      ..setUint32(4, frames.length, Endian.little);
    final output = BytesBuilder(copy: false)..add(header);
    for (final frame in frames) {
      if (frame.durationUs <= 0 ||
          frame.jpeg.isEmpty ||
          frame.jpeg.length > _maximumCachedFrameBytes) {
        return;
      }
      final entry = Uint8List(_cacheEntrySize);
      ByteData.sublistView(entry)
        ..setUint32(0, frame.durationUs, Endian.little)
        ..setUint32(4, frame.jpeg.length, Endian.little);
      output
        ..add(entry)
        ..add(frame.jpeg);
    }
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsBytes(output.takeBytes(), flush: true);
      if (await target.exists()) {
        await temporary.delete();
      } else {
        await temporary.rename(target.path);
      }
      if (maintain) await trim();
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
  }

  Future<void> trim() async {
    if (!await root.exists()) return;
    final files = await root
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.zcc'))
        .cast<File>()
        .toList();
    final entries = <({File file, int size, DateTime modified})>[];
    var total = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        total += stat.size;
        entries.add((file: file, size: stat.size, modified: stat.modified));
      } catch (_) {}
    }
    if (total <= _maximumCacheBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= _maximumCacheBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  }
}
