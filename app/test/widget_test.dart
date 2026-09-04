import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:znachok_bmw/main.dart';
import 'package:znachok_bmw/project_model.dart';
import 'package:znachok_bmw/show_publisher.dart';

void main() {
  testWidgets('starts with a compact media step and one add action',
      (tester) async {
    await tester.pumpWidget(
      const ZnachokApp(initialProject: ShowProject()),
    );

    expect(find.text('Znachok'), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-compose')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-publish')), findsOneWidget);
    expect(find.text('Добавьте медиа'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-content-empty')));
    await tester.pumpAndSettle();

    expect(find.text('Медиа'), findsWidgets);
    expect(find.text('Текст'), findsOneWidget);
    expect(find.text('Логотип'), findsOneWidget);
    expect(find.text('Фон'), findsOneWidget);
    expect(find.text('Бегущая строка'), findsOneWidget);
    expect(find.textContaining('.zshow'), findsNothing);
  });

  testWidgets('separates clip composition from the final project preview',
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

    expect(find.byKey(const ValueKey('compose-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('publish-preview')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('flow-step-publish')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('compose-canvas')), findsNothing);
    expect(find.byKey(const ValueKey('publish-preview')), findsOneWidget);
    expect(find.text('Загрузить'), findsOneWidget);
  });

  testWidgets('keeps timing and transitions on their own step', (tester) async {
    await tester.pumpWidget(
      const ZnachokApp(
        initialProject: ShowProject(
          clips: [
            ShowClip(
              id: 'timeline',
              name: 'timeline.png',
              assetPath: 'missing-timeline.png',
              kind: ClipKind.image,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Тайминг'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('flow-step-timeline')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('timeline-list')), findsOneWidget);
    expect(find.text('Тайминг'), findsOneWidget);
    expect(find.text('Переход'), findsOneWidget);
  });

  testWidgets('allows free step navigation and clears board media explicitly',
      (tester) async {
    final device = _ClearableDevice();
    await tester.pumpWidget(
      ZnachokApp(
        initialProject: const ShowProject(),
        device: device,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('flow-step-publish')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Нет клипов'), findsOneWidget);

    await tester.tap(find.text('Очистить память значка'));
    await tester.pumpAndSettle();
    expect(find.text('Очистить память значка?'), findsOneWidget);
    expect(find.textContaining('Прошивка, настройки'), findsOneWidget);

    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();

    expect(device.connectCalls, 1);
    expect(device.clearCalls, 1);
    expect(device.disconnectCalls, 1);
  });

  testWidgets('media step stays usable on a 375px phone', (tester) async {
    await _setScreenSize(tester, const Size(375, 812));

    await tester.pumpWidget(
      const ZnachokApp(initialProject: ShowProject()),
    );
    await tester.pump();

    expect(find.text('Добавьте медиа'), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compose step has no layout overflow in phone landscape',
      (tester) async {
    await _setScreenSize(tester, const Size(812, 375));

    await tester.pumpWidget(
      const ZnachokApp(
        initialProject: ShowProject(
          clips: [
            ShowClip(
              id: 'responsive',
              name: 'responsive-preview.png',
              assetPath: 'missing-responsive-preview.png',
              kind: ClipKind.image,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('compose-canvas')), findsOneWidget);
    expect(find.text('Вписать'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Y'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four-step structure remains intact on a large screen',
      (tester) async {
    await _setScreenSize(tester, const Size(1200, 800));

    await tester.pumpWidget(
      const ZnachokApp(initialProject: ShowProject()),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('flow-step-media')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-compose')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-timeline')), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-publish')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('step flow supports large system text on a small phone',
      (tester) async {
    await _setScreenSize(tester, const Size(375, 812));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const ZnachokApp(initialProject: ShowProject()),
    );
    await tester.pump();

    expect(find.text('Добавьте медиа'), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-step-publish')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _ClearableDevice implements ShowDevice {
  int connectCalls = 0;
  int clearCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<void> clearMedia() async {
    clearCalls++;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
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
