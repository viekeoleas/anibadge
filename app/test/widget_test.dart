import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:znachok_bmw/main.dart';
import 'package:znachok_bmw/project_model.dart';
import 'package:znachok_bmw/show_publisher.dart';

void main() {
  testWidgets('shows media import instead of internal package format',
      (tester) async {
    await tester.pumpWidget(
      const ZnachokApp(initialProject: ShowProject()),
    );

    expect(find.text('Znachok — редактор'), findsOneWidget);
    expect(find.text('Добавить PNG, JPEG, GIF или MP4'), findsOneWidget);
    expect(find.text('Text-card'), findsOneWidget);
    expect(find.text('Logo-card'), findsOneWidget);
    expect(find.text('Ambient'), findsOneWidget);
    expect(find.text('Ticker'), findsOneWidget);
    expect(find.textContaining('.zshow'), findsNothing);
  });

  testWidgets('shows live project preview without a package build step',
      (tester) async {
    await tester.pumpWidget(
      const ZnachokApp(
        initialProject: ShowProject(
          clips: [
            ShowClip(
              id: 'draft',
              name: 'draft.png',
              assetPath: 'missing-draft.png',
              kind: ClipKind.image,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Живое превью проекта'), findsOneWidget);
    expect(find.text('Собрать финальное превью'), findsNothing);
    expect(find.text('Подготовить и загрузить на значок'), findsOneWidget);
  });

  testWidgets('clears only board media after explicit confirmation',
      (tester) async {
    final device = _ClearableDevice();
    await tester.pumpWidget(
      ZnachokApp(
        initialProject: const ShowProject(),
        device: device,
      ),
    );

    await tester.ensureVisible(find.text('Очистить память значка'));
    await tester.tap(find.text('Очистить память значка'));
    await tester.pumpAndSettle();
    expect(find.text('Очистить память значка?'), findsOneWidget);
    expect(find.textContaining('Прошивка, настройки'), findsOneWidget);

    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();

    expect(device.connectCalls, 1);
    expect(device.clearCalls, 1);
    expect(find.textContaining('Память значка очищена'), findsOneWidget);
  });
}

class _ClearableDevice implements ShowDevice {
  int connectCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> clearMedia() async {
    clearCalls++;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<ShowDeviceStatus> status() async =>
      const ShowDeviceStatus(state: 'fallback', installed: false);

  @override
  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    required void Function() onTransferComplete,
  }) async {}
}
