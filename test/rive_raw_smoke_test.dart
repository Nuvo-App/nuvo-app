import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/widgets/rive_movement_preview.dart';
import 'package:rive/rive.dart';

void main() {
  testWidgets('raw Nuvo stickman Rive smoke render loads the artboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RiveJumpingJackPreview(fallback: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(RiveWidget), findsOneWidget);
  });
}
