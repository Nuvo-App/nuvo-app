import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/animated_race_track.dart';
import 'package:nuvo/core/widgets/nuvo_leaderboard.dart';
import 'package:nuvo/core/widgets/nuvo_race_strip.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

void main() {
  Future<void> pumpArena(
    WidgetTester tester, {
    Size physicalSize = const Size(390, 844),
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

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
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('Arena mounts shared components on 390x844', (tester) async {
    await pumpArena(tester);

    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.byType(NuvoRaceTrack), findsWidgets);
    expect(find.byType(NuvoLeaderboard), findsOneWidget);
    expect(find.byType(NuvoRaceStripRail), findsOneWidget);

    expect(find.text('CREW STANDINGS'), findsOneWidget);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('Your next move'), findsOneWidget);
    expect(find.text('Submit proof'), findsOneWidget);
  });

  testWidgets('Arena mounts shared components on taller inset viewport', (
    tester,
  ) async {
    await pumpArena(
      tester,
      physicalSize: const Size(390, 932),
      bottomInset: 34,
    );

    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.byType(NuvoRaceTrack), findsWidgets);
    expect(find.byType(NuvoLeaderboard), findsOneWidget);
    expect(find.byType(NuvoRaceStripRail), findsOneWidget);
    expect(find.text('CREW STANDINGS'), findsOneWidget);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
  });

  testWidgets('NuvoRaceStripRail taps switch the active race', (tester) async {
    await pumpArena(tester);

    // Preview snapshot has 3 races: Pushups (selected), Squats, Lunges.
    expect(find.byType(NuvoRaceStripRail), findsOneWidget);

    // Tap the "Squats" strip to switch races.
    await tester.tap(find.text('Squats'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Squats board center value is 28 / 60 (race track center + leaderboard).
    expect(find.text('28 / 60'), findsWidgets);
  });
}
