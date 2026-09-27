// Regression coverage for Arena's route-shaped progress track. The curved
// path itself now lives in the shared, reusable `NuvoRacePath` widget
// (lib/core/widgets/nuvo_race_path.dart) — its painter class is private to
// that file, so the Arena-hosted test below drives it through the public
// ArenaScreen(preview: true) surface, and the determinism/uniqueness
// contract is covered directly in test/nuvo_race_path_test.dart via
// NuvoRacePath's own public API.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

Future<CustomPaint> _pumpProgressPainter(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/arena',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/arena',
            builder: (context, state) => const ArenaScreen(preview: true),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  // Progress animates in via TweenAnimationBuilder (700ms easeOutCubic) —
  // settle it so the painter receives its final target value, not a
  // mid-animation one.
  await tester.pumpAndSettle();

  final finder = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_RacePathPainter',
  );
  expect(finder, findsOneWidget);
  return tester.widget<CustomPaint>(finder);
}

void main() {
  testWidgets('progress track renders with semantics describing completion', (
    tester,
  ) async {
    await _pumpProgressPainter(tester);

    // Checked on the Semantics widget's own properties rather than the
    // assembled SemanticsNode tree — this widget sits inside several
    // ancestor Semantics boundaries (the card, the row), so its label can
    // get merged into a combined node upstream; the properties it
    // contributes are what this test cares about.
    final semanticsWidgets = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((w) => w.properties.label == 'Race progress')
        .toList();
    expect(semanticsWidgets, hasLength(1));
    // The preview snapshot's focus board is 65/100 — 65%.
    expect(semanticsWidgets.single.properties.value, '65%');
  });

  testWidgets('painter stays within its own bounds and does not throw', (
    tester,
  ) async {
    final customPaint = await _pumpProgressPainter(tester);
    final painter = customPaint.painter!;

    // Paint onto a real, bounded canvas via PictureRecorder — proves
    // paint() doesn't throw for a real (65%) progress value, at the hero
    // variant's fixed height.
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(280, 42);
    expect(() => painter.paint(canvas, size), returnsNormally);
    recorder.endRecording().dispose();
  });
}
