import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:znachok_bmw/mp4_normalizer.dart';
import 'package:znachok_bmw/project_model.dart';
import 'package:znachok_bmw/show_compiler.dart';
import 'package:znachok_bmw/video_manifest.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android decodes an H264 MP4 and ignores its AAC audio track',
      (_) async {
    final root = Directory(path.join(
      (await getTemporaryDirectory()).path,
      'znachok-mp4-integration',
    ));
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final fixture = await rootBundle.load(
      'integration_test/fixtures/android-system.mp4',
    );
    final source = File(path.join(root.path, 'source-with-audio.mp4'));
    await source.writeAsBytes(fixture.buffer.asUint8List(), flush: true);

    final manifestPath = await AndroidMp4Normalizer().normalize(
      sourcePath: source.path,
      outputDirectory: path.join(root.path, 'normalized'),
    );
    final video = await loadNormalizedVideo(manifestPath);
    final clip = ShowClip(
      id: 'android-mp4',
      name: 'source-with-audio.mp4',
      assetPath: source.path,
      normalizedPath: manifestPath,
      kind: ClipKind.mp4,
      durationMs: 0,
    );
    final compiled = await compileProjectInBackground(
      ShowProject(clips: [clip]),
    );

    expect(video.frames, hasLength(10));
    expect(video.durationUs, inInclusiveRange(950000, 1050000));
    expect(compiled.frames, hasLength(10));
    expect(compiled.durationUs, inInclusiveRange(950000, 1050000));
    expect(clip.toJson().containsKey('audio'), isFalse);
  });

  testWidgets('Android rejects a corrupt MP4 with a user-facing error',
      (_) async {
    final root = Directory(path.join(
      (await getTemporaryDirectory()).path,
      'znachok-mp4-corrupt-integration',
    ));
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final source = File(path.join(root.path, 'broken.mp4'));
    await source.writeAsBytes(List<int>.generate(128, (index) => index));

    await expectLater(
      AndroidMp4Normalizer().normalize(
        sourcePath: source.path,
        outputDirectory: path.join(root.path, 'normalized'),
      ),
      throwsA(
        isA<Mp4ImportException>().having(
          (error) => error.message,
          'message',
          isNotEmpty,
        ),
      ),
    );
  });
}
