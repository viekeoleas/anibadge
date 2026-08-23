import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

import 'project_model.dart';

const int generatedCanvasSize = 800;
const int generatedMotionFps = 60;

Future<void> renderGeneratedClip(ShowClip clip) async {
  final config = clip.generated;
  if (!clip.kind.isGenerated || config == null) {
    throw ArgumentError('Generated clip configuration is missing');
  }
  if (clip.kind.isGeneratedMotion) {
    await _renderGeneratedMotion(clip, config);
    return;
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  _drawSolidBackground(canvas, config.backgroundColor);
  if (clip.kind == ClipKind.textCard) {
    _drawTextCard(canvas, config);
  } else {
    await _drawLogoCard(canvas, config);
  }
  await _writePicture(recorder, clip.assetPath, png: true);
}

Future<void> _renderGeneratedMotion(
  ShowClip clip,
  GeneratedClipConfig config,
) async {
  final manifestPath = clip.normalizedPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    throw const FormatException('Для анимации не задан manifest');
  }
  final output = File(manifestPath);
  await output.parent.create(recursive: true);

  final frameCount = switch (clip.kind) {
    ClipKind.ambient => generatedMotionFps * 2,
    ClipKind.ticker => _tickerFrameCount(config),
    _ => throw ArgumentError.value(clip.kind, 'kind'),
  };
  final frames = <Map<String, Object>>[];
  for (var index = 0; index < frameCount; index++) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final phase = index / frameCount;
    if (clip.kind == ClipKind.ambient) {
      _drawAmbient(canvas, config, phase);
    } else {
      _drawTicker(canvas, config, phase);
    }
    final fileName = 'frame-${index.toString().padLeft(5, '0')}.jpg';
    await _writePicture(
      recorder,
      path.join(output.parent.path, fileName),
      png: false,
    );
    frames.add({'file': fileName, 'durationUs': _durationUsAt(index)});
  }
  await output.writeAsString(
    jsonEncode({
      'version': 1,
      'width': generatedCanvasSize,
      'height': generatedCanvasSize,
      'fps': generatedMotionFps,
      'frames': frames,
    }),
    flush: true,
  );
}

int _durationUsAt(int index) =>
    ((index + 1) * 1000000 ~/ generatedMotionFps) -
    (index * 1000000 ~/ generatedMotionFps);

int _tickerFrameCount(GeneratedClipConfig config) {
  final paragraph = _buildTickerParagraph(config);
  final travel = generatedCanvasSize + paragraph.maxIntrinsicWidth;
  paragraph.dispose();
  final seconds = (travel / config.tickerSpeed.clamp(100, 600)).clamp(2, 10);
  return (seconds * generatedMotionFps).round();
}

void _drawAmbient(
  ui.Canvas canvas,
  GeneratedClipConfig config,
  double phase,
) {
  const rect = ui.Rect.fromLTWH(0, 0, 800, 800);
  final wave = (math.sin(phase * math.pi * 2) + 1) / 2;
  final strength = config.pulseStrength.clamp(0.0, 1.0);
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(80, 40),
        const ui.Offset(720, 760),
        [
          ui.Color(config.backgroundColor),
          ui.Color(config.secondaryColor),
        ],
      ),
  );
  final center = ui.Offset(
    400 + math.sin(phase * math.pi * 2) * 90,
    400 + math.cos(phase * math.pi * 2) * 70,
  );
  final glowAlpha = (70 + wave * 150 * strength).round().clamp(0, 255);
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        center,
        250 + wave * 150 * strength,
        [
          ui.Color(config.glowColor).withAlpha(glowAlpha),
          ui.Color(config.glowColor).withAlpha(0),
        ],
      ),
  );
  canvas.drawCircle(
    center,
    70 + wave * 45 * strength,
    ui.Paint()
      ..color = ui.Color(config.glowColor).withAlpha((35 + wave * 50).round())
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 42),
  );
}

void _drawTicker(
  ui.Canvas canvas,
  GeneratedClipConfig config,
  double phase,
) {
  _drawSolidBackground(canvas, config.backgroundColor);
  final paragraph = _buildTickerParagraph(config);
  final width = paragraph.maxIntrinsicWidth;
  final travel = generatedCanvasSize + width;
  final x = switch (config.tickerDirection) {
    TickerDirection.rightToLeft => generatedCanvasSize - travel * phase,
    TickerDirection.leftToRight => -width + travel * phase,
  };
  canvas.drawParagraph(
    paragraph,
    ui.Offset(x, (generatedCanvasSize - paragraph.height) / 2),
  );
  paragraph.dispose();
}

ui.Paragraph _buildTickerParagraph(GeneratedClipConfig config) {
  final (fontFamily, fontWeight) = _fontStyle(config.font);
  final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
        ..pushStyle(ui.TextStyle(
          color: ui.Color(config.foregroundColor),
          fontFamily: fontFamily,
          fontSize: config.fontSize.clamp(32, 180),
          fontWeight: fontWeight,
          height: 1.05,
        ))
        ..addText(config.text))
      .build();
  paragraph.layout(const ui.ParagraphConstraints(width: 10000));
  return paragraph;
}

void _drawSolidBackground(ui.Canvas canvas, int color) {
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 800, 800),
    ui.Paint()..color = ui.Color(color),
  );
}

Future<void> _writePicture(
  ui.PictureRecorder recorder,
  String outputPath, {
  required bool png,
}) async {
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(
    generatedCanvasSize,
    generatedCanvasSize,
  );
  final bytes = png
      ? await rendered.toByteData(format: ui.ImageByteFormat.png)
      : await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  rendered.dispose();
  if (bytes == null) throw StateError('Не удалось создать кадр');
  final encoded = png
      ? bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
      : image.encodeJpg(
          image.Image.fromBytes(
            width: generatedCanvasSize,
            height: generatedCanvasSize,
            bytes: bytes.buffer,
            bytesOffset: bytes.offsetInBytes,
            order: image.ChannelOrder.rgba,
          ),
          quality: 88,
          chroma: image.JpegChroma.yuv420,
        );
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(encoded, flush: true);
}

void _drawTextCard(ui.Canvas canvas, GeneratedClipConfig config) {
  final (fontFamily, fontWeight) = _fontStyle(config.font);
  final alignment = switch (config.alignment) {
    CardTextAlignment.left => ui.TextAlign.left,
    CardTextAlignment.center => ui.TextAlign.center,
    CardTextAlignment.right => ui.TextAlign.right,
  };
  final paragraph = (ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: alignment,
    maxLines: 6,
    ellipsis: '…',
  ))
        ..pushStyle(ui.TextStyle(
          color: ui.Color(config.foregroundColor),
          fontFamily: fontFamily,
          fontSize: config.fontSize.clamp(24, 180),
          fontWeight: fontWeight,
          height: 1.05,
        ))
        ..addText(config.text))
      .build();
  paragraph.layout(const ui.ParagraphConstraints(width: 680));
  final y = (generatedCanvasSize - paragraph.height) / 2;
  canvas.drawParagraph(paragraph, ui.Offset(60, y));
  paragraph.dispose();
}

(String, ui.FontWeight) _fontStyle(GeneratedFont font) => switch (font) {
      GeneratedFont.clean => ('sans-serif', ui.FontWeight.w400),
      GeneratedFont.bold => ('sans-serif', ui.FontWeight.w800),
      GeneratedFont.condensed => ('sans-serif-condensed', ui.FontWeight.w600),
      GeneratedFont.mono => ('monospace', ui.FontWeight.w500),
    };

Future<void> _drawLogoCard(
  ui.Canvas canvas,
  GeneratedClipConfig config,
) async {
  final sourcePath = config.logoSourcePath;
  if (sourcePath == null || sourcePath.isEmpty) {
    throw const FormatException('Для logo-card не выбран логотип или фото');
  }
  final bytes = await File(sourcePath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  final maxSide = generatedCanvasSize * config.logoScale.clamp(0.1, 1.2);
  final scale =
      maxSide / (source.width > source.height ? source.width : source.height);
  final width = source.width * scale;
  final height = source.height * scale;
  final destination = ui.Rect.fromLTWH(
    (generatedCanvasSize - width) / 2,
    (generatedCanvasSize - height) / 2,
    width,
    height,
  );
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(
      0,
      0,
      source.width.toDouble(),
      source.height.toDouble(),
    ),
    destination,
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  source.dispose();
  codec.dispose();
}
