import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import 'package:znachok_bmw/generated_clip_renderer.dart';
import 'package:znachok_bmw/project_model.dart';
import 'package:znachok_bmw/project_store.dart';
import 'package:znachok_bmw/show_compiler.dart';
import 'package:znachok_bmw/show_package.dart';
import 'package:znachok_bmw/show_publisher.dart';
import 'package:znachok_bmw/video_manifest.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('znachok-compiler-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('project persists clips and editable geometry in private storage',
      () async {
    final store = ProjectStore(temp);
    final source = _solid(80, 40, image.ColorRgb8(220, 20, 30));
    final clip = (await store.importMedia(
      originalName: 'logo.png',
      bytes: image.encodePng(source),
      kind: ClipKind.image,
    ))
        .copyWith(
      offsetX: 37,
      offsetY: -21,
      scale: 1.4,
      rotation: 0.35,
      layout: ClipLayout.fill,
      outgoingTransition: TransitionKind.lightSweep,
      transitionDurationMs: 700,
    );
    await store.save(ShowProject(clips: [clip]));

    final restored = await store.load();
    expect(restored.clips, hasLength(1));
    expect(restored.clips.single.assetPath, clip.assetPath);
    expect(restored.clips.single.offsetX, 37);
    expect(restored.clips.single.rotation, 0.35);
    expect(restored.clips.single.layout, ClipLayout.fill);
    expect(restored.clips.single.outgoingTransition, TransitionKind.lightSweep);
    expect(restored.clips.single.transitionDurationMs, 700);
  });

  test('four outgoing transitions render at 60 FPS from real adjacent clips',
      () async {
    final redPath = await _writePng(
        temp, 'transition-red.png', image.ColorRgb8(240, 10, 10));
    final bluePath = await _writePng(
      temp,
      'transition-blue.png',
      image.ColorRgb8(10, 20, 240),
    );
    final signatures = <String>{};
    for (final transition in TransitionKind.values.skip(1)) {
      final compiled = await compileProject(ShowProject(clips: [
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
      ]));

      expect(compiled.frames, hasLength(14));
      expect(compiled.durationUs, 1200000);
      expect(
        compiled.frames
            .skip(1)
            .take(12)
            .map((frame) => frame.durationUs)
            .toSet(),
        {16666, 16667},
      );
      expect(inspectShowPackage(compiled.package).frameCount, 14);
      signatures.add(base64Encode(compiled.frames[6].jpeg));
      final end = image.decodeJpg(compiled.frames[12].jpeg)!.getPixel(400, 400);
      expect(end.b, greaterThan(end.r));
    }
    expect(signatures, hasLength(4));
  });

  test('last clip transition reveals the first clip in the loop', () async {
    final redPath =
        await _writePng(temp, 'loop-red.png', image.ColorRgb8(240, 10, 10));
    final bluePath =
        await _writePng(temp, 'loop-blue.png', image.ColorRgb8(10, 20, 240));
    final compiled = await compileProject(ShowProject(clips: [
      ShowClip(
        id: 'loop-red',
        name: 'red.png',
        assetPath: redPath,
        kind: ClipKind.image,
        durationMs: 500,
      ),
      ShowClip(
        id: 'loop-blue',
        name: 'blue.png',
        assetPath: bluePath,
        kind: ClipKind.image,
        durationMs: 500,
        outgoingTransition: TransitionKind.radialBloom,
        transitionDurationMs: 200,
      ),
    ]));

    expect(compiled.frames, hasLength(14));
    expect(
        compiled.frames.skip(2).every((frame) => frame.clipIndex == 1), isTrue);
    final end = image.decodeJpg(compiled.frames.last.jpeg)!.getPixel(400, 400);
    expect(end.r, greaterThan(end.b));
  });

  test('adjacent transition preview compiles in the background', () async {
    final redPath =
        await _writePng(temp, 'preview-red.png', image.ColorRgb8(240, 10, 10));
    final bluePath = await _writePng(
      temp,
      'preview-blue.png',
      image.ColorRgb8(10, 20, 240),
    );
    final preview = await compileTransitionPreviewInBackground(
      ShowClip(
        id: 'preview-red',
        name: 'red.png',
        assetPath: redPath,
        kind: ClipKind.image,
        outgoingTransition: TransitionKind.lightSweep,
        transitionDurationMs: 200,
      ),
      ShowClip(
        id: 'preview-blue',
        name: 'blue.png',
        assetPath: bluePath,
        kind: ClipKind.image,
      ),
    );

    expect(preview.frames, hasLength(14));
    expect(preview.durationUs, 900000);
  });

  test('persistent cache reuses clips and transitions byte-for-byte', () async {
    final cache = '${temp.path}${Platform.pathSeparator}cache';
    final redPath =
        await _writePng(temp, 'cache-red.png', image.ColorRgb8(240, 10, 10));
    final bluePath =
        await _writePng(temp, 'cache-blue.png', image.ColorRgb8(10, 20, 240));
    final project = ShowProject(clips: [
      ShowClip(
        id: 'cache-red',
        name: 'red.png',
        assetPath: redPath,
        kind: ClipKind.image,
        durationMs: 500,
        outgoingTransition: TransitionKind.dissolve,
        transitionDurationMs: 200,
      ),
      ShowClip(
        id: 'cache-blue',
        name: 'blue.png',
        assetPath: bluePath,
        kind: ClipKind.image,
        durationMs: 500,
        outgoingTransition: TransitionKind.lightSweep,
        transitionDurationMs: 200,
      ),
    ]);

    final coldClock = Stopwatch()..start();
    final cold = await compileProject(project, cacheDirectory: cache);
    coldClock.stop();
    final warmClock = Stopwatch()..start();
    final warm = await compileProjectInBackground(
      project,
      cacheDirectory: cache,
    );
    warmClock.stop();

    expect(cold.cacheHits, 0);
    expect(cold.cacheMisses, 4);
    expect(warm.cacheHits, 4);
    expect(warm.cacheMisses, 0);
    expect(warm.package, cold.package);
    expect(
        warmClock.elapsedMicroseconds, lessThan(coldClock.elapsedMicroseconds));

    final changed = project.copyWith(clips: [
      project.clips.first.copyWith(offsetX: 12),
      project.clips.last,
    ]);
    final selective = await compileProject(changed, cacheDirectory: cache);
    expect(selective.cacheHits, 1);
    expect(selective.cacheMisses, 3);
  });

  test('GIF timing edits reuse visual frames without JPEG rebuild', () async {
    final cache = '${temp.path}${Platform.pathSeparator}gif-timing-cache';
    final gifPath = await _writeGif(temp);
    final original = ShowClip(
      id: 'gif-timing',
      name: 'motion.gif',
      assetPath: gifPath,
      kind: ClipKind.gif,
      durationMs: 0,
    );

    final cold = await compileProject(
      ShowProject(clips: [original]),
      cacheDirectory: cache,
    );
    final retimed = await compileProject(
      ShowProject(clips: [original.copyWith(speed: 2, repeat: 2)]),
      cacheDirectory: cache,
    );

    expect(cold.cacheHits, 0);
    expect(cold.cacheMisses, 3);
    expect(retimed.cacheHits, 3);
    expect(retimed.cacheMisses, 0);
    expect(
      retimed.frames.map((frame) => frame.durationUs),
      [50000, 125000, 25000, 50000, 125000, 25000],
    );
  });

  test('expanded GIF trim renders only newly visible source frames', () async {
    final cache = '${temp.path}${Platform.pathSeparator}gif-partial-cache';
    final gifPath = await _writeGif(temp);
    final clipped = ShowClip(
      id: 'gif-partial',
      name: 'motion.gif',
      assetPath: gifPath,
      kind: ClipKind.gif,
      durationMs: 0,
      trimEndMs: 300,
    );

    final partial = await compileProject(
      ShowProject(clips: [clipped]),
      cacheDirectory: cache,
    );
    final expanded = await compileProject(
      ShowProject(clips: [clipped.copyWith(trimEndMs: 0)]),
      cacheDirectory: cache,
    );

    expect(partial.cacheHits, 0);
    expect(partial.cacheMisses, 2);
    expect(expanded.cacheHits, 2);
    expect(expanded.cacheMisses, 1);
    expect(expanded.frames, hasLength(3));
  });

  test('static duration edits reuse the visual frame', () async {
    final cache = '${temp.path}${Platform.pathSeparator}image-timing-cache';
    final path = await _writePng(
      temp,
      'retimed.png',
      image.ColorRgb8(30, 80, 200),
    );
    final clip = ShowClip(
      id: 'retimed-image',
      name: 'retimed.png',
      assetPath: path,
      kind: ClipKind.image,
      durationMs: 1000,
    );

    await compileProject(
      ShowProject(clips: [clip]),
      cacheDirectory: cache,
    );
    final retimed = await compileProject(
      ShowProject(clips: [clip.copyWith(durationMs: 5000)]),
      cacheDirectory: cache,
    );

    expect(retimed.cacheHits, 1);
    expect(retimed.cacheMisses, 0);
    expect(retimed.frames.single.durationUs, 5000000);
  });

  test('corrupt cache entry is discarded and rebuilt safely', () async {
    final cachePath = '${temp.path}${Platform.pathSeparator}corrupt-cache';
    final source =
        await _writePng(temp, 'cache-source.png', image.ColorRgb8(30, 80, 200));
    final project = ShowProject(clips: [
      ShowClip(
        id: 'cache-source',
        name: 'source.png',
        assetPath: source,
        kind: ClipKind.image,
      ),
    ]);
    final original = await compileProject(project, cacheDirectory: cachePath);
    final cacheFiles = await Directory(cachePath)
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(cacheFiles, hasLength(1));
    await cacheFiles.single.writeAsBytes([1, 2, 3], flush: true);

    final rebuilt = await compileProject(project, cacheDirectory: cachePath);

    expect(rebuilt.cacheHits, 0);
    expect(rebuilt.cacheMisses, 1);
    expect(rebuilt.package, original.package);
  });

  test('transition preview reads only adjacent motion edge frames', () async {
    final manifestPath = await _writeVideoManifest(temp);
    final middle = File(
      '${File(manifestPath).parent.path}${Platform.pathSeparator}frame-1.jpg',
    );
    await middle.writeAsBytes([1, 2, 3], flush: true);
    final incoming = await _writePng(
        temp, 'edge-incoming.png', image.ColorRgb8(10, 20, 240));

    final preview = await compileTransitionPreview(
      ShowClip(
        id: 'edge-video',
        name: 'edge.mp4',
        assetPath: '${temp.path}${Platform.pathSeparator}edge.mp4',
        normalizedPath: manifestPath,
        kind: ClipKind.mp4,
        durationMs: 0,
        outgoingTransition: TransitionKind.dissolve,
        transitionDurationMs: 200,
      ),
      ShowClip(
        id: 'edge-image',
        name: 'edge.png',
        assetPath: incoming,
        kind: ClipKind.image,
      ),
    );

    expect(preview.frames, hasLength(14));
    expect(preview.durationUs, 900000);
  });

  test(
      'static playlist compiles in order with exact durations and valid package',
      () async {
    final redPath =
        await _writePng(temp, 'red.png', image.ColorRgb8(240, 10, 10));
    final bluePath =
        await _writePng(temp, 'blue.png', image.ColorRgb8(10, 20, 240));
    final project = ShowProject(clips: [
      ShowClip(
        id: 'red',
        name: 'red.png',
        assetPath: redPath,
        kind: ClipKind.image,
        durationMs: 1500,
      ),
      ShowClip(
        id: 'blue',
        name: 'blue.png',
        assetPath: bluePath,
        kind: ClipKind.image,
        durationMs: 2500,
      ),
    ]);

    final compiled = await compileProject(project);
    final info = inspectShowPackage(compiled.package);
    expect(compiled.frames.map((frame) => frame.clipIndex), [0, 1]);
    expect(
        compiled.frames.map((frame) => frame.durationUs), [1500000, 2500000]);
    expect(info.frameCount, 2);
    expect(compiled.durationUs, 4000000);
    expect(compiled.frameIndexAtElapsedUs(0), 0);
    expect(compiled.frameIndexAtElapsedUs(1499999), 0);
    expect(compiled.frameIndexAtElapsedUs(1500000), 1);
    expect(compiled.frameIndexAtElapsedUs(3999999), 1);
    expect(compiled.frameIndexAtElapsedUs(4000000), 0);
    expect(compiled.frameIndexAtElapsedUs(4000000 * 1000 + 1500000), 1);

    final output = File('${temp.path}${Platform.pathSeparator}playlist.zshow');
    await output.writeAsBytes(compiled.package);
    final validation = await Process.run(
      'python',
      ['tools/zshow.py', 'validate', output.path],
      workingDirectory: Directory.current.parent.path,
    );
    expect(validation.exitCode, 0, reason: '${validation.stderr}');
  });

  test('compiled geometry is circular and deterministic', () async {
    final path =
        await _writePng(temp, 'shape.png', image.ColorRgb8(250, 30, 20));
    final project = ShowProject(clips: [
      ShowClip(
        id: 'shape',
        name: 'shape.png',
        assetPath: path,
        kind: ClipKind.image,
        offsetX: 60,
        scale: 0.5,
        rotation: 0.2,
      ),
    ]);

    final first = await compileProject(project);
    final second = await compileProject(project);
    expect(first.package, second.package);
    final rendered = image.decodeJpg(first.frames.single.jpeg)!;
    final corner = rendered.getPixel(0, 0);
    final center = rendered.getPixel(460, 400);
    expect(corner.r, lessThan(8));
    expect(corner.g, lessThan(8));
    expect(center.r, greaterThan(180));
  });

  test('GIF keeps source frame timing and one natural pass by default',
      () async {
    final gifPath = await _writeGif(temp);
    final clip = ShowClip(
      id: 'gif',
      name: 'motion.gif',
      assetPath: gifPath,
      kind: ClipKind.gif,
      durationMs: 0,
    );

    final compiled = await compileProject(ShowProject(clips: [clip]));
    expect(compiled.frames, hasLength(3));
    expect(
      compiled.frames.map((frame) => frame.durationUs),
      [100000, 250000, 50000],
    );
    expect(compiled.durationUs, 400000);
  });

  test('GIF trim speed and repeat change schedule without invented frames',
      () async {
    final gifPath = await _writeGif(temp);
    final clip = ShowClip(
      id: 'gif-edit',
      name: 'motion.gif',
      assetPath: gifPath,
      kind: ClipKind.gif,
      durationMs: 0,
      trimStartMs: 50,
      trimEndMs: 350,
      speed: 2,
      repeat: 2,
    );

    final compiled = await compileProject(ShowProject(clips: [clip]));
    expect(compiled.frames, hasLength(4));
    expect(
      compiled.frames.map((frame) => frame.durationUs),
      [25000, 125000, 25000, 125000],
    );
    expect(compiled.durationUs, 300000);
  });

  test('two distinct GIFs remain distinct across an outgoing transition',
      () async {
    final firstPath = await _writeColoredGif(
      temp,
      'first.gif',
      [
        image.ColorRgb8(240, 20, 20),
        image.ColorRgb8(210, 40, 20),
      ],
    );
    final secondPath = await _writeColoredGif(
      temp,
      'second.gif',
      [
        image.ColorRgb8(20, 20, 240),
        image.ColorRgb8(20, 40, 210),
      ],
    );
    final compiled = await compileProject(
      ShowProject(clips: [
        ShowClip(
          id: 'first-gif',
          name: 'first.gif',
          assetPath: firstPath,
          kind: ClipKind.gif,
          durationMs: 0,
          outgoingTransition: TransitionKind.dissolve,
          transitionDurationMs: 200,
        ),
        ShowClip(
          id: 'second-gif',
          name: 'second.gif',
          assetPath: secondPath,
          kind: ClipKind.gif,
          durationMs: 0,
        ),
      ]),
      cacheDirectory: '${temp.path}${Platform.pathSeparator}two-gif-cache',
    );

    expect(compiled.frames.map((frame) => frame.clipIndex), [
      0,
      0,
      ...List.filled(12, 0),
      1,
      1,
    ]);
    final first =
        image.decodeJpg(compiled.frames.first.jpeg)!.getPixel(400, 400);
    final afterTransition =
        image.decodeJpg(compiled.frames[14].jpeg)!.getPixel(400, 400);
    expect(first.r, greaterThan(first.b));
    expect(afterTransition.b, greaterThan(afterTransition.r));
    expect(compiled.frames.first.jpeg, isNot(compiled.frames[14].jpeg));

    final index = ByteData.sublistView(compiled.package, 64, 64 + 16 * 16);
    final payloadOffset =
        ByteData.sublistView(compiled.package).getUint32(36, Endian.little);
    final secondGifOffset = index.getUint32(14 * 16, Endian.little);
    final secondGifSize = index.getUint32(14 * 16 + 4, Endian.little);
    expect(
      compiled.package.sublist(
        payloadOffset + secondGifOffset,
        payloadOffset + secondGifOffset + secondGifSize,
      ),
      compiled.frames[14].jpeg,
    );
  });

  test('direct GIF workflow publishes the compiled package to the device',
      () async {
    final gifPath = await _writeGif(temp);
    final project = ShowProject(clips: [
      ShowClip(
        id: 'direct-gif',
        name: 'motion.gif',
        assetPath: gifPath,
        kind: ClipKind.gif,
        durationMs: 0,
      ),
    ]);
    final compiled = await compileProject(project);
    final device = _CaptureDevice();

    final published = await ShowPublisher(
      device,
      pollInterval: Duration.zero,
    ).publish(compiled.package, onState: (_) {});

    expect(published, isTrue);
    expect(device.uploaded, compiled.package);
    expect(inspectShowPackage(device.uploaded!).frameCount, 3);
  });

  test('background compiler transfers only serialized project data', () async {
    final gifPath = await _writeGif(temp);
    final project = ShowProject(clips: [
      ShowClip(
        id: 'background-gif',
        name: 'motion.gif',
        assetPath: gifPath,
        kind: ClipKind.gif,
        durationMs: 0,
      ),
    ]);

    final compiled = await compileProjectInBackground(project);

    expect(compiled.frames, hasLength(3));
    expect(compiled.durationUs, 400000);
  });

  test('background compiler reports per-frame progress', () async {
    final gifPath = await _writeGif(temp);
    final updates = <ShowCompileProgress>[];
    final compiled = await compileProjectInBackground(
      ShowProject(clips: [
        ShowClip(
          id: 'progress-gif',
          name: 'motion.gif',
          assetPath: gifPath,
          kind: ClipKind.gif,
          durationMs: 0,
        ),
      ]),
      cacheDirectory: '${temp.path}${Platform.pathSeparator}progress-cache',
      onProgress: updates.add,
    );

    expect(compiled.frames, hasLength(3));
    expect(updates, isNotEmpty);
    expect(updates.last.clipIndex, 0);
    expect(updates.last.clipCount, 1);
    expect(updates.last.completedFrames, 3);
    expect(updates.last.totalFrames, 3);
  });

  test('MP4 manifest keeps video timing and contains no audio model', () async {
    final manifestPath = await _writeVideoManifest(temp);
    final clip = ShowClip(
      id: 'video',
      name: 'drive.mp4',
      assetPath: '${temp.path}${Platform.pathSeparator}source.mp4',
      normalizedPath: manifestPath,
      kind: ClipKind.mp4,
      durationMs: 0,
    );

    final compiled = await compileProject(ShowProject(clips: [clip]));
    final restored =
        ShowProject.decode(ShowProject(clips: [clip]).encode()).clips.single;

    expect(compiled.frames, hasLength(3));
    expect(
      compiled.frames.map((frame) => frame.durationUs),
      [100000, 250000, 50000],
    );
    expect(compiled.durationUs, 400000);
    expect(clip.toJson().containsKey('audio'), isFalse);
    expect(restored.kind, ClipKind.mp4);
    expect(restored.normalizedPath, manifestPath);
  });

  test('MP4 trim speed repeat and transforms use normalized frames', () async {
    final manifestPath = await _writeVideoManifest(temp);
    final clip = ShowClip(
      id: 'video-edit',
      name: 'drive.mp4',
      assetPath: '${temp.path}${Platform.pathSeparator}source.mp4',
      normalizedPath: manifestPath,
      kind: ClipKind.mp4,
      durationMs: 0,
      trimStartMs: 50,
      trimEndMs: 350,
      speed: 2,
      repeat: 2,
      offsetX: 40,
      scale: 0.75,
      rotation: 0.1,
    );

    final compiled = await compileProject(ShowProject(clips: [clip]));

    expect(compiled.frames, hasLength(4));
    expect(
      compiled.frames.map((frame) => frame.durationUs),
      [25000, 125000, 25000, 125000],
    );
    expect(compiled.durationUs, 300000);
  });

  test('corrupt MP4 manifest returns an actionable compile error', () async {
    final manifest = File('${temp.path}${Platform.pathSeparator}broken.json');
    await manifest.writeAsString('{"version":1,"frames":[]}');
    final clip = ShowClip(
      id: 'broken-video',
      name: 'broken.mp4',
      assetPath: '${temp.path}${Platform.pathSeparator}broken.mp4',
      normalizedPath: manifest.path,
      kind: ClipKind.mp4,
      durationMs: 0,
    );

    await expectLater(
      compileProject(ShowProject(clips: [clip])),
      throwsA(
        isA<ShowCompileException>().having(
          (error) => error.message,
          'message',
          contains('Не удалось подготовить MP4 broken.mp4'),
        ),
      ),
    );
  });

  testWidgets('text-card renders, persists, edits and compiles consistently',
      (tester) async {
    await tester.runAsync(() async {
      final store = ProjectStore(temp);
      const config = GeneratedClipConfig(
        text: 'Привет BMW',
        font: GeneratedFont.bold,
        fontSize: 104,
        foregroundColor: 0xFFFFFFFF,
        backgroundColor: 0xFF0066B1,
        alignment: CardTextAlignment.center,
      );
      var clip = await store.createGeneratedClip(
        kind: ClipKind.textCard,
        name: 'Text-card',
        config: config,
      );
      await renderGeneratedClip(clip);
      final draft = image.decodePng(await File(clip.assetPath).readAsBytes())!;
      final background = draft.getPixel(0, 0);
      var brightPixels = 0;
      final pixels = draft.getRange(40, 250, 720, 300);
      while (pixels.moveNext()) {
        final pixel = pixels.current;
        if (pixel.r > 220 && pixel.g > 220 && pixel.b > 220) {
          brightPixels++;
        }
      }
      expect(background.r, 0);
      expect(background.g, 102);
      expect(background.b, 177);
      expect(brightPixels, greaterThan(100));

      final restored =
          ShowProject.decode(ShowProject(clips: [clip]).encode()).clips.single;
      expect(restored.generated?.text, 'Привет BMW');
      expect(restored.generated?.font, GeneratedFont.bold);
      expect(restored.generated?.alignment, CardTextAlignment.center);

      final editedConfig = config.copyWith(
        text: 'Новый текст',
        alignment: CardTextAlignment.right,
        revision: 1,
      );
      clip = clip.copyWith(
        assetPath: store.generatedRasterPath(clip.id, 1),
        generated: editedConfig,
        durationMs: 2200,
      );
      await renderGeneratedClip(clip);
      final compiled = await compileProject(ShowProject(clips: [clip]));
      expect(compiled.frames, hasLength(1));
      expect(compiled.frames.single.durationUs, 2200000);
    });
  });

  testWidgets('logo-card renders source over background and compiles',
      (tester) async {
    await tester.runAsync(() async {
      final store = ProjectStore(temp);
      final logoPath = await store.importGeneratorSource(
        originalName: 'logo.png',
        bytes: Uint8List.fromList(image.encodePng(
          _solid(120, 60, image.ColorRgb8(245, 30, 20)),
        )),
      );
      final clip = await store.createGeneratedClip(
        kind: ClipKind.logoCard,
        name: 'Logo-card',
        config: GeneratedClipConfig(
          logoSourcePath: logoPath,
          logoScale: 0.6,
          backgroundColor: 0xFF000000,
        ),
      );
      await renderGeneratedClip(clip);
      final draft = image.decodePng(await File(clip.assetPath).readAsBytes())!;
      final center = draft.getPixel(400, 400);
      final corner = draft.getPixel(0, 0);
      expect(center.r, greaterThan(220));
      expect(center.g, lessThan(60));
      expect(corner.r, 0);

      final compiled = await compileProject(ShowProject(clips: [clip]));
      final finalFrame = image.decodeJpg(compiled.frames.single.jpeg)!;
      expect(finalFrame.getPixel(400, 400).r, greaterThan(200));
      expect(compiled.frames.single.durationUs, 3000000);
    });
  });

  testWidgets('ambient renders a seamless 60 FPS motion manifest and compiles',
      (tester) async {
    await tester.runAsync(() async {
      final store = ProjectStore(temp);
      final clip = await store.createGeneratedClip(
        kind: ClipKind.ambient,
        name: 'Ambient',
        config: const GeneratedClipConfig(
          backgroundColor: 0xFF0066B1,
          secondaryColor: 0xFF6C4DFF,
          glowColor: 0xFF00A8E8,
          pulseStrength: 0.7,
        ),
      );
      await renderGeneratedClip(clip);

      final video = await loadNormalizedVideo(clip.normalizedPath!);
      expect(video.frames, hasLength(120));
      expect(video.durationUs, 2000000);
      expect(
        video.frames.every(
          (frame) => frame.durationUs == 16666 || frame.durationUs == 16667,
        ),
        isTrue,
      );
      expect(
          await File(video.frames.first.path).length(), lessThan(212 * 1024));
      final firstBytes = await File(video.frames.first.path).readAsBytes();
      final middleBytes = await File(video.frames[60].path).readAsBytes();
      expect(firstBytes, isNot(equals(middleBytes)));

      final compiled = await compileProject(
        ShowProject(clips: [clip.copyWith(durationMs: 200)]),
      );
      expect(compiled.frames, hasLength(12));
      expect(compiled.durationUs, 200000);
    });
  });

  testWidgets('ticker persists controls, moves at 60 FPS and compiles',
      (tester) async {
    await tester.runAsync(() async {
      final store = ProjectStore(temp);
      final clip = await store.createGeneratedClip(
        kind: ClipKind.ticker,
        name: 'Ticker',
        config: const GeneratedClipConfig(
          text: 'BMW',
          fontSize: 112,
          foregroundColor: 0xFFFFFFFF,
          backgroundColor: 0xFF000000,
          tickerDirection: TickerDirection.leftToRight,
          tickerSpeed: 600,
        ),
      );
      await renderGeneratedClip(clip);

      final restored =
          ShowProject.decode(ShowProject(clips: [clip]).encode()).clips.single;
      expect(restored.generated?.tickerDirection, TickerDirection.leftToRight);
      expect(restored.generated?.tickerSpeed, 600);
      final video = await loadNormalizedVideo(clip.normalizedPath!);
      expect(video.frames.length, greaterThanOrEqualTo(120));
      expect(
        video.frames.every(
          (frame) => frame.durationUs == 16666 || frame.durationUs == 16667,
        ),
        isTrue,
      );
      expect(
          await File(video.frames.first.path).length(), lessThan(212 * 1024));

      final compiled = await compileProject(
        ShowProject(clips: [clip.copyWith(durationMs: 200)]),
      );
      expect(compiled.frames, hasLength(12));
      expect(compiled.durationUs, 200000);
    });
  });
}

class _CaptureDevice implements ShowDevice {
  Uint8List? uploaded;

  @override
  Future<void> clearMedia() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    required void Function() onTransferComplete,
  }) async {
    uploaded = Uint8List.fromList(bytes);
    onProgress(1);
    onTransferComplete();
  }

  @override
  Future<ShowDeviceStatus> status() async =>
      const ShowDeviceStatus(state: 'playing', installed: true);
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

Future<String> _writeColoredGif(
  Directory temp,
  String name,
  List<image.Color> colors,
) async {
  final animation = _solid(48, 48, colors.first)
    ..frameDuration = 120
    ..frameType = image.FrameType.animation;
  for (final color in colors.skip(1)) {
    animation.addFrame(_solid(48, 48, color)..frameDuration = 120);
  }
  final file = File('${temp.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(image.encodeGif(animation));
  return file.path;
}

Future<String> _writeVideoManifest(Directory temp) async {
  final video = Directory('${temp.path}${Platform.pathSeparator}video');
  await video.create();
  final colors = [
    image.ColorRgb8(240, 20, 20),
    image.ColorRgb8(20, 240, 20),
    image.ColorRgb8(20, 20, 240),
  ];
  final durations = [100000, 250000, 50000];
  final frames = <Map<String, Object>>[];
  for (var index = 0; index < colors.length; index++) {
    final name = 'frame-$index.jpg';
    await File('${video.path}${Platform.pathSeparator}$name')
        .writeAsBytes(image.encodeJpg(_solid(48, 48, colors[index])));
    frames.add({'file': name, 'durationUs': durations[index]});
  }
  final manifest = File('${video.path}${Platform.pathSeparator}manifest.json');
  await manifest.writeAsString(jsonEncode({
    'version': 1,
    'width': 48,
    'height': 48,
    'frames': frames,
  }));
  return manifest.path;
}

image.Image _solid(int width, int height, image.Color color) {
  final result = image.Image(width: width, height: height);
  image.fill(result, color: color);
  return result;
}
