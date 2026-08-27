import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'compiled_frame_cache.dart';
import 'frame_pipeline.dart';
import 'media_timeline.dart';
import 'project_model.dart';
import 'show_package.dart' show maxShowBytes;
import 'ui_frame_pipeline.dart';
import 'video_manifest.dart';

export 'frame_pipeline.dart'
    show DartFramePipeline, FramePipeline, ShowCompileException;
export 'ui_frame_pipeline.dart' show UiFramePipeline;

const int _canvasSize = showCanvasSize;
const int _headerSize = 64;
const int _frameEntrySize = 16;
const int _maxFrames = 20000;

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

/// Fast path for the application: compiles on the root isolate with the GPU
/// pipeline (Skia decode, raster-thread rendering, native JPEG encoder). The
/// per-frame Dart work is only orchestration, so the UI stays responsive.
Future<CompiledShow> compileProjectFast(
  ShowProject project, {
  String? cacheDirectory,
  ShowCompileProgressCallback? onProgress,
}) async {
  final pipeline = UiFramePipeline();
  try {
    return await compileProject(
      project,
      cacheDirectory: cacheDirectory,
      onProgress: onProgress,
      pipeline: pipeline,
    );
  } finally {
    pipeline.dispose();
  }
}

/// Fast transition preview on the root isolate; see [compileProjectFast].
Future<CompiledShow> compileTransitionPreviewFast(
  ShowClip outgoing,
  ShowClip incoming, {
  String? cacheDirectory,
}) async {
  final pipeline = UiFramePipeline();
  try {
    return await compileTransitionPreview(
      outgoing,
      incoming,
      cacheDirectory: cacheDirectory,
      pipeline: pipeline,
    );
  } finally {
    pipeline.dispose();
  }
}

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
  FramePipeline? pipeline,
}) async {
  if (project.clips.isEmpty) {
    throw const ShowCompileException('Добавьте хотя бы один клип');
  }
  final engine = pipeline ?? DartFramePipeline();
  final cache =
      cacheDirectory == null ? null : CompiledFrameCache(cacheDirectory);
  final clipFrames = <List<CompiledFrame>>[];
  for (var clipIndex = 0; clipIndex < project.clips.length; clipIndex++) {
    clipFrames.add(await _compileClipCached(
      project.clips[clipIndex],
      clipIndex,
      cache,
      engine,
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
        engine,
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
  FramePipeline? pipeline,
}) async {
  final engine = pipeline ?? DartFramePipeline();
  final cache =
      cacheDirectory == null ? null : CompiledFrameCache(cacheDirectory);
  final outgoingFrame =
      await _compileClipEdgeCached(outgoing, 0, false, cache, engine);
  final incomingFrame =
      await _compileClipEdgeCached(incoming, 1, true, cache, engine);
  final frames = <CompiledFrame>[
    CompiledFrame(outgoingFrame.jpeg, 350000, 0),
    ...await _compileTransitionCached(
      outgoingFrame,
      incomingFrame,
      outgoing,
      0,
      cache,
      engine,
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
  CompiledFrameCache? cache,
  FramePipeline engine, {
  void Function(int completed, int total)? onFrameProgress,
}) async {
  if (cache == null) {
    final compiled = await _compileClip(clip, clipIndex, engine);
    onFrameProgress?.call(compiled.length, compiled.length);
    return compiled;
  }
  if (clip.kind == ClipKind.gif) {
    return _compileGifCached(
      clip,
      clipIndex,
      cache,
      engine,
      onFrameProgress: onFrameProgress,
    );
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotionCached(
      clip,
      clipIndex,
      cache,
      engine,
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
  final compiled = await _compileClip(clip, clipIndex, engine);
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
  FramePipeline engine,
) async {
  if (cache == null) return _compileClipEdge(clip, clipIndex, first, engine);
  if (clip.kind == ClipKind.gif) {
    return _compileGifEdgeCached(clip, clipIndex, first, cache, engine);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotionEdgeCached(
        clip, clipIndex, first, cache, engine);
  }
  return (await _compileClipCached(clip, clipIndex, cache, engine)).single;
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
  FramePipeline engine,
) async {
  if (clip.outgoingTransition == TransitionKind.none) return const [];
  if (cache == null) {
    return _compileTransition(outgoing, incoming, clip, clipIndex, engine);
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
  final compiled =
      await _compileTransition(outgoing, incoming, clip, clipIndex, engine);
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
  FramePipeline engine,
) async {
  if (clip.kind == ClipKind.gif) {
    final bytes = await File(clip.assetPath).readAsBytes();
    return _compileGif(bytes, clip, clipIndex, engine);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    return _compileNormalizedMotion(clip, clipIndex, engine);
  }
  final bytes = await File(clip.assetPath).readAsBytes();
  final decoded = await engine.decodeImage(bytes, clip.name);
  try {
    return [
      CompiledFrame(
        await engine.renderClipFrame(decoded, clip, clip.name),
        clip.durationMs.clamp(500, 10000) * 1000,
        clipIndex,
      ),
    ];
  } finally {
    decoded.dispose();
  }
}

Future<CompiledFrame> _compileClipEdge(
  ShowClip clip,
  int clipIndex,
  bool first,
  FramePipeline engine,
) async {
  if (clip.kind == ClipKind.gif) {
    final bytes = await File(clip.assetPath).readAsBytes();
    return _compileGifEdge(bytes, clip, clipIndex, first, engine);
  }
  if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
    final manifestPath = clip.normalizedPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      throw ShowCompileException('${clip.name} нужно подготовить заново');
    }
    final video = await loadNormalizedVideo(manifestPath);
    final schedule = scheduleNormalizedVideo(video, clip);
    final scheduled = first ? schedule.first : schedule.last;
    final decoded = await engine.decodeImage(
      await File(scheduled.path).readAsBytes(),
      clip.name,
    );
    try {
      return CompiledFrame(
        await engine.renderClipFrame(
            decoded, clip, '${clip.name}, крайний кадр'),
        scheduled.durationUs,
        clipIndex,
      );
    } finally {
      decoded.dispose();
    }
  }
  return (await _compileClip(clip, clipIndex, engine)).single;
}

Future<List<CompiledFrame>> _compileNormalizedMotion(
  ShowClip clip,
  int clipIndex,
  FramePipeline engine,
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
      final decoded = await engine.decodeImage(
        await File(scheduled.path).readAsBytes(),
        clip.name,
      );
      try {
        frames.add(CompiledFrame(
          await engine.renderClipFrame(
              decoded, clip, '${clip.name}, кадр ${index + 1}'),
          scheduled.durationUs,
          clipIndex,
        ));
      } finally {
        decoded.dispose();
      }
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
  CompiledFrameCache cache,
  FramePipeline engine, {
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
        engine,
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
  FramePipeline engine,
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
    engine,
  );
  return CompiledFrame(jpeg, scheduled.durationUs, clipIndex);
}

Future<Uint8List> _compileNormalizedFrameCached(
  String framePath,
  ShowClip clip,
  String visualKey,
  CompiledFrameCache cache,
  FramePipeline engine,
) async {
  final sourceKey = CompiledFrameCache.digestText(
    await _fileFingerprint(framePath),
  );
  final key = 'frame-$visualKey-$sourceKey';
  final cached = await cache.read(key);
  if (cached != null && cached.length == 1) return cached.single.jpeg;
  final decoded = await engine.decodeImage(
    await File(framePath).readAsBytes(),
    clip.name,
  );
  Uint8List jpeg;
  try {
    jpeg = await engine.renderClipFrame(decoded, clip, clip.name);
  } finally {
    decoded.dispose();
  }
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
  CompiledFrameCache cache,
  FramePipeline engine, {
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
    missing.sort();
    final animation = await engine.decodeAnimation(bytes, clip.name);
    try {
      for (final sourceIndex in missing) {
        final source = await animation.frameAt(sourceIndex);
        Uint8List jpeg;
        try {
          jpeg = await engine.renderClipFrame(
            source,
            clip,
            '${clip.name}, кадр ${sourceIndex + 1}',
          );
        } finally {
          source.dispose();
        }
        encoded[sourceIndex] = jpeg;
        await cache.write(
          'frame-$visualKey-gif-$sourceIndex',
          [CachedFrameData(jpeg, 1)],
          maintain: false,
        );
        completed++;
        onFrameProgress?.call(completed, sourceIndices.length);
      }
    } finally {
      animation.dispose();
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
  FramePipeline engine,
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
  final jpeg = await _renderGifFrame(
    bytes,
    clip,
    scheduled.sourceIndex,
    engine,
  );
  await cache.write(
    key,
    [CachedFrameData(jpeg, 1)],
    maintain: false,
  );
  return CompiledFrame(jpeg, scheduled.durationUs, clipIndex);
}

Future<List<CompiledFrame>> _compileGif(
  Uint8List bytes,
  ShowClip clip,
  int clipIndex,
  FramePipeline engine,
) async {
  final schedule = _scheduleGifBytes(bytes, clip);
  final needed = schedule.map((frame) => frame.sourceIndex).toSet().toList()
    ..sort();
  final encoded = <int, Uint8List>{};
  final animation = await engine.decodeAnimation(bytes, clip.name);
  try {
    for (final sourceIndex in needed) {
      final source = await animation.frameAt(sourceIndex);
      try {
        encoded[sourceIndex] = await engine.renderClipFrame(
          source,
          clip,
          '${clip.name}, кадр ${sourceIndex + 1}',
        );
      } finally {
        source.dispose();
      }
    }
  } finally {
    animation.dispose();
  }
  return schedule
      .map((scheduled) => CompiledFrame(
            encoded[scheduled.sourceIndex]!,
            scheduled.durationUs,
            clipIndex,
          ))
      .toList(growable: false);
}

Future<CompiledFrame> _compileGifEdge(
  Uint8List bytes,
  ShowClip clip,
  int clipIndex,
  bool first,
  FramePipeline engine,
) async {
  final schedule = _scheduleGifBytes(bytes, clip);
  final scheduled = first ? schedule.first : schedule.last;
  return CompiledFrame(
    await _renderGifFrame(bytes, clip, scheduled.sourceIndex, engine),
    scheduled.durationUs,
    clipIndex,
  );
}

Future<Uint8List> _renderGifFrame(
  Uint8List bytes,
  ShowClip clip,
  int sourceIndex,
  FramePipeline engine,
) async {
  final animation = await engine.decodeAnimation(bytes, clip.name);
  try {
    final source = await animation.frameAt(sourceIndex);
    try {
      return await engine.renderClipFrame(
        source,
        clip,
        '${clip.name}, кадр ${sourceIndex + 1}',
      );
    } finally {
      source.dispose();
    }
  } finally {
    animation.dispose();
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

Future<List<CompiledFrame>> _compileTransition(
  CompiledFrame outgoing,
  CompiledFrame incoming,
  ShowClip clip,
  int clipIndex,
  FramePipeline engine,
) async {
  if (clip.outgoingTransition == TransitionKind.none) return const [];
  final PipelineImage from;
  final PipelineImage to;
  try {
    from = await engine.decodeImage(outgoing.jpeg, clip.name);
  } catch (_) {
    throw ShowCompileException(
      'Не удалось подготовить переход после ${clip.name}',
    );
  }
  try {
    to = await engine.decodeImage(incoming.jpeg, clip.name);
  } catch (_) {
    from.dispose();
    throw ShowCompileException(
      'Не удалось подготовить переход после ${clip.name}',
    );
  }
  try {
    final durationUs = clip.transitionDurationMs.clamp(200, 1500) * 1000;
    final frameCount = math.max(1, (durationUs * 60 / 1000000).round());
    final frameDuration = durationUs ~/ frameCount;
    final remainder = durationUs % frameCount;
    final frames = <CompiledFrame>[];
    for (var index = 0; index < frameCount; index++) {
      final progress = _ease((index + 1) / frameCount);
      frames.add(CompiledFrame(
        await engine.renderTransitionFrame(
          from,
          to,
          clip.outgoingTransition,
          progress,
          '${clip.name}, переход ${clip.outgoingTransition.label}',
        ),
        frameDuration + (index < remainder ? 1 : 0),
        clipIndex,
      ));
    }
    return frames;
  } finally {
    from.dispose();
    to.dispose();
  }
}

double _ease(double value) => value * value * (3 - 2 * value);

Uint8List _buildPackage(List<CompiledFrame> frames) {
  if (frames.isEmpty || frames.length > _maxFrames) {
    throw const ShowCompileException('Некорректное число кадров');
  }
  final indexSize = frames.length * _frameEntrySize;
  final payloadSize =
      frames.fold<int>(0, (sum, frame) => sum + frame.jpeg.length);
  final payloadOffset = _headerSize + indexSize;
  final packageSize = payloadOffset + payloadSize;
  if (packageSize > maxShowBytes) {
    throw ShowCompileException(
      'Шоу занимает ${(packageSize / 1048576).toStringAsFixed(1)} МБ, максимум 23 МБ',
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

Uint32List? _crcTableCache;

Uint32List _crcTable() {
  final cached = _crcTableCache;
  if (cached != null) return cached;
  final table = Uint32List(256);
  for (var index = 0; index < 256; index++) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? (value >> 1) ^ 0xEDB88320 : value >> 1;
    }
    table[index] = value;
  }
  _crcTableCache = table;
  return table;
}

int _crc32(Uint8List bytes) {
  final table = _crcTable();
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = (crc >> 8) ^ table[(crc ^ byte) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
