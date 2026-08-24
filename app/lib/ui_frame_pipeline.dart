import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'frame_pipeline.dart';
import 'jpeg_frame_encoder.dart';
import 'project_model.dart';

const ui.Rect _canvasRect = ui.Rect.fromLTWH(
  0,
  0,
  showCanvasSize + 0.0,
  showCanvasSize + 0.0,
);
const ui.Offset _canvasCenter = ui.Offset(
  (showCanvasSize - 1) / 2,
  (showCanvasSize - 1) / 2,
);

/// GPU pipeline for the root isolate: decodes through the Skia codecs,
/// rasterises geometry and transitions on the engine's raster thread and
/// encodes through the native JPEG encoder. This is the fast path used by the
/// application itself; the pure-Dart [DartFramePipeline] stays the portable
/// reference.
class UiFramePipeline implements FramePipeline {
  @override
  Future<PipelineImage> decodeImage(Uint8List bytes, String label) async {
    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      throw ShowCompileException('Не удалось декодировать $label');
    }
    try {
      final frame = await codec.getNextFrame();
      return _UiImage(frame.image);
    } catch (_) {
      throw ShowCompileException('Не удалось декодировать $label');
    } finally {
      codec.dispose();
    }
  }

  @override
  Future<PipelineAnimation> decodeAnimation(
    Uint8List bytes,
    String label,
  ) async {
    final ui.Codec codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
    } catch (_) {
      throw ShowCompileException('GIF $label повреждён или не поддерживается');
    }
    if (codec.frameCount <= 0) {
      codec.dispose();
      throw ShowCompileException('GIF $label повреждён или не поддерживается');
    }
    return _UiAnimation(codec, label);
  }

  @override
  Future<Uint8List> renderClipFrame(
    PipelineImage source,
    ShowClip clip,
    String label,
  ) {
    final sourceImage = (source as _UiImage).image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, _canvasRect);
    canvas.drawRect(_canvasRect, ui.Paint()..color = const ui.Color(0xFF000000));
    canvas.save();
    canvas.clipPath(ui.Path()..addOval(_canvasRect));
    final fitScale = clip.layout == ClipLayout.fit
        ? math.min(showCanvasSize / sourceImage.width,
            showCanvasSize / sourceImage.height)
        : math.max(showCanvasSize / sourceImage.width,
            showCanvasSize / sourceImage.height);
    final scale = fitScale * clip.scale.clamp(0.1, 8);
    canvas.translate(
      showCanvasSize / 2 + clip.offsetX,
      showCanvasSize / 2 + clip.offsetY,
    );
    canvas.rotate(clip.rotation);
    canvas.scale(scale);
    canvas.drawImage(
      sourceImage,
      ui.Offset(-sourceImage.width / 2, -sourceImage.height / 2),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..isAntiAlias = true,
    );
    canvas.restore();
    return _encodePicture(recorder, label);
  }

  @override
  Future<Uint8List> renderTransitionFrame(
    PipelineImage from,
    PipelineImage to,
    TransitionKind kind,
    double progress,
    String label,
  ) {
    final fromImage = (from as _UiImage).image;
    final toImage = (to as _UiImage).image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, _canvasRect);
    switch (kind) {
      case TransitionKind.none:
        canvas.drawImage(toImage, ui.Offset.zero, ui.Paint());
      case TransitionKind.dissolve:
        canvas.drawImage(fromImage, ui.Offset.zero, ui.Paint());
        canvas.drawImage(
          toImage,
          ui.Offset.zero,
          ui.Paint()
            ..color = ui.Color.fromRGBO(
                255, 255, 255, progress.clamp(0.0, 1.0).toDouble()),
        );
      case TransitionKind.radialBloom:
        _drawRadialBloom(canvas, fromImage, toImage, progress);
      case TransitionKind.lightSweep:
        _drawLightSweep(canvas, fromImage, toImage, progress);
      case TransitionKind.depthFlow:
        canvas.drawRect(
            _canvasRect, ui.Paint()..color = const ui.Color(0xFF000000));
        _drawScaledAboutCenter(canvas, fromImage, 1 + progress * 0.1, 1);
        _drawScaledAboutCenter(canvas, toImage, 0.9 + progress * 0.1,
            progress.clamp(0.0, 1.0).toDouble());
    }
    return _encodePicture(recorder, label);
  }

  @override
  void dispose() {}
}

class _UiImage implements PipelineImage {
  _UiImage(this.image);

  final ui.Image image;

  @override
  int get width => image.width;

  @override
  int get height => image.height;

  @override
  void dispose() => image.dispose();
}

class _UiAnimation implements PipelineAnimation {
  _UiAnimation(this._codec, this._label);

  final ui.Codec _codec;
  final String _label;
  int _cursor = 0;

  @override
  int get frameCount => _codec.frameCount;

  @override
  Future<PipelineImage> frameAt(int index) async {
    if (index < _cursor || index >= frameCount) {
      throw StateError(
          'GIF $_label: кадры читаются один раз в порядке воспроизведения');
    }
    while (true) {
      final frame = await _codec.getNextFrame();
      if (_cursor++ == index) return _UiImage(frame.image);
      frame.image.dispose();
    }
  }

  @override
  void dispose() => _codec.dispose();
}

void _drawRadialBloom(
  ui.Canvas canvas,
  ui.Image from,
  ui.Image to,
  double progress,
) {
  canvas.drawImage(from, ui.Offset.zero, ui.Paint());
  const feather = 0.13;
  const maximumDistance = 565.0;
  final radius = progress * 1.12;
  final outer = radius + feather;
  if (outer <= 0) return;
  final inner = math.max(0.0, radius - feather);
  canvas.saveLayer(_canvasRect, ui.Paint());
  canvas.drawImage(to, ui.Offset.zero, ui.Paint());
  canvas.drawRect(
    _canvasRect,
    ui.Paint()
      ..blendMode = ui.BlendMode.dstIn
      ..shader = ui.Gradient.radial(
        _canvasCenter,
        math.max(outer * maximumDistance, 0.001),
        const [
          ui.Color(0xFFFFFFFF),
          ui.Color(0xFFFFFFFF),
          ui.Color(0x00FFFFFF),
        ],
        [0, (inner / outer).clamp(0.0, 1.0).toDouble(), 1],
      ),
  );
  canvas.restore();
}

void _drawLightSweep(
  ui.Canvas canvas,
  ui.Image from,
  ui.Image to,
  double progress,
) {
  canvas.drawImage(from, ui.Offset.zero, ui.Paint());
  const feather = 0.16;
  final edge = progress * 1.5 - 0.25;
  final visibleFrom = edge - feather;
  final hiddenFrom = edge + feather;
  if (hiddenFrom > 0) {
    canvas.saveLayer(_canvasRect, ui.Paint());
    canvas.drawImage(to, ui.Offset.zero, ui.Paint());
    if (visibleFrom < 1) {
      canvas.drawRect(
        _canvasRect,
        ui.Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..shader = _sweepRampShader(
            (position) => hiddenFrom <= visibleFrom
                ? (position < visibleFrom ? 1.0 : 0.0)
                : (1 -
                        (position - visibleFrom) /
                            (hiddenFrom - visibleFrom))
                    .clamp(0.0, 1.0)
                    .toDouble(),
            [visibleFrom, hiddenFrom],
          ),
      );
    }
    canvas.restore();
  }
  const band = 0.055;
  const strength = 0.12;
  if (edge + band > 0 && edge - band < 1) {
    canvas.drawRect(
      _canvasRect,
      ui.Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = _sweepRampShader(
          (position) =>
              strength * math.max(0.0, 1 - (position - edge).abs() / band),
          [edge - band, edge, edge + band],
        ),
    );
  }
}

/// Builds a linear gradient whose projected coordinate equals the sweep
/// position `(0.68 x + 0.32 y) / (canvas - 1)` used by the CPU reference, and
/// whose white alpha follows [alphaAt] piecewise-linearly across the clamped
/// [breakpoints].
ui.Shader _sweepRampShader(
  double Function(double position) alphaAt,
  List<double> breakpoints,
) {
  const direction = 0.68 * 0.68 + 0.32 * 0.32;
  const scale = (showCanvasSize - 1) / direction;
  final stops = <double>[
    0,
    ...breakpoints.map((value) => value.clamp(0.0, 1.0).toDouble()),
    1,
  ];
  final colors = stops
      .map((stop) => ui.Color.fromRGBO(
          255, 255, 255, alphaAt(stop).clamp(0.0, 1.0).toDouble()))
      .toList(growable: false);
  return ui.Gradient.linear(
    ui.Offset.zero,
    const ui.Offset(0.68 * scale, 0.32 * scale),
    colors,
    stops,
  );
}

void _drawScaledAboutCenter(
  ui.Canvas canvas,
  ui.Image source,
  double scale,
  double opacity,
) {
  canvas.save();
  canvas.translate(_canvasCenter.dx, _canvasCenter.dy);
  canvas.scale(scale);
  canvas.translate(-_canvasCenter.dx, -_canvasCenter.dy);
  canvas.drawImage(
    source,
    ui.Offset.zero,
    ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..color = ui.Color.fromRGBO(255, 255, 255, opacity),
  );
  canvas.restore();
}

Future<Uint8List> _encodePicture(
  ui.PictureRecorder recorder,
  String label,
) async {
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(showCanvasSize, showCanvasSize);
  picture.dispose();
  final byteData =
      await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  if (byteData == null) {
    throw ShowCompileException('Не удалось получить кадр: $label');
  }
  final jpeg = await encodeRgbaJpegUnderBudget(
    rgba: byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    width: showCanvasSize,
    height: showCanvasSize,
  );
  if (jpeg == null) {
    throw ShowCompileException('$label слишком сложный для плавного вывода');
  }
  return jpeg;
}
