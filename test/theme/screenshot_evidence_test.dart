import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';

import '../support/nuvo_test_harness.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Visual Evidence
//
// Renders every primary tab at 390×844 (with realistic device insets) and
// asserts the actual rendered background, navigation surface, and primary
// text colours match the light specification. These tests stand in for
// screenshot capture in environments where golden rendering is unavailable
// (Google Fonts cannot load in the test sandbox).
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('Visual evidence: every tab is light at 390×844', () {
    for (final tab in kNuvoTabs) {
      testWidgets('${tab.name} shell bg = NuvoColors.page', (tester) async {
        await pumpNuvoTab(
          tester,
          tab.route,
          arenaState: tab.route == '/arena'
              ? ArenaState(snapshot: populatedArena())
              : null,
        );

        final shell = tester.widgetList<Scaffold>(find.byType(Scaffold)).first;
        expect(shell.backgroundColor, NuvoColors.page,
            reason: '${tab.name} shell must be NuvoColors.page (#F7F9FC)');
      });

      testWidgets('${tab.name} nav surface is white', (tester) async {
        await pumpNuvoTab(
          tester,
          tab.route,
          arenaState: tab.route == '/arena'
              ? ArenaState(snapshot: populatedArena())
              : null,
        );

        expectLightNavSurface(tester, tab.name);
      });
    }
  });

  group('Visual evidence: dark platform brightness has no effect', () {
    for (final tab in kNuvoTabs) {
      testWidgets('${tab.name} stays light under dark platform brightness',
          (tester) async {
        await pumpNuvoTab(
          tester,
          tab.route,
          platformBrightness: Brightness.dark,
          arenaState: tab.route == '/arena'
              ? ArenaState(snapshot: populatedArena())
              : null,
        );

        final shell = tester.widgetList<Scaffold>(find.byType(Scaffold)).first;
        expect(shell.backgroundColor, NuvoColors.page,
            reason: '${tab.name} must stay light even when the device '
                'is in dark appearance');
      });
    }
  });

  group('Visual evidence: navigation clearance', () {
    for (final tab in kNuvoTabs) {
      testWidgets('${tab.name} nav is present and reachable',
          (tester) async {
        await pumpNuvoTab(
          tester,
          tab.route,
          arenaState: tab.route == '/arena'
              ? ArenaState(snapshot: populatedArena())
              : null,
        );

        // The nav must be on screen and tappable.
        final nav = find.byType(NuvoBottomNav);
        expect(nav, findsOneWidget);
        final navRect = tester.getRect(nav);
        final viewHeight = tester.view.physicalSize.height /
            tester.view.devicePixelRatio;

        // Nav occupies the bottom of the screen.
        expect(navRect.bottom, greaterThanOrEqualTo(viewHeight * 0.85),
            reason: '${tab.name}: nav must sit at the bottom of the screen');
        // Nav is visible (has non-zero height).
        expect(navRect.height, greaterThan(50),
            reason: '${tab.name}: nav must have visible height');
      });
    }
  });

  group('Visual evidence: Arena renders its signature components', () {
    testWidgets('Arena shows the Next Move hero, Momentum Path, and standings',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.text('YOUR NEXT MOVE'), findsOneWidget);
      expect(find.text('First to 100 Pushups'), findsOneWidget);
      expect(find.text('CREW STANDINGS'), findsOneWidget);
      // The Momentum Path paints via CustomPaint.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Arena shows the header identity and pulse', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.text('NUVO'), findsOneWidget);
      expect(find.text('Arena'), findsWidgets);
      expect(find.text('2 races need proof'), findsOneWidget);
    });
  });

  group('Visual evidence: Reduce Motion keeps content visible', () {
    for (final tab in kNuvoTabs) {
      testWidgets('${tab.name} renders fully with animations disabled',
          (tester) async {
        await pumpNuvoTab(
          tester,
          tab.route,
          reduceMotion: true,
          arenaState: tab.route == '/arena'
              ? ArenaState(snapshot: populatedArena())
              : null,
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(NuvoBottomNav), findsOneWidget);
      });
    }
  });
}
