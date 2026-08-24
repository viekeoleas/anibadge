import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'project_model.dart';

/// Square canvas of the round display and of every ZSHOW frame.
const int showCanvasSize = 800;

class ShowCompileException implements Exception {
  const ShowCompileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One decoded source frame owned by the caller until [dispose].
abstract class PipelineImage {
  int get width;
  int get height;
  void dispose();
}

/// A decoded animation. Frames are requested in playback order; each frame
/// may be requested once and is owned by the caller after [frameAt].
abstract class PipelineAnimation {
  int get frameCount;
  Future<PipelineImage> frameAt(int index);
  void dispose();
}

/// The pixel engine behind the show compiler: decoding sources, rendering
/// clip geometry and transitions, and encoding budgeted baseline JPEG frames.
/// The scheduling, caching and packaging logic of the compiler is engine
/// agnostic.
abstract class FramePipeline {
  Future<PipelineImage> decodeImage(Uint8List bytes, String label);
  Future<PipelineAnimation> decodeAnimation(Uint8List bytes, String label);
  Future<Uint8List> renderClipFrame(
    PipelineImage source,
    ShowClip clip,
    String label,
  );
  Future<Uint8List> renderTransitionFrame(
    PipelineImage from,
    PipelineImage to,
    TransitionKind kind,
    double progress,
    String label,
  );
  void dispose();
}

/// Pure-Dart pipeline: works in any isolate and produces byte-stable frames.
/// It is the reference implementation used by background compilation and by
/// the host test-suite.
class DartFramePipeline implements FramePipeline {
  @override
  Future<PipelineImage> decodeImage(Uint8List bytes, String label) async {
    final decoded = image.decodeImage(bytes);
    if (decoded == null || decoded.frames.isEmpty) {
      throw ShowCompileException('Не удалось декодировать $label');
    }
    return _DartImage(decoded.frames.first);
  }

  @override
  Future<PipelineAnimation> decodeAnimation(Uint8List bytes, String label) async {
    final decoded = image.decodeGif(bytes);
    if (decoded == null || decoded.frames.isEmpty) {
      throw ShowCompileException('GIF $label повреждён или не поддерживается');
    }
    return _DartAnimation(decoded);
  }

  @override
  Future<Uint8List> renderClipFrame(
    PipelineImage source,
    ShowClip clip,
    String label,
  ) async {
    final rendered = _renderFrame((source as _DartImage).frame, clip);
    return _encodeFrame(rendered, label);
  }

  @override
  Future<Uint8List> renderTransitionFrame(
    PipelineImage from,
    PipelineImage to,
    TransitionKind kind,
    double progress,
    String label,
  ) async {
    final rendered = _renderTransition(
      (from as _DartImage).frame,
      (to as _DartImage).frame,
      kind,
      progress,
    );
    return _encodeFrame(rendered, label);
  }

  @override
  void dispose() {}
}

class _DartImage implements PipelineImage {
  const _DartImage(this.frame);

  final image.Image frame;

  @override
  int get width => frame.width;

  @override
  int get height => frame.height;

  @override
  void dispose() {}
}

class _DartAnimation implements PipelineAnimation {
  const _DartAnimation(this._decoded);

  final image.Image _decoded;

  @override
  int get frameCount => _decoded.frames.length;

  @override
  Future<PipelineImage> frameAt(int index) async =>
      _DartImage(_decoded.frames[index]);

  @override
  void dispose() {}
}

final List<({int left, int right})> _circleBounds = List.generate(
  showCanvasSize,
  (y) {
    const center = (showCanvasSize - 1) / 2;
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

image.Image _renderFrame(image.Image sourceFrame, ShowClip clip) {
  final source = image.Image.from(sourceFrame, noAnimation: true);
  final fitScale = clip.layout == ClipLayout.fit
      ? math.min(showCanvasSize / source.width, showCanvasSize / source.height)
      : math.max(showCanvasSize / source.width, showCanvasSize / source.height);
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
  final canvas = image.Image(width: showCanvasSize, height: showCanvasSize);
  image.fill(canvas, color: image.ColorRgb8(0, 0, 0));
  image.compositeImage(
    canvas,
    rotated,
    dstX: ((showCanvasSize - rotated.width) / 2 + clip.offsetX).round(),
    dstY: ((showCanvasSize - rotated.height) / 2 + clip.offsetY).round(),
  );
  for (var y = 0; y < showCanvasSize; y++) {
    final bounds = _circleBounds[y];
    for (var x = 0; x < bounds.left; x++) {
      canvas.setPixelRgb(x, y, 0, 0, 0);
    }
    for (var x = bounds.right + 1; x < showCanvasSize; x++) {
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
    if (encoded.length <= 212 * 1024) return encoded;
  }
  throw ShowCompileException('$label слишком сложный для плавного вывода');
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
  final result = image.Image(width: showCanvasSize, height: showCanvasSize);
  for (var y = 0; y < showCanvasSize; y++) {
    for (var x = 0; x < showCanvasSize; x++) {
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
  final result = image.Image(width: showCanvasSize, height: showCanvasSize);
  const center = (showCanvasSize - 1) / 2;
  const maximumDistance = 565.0;
  final radius = progress * 1.12;
  const feather = 0.13;
  for (var y = 0; y < showCanvasSize; y++) {
    final dy = y - center;
    for (var x = 0; x < showCanvasSize; x++) {
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
  final result = image.Image(width: showCanvasSize, height: showCanvasSize);
  final edge = progress * 1.5 - 0.25;
  const feather = 0.16;
  for (var y = 0; y < showCanvasSize; y++) {
    for (var x = 0; x < showCanvasSize; x++) {
      final position = (x * 0.68 + y * 0.32) / (showCanvasSize - 1);
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
  final result = image.Image(width: showCanvasSize, height: showCanvasSize);
  const center = (showCanvasSize - 1) / 2;
  final fromScale = 1 + progress * 0.1;
  final toScale = 0.9 + progress * 0.1;
  for (var y = 0; y < showCanvasSize; y++) {
    for (var x = 0; x < showCanvasSize; x++) {
      final fromX = ((x - center) / fromScale + center)
          .round()
          .clamp(0, showCanvasSize - 1);
      final fromY = ((y - center) / fromScale + center)
          .round()
          .clamp(0, showCanvasSize - 1);
      final toX = ((x - center) / toScale + center)
          .round()
          .clamp(0, showCanvasSize - 1);
      final toY = ((y - center) / toScale + center)
          .round()
          .clamp(0, showCanvasSize - 1);
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

double _smoothStep(double edge0, double edge1, double value) {
  final normalized = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return normalized * normalized * (3 - 2 * normalized);
}
