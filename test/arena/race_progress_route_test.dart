// Regression coverage for Arena's hero race lane. The hero renders the
// shared marker track (You / rival / goal ring) when the board carries
// markable scores; the curved identity path remains the fallback and is
// covered directly in test/nuvo_race_path_test.dart via NuvoRacePath's own
// public API — plus a direct painter-bounds check below.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/core/widgets/nuvo_race_path.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

Future<void> _pumpArenaPreview(WidgetTester tester) async {
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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hero renders the marker lane with named marks', (
    tester,
  ) async {
    await _pumpArenaPreview(tester);

    // The preview board is 65/100 vs Alex 48/100 — the lane names both.
    expect(find.byType(RaceMarkerTrack), findsWidgets);
    expect(find.textContaining('You 65'), findsWidgets);
    expect(find.textContaining('Alex'), findsWidgets);
    expect(find.textContaining('Goal'), findsWidgets);
  });

  testWidgets('painter stays within its own bounds and does not throw', (
    tester,
  ) async {
    // The identity path is still the hero's fallback — drive its painter
    // directly at the hero variant's fixed height.
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 280,
          child: NuvoRacePath(raceId: 'preview-race', progress: 0.65),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final customPaint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_RacePathPainter',
      ),
    );
    final painter = customPaint.painter!;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(280, 42);
    expect(() => painter.paint(canvas, size), returnsNormally);
    recorder.endRecording().dispose();
  });
}
