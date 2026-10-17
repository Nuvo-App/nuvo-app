import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

void main() {
  test('pushups and plank use the side view, others stay front view', () {
    expect(pushupsDemo.sideView, isTrue);
    expect(plankHoldDemo.sideView, isTrue);
    expect(squatsDemo.sideView, isFalse);
  });

  test('pushup bottom frame is clearly lower than the top frame', () {
    final top = pushupsDemo.poseAt(0);
    final bottom = pushupsDemo.poseAt(0.5);
    expect(bottom.leftShoulder.dy - top.leftShoulder.dy, greaterThan(0.1));
    // Hands stay planted.
    expect(bottom.leftWrist, top.leftWrist);
  });

  testWidgets('side view paints without error', (tester) async {
    for (final demo in [pushupsDemo, plankHoldDemo]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 300,
            child: CustomPaint(
              painter: NuvoCharacterPainter(
                pose: demo.poseAt(0.5),
                view: NuvoCharacterView.side,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
