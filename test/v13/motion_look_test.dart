import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/core/widgets/nuvo_focused_stage.dart';
import 'package:nuvo/features/races/presentation/ai_motion_proof_entry.dart';

import '../helpers/screenshot.dart';

void main() {
  setUpAll(loadShotFonts);

  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('camera primer sheet renders in the v13 look', (tester) async {
    size(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: V13.bg,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: CameraPrimerSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(V13Button), findsWidgets);
    await shot(tester, 'v13_motion_primer');
  });

  testWidgets('focused stage (verified result) renders in the v13 look', (
    tester,
  ) async {
    size(tester);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: V13.bg,
          body: NuvoFocusedStage(
            title: 'Nice set.',
            body: 'AI Motion verified it.',
            icon: Icons.check_rounded,
            accent: V13.mint,
            primaryLabel: 'View race',
            onPrimary: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'v13_motion_verified');
    await tester.tap(find.text('View race'));
    expect(tapped, isTrue);
  });
}
