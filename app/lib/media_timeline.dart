import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'project_model.dart';
import 'video_manifest.dart';

const int maximumTimelineFrames = 20000;

class ScheduledGifFrame {
  const ScheduledGifFrame(this.sourceIndex, this.durationUs);

  final int sourceIndex;
  final int durationUs;
}

List<int> inspectGifFrameDurations(Uint8List bytes) {
  final decoder = image.GifDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null || info.frames.isEmpty) {
    throw const FormatException('GIF повреждён или не поддерживается');
  }
  return info.frames
      .map((frame) => frame.duration <= 0 ? 100 : frame.duration * 10)
      .toList(growable: false);
}

List<ScheduledGifFrame> scheduleGifFrames(
  List<int> rawDurations,
  ShowClip clip,
) {
  final naturalDuration = rawDurations.fold<int>(0, (sum, item) => sum + item);
  final trimStart = clip.trimStartMs.clamp(0, naturalDuration - 1);
  final trimEnd = clip.trimEndMs <= 0
      ? naturalDuration
      : clip.trimEndMs.clamp(trimStart + 1, naturalDuration);
  final onePass = <ScheduledGifFrame>[];
  var cursor = 0;
  for (var index = 0; index < rawDurations.length; index++) {
    final frameStart = cursor;
    final frameEnd = cursor + rawDurations[index];
    cursor = frameEnd;
    final overlapStart = math.max(frameStart, trimStart);
    final overlapEnd = math.min(frameEnd, trimEnd);
    if (overlapEnd <= overlapStart) continue;
    final durationUs =
        (((overlapEnd - overlapStart) * 1000) / clip.speed.clamp(0.25, 4))
            .round()
            .clamp(1000, 10000000);
    onePass.add(ScheduledGifFrame(index, durationUs));
  }
  if (onePass.isEmpty) {
    throw const FormatException('После обрезки GIF не осталось кадров');
  }

  final repeated = <ScheduledGifFrame>[];
  for (var pass = 0; pass < clip.repeat.clamp(1, 20); pass++) {
    repeated.addAll(onePass);
  }
  if (clip.durationMs <= 0) return repeated;
  final targetUs = clip.durationMs * 1000;
  final fitted = <ScheduledGifFrame>[];
  var usedUs = 0;
  var index = 0;
  while (usedUs < targetUs && fitted.length < maximumTimelineFrames) {
    final frame = repeated[index++ % repeated.length];
    final durationUs = math.min(frame.durationUs, targetUs - usedUs);
    fitted.add(ScheduledGifFrame(frame.sourceIndex, durationUs));
    usedUs += durationUs;
  }
  return fitted;
}

Future<List<ScheduledGifFrame>> loadGifSchedule(ShowClip clip) async {
  final bytes = await File(clip.assetPath).readAsBytes();
  return scheduleGifFrames(inspectGifFrameDurations(bytes), clip);
}

Future<int> clipPlaybackDurationUs(ShowClip clip) async {
  if (clip.kind == ClipKind.gif) {
    final schedule = await loadGifSchedule(clip);
    return schedule.fold<int>(0, (total, frame) => total + frame.durationUs);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    final manifestPath = clip.normalizedPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      throw const FormatException('Анимацию нужно подготовить заново');
    }
    return scheduleNormalizedVideo(
            await loadNormalizedVideo(manifestPath), clip)
        .fold<int>(0, (total, frame) => total + frame.durationUs);
  }
  return clip.durationMs.clamp(500, 10000) * 1000;
}
