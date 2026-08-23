import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;

import 'project_model.dart';

class NormalizedVideoFrame {
  const NormalizedVideoFrame({
    required this.path,
    required this.durationUs,
  });

  final String path;
  final int durationUs;
}

class NormalizedVideo {
  const NormalizedVideo({
    required this.width,
    required this.height,
    required this.frames,
  });

  final int width;
  final int height;
  final List<NormalizedVideoFrame> frames;

  int get durationUs =>
      frames.fold(0, (total, frame) => total + frame.durationUs);
}

Future<NormalizedVideo> loadNormalizedVideo(String manifestPath) async {
  final manifestFile = File(manifestPath);
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
    throw const FormatException('Неподдерживаемый MP4 manifest');
  }
  final base = manifestFile.parent.path;
  final rawFrames = decoded['frames'];
  if (rawFrames is! List || rawFrames.isEmpty) {
    throw const FormatException('В MP4 не найдено видеокадров');
  }
  final frames = rawFrames.map((item) {
    if (item is! Map<String, dynamic>) {
      throw const FormatException('Повреждён список кадров MP4');
    }
    final file = item['file'];
    final durationUs = (item['durationUs'] as num?)?.toInt() ?? 0;
    if (file is! String || file.isEmpty || durationUs <= 0) {
      throw const FormatException('Повреждён тайминг MP4');
    }
    return NormalizedVideoFrame(
      path: path.join(base, file),
      durationUs: durationUs,
    );
  }).toList(growable: false);
  return NormalizedVideo(
    width: (decoded['width'] as num?)?.toInt() ?? 0,
    height: (decoded['height'] as num?)?.toInt() ?? 0,
    frames: frames,
  );
}

List<NormalizedVideoFrame> scheduleNormalizedVideo(
  NormalizedVideo video,
  ShowClip clip,
) {
  final naturalDurationUs = video.durationUs;
  final trimStartUs =
      clip.trimStartMs.clamp(0, naturalDurationUs ~/ 1000 - 1) * 1000;
  final requestedEndUs = clip.trimEndMs * 1000;
  final trimEndUs = requestedEndUs <= 0
      ? naturalDurationUs
      : requestedEndUs.clamp(trimStartUs + 1000, naturalDurationUs);
  final onePass = <NormalizedVideoFrame>[];
  var cursorUs = 0;
  for (final frame in video.frames) {
    final frameStartUs = cursorUs;
    final frameEndUs = cursorUs + frame.durationUs;
    cursorUs = frameEndUs;
    final overlapStartUs = math.max(frameStartUs, trimStartUs);
    final overlapEndUs = math.min(frameEndUs, trimEndUs);
    if (overlapEndUs <= overlapStartUs) continue;
    onePass.add(NormalizedVideoFrame(
      path: frame.path,
      durationUs: ((overlapEndUs - overlapStartUs) / clip.speed.clamp(0.25, 4))
          .round()
          .clamp(1000, 10000000),
    ));
  }
  if (onePass.isEmpty) {
    throw const FormatException('После обрезки MP4 не осталось кадров');
  }
  final repeated = <NormalizedVideoFrame>[];
  for (var pass = 0; pass < clip.repeat.clamp(1, 20); pass++) {
    repeated.addAll(onePass);
  }
  if (clip.durationMs <= 0) return repeated;
  final targetUs = clip.durationMs * 1000;
  final fitted = <NormalizedVideoFrame>[];
  var usedUs = 0;
  var index = 0;
  while (usedUs < targetUs) {
    final frame = repeated[index++ % repeated.length];
    final durationUs = math.min(frame.durationUs, targetUs - usedUs);
    fitted.add(NormalizedVideoFrame(path: frame.path, durationUs: durationUs));
    usedUs += durationUs;
  }
  return fitted;
}
