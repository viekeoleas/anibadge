import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'media_timeline.dart';
import 'project_model.dart';
import 'show_compiler.dart';
import 'video_manifest.dart';

const int _draftDecodeWidth = 480;

class DraftClipCanvas extends StatefulWidget {
  const DraftClipCanvas({
    super.key,
    required this.clip,
    required this.onChanged,
    this.interactive = true,
    this.showBorder = true,
  });

  final ShowClip clip;
  final ValueChanged<ShowClip> onChanged;
  final bool interactive;
  final bool showBorder;

  @override
  State<DraftClipCanvas> createState() => _DraftClipCanvasState();
}

class _DraftClipCanvasState extends State<DraftClipCanvas> {
  late double _startScale;
  late double _startRotation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final diameter = math.min(constraints.maxWidth, constraints.maxHeight);
      final surface = Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: widget.showBorder
              ? Border.all(color: const Color(0xFF90CAF9), width: 2)
              : null,
        ),
        child: ClipOval(
          child: ColoredBox(
            color: Colors.black,
            child: Transform.translate(
              offset: Offset(
                widget.clip.offsetX * diameter / 800,
                widget.clip.offsetY * diameter / 800,
              ),
              child: Transform.rotate(
                angle: widget.clip.rotation,
                child: Transform.scale(
                  scale: widget.clip.scale,
                  child: SizedBox.square(
                    dimension: diameter,
                    child: _DraftMedia(
                      clip: widget.clip,
                      fit: widget.clip.layout == ClipLayout.fit
                          ? BoxFit.contain
                          : BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return Center(
        child: widget.interactive
            ? GestureDetector(
                onScaleStart: (_) {
                  _startScale = widget.clip.scale;
                  _startRotation = widget.clip.rotation;
                },
                onScaleUpdate: (details) {
                  widget.onChanged(widget.clip.copyWith(
                    scale: (_startScale * details.scale).clamp(0.1, 8),
                    rotation: _startRotation + details.rotation,
                    offsetX: (widget.clip.offsetX +
                            details.focalPointDelta.dx * 800 / diameter)
                        .clamp(-800, 800),
                    offsetY: (widget.clip.offsetY +
                            details.focalPointDelta.dy * 800 / diameter)
                        .clamp(-800, 800),
                  ));
                },
                child: surface,
              )
            : surface,
      );
    });
  }
}

class _DraftMedia extends StatelessWidget {
  const _DraftMedia({required this.clip, required this.fit});

  final ShowClip clip;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (clip.kind == ClipKind.gif) {
      return _GifDraftPreview(clip: clip, fit: fit);
    }
    if (clip.kind == ClipKind.mp4 || clip.kind.isGeneratedMotion) {
      return _MotionDraftPreview(clip: clip, fit: fit);
    }
    return Image.file(
      File(clip.assetPath),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const Center(
        child: Text('Не удалось открыть медиа'),
      ),
    );
  }
}

class _GifDraftPreview extends StatefulWidget {
  const _GifDraftPreview({required this.clip, required this.fit});

  final ShowClip clip;
  final BoxFit fit;

  @override
  State<_GifDraftPreview> createState() => _GifDraftPreviewState();
}

class _GifDraftPreviewState extends State<_GifDraftPreview> {
  ui.Codec? _codec;
  ui.Image? _image;
  Uint8List? _bytes;
  List<ScheduledGifFrame>? _schedule;
  Timer? _timer;
  Object? _error;
  int _scheduleIndex = 0;
  int _decodedSourceIndex = -1;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _GifDraftPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_timingChanged(oldWidget.clip, widget.clip)) unawaited(_load());
  }

  bool _timingChanged(ShowClip before, ShowClip after) =>
      before.assetPath != after.assetPath ||
      before.trimStartMs != after.trimStartMs ||
      before.trimEndMs != after.trimEndMs ||
      before.speed != after.speed ||
      before.repeat != after.repeat ||
      before.durationMs != after.durationMs;

  Future<void> _load() async {
    final generation = ++_generation;
    _timer?.cancel();
    _codec?.dispose();
    _codec = null;
    final oldImage = _image;
    _image = null;
    oldImage?.dispose();
    _decodedSourceIndex = -1;
    _scheduleIndex = 0;
    try {
      final bytes = await File(widget.clip.assetPath).readAsBytes();
      final schedule = scheduleGifFrames(
        inspectGifFrameDurations(bytes),
        widget.clip,
      );
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _draftDecodeWidth,
      );
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _bytes = bytes;
      _schedule = schedule;
      _codec = codec;
      _error = null;
      await _showScheduledFrame(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  Future<void> _resetCodec(int generation) async {
    final bytes = _bytes;
    if (bytes == null) return;
    _codec?.dispose();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _draftDecodeWidth,
    );
    if (!mounted || generation != _generation) {
      codec.dispose();
      return;
    }
    _codec = codec;
    _decodedSourceIndex = -1;
  }

  Future<void> _showScheduledFrame(int generation) async {
    final schedule = _schedule;
    if (!mounted ||
        generation != _generation ||
        schedule == null ||
        schedule.isEmpty) {
      return;
    }
    final scheduled = schedule[_scheduleIndex];
    if (scheduled.sourceIndex < _decodedSourceIndex) {
      await _resetCodec(generation);
    }
    var nextImage = _image;
    while (_decodedSourceIndex < scheduled.sourceIndex) {
      final codec = _codec;
      if (codec == null) return;
      final frame = await codec.getNextFrame();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      if (nextImage != _image) nextImage?.dispose();
      nextImage = frame.image;
      _decodedSourceIndex++;
    }
    if (nextImage != null && !identical(nextImage, _image)) {
      final previous = _image;
      setState(() => _image = nextImage);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    } else if (_image == null) {
      setState(() {});
    }
    _timer = Timer(Duration(microseconds: scheduled.durationUs), () {
      if (!mounted || generation != _generation) return;
      _scheduleIndex = (_scheduleIndex + 1) % schedule.length;
      unawaited(_showScheduledFrame(generation));
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _codec?.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Не удалось открыть GIF: $_error'));
    }
    final frame = _image;
    if (frame == null) return const Center(child: CircularProgressIndicator());
    return RawImage(
      image: frame,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _MotionDraftPreview extends StatefulWidget {
  const _MotionDraftPreview({required this.clip, required this.fit});

  final ShowClip clip;
  final BoxFit fit;

  @override
  State<_MotionDraftPreview> createState() => _MotionDraftPreviewState();
}

class _MotionDraftPreviewState extends State<_MotionDraftPreview> {
  List<NormalizedVideoFrame>? _frames;
  Object? _error;
  Timer? _timer;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MotionDraftPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_timingChanged(oldWidget.clip, widget.clip)) _load();
  }

  bool _timingChanged(ShowClip before, ShowClip after) =>
      before.normalizedPath != after.normalizedPath ||
      before.trimStartMs != after.trimStartMs ||
      before.trimEndMs != after.trimEndMs ||
      before.speed != after.speed ||
      before.repeat != after.repeat ||
      before.durationMs != after.durationMs;

  Future<void> _load() async {
    _timer?.cancel();
    final manifestPath = widget.clip.normalizedPath;
    if (manifestPath == null) {
      setState(() => _error = 'Видео нужно импортировать заново');
      return;
    }
    try {
      final video = await loadNormalizedVideo(manifestPath);
      final frames = scheduleNormalizedVideo(video, widget.clip);
      if (!mounted) return;
      setState(() {
        _frames = frames;
        _error = null;
        _frameIndex = 0;
      });
      _schedule();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _schedule() {
    final frames = _frames;
    if (frames == null || frames.isEmpty) return;
    _timer = Timer(Duration(microseconds: frames[_frameIndex].durationUs), () {
      if (!mounted) return;
      setState(() => _frameIndex = (_frameIndex + 1) % frames.length);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('Не удалось открыть анимацию: $_error'));
    }
    final frames = _frames;
    if (frames == null || frames.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Image.file(
      File(frames[_frameIndex].path),
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}

class ProjectDraftPreview extends StatefulWidget {
  const ProjectDraftPreview({super.key, required this.project});

  final ShowProject project;

  @override
  State<ProjectDraftPreview> createState() => _ProjectDraftPreviewState();
}

class _ProjectDraftPreviewState extends State<ProjectDraftPreview> {
  List<int>? _durationsUs;
  Timer? _timer;
  Object? _error;
  int _clipIndex = 0;
  int _playbackEpoch = 0;
  int _generation = 0;
  TransitionKind _activeTransition = TransitionKind.none;
  Duration _transitionDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTimeline());
  }

  @override
  void didUpdateWidget(covariant ProjectDraftPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_timelineChanged(oldWidget.project, widget.project)) {
      unawaited(_loadTimeline());
    }
  }

  bool _timelineChanged(ShowProject before, ShowProject after) {
    if (before.clips.length != after.clips.length) return true;
    for (var index = 0; index < before.clips.length; index++) {
      final left = before.clips[index];
      final right = after.clips[index];
      if (left.id != right.id ||
          left.assetPath != right.assetPath ||
          left.normalizedPath != right.normalizedPath ||
          left.durationMs != right.durationMs ||
          left.trimStartMs != right.trimStartMs ||
          left.trimEndMs != right.trimEndMs ||
          left.speed != right.speed ||
          left.repeat != right.repeat ||
          left.outgoingTransition != right.outgoingTransition ||
          left.transitionDurationMs != right.transitionDurationMs) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadTimeline() async {
    final generation = ++_generation;
    _timer?.cancel();
    if (widget.project.clips.isEmpty) return;
    try {
      final durations = <int>[];
      for (final clip in widget.project.clips) {
        durations.add(await clipPlaybackDurationUs(clip));
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _durationsUs = durations;
        _error = null;
        _clipIndex = 0;
        _playbackEpoch++;
        _activeTransition = TransitionKind.none;
        _transitionDuration = Duration.zero;
      });
      _scheduleClip(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  void _scheduleClip(int generation) {
    final durations = _durationsUs;
    if (durations == null || durations.isEmpty) return;
    _timer = Timer(Duration(microseconds: durations[_clipIndex]), () {
      if (!mounted || generation != _generation) return;
      _advance(generation);
    });
  }

  void _advance(int generation) {
    final clips = widget.project.clips;
    final outgoing = clips[_clipIndex];
    final nextIndex = (_clipIndex + 1) % clips.length;
    if (clips.length == 1) {
      _scheduleClip(generation);
      return;
    }
    if (outgoing.outgoingTransition == TransitionKind.none) {
      setState(() {
        _clipIndex = nextIndex;
        _playbackEpoch++;
        _activeTransition = TransitionKind.none;
        _transitionDuration = Duration.zero;
      });
      _scheduleClip(generation);
      return;
    }
    final duration = Duration(
      milliseconds: outgoing.transitionDurationMs.clamp(200, 1500),
    );
    setState(() {
      _clipIndex = nextIndex;
      _activeTransition = outgoing.outgoingTransition;
      _transitionDuration = duration;
    });
    _timer = Timer(duration, () {
      if (!mounted || generation != _generation) return;
      setState(() {
        _playbackEpoch++;
        _activeTransition = TransitionKind.none;
        _transitionDuration = Duration.zero;
      });
      _scheduleClip(generation);
    });
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
    return switch (_activeTransition) {
      TransitionKind.none => child,
      TransitionKind.dissolve => FadeTransition(opacity: curved, child: child),
      TransitionKind.radialBloom => FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.72, end: 1.0).animate(curved),
            child: child,
          ),
        ),
      TransitionKind.lightSweep => FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position:
                Tween(begin: const Offset(0.16, 0), end: Offset.zero).animate(
              curved,
            ),
            child: child,
          ),
        ),
      TransitionKind.depthFlow => FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(curved),
            child: child,
          ),
        ),
    };
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Не удалось открыть превью проекта: $_error',
          textAlign: TextAlign.center,
        ),
      );
    }
    final durations = _durationsUs;
    if (durations == null || durations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final clip = widget.project.clips[_clipIndex];
    return AnimatedSwitcher(
      duration: _transitionDuration,
      transitionBuilder: _buildTransition,
      child: DraftClipCanvas(
        key: ValueKey('${clip.id}:$_playbackEpoch'),
        clip: clip,
        onChanged: (_) {},
        interactive: false,
        showBorder: false,
      ),
    );
  }
}

class CompiledShowPreview extends StatefulWidget {
  const CompiledShowPreview({super.key, required this.show});

  final CompiledShow show;

  @override
  State<CompiledShowPreview> createState() => _CompiledShowPreviewState();
}

class _CompiledShowPreviewState extends State<CompiledShowPreview> {
  Timer? _timer;
  Stopwatch _clock = Stopwatch();
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _clock.start();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant CompiledShowPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.show, widget.show)) {
      _timer?.cancel();
      _clock = Stopwatch()..start();
      _frameIndex = 0;
      _schedule();
    }
  }

  void _schedule() {
    if (widget.show.frames.isEmpty) return;
    final cycleUs = widget.show.durationUs;
    final positionUs = _clock.elapsedMicroseconds % cycleUs;
    final frameIndex = widget.show.frameIndexAtElapsedUs(positionUs);
    var frameEndUs = 0;
    for (var index = 0; index <= frameIndex; index++) {
      frameEndUs += widget.show.frames[index].durationUs;
    }
    if (_frameIndex != frameIndex && mounted) {
      setState(() => _frameIndex = frameIndex);
    }
    _timer = Timer(Duration(microseconds: frameEndUs - positionUs), () {
      if (!mounted) return;
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.show.frames[_frameIndex];
    return AspectRatio(
      aspectRatio: 1,
      child: ClipOval(
        child: ColoredBox(
          color: Colors.black,
          child: Image.memory(
            frame.jpeg,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class TransitionJoinPreview extends StatefulWidget {
  const TransitionJoinPreview({
    super.key,
    required this.outgoing,
    required this.incoming,
    this.cacheDirectory,
  });

  final ShowClip outgoing;
  final ShowClip incoming;
  final String? cacheDirectory;

  @override
  State<TransitionJoinPreview> createState() => _TransitionJoinPreviewState();
}

class _TransitionJoinPreviewState extends State<TransitionJoinPreview> {
  late Future<CompiledShow> _preview;

  @override
  void initState() {
    super.initState();
    _compile();
  }

  @override
  void didUpdateWidget(covariant TransitionJoinPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outgoing.id != widget.outgoing.id ||
        oldWidget.incoming.id != widget.incoming.id ||
        oldWidget.cacheDirectory != widget.cacheDirectory ||
        oldWidget.outgoing.outgoingTransition !=
            widget.outgoing.outgoingTransition ||
        oldWidget.outgoing.transitionDurationMs !=
            widget.outgoing.transitionDurationMs) {
      _compile();
    }
  }

  void _compile() {
    _preview = compileTransitionPreviewFast(
      widget.outgoing,
      widget.incoming,
      cacheDirectory: widget.cacheDirectory,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CompiledShow>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Не удалось собрать превью: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }
          final show = snapshot.data;
          if (show == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return CompiledShowPreview(show: show);
        },
      );
}
