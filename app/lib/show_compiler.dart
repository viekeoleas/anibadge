import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import 'compiled_frame_cache.dart';
import 'media_timeline.dart';
import 'project_model.dart';
import 'video_manifest.dart';

const int _canvasSize = 800;
const int _headerSize = 64;
const int _frameEntrySize = 16;
const int _maxFrameBytes = 212 * 1024;
const int _maxPackageBytes = 20 * 1024 * 1024;
const int _maxFrames = 20000;
final List<({int left, int right})> _circleBounds = List.generate(
  _canvasSize,
  (y) {
    const center = (_canvasSize - 1) / 2;
    const radiusSquared = center * center;
    final dy = y - center;
    final halfWidth = math.sqrt(radiusSquared - dy * dy);
    return (
      left: (center - halfWidth).ceil(),
      right: (center + halfWidth).floor(),
    );
  },
  growable: false,
);

class ShowCompileException implements Exception {
  const ShowCompileException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CompiledFrame {
  const CompiledFrame(this.jpeg, this.durationUs, this.clipIndex);

  final Uint8List jpeg;
  final int durationUs;
  final int clipIndex;
}

class CompiledShow {
  const CompiledShow(
    this.package,
    this.frames, {
    this.cacheHits = 0,
    this.cacheMisses = 0,
  });

  final Uint8List package;
  final List<CompiledFrame> frames;
  final int cacheHits;
  final int cacheMisses;

  int get durationUs => frames.fold(0, (sum, frame) => sum + frame.durationUs);

  int frameIndexAtElapsedUs(int elapsedUs) {
    if (frames.isEmpty) return 0;
    final cycleUs = durationUs;
    if (cycleUs <= 0) return 0;
    var positionUs = elapsedUs % cycleUs;
    if (positionUs < 0) positionUs += cycleUs;
    for (var index = 0; index < frames.length; index++) {
      final durationUs = frames[index].durationUs;
      if (positionUs < durationUs) return index;
      positionUs -= durationUs;
    }
    return frames.length - 1;
  }
}

class ShowCompileProgress {
  const ShowCompileProgress({
    required this.clipIndex,
    required this.clipCount,
    required this.completedFrames,
    required this.totalFrames,
  });

  final int clipIndex;
  final int clipCount;
  final int completedFrames;
  final int totalFrames;
}

typedef ShowCompileProgressCallback = void Function(ShowCompileProgress value);

Future<CompiledShow> compileProjectInBackground(
  ShowProject project, {
  String? cacheDirectory,
  ShowCompileProgressCallback? onProgress,
}) async {
  if (onProgress != null) {
    final receive = ReceivePort();
    await Isolate.spawn(
      _compileProjectIsolate,
      [receive.sendPort, project.encode(), cacheDirectory],
      debugName: 'znachok-show-compiler',
    );
    await for (final message in receive) {
      final payload = message as List<Object?>;
      switch (payload[0]) {
        case 'progress':
          onProgress(ShowCompileProgress(
            clipIndex: payload[1]! as int,
            clipCount: payload[2]! as int,
            completedFrames: payload[3]! as int,
            totalFrames: payload[4]! as int,
          ));
          continue;
        case 'result':
          receive.close();
          return payload[1]! as CompiledShow;
        case 'error':
          receive.close();
          throw ShowCompileException(payload[1]! as String);
      }
    }
    throw const ShowCompileException('Фоновая подготовка была прервана');
  }
  return compute(
    _compileProjectPayload,
    [project.encode(), cacheDirectory],
    debugLabel: 'znachok-show-compiler',
  );
}

Future<void> _compileProjectIsolate(List<Object?> payload) async {
  final send = payload[0]! as SendPort;
  try {
    final result = await compileProject(
      ShowProject.decode(payload[1]! as String),
      cacheDirectory: payload[2] as String?,
      onProgress: (progress) => send.send([
        'progress',
        progress.clipIndex,
        progress.clipCount,
        progress.completedFrames,
        progress.totalFrames,
      ]),
    );
    send.send(['result', result]);
  } catch (error) {
    send.send(['error', error.toString()]);
  }
}

Future<CompiledShow> _compileProjectPayload(List<String?> payload) {
  return compileProject(
    ShowProject.decode(payload[0]!),
    cacheDirectory: payload[1],
  );
}

Future<CompiledShow> compileTransitionPreviewInBackground(
  ShowClip outgoing,
  ShowClip incoming, {
  String? cacheDirectory,
}) {
  return compute(
    _compileTransitionPreviewPayload,
    [
      ShowProject(clips: [outgoing, incoming]).encode(),
      cacheDirectory
    ],
    debugLabel: 'znachok-transition-preview',
  );
}

Future<CompiledShow> _compileTransitionPreviewPayload(List<String?> payload) {
  final clips = ShowProject.decode(payload[0]!).clips;
  return compileTransitionPreview(
    clips[0],
    clips[1],
    cacheDirectory: payload[1],
  );
}

Future<CompiledShow> compileProject(
  ShowProject project, {
  String? cacheDirectory,
  ShowCompileProgressCallback? onProgress,
}) async {
  if (project.clips.isEmpty) {
    throw const ShowCompileException('Добавьте хотя бы один клип');
  }
  final cache =
      cacheDirectory == null ? null : CompiledFrameCache(cacheDirectory);
  final clipFrames = <List<CompiledFrame>>[];
  for (var clipIndex = 0; clipIndex < project.clips.length; clipIndex++) {
    clipFrames.add(await _compileClipCached(
      project.clips[clipIndex],
      clipIndex,
      cache,
      onFrameProgress: (completed, total) => onProgress?.call(
        ShowCompileProgress(
          clipIndex: clipIndex,
          clipCount: project.clips.length,
          completedFrames: completed,
          totalFrames: total,
        ),
      ),
    ));
  }
  final frames = <CompiledFrame>[];
  for (var clipIndex = 0; clipIndex < project.clips.length; clipIndex++) {
    final clip = project.clips[clipIndex];
    final current = clipFrames[clipIndex];
    frames.addAll(current);
    if (project.clips.length > 1 &&
        clip.outgoingTransition != TransitionKind.none) {
      final nextIndex = (clipIndex + 1) % project.clips.length;
      frames.addAll(await _compileTransitionCached(
        current.last,
        clipFrames[nextIndex].first,
        clip,
        clipIndex,
        cache,
      ));
    }
    if (frames.length > _maxFrames) {
      throw const ShowCompileException('В проекте слишком много кадров');
    }
  }
  final result = CompiledShow(
    _buildPackage(frames),
    List.unmodifiable(frames),
    cacheHits: cache?.hits ?? 0,
    cacheMisses: cache?.misses ?? 0,
  );
  await cache?.trim();
  return result;
}

Future<CompiledShow> compileTransitionPreview(
  ShowClip outgoing,
  ShowClip incoming, {
  String? cacheDirectory,
}) async {
  final cache =
      cacheDirectory == null ? null : CompiledFrameCache(cacheDirectory);
  final outgoingFrame = await _compileClipEdgeCached(outgoing, 0, false, cache);
  final incomingFrame = await _compileClipEdgeCached(incoming, 1, true, cache);
  final frames = <CompiledFrame>[
    CompiledFrame(outgoingFrame.jpeg, 350000, 0),
    ...await _compileTransitionCached(
      outgoingFrame,
      incomingFrame,
      outgoing,
      0,
      cache,
    ),
    CompiledFrame(incomingFrame.jpeg, 350000, 1),
  ];
  final result = CompiledShow(
    _buildPackage(frames),
    List.unmodifiable(frames),
    cacheHits: cache?.hits ?? 0,
    cacheMisses: cache?.misses ?? 0,
  );
  await cache?.trim();
  return result;
}

Future<List<CompiledFrame>> _compileClipCached(
  ShowClip clip,
  int clipIndex,
  CompiledFrameCache? cache, {
  void Function(int completed, int total)? onFrameProgress,
}) async {
  if (cache == null) {
    final compiled = await _compileClip(clip, clipIndex);
    onFrameProgress?.call(compiled.length, compiled.length);
    return compiled;
  }
  if (clip.kind == ClipKind.gif) {
    return _compileGifCached(
      clip,
      clipIndex,
      cache,
      onFrameProgress: onFrameProgress,
    );
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotionCached(
      clip,
      clipIndex,
      cache,
      onFrameProgress: onFrameProgress,
    );
  }
  final key = 'frame-${await _visualCacheKey(clip)}-static';
  final cached = await cache.read(key);
  if (cached != null && cached.length == 1) {
    onFrameProgress?.call(1, 1);
    return [
      CompiledFrame(
        cached.single.jpeg,
        clip.durationMs.clamp(500, 10000) * 1000,
        clipIndex,
      ),
    ];
  }
  final compiled = await _compileClip(clip, clipIndex);
  await cache.write(
    key,
    [CachedFrameData(compiled.single.jpeg, 1)],
    maintain: false,
  );
  onFrameProgress?.call(1, 1);
  return compiled;
}

Future<CompiledFrame> _compileClipEdgeCached(
  ShowClip clip,
  int clipIndex,
  bool first,
  CompiledFrameCache? cache,
) async {
  if (cache == null) return _compileClipEdge(clip, clipIndex, first);
  if (clip.kind == ClipKind.gif) {
    return _compileGifEdgeCached(clip, clipIndex, first, cache);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotionEdgeCached(clip, clipIndex, first, cache);
  }
  return (await _compileClipCached(clip, clipIndex, cache)).single;
}

Future<String> _visualCacheKey(ShowClip clip) async {
  final motion = clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion;
  final sourcePath = motion ? clip.normalizedPath : clip.assetPath;
  if (sourcePath == null || sourcePath.isEmpty) {
    throw ShowCompileException('${clip.name} нужно подготовить заново');
  }
  return CompiledFrameCache.digestText(jsonEncode({
    'version': 3,
    'kind': clip.kind.name,
    'source': await _fileFingerprint(sourcePath),
    'layout': clip.layout.name,
    'offsetX': clip.offsetX,
    'offsetY': clip.offsetY,
    'scale': clip.scale,
    'rotation': clip.rotation,
  }));
}

Future<String> _fileFingerprint(String filePath) async {
  final file = File(filePath);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw FileSystemException('Файл не найден', filePath);
  }
  return '$filePath:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
}

Future<List<CompiledFrame>> _compileTransitionCached(
  CompiledFrame outgoing,
  CompiledFrame incoming,
  ShowClip clip,
  int clipIndex,
  CompiledFrameCache? cache,
) async {
  if (clip.outgoingTransition == TransitionKind.none) return const [];
  if (cache == null) {
    return _compileTransition(outgoing, incoming, clip, clipIndex);
  }
  final key = 'transition-${CompiledFrameCache.digestText(jsonEncode({
        'version': 2,
        'from': CompiledFrameCache.digestBytes(outgoing.jpeg),
        'to': CompiledFrameCache.digestBytes(incoming.jpeg),
        'kind': clip.outgoingTransition.name,
        'durationMs': clip.transitionDurationMs.clamp(200, 1500),
      }))}';
  final cached = await cache.read(key);
  if (cached != null) {
    return cached
        .map((frame) => CompiledFrame(frame.jpeg, frame.durationUs, clipIndex))
        .toList(growable: false);
  }
  final compiled = _compileTransition(outgoing, incoming, clip, clipIndex);
  await cache.write(
    key,
    compiled
        .map((frame) => CachedFrameData(frame.jpeg, frame.durationUs))
        .toList(growable: false),
  );
  return compiled;
}

Future<List<CompiledFrame>> _compileClip(
  ShowClip clip,
  int clipIndex,
) async {
  if (clip.kind == ClipKind.gif) {
    final bytes = await File(clip.assetPath).readAsBytes();
    return _compileGif(bytes, clip, clipIndex);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotion(clip, clipIndex);
  }
  final bytes = await File(clip.assetPath).readAsBytes();
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw ShowCompileException('Не удалось декодировать ${clip.name}');
  }
  final rendered = _renderFrame(decoded.frames.first, clip);
  return [
    CompiledFrame(
      _encodeFrame(rendered, clip.name),
      clip.durationMs.clamp(500, 10000) * 1000,
      clipIndex,
    ),
  ];
}

Future<CompiledFrame> _compileClipEdge(
  ShowClip clip,
  int clipIndex,
  bool first,
) async {
  if (clip.kind == ClipKind.gif) {
    final bytes = await File(clip.assetPath).readAsBytes();
    return _compileGifEdge(bytes, clip, clipIndex, first);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    final manifestPath = clip.normalizedPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      throw ShowCompileException('${clip.name} нужно подготовить заново');
    }
    final video = await loadNormalizedVideo(manifestPath);
    final schedule = scheduleNormalizedVideo(video, clip);
    final scheduled = first ? schedule.first : schedule.last;
    final decoded = image.decodeJpg(await File(scheduled.path).readAsBytes());
    if (decoded == null) {
      throw ShowCompileException('Не удалось прочитать кадр ${clip.name}');
    }
    return CompiledFrame(
      _encodeFrame(_renderFrame(decoded, clip), '${clip.name}, крайний кадр'),
      scheduled.durationUs,
      clipIndex,
    );
  }
  return (await _compileClip(clip, clipIndex)).single;
}

Future<List<CompiledFrame>> _compileNormalizedMotion(
  ShowClip clip,
  int clipIndex,
) async {
  final manifestPath = clip.normalizedPath;
  final label = clip.kind == ClipKind.mp4 ? 'MP4 ${clip.name}' : clip.name;
  if (manifestPath == null || manifestPath.isEmpty) {
    throw ShowCompileException('$label нужно подготовить заново');
  }
  try {
    final video = await loadNormalizedVideo(manifestPath);
    final schedule = scheduleNormalizedVideo(video, clip);
    final frames = <CompiledFrame>[];
    for (var index = 0; index < schedule.length; index++) {
      final scheduled = schedule[index];
      final decoded = image.decodeJpg(await File(scheduled.path).readAsBytes());
      if (decoded == null) {
        throw const FormatException(
            'Не удалось прочитать нормализованный кадр');
      }
      final rendered = _renderFrame(decoded, clip);
      frames.add(CompiledFrame(
        _encodeFrame(rendered, '${clip.name}, кадр ${index + 1}'),
        scheduled.durationUs,
        clipIndex,
      ));
    }
    return frames;
  } on ShowCompileException {
    rethrow;
  } catch (error) {
    throw ShowCompileException('Не удалось подготовить $label: $error');
  }
}

Future<List<CompiledFrame>> _compileNormalizedMotionCached(
  ShowClip clip,
  int clipIndex,
  CompiledFrameCache cache, {
  void Function(int completed, int total)? onFrameProgress,
}) async {
  final manifestPath = clip.normalizedPath;
  final label = clip.kind == ClipKind.mp4 ? 'MP4 ${clip.name}' : clip.name;
  if (manifestPath == null || manifestPath.isEmpty) {
    throw ShowCompileException('$label нужно подготовить заново');
  }
  try {
    final video = await loadNormalizedVideo(manifestPath);
    final schedule = scheduleNormalizedVideo(video, clip);
    final visualKey = await _visualCacheKey(clip);
    final encoded = <String, Uint8List>{};
    final uniquePaths = schedule.map((frame) => frame.path).toSet();
    var completed = 0;
    for (final scheduled in schedule) {
      if (encoded.containsKey(scheduled.path)) continue;
      encoded[scheduled.path] = await _compileNormalizedFrameCached(
        scheduled.path,
        clip,
        visualKey,
        cache,
      );
      completed++;
      onFrameProgress?.call(completed, uniquePaths.length);
    }
    return schedule
        .map((scheduled) => CompiledFrame(
              encoded[scheduled.path]!,
              scheduled.durationUs,
              clipIndex,
            ))
        .toList(growable: false);
  } on ShowCompileException {
    rethrow;
  } catch (error) {
    throw ShowCompileException('Не удалось подготовить $label: $error');
  }
}

Future<CompiledFrame> _compileNormalizedMotionEdgeCached(
  ShowClip clip,
  int clipIndex,
  bool first,
  CompiledFrameCache cache,
) async {
  final manifestPath = clip.normalizedPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    throw ShowCompileException('${clip.name} нужно подготовить заново');
  }
  final video = await loadNormalizedVideo(manifestPath);
  final schedule = scheduleNormalizedVideo(video, clip);
  final scheduled = first ? schedule.first : schedule.last;
  final jpeg = await _compileNormalizedFrameCached(
    scheduled.path,
    clip,
    await _visualCacheKey(clip),
    cache,
  );
  return CompiledFrame(jpeg, scheduled.durationUs, clipIndex);
}

Future<Uint8List> _compileNormalizedFrameCached(
  String framePath,
  ShowClip clip,
  String visualKey,
  CompiledFrameCache cache,
) async {
  final sourceKey = CompiledFrameCache.digestText(
    await _fileFingerprint(framePath),
  );
  final key = 'frame-$visualKey-$sourceKey';
  final cached = await cache.read(key);
  if (cached != null && cached.length == 1) return cached.single.jpeg;
  final decoded = image.decodeJpg(await File(framePath).readAsBytes());
  if (decoded == null) {
    throw ShowCompileException('Не удалось прочитать кадр ${clip.name}');
  }
  final jpeg = _encodeFrame(_renderFrame(decoded, clip), clip.name);
  await cache.write(
    key,
    [CachedFrameData(jpeg, 1)],
    maintain: false,
  );
  return jpeg;
}

Future<List<CompiledFrame>> _compileGifCached(
  ShowClip clip,
  int clipIndex,
  CompiledFrameCache cache, {
  void Function(int completed, int total)? onFrameProgress,
}) async {
  final bytes = await File(clip.assetPath).readAsBytes();
  final schedule = _scheduleGifBytes(bytes, clip);
  final visualKey = await _visualCacheKey(clip);
  final encoded = <int, Uint8List>{};
  final missing = <int>[];
  final sourceIndices = schedule.map((frame) => frame.sourceIndex).toSet();
  var completed = 0;
  for (final sourceIndex in sourceIndices) {
    final cached = await cache.read('frame-$visualKey-gif-$sourceIndex');
    if (cached != null && cached.length == 1) {
      encoded[sourceIndex] = cached.single.jpeg;
      completed++;
      onFrameProgress?.call(completed, sourceIndices.length);
    } else {
      missing.add(sourceIndex);
    }
  }
  if (missing.isNotEmpty) {
    final decoded = _decodeGif(bytes, clip);
    for (final sourceIndex in missing) {
      final jpeg = _encodeFrame(
        _renderFrame(decoded.frames[sourceIndex], clip),
        '${clip.name}, кадр ${sourceIndex + 1}',
      );
      encoded[sourceIndex] = jpeg;
      await cache.write(
        'frame-$visualKey-gif-$sourceIndex',
        [CachedFrameData(jpeg, 1)],
        maintain: false,
      );
      completed++;
      onFrameProgress?.call(completed, sourceIndices.length);
    }
  }
  return schedule
      .map((scheduled) => CompiledFrame(
            encoded[scheduled.sourceIndex]!,
            scheduled.durationUs,
            clipIndex,
          ))
      .toList(growable: false);
}

Future<CompiledFrame> _compileGifEdgeCached(
  ShowClip clip,
  int clipIndex,
  bool first,
  CompiledFrameCache cache,
) async {
  final bytes = await File(clip.assetPath).readAsBytes();
  final schedule = _scheduleGifBytes(bytes, clip);
  final scheduled = first ? schedule.first : schedule.last;
  final visualKey = await _visualCacheKey(clip);
  final key = 'frame-$visualKey-gif-${scheduled.sourceIndex}';
  final cached = await cache.read(key);
  if (cached != null && cached.length == 1) {
    return CompiledFrame(cached.single.jpeg, scheduled.durationUs, clipIndex);
  }
  final decoded = _decodeGif(bytes, clip);
  final jpeg = _encodeFrame(
    _renderFrame(decoded.frames[scheduled.sourceIndex], clip),
    '${clip.name}, кадр ${scheduled.sourceIndex + 1}',
  );
  await cache.write(
    key,
    [CachedFrameData(jpeg, 1)],
    maintain: false,
  );
  return CompiledFrame(jpeg, scheduled.durationUs, clipIndex);
}

List<CompiledFrame> _compileGif(
  Uint8List bytes,
  ShowClip clip,
  int clipIndex,
) {
  final decoded = _decodeGif(bytes, clip);
  final schedule = _scheduleGif(decoded, clip);
  final encoded = <int, Uint8List>{};
  return schedule.map((scheduled) {
    final jpeg = encoded.putIfAbsent(scheduled.sourceIndex, () {
      final rendered = _renderFrame(
        decoded.frames[scheduled.sourceIndex],
        clip,
      );
      return _encodeFrame(
        rendered,
        '${clip.name}, кадр ${scheduled.sourceIndex + 1}',
      );
    });
    return CompiledFrame(jpeg, scheduled.durationUs, clipIndex);
  }).toList(growable: false);
}

image.Image _decodeGif(Uint8List bytes, ShowClip clip) {
  final decoded = image.decodeGif(bytes);
  if (decoded == null || decoded.frames.isEmpty) {
    throw ShowCompileException(
        'GIF ${clip.name} повреждён или не поддерживается');
  }
  return decoded;
}

CompiledFrame _compileGifEdge(
  Uint8List bytes,
  ShowClip clip,
  int clipIndex,
  bool first,
) {
  final decoded = image.decodeGif(bytes);
  if (decoded == null || decoded.frames.isEmpty) {
    throw ShowCompileException(
        'GIF ${clip.name} повреждён или не поддерживается');
  }
  final schedule = _scheduleGif(decoded, clip);
  final scheduled = first ? schedule.first : schedule.last;
  final rendered = _renderFrame(decoded.frames[scheduled.sourceIndex], clip);
  return CompiledFrame(
    _encodeFrame(
      rendered,
      '${clip.name}, кадр ${scheduled.sourceIndex + 1}',
    ),
    scheduled.durationUs,
    clipIndex,
  );
}

List<ScheduledGifFrame> _scheduleGif(image.Image decoded, ShowClip clip) {
  final rawDurations = decoded.frames
      .map((frame) => frame.frameDuration <= 0 ? 100 : frame.frameDuration)
      .toList(growable: false);
  try {
    return scheduleGifFrames(rawDurations, clip);
  } on FormatException catch (error) {
    throw ShowCompileException('${error.message}: ${clip.name}');
  }
}

List<ScheduledGifFrame> _scheduleGifBytes(
  Uint8List bytes,
  ShowClip clip,
) {
  try {
    return scheduleGifFrames(inspectGifFrameDurations(bytes), clip);
  } on FormatException catch (error) {
    throw ShowCompileException('${error.message}: ${clip.name}');
  }
}

List<CompiledFrame> _compileTransition(
  CompiledFrame outgoing,
  CompiledFrame incoming,
  ShowClip clip,
  int clipIndex,
) {
  if (clip.outgoingTransition == TransitionKind.none) return const [];
  final from = image.decodeJpg(outgoing.jpeg);
  final to = image.decodeJpg(incoming.jpeg);
  if (from == null || to == null) {
    throw ShowCompileException(
      'Не удалось подготовить переход после ${clip.name}',
    );
  }
  final durationUs = clip.transitionDurationMs.clamp(200, 1500) * 1000;
  final frameCount = math.max(1, (durationUs * 60 / 1000000).round());
  final frameDuration = durationUs ~/ frameCount;
  final remainder = durationUs % frameCount;
  return List.generate(frameCount, (index) {
    final progress = _ease((index + 1) / frameCount);
    final rendered = _renderTransition(
      from,
      to,
      clip.outgoingTransition,
      progress,
    );
    return CompiledFrame(
      _encodeFrame(
        rendered,
        '${clip.name}, переход ${clip.outgoingTransition.label}',
      ),
      frameDuration + (index < remainder ? 1 : 0),
      clipIndex,
    );
  }, growable: false);
}

image.Image _renderTransition(
  image.Image from,
  image.Image to,
  TransitionKind kind,
  double progress,
) {
  return switch (kind) {
    TransitionKind.none => image.Image.from(to, noAnimation: true),
    TransitionKind.dissolve => _blendTransition(from, to, progress),
    TransitionKind.radialBloom => _radialTransition(from, to, progress),
    TransitionKind.lightSweep => _sweepTransition(from, to, progress),
    TransitionKind.depthFlow => _depthTransition(from, to, progress),
  };
}

image.Image _blendTransition(
  image.Image from,
  image.Image to,
  double amount,
) {
  final result = image.Image(width: _canvasSize, height: _canvasSize);
  for (var y = 0; y < _canvasSize; y++) {
    for (var x = 0; x < _canvasSize; x++) {
      _setMixedPixel(
          result, x, y, from.getPixel(x, y), to.getPixel(x, y), amount);
    }
  }
  return result;
}

image.Image _radialTransition(
  image.Image from,
  image.Image to,
  double progress,
) {
  final result = image.Image(width: _canvasSize, height: _canvasSize);
  const center = (_canvasSize - 1) / 2;
  const maximumDistance = 565.0;
  final radius = progress * 1.12;
  const feather = 0.13;
  for (var y = 0; y < _canvasSize; y++) {
    final dy = y - center;
    for (var x = 0; x < _canvasSize; x++) {
      final dx = x - center;
      final distance = math.sqrt(dx * dx + dy * dy) / maximumDistance;
      final amount =
          1 - _smoothStep(radius - feather, radius + feather, distance);
      _setMixedPixel(
          result, x, y, from.getPixel(x, y), to.getPixel(x, y), amount);
    }
  }
  return result;
}

image.Image _sweepTransition(
  image.Image from,
  image.Image to,
  double progress,
) {
  final result = image.Image(width: _canvasSize, height: _canvasSize);
  final edge = progress * 1.5 - 0.25;
  const feather = 0.16;
  for (var y = 0; y < _canvasSize; y++) {
    for (var x = 0; x < _canvasSize; x++) {
      final position = (x * 0.68 + y * 0.32) / (_canvasSize - 1);
      final amount = 1 - _smoothStep(edge - feather, edge + feather, position);
      final highlight = math.max(0.0, 1 - ((position - edge).abs() / 0.055));
      _setMixedPixel(
        result,
        x,
        y,
        from.getPixel(x, y),
        to.getPixel(x, y),
        amount,
        highlight: highlight * 0.12,
      );
    }
  }
  return result;
}

image.Image _depthTransition(
  image.Image from,
  image.Image to,
  double progress,
) {
  final result = image.Image(width: _canvasSize, height: _canvasSize);
  const center = (_canvasSize - 1) / 2;
  final fromScale = 1 + progress * 0.1;
  final toScale = 0.9 + progress * 0.1;
  for (var y = 0; y < _canvasSize; y++) {
    for (var x = 0; x < _canvasSize; x++) {
      final fromX =
          ((x - center) / fromScale + center).round().clamp(0, _canvasSize - 1);
      final fromY =
          ((y - center) / fromScale + center).round().clamp(0, _canvasSize - 1);
      final toX =
          ((x - center) / toScale + center).round().clamp(0, _canvasSize - 1);
      final toY =
          ((y - center) / toScale + center).round().clamp(0, _canvasSize - 1);
      _setMixedPixel(
        result,
        x,
        y,
        from.getPixel(fromX, fromY),
        to.getPixel(toX, toY),
        progress,
      );
    }
  }
  return result;
}

void _setMixedPixel(
  image.Image target,
  int x,
  int y,
  image.Pixel from,
  image.Pixel to,
  double amount, {
  double highlight = 0,
}) {
  final mix = amount.clamp(0.0, 1.0);
  final glow = highlight.clamp(0.0, 1.0);
  int channel(num a, num b) =>
      (a + (b - a) * mix + 255 * glow).round().clamp(0, 255);
  target.setPixelRgb(
    x,
    y,
    channel(from.r, to.r),
    channel(from.g, to.g),
    channel(from.b, to.b),
  );
}

double _ease(double value) => value * value * (3 - 2 * value);

double _smoothStep(double edge0, double edge1, double value) {
  final normalized = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return normalized * normalized * (3 - 2 * normalized);
}

image.Image _renderFrame(image.Image sourceFrame, ShowClip clip) {
  final source = image.Image.from(sourceFrame, noAnimation: true);
  final fitScale = clip.layout == ClipLayout.fit
      ? math.min(_canvasSize / source.width, _canvasSize / source.height)
      : math.max(_canvasSize / source.width, _canvasSize / source.height);
  final scale = fitScale * clip.scale.clamp(0.1, 8);
  final width = math.max(1, (source.width * scale).round());
  final height = math.max(1, (source.height * scale).round());
  final resized = image.copyResize(
    source,
    width: width,
    height: height,
    interpolation: image.Interpolation.linear,
  );
  final rotated = clip.rotation == 0
      ? resized
      : image.copyRotate(
          resized,
          angle: clip.rotation * 180 / math.pi,
          interpolation: image.Interpolation.linear,
        );
  final canvas = image.Image(width: _canvasSize, height: _canvasSize);
  image.fill(canvas, color: image.ColorRgb8(0, 0, 0));
  image.compositeImage(
    canvas,
    rotated,
    dstX: ((_canvasSize - rotated.width) / 2 + clip.offsetX).round(),
    dstY: ((_canvasSize - rotated.height) / 2 + clip.offsetY).round(),
  );
  for (var y = 0; y < _canvasSize; y++) {
    final bounds = _circleBounds[y];
    for (var x = 0; x < bounds.left; x++) {
      canvas.setPixelRgb(x, y, 0, 0, 0);
    }
    for (var x = bounds.right + 1; x < _canvasSize; x++) {
      canvas.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  return canvas;
}

Uint8List _encodeFrame(image.Image frame, String label) {
  for (final quality in const [88, 82, 76, 68, 60, 52, 44, 36]) {
    final encoded = image.encodeJpg(
      frame,
      quality: quality,
      chroma: image.JpegChroma.yuv420,
    );
    if (encoded.length <= _maxFrameBytes) return encoded;
  }
  throw ShowCompileException('$label слишком сложный для плавного вывода');
}

Uint8List _buildPackage(List<CompiledFrame> frames) {
  if (frames.isEmpty || frames.length > _maxFrames) {
    throw const ShowCompileException('Некорректное число кадров');
  }
  final indexSize = frames.length * _frameEntrySize;
  final payloadSize =
      frames.fold<int>(0, (sum, frame) => sum + frame.jpeg.length);
  final payloadOffset = _headerSize + indexSize;
  final packageSize = payloadOffset + payloadSize;
  if (packageSize > _maxPackageBytes) {
    throw ShowCompileException(
      'Шоу занимает ${(packageSize / 1048576).toStringAsFixed(1)} МБ, максимум 20 МБ',
    );
  }

  final header = Uint8List(_headerSize);
  header.setAll(0, [0x5A, 0x53, 0x48, 0x4F, 0x57, 0x56, 0x31, 0]);
  final h = ByteData.sublistView(header);
  h.setUint16(8, 1, Endian.little);
  h.setUint16(10, _headerSize, Endian.little);
  h.setUint32(12, packageSize, Endian.little);
  h.setUint16(16, _canvasSize, Endian.little);
  h.setUint16(18, _canvasSize, Endian.little);
  h.setUint16(20, 60, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, frames.length, Endian.little);
  h.setUint32(28, _headerSize, Endian.little);
  h.setUint32(32, indexSize, Endian.little);
  h.setUint32(36, payloadOffset, Endian.little);
  h.setUint32(40, payloadSize, Endian.little);
  h.setUint16(52, 1, Endian.little);
  h.setUint16(54, 1, Endian.little);
  h.setUint32(56, 1, Endian.little);

  final index = Uint8List(indexSize);
  final i = ByteData.sublistView(index);
  var payloadCursor = 0;
  for (var frameIndex = 0; frameIndex < frames.length; frameIndex++) {
    final entry = frameIndex * _frameEntrySize;
    final frame = frames[frameIndex];
    i.setUint32(entry, payloadCursor, Endian.little);
    i.setUint32(entry + 4, frame.jpeg.length, Endian.little);
    i.setUint32(entry + 8, frame.durationUs, Endian.little);
    payloadCursor += frame.jpeg.length;
  }
  final payload = BytesBuilder(copy: false);
  for (final frame in frames) {
    payload.add(frame.jpeg);
  }
  final payloadBytes = payload.takeBytes();
  h.setUint32(48, _crc32(payloadBytes), Endian.little);
  final manifest = BytesBuilder(copy: false)
    ..add(header)
    ..add(index);
  h.setUint32(44, _crc32(manifest.toBytes()), Endian.little);

  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(index)
        ..add(payloadBytes))
      .takeBytes();
}

int _crc32(Uint8List bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
