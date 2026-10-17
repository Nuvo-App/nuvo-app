import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// The Arena first composition:
///   header -> Your next move -> [card] -> actions -> TOP 3 standings ->
///   "See full leaderboard" control. Rank 4+ sit behind the curtain and
///   appear only when it is unfolded; Recent activity no longer exists here.
ArenaSnapshot _board(int rows, {int me = 0}) => ArenaSnapshot(
  mode: 'real',
  headerPulse: '$rows moving',
  focusBoard: ArenaBoard(
    id: 'fv-race',
    source: 'demo',
    title: 'Pushup Battle',
    progressLabel: '65 / 100 reps',
    boardContext: '',
    primaryActionLabel: 'Submit proof',
    primaryActionType: 'submit_proof',
    progressPercent: 65,
    racerCount: rows,
    isResult: false,
    miniLeaderboard: [
      for (var i = 0; i < rows; i++)
        ArenaMiniLeaderboardRow(
          label: 'Racer ${i + 1}',
          value: '${90 - i * 7} / 100',
          isCurrentUser: i == me,
        ),
    ],
  ),
  activity: const [],
);

void main() {
  Future<void> pumpArena(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
    double textScale = 1.0,
    ArenaSnapshot? snapshot,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(top: 47, bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/arena',
              builder: (c, s) =>
                  ArenaScreen(preview: true, debugSnapshot: snapshot),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? ThemeData.dark() : null,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const sizes = <String, Size>{
    'compact (320x568)': Size(320, 568),
    'small iPhone (SE)': Size(375, 667),
    'standard (390x844)': Size(390, 844),
    'iPhone 393x852': Size(393, 852),
    'Pro Max (430x932)': Size(430, 932),
    'tall Android': Size(412, 915),
  };

  double dockTop(WidgetTester t) => t.getTopLeft(find.byType(NuvoBottomNav)).dy;

  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: top 3 visible, rank 4+ behind the curtain', (
      tester,
    ) async {
      final size = entry.value;
      final compact = size.width < 340;
      await pumpArena(
        tester,
        size,
        bottomInset: compact ? 0 : 34,
        snapshot: _board(6, me: 5),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Recent activity'), findsNothing);

      final foldY = dockTop(tester);
      // The section label only appears when the viewport has room for it.
      if (size.height >= 900) {
        expect(find.text('Your next move'), findsOneWidget);
      }

      // Top 3 rows plus the pinned "You . 6th" row, whole and above the dock
      // (the 320x568 page may scroll, so only the non-compact sizes assert
      // the full composition fits).
      expect(find.text('Racer 1'), findsOneWidget);
      expect(find.text('Racer 2'), findsOneWidget);
      expect(find.text('Racer 3'), findsOneWidget);
      expect(find.text('You · 6th'), findsOneWidget);
      expect(find.text('Racer 4'), findsNothing);
      expect(find.text('Racer 5'), findsNothing);
      expect(find.text('See full leaderboard'), findsOneWidget);
      if (!compact) {
        for (final f in [
          find.text('Racer 3'),
          find.text('You · 6th'),
          find.text('See full leaderboard'),
        ]) {
          expect(
            tester.getBottomLeft(f).dy,
            lessThanOrEqualTo(foldY),
            reason: '${entry.key}: first screen ends above the dock',
          );
        }
        // Whole page fits: nothing to scroll while folded.
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scrollable.position.maxScrollExtent,
          0,
          reason: '${entry.key}: folded page does not scroll',
        );
      }

      final progressFinder = find.textContaining('reps');
      expect(progressFinder, findsWidgets);
      if (!compact) {
        expect(
          tester.getBottomLeft(progressFinder.first).dy,
          lessThanOrEqualTo(foldY),
          reason: '${entry.key}: hero progress row above the dock',
        );
      }
      final cardBox = tester.getSize(find.byType(PageView).first);
      expect(cardBox.height, greaterThan(250));
      final submitBtn = tester.widget<NuvoPrimaryButton>(
        find.byType(NuvoPrimaryButton),
      );
      expect(submitBtn.height, greaterThanOrEqualTo(48));

      // Unfold: rank 4+ appear, scrolling to the end clears the dock.
      if (compact) {
        // 320x568 genuinely cannot fit: scroll the control above the dock.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('See full leaderboard'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Show less'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Racer 4'), findsOneWidget);
      // Row 6 is the viewer ("You").
      expect(find.text('You'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('You')).dy,
        lessThanOrEqualTo(dockTop(tester)),
        reason: '${entry.key}: last row clears the dock',
      );

      // Fold back.
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('Racer 4'), findsNothing);
      expect(find.text('See full leaderboard'), findsOneWidget);
    });
  }

  testWidgets('control only appears with 4 or more rows', (tester) async {
    await pumpArena(tester, const Size(390, 844), snapshot: _board(3));
    expect(find.text('Racer 3'), findsOneWidget);
    expect(find.text('See full leaderboard'), findsNothing);
    await pumpArena(tester, const Size(390, 844), snapshot: _board(4));
    expect(find.text('See full leaderboard'), findsOneWidget);
    expect(find.text('Racer 4'), findsNothing);
  });

  testWidgets('viewer inside the top 3 is highlighted, not pinned again', (
    tester,
  ) async {
    await pumpArena(tester, const Size(390, 844), snapshot: _board(5, me: 1));
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining('You ·'), findsNothing);
  });

  testWidgets('upward fling on the control unfolds the curtain', (
    tester,
  ) async {
    await pumpArena(tester, const Size(390, 844), snapshot: _board(6));
    await tester.fling(
      find.text('See full leaderboard'),
      const Offset(0, -120),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Racer 4'), findsOneWidget);
  });

  testWidgets('curtain animates by reveal (not scroll) and reduce-motion is '
      'instant', (tester) async {
    await pumpArena(tester, const Size(390, 844), snapshot: _board(6));
    await tester.tap(find.text('See full leaderboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // Mid-flight: rows exist but the clip is still partial and the scroll
    // position never moved.
    expect(find.text('Racer 4'), findsOneWidget);
    final sheetMid = tester.getSize(find.byType(ClipRect).last).height;
    await tester.pumpAndSettle();
    final sheetEnd = tester.getSize(find.byType(ClipRect).last).height;
    expect(sheetMid, lessThan(sheetEnd));

    // Reduce motion: one pump is enough.
    await tester.pumpWidget(const SizedBox());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpArena(tester, const Size(390, 844), snapshot: _board(6));
    await tester.tap(find.text('See full leaderboard'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Racer 4'), findsOneWidget);
    // The control rides the bottom of the dropped curtain.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text('Racer 4'), findsNothing);
  });

  testWidgets('control exposes button + expanded semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpArena(tester, const Size(390, 844), snapshot: _board(6));
    var node = tester.getSemantics(find.text('See full leaderboard'));
    expect(node.label, contains('See full leaderboard'));
    expect(node.flagsCollection.isButton, isTrue);
    await tester.tap(find.text('See full leaderboard'));
    await tester.pumpAndSettle();
    node = tester.getSemantics(find.text('Show less'));
    expect(node.label, contains('Show less'));
    handle.dispose();
  });

  testWidgets('dark mode renders the folded and unfolded board', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(390, 844),
      snapshot: _board(6),
      dark: true,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('See full leaderboard'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('320x568 at 1.4 text scale renders without overflow', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(320, 568),
      bottomInset: 0,
      textScale: 1.4,
      snapshot: _board(6, me: 5),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See full leaderboard'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('card height is content-driven: same density tier gives the same '
      'height regardless of raw width', (tester) async {
    await pumpArena(tester, const Size(390, 844));
    final hStandard = tester.getSize(find.byType(PageView).first).height;
    await pumpArena(tester, const Size(430, 850));
    final hProMax = tester.getSize(find.byType(PageView).first).height;
    expect(hProMax, closeTo(hStandard, 1.0));
  });

  testWidgets(
    'card height grows only when the density tier actually changes (compact -> large)',
    (tester) async {
      await pumpArena(tester, const Size(320, 568), bottomInset: 0);
      final hCompact = tester.getSize(find.byType(PageView).first).height;
      await pumpArena(tester, const Size(430, 980), bottomInset: 0);
      final hLarge = tester.getSize(find.byType(PageView).first).height;
      expect(hLarge, greaterThan(hCompact));
    },
  );

  group('dark-mode hero surface', () {
    double lum(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('dark hero is lighter than the old surface; light unchanged', () {
      final dark = arenaHeroSurface(Brightness.dark, NuvoColors.darkSurface);
      expect(dark, isNot(NuvoColors.darkSurface));
      expect(lum(dark), greaterThan(lum(NuvoColors.darkSurface)));
      expect(
        arenaHeroSurface(Brightness.light, NuvoColors.surface),
        NuvoColors.surface,
      );
    });

    test('text on the dark hero keeps >= 4.5:1', () {
      final dark = arenaHeroSurface(Brightness.dark, NuvoColors.darkSurface);
      expect(contrast(NuvoColors.darkInk, dark), greaterThanOrEqualTo(4.5));
      expect(
        contrast(NuvoColors.darkInkMuted, dark),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
