import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:znachok_bmw/clip_preview.dart';
import 'package:znachok_bmw/project_model.dart';

void main() {
  test('canvas axis snaps to center only inside the guide threshold', () {
    expect(snapCanvasAxis(4, 8), 0);
    expect(snapCanvasAxis(-8, 8), 0);
    expect(snapCanvasAxis(8.1, 8), 8.1);
  });

  test('canvas angle snaps to level quarter turns', () {
    expect(snapCanvasAngle(0.03), 0);
    expect(snapCanvasAngle(math.pi / 2 + 0.03), closeTo(math.pi / 2, 1e-9));
    expect(snapCanvasAngle(math.pi + 0.03), closeTo(math.pi, 1e-9));
    expect(snapCanvasAngle(0.2), 0.2);
  });

  testWidgets('canvas shows a guide while an item is magnetized',
      (tester) async {
    ShowClip? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 300,
            child: DraftClipCanvas(
              clip: const ShowClip(
                id: 'snap',
                name: 'snap.png',
                assetPath: 'missing-snap.png',
                kind: ClipKind.image,
                offsetX: 30,
              ),
              onChanged: (clip) => changed = clip,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DraftClipCanvas)),
    );
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();

    expect(changed?.offsetX, 0);
    expect(find.byKey(const ValueKey('canvas-guide-x')), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('canvas-guide-x')), findsNothing);
  });
}
