import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'package:znachok_bmw/project_model.dart';
import 'package:znachok_bmw/show_compiler.dart';
import 'package:znachok_bmw/show_package.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('znachok-ui-pipeline-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  testWidgets('ui pipeline renders circular geometry within the frame budget',
      (tester) async {
    await tester.runAsync(() async {
      final path =
          await _writePng(temp, 'shape.png', image.ColorRgb8(250, 30, 20));
      final pipeline = UiFramePipeline();
      final compiled = await compileProject(
        ShowProject(clips: [
          ShowClip(
            id: 'shape',
            name: 'shape.png',
            assetPath: path,
            kind: ClipKind.image,
            offsetX: 60,
            scale: 0.5,
            rotation: 0.2,
          ),
        ]),
        pipeline: pipeline,
      );
      pipeline.dispose();

      expect(inspectShowPackage(compiled.package).frameCount, 1);
      expect(compiled.frames.single.jpeg.length, lessThanOrEqualTo(212 * 1024));
      final rendered = image.decodeJpg(compiled.frames.single.jpeg)!;
      expect(rendered.width, 800);
      expect(rendered.height, 800);
      final corner = rendered.getPixel(0, 0);
      final center = rendered.getPixel(460, 400);
      expect(corner.r, lessThan(8));
      expect(corner.g, lessThan(8));
      expect(center.r, greaterThan(180));
    });
  });

  testWidgets('ui pipeline keeps GIF timing and renders distinct frames',
      (tester) async {
    await tester.runAsync(() async {
      final gifPath = await _writeGif(temp);
      final pipeline = UiFramePipeline();
      final compiled = await compileProject(
        ShowProject(clips: [
          ShowClip(
            id: 'ui-gif',
            name: 'motion.gif',
            assetPath: gifPath,
            kind: ClipKind.gif,
            durationMs: 0,
          ),
        ]),
        pipeline: pipeline,
      );
      pipeline.dispose();

      expect(compiled.frames, hasLength(3));
      expect(
        compiled.frames.map((frame) => frame.durationUs),
        [100000, 250000, 50000],
      );
      final first = image.decodeJpg(compiled.frames[0].jpeg)!.getPixel(400, 400);
      final last = image.decodeJpg(compiled.frames[2].jpeg)!.getPixel(400, 400);
      expect(first.r, greaterThan(first.b));
      expect(last.b, greaterThan(last.r));
    });
  });

  testWidgets('ui pipeline renders all four transitions at 60 FPS',
      (tester) async {
    await tester.runAsync(() async {
      final redPath =
          await _writePng(temp, 'red.png', image.ColorRgb8(240, 10, 10));
      final bluePath =
          await _writePng(temp, 'blue.png', image.ColorRgb8(10, 20, 240));
      final pipeline = UiFramePipeline();
      final signatures = <String>{};
      for (final transition in TransitionKind.values.skip(1)) {
        final compiled = await compileProject(
          ShowProject(clips: [
            ShowClip(
              id: 'red-$transition',
              name: 'red.png',
              assetPath: redPath,
              kind: ClipKind.image,
              durationMs: 500,
              outgoingTransition: transition,
              transitionDurationMs: 200,
            ),
            ShowClip(
              id: 'blue-$transition',
              name: 'blue.png',
              assetPath: bluePath,
              kind: ClipKind.image,
              durationMs: 500,
            ),
          ]),
          pipeline: pipeline,
        );

        expect(compiled.frames, hasLength(14));
        expect(compiled.durationUs, 1200000);
        for (final frame in compiled.frames) {
          expect(frame.jpeg.length, lessThanOrEqualTo(212 * 1024));
        }
        signatures.add(base64Encode(compiled.frames[6].jpeg));
        final end =
            image.decodeJpg(compiled.frames[12].jpeg)!.getPixel(400, 400);
        expect(end.b, greaterThan(end.r),
            reason: '$transition должен раскрыть следующий клип');
      }
      pipeline.dispose();
      expect(signatures, hasLength(4));
    });
  });

  testWidgets('ui pipeline reuses the persistent cache byte-for-byte',
      (tester) async {
    await tester.runAsync(() async {
      final cache = '${temp.path}${Platform.pathSeparator}ui-cache';
      final gifPath = await _writeGif(temp);
      final project = ShowProject(clips: [
        ShowClip(
          id: 'ui-cached-gif',
          name: 'motion.gif',
          assetPath: gifPath,
          kind: ClipKind.gif,
          durationMs: 0,
        ),
      ]);

      final cold = await compileProjectFast(project, cacheDirectory: cache);
      final warm = await compileProjectFast(project, cacheDirectory: cache);

      expect(cold.cacheMisses, 3);
      expect(cold.cacheHits, 0);
      expect(warm.cacheHits, 3);
      expect(warm.cacheMisses, 0);
      expect(warm.package, cold.package);
    });
  });
}

Future<String> _writePng(
  Directory temp,
  String name,
  image.Color color,
) async {
  final file = File('${temp.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(image.encodePng(_solid(64, 64, color)));
  return file.path;
}

Future<String> _writeGif(Directory temp) async {
  final animation = _solid(48, 48, image.ColorRgb8(240, 20, 20))
    ..frameDuration = 100
    ..frameType = image.FrameType.animation;
  animation.addFrame(
    _solid(48, 48, image.ColorRgb8(20, 240, 20))..frameDuration = 250,
  );
  animation.addFrame(
    _solid(48, 48, image.ColorRgb8(20, 20, 240))..frameDuration = 50,
  );
  final file = File('${temp.path}${Platform.pathSeparator}motion.gif');
  await file.writeAsBytes(image.encodeGif(animation));
  return file.path;
}

image.Image _solid(int width, int height, image.Color color) {
  final result = image.Image(width: width, height: height);
  image.fill(result, color: color);
  return result;
}
