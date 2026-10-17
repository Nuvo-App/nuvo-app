import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// The Arena first composition:
///   header -> Your next move -> [card through its N / M reps progress row]
///   -> actions -> (fold). The standings (Leaderboard) begin BELOW the visible
/// area and only appear on scroll; Recent activity no longer exists here.
void main() {
  Future<void> pumpArena(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
    double textScale = 1.0,
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
              builder: (c, s) => const ArenaScreen(preview: true),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
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

  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: standings start below the fold; hero is whole',
        (tester) async {
      final size = entry.value;
      final compact = size.width < 340;
      await pumpArena(tester, size, bottomInset: compact ? 0 : 34);
      expect(tester.takeException(), isNull);

      expect(find.text('Your next move'), findsOneWidget);
      expect(find.text('Recent activity'), findsNothing);

      final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
      // Standings label is built lazily; if it exists it must be at/below the
      // fold. (SliverList builds only what is near the viewport.)
      final lb = find.text('Leaderboard');
      if (lb.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(lb).dy,
          greaterThanOrEqualTo(foldY),
          reason: '${entry.key}: standings label starts at/below the dock',
        );
      }

      // The hero's progress row ("65" + "/ 100 reps") is fully above the dock
      // on every phone (the 320x568 hero is taller than its slot by design
      // and may scroll, so only its top is asserted there).
      final progressFinder = find.textContaining('reps');
      expect(progressFinder, findsWidgets);
      expect(tester.getTopLeft(progressFinder.first).dy, lessThan(foldY));
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

      // Scrolling reveals the standings.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Leaderboard')).dy,
        lessThan(foldY),
        reason: '${entry.key}: standings reachable by scrolling',
      );
    });
  }

  testWidgets('320x568 at 1.4 text scale renders without overflow', (
    tester,
  ) async {
    await pumpArena(tester, const Size(320, 568), bottomInset: 0, textScale: 1.4);
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
      expect(contrast(NuvoColors.darkInkMuted, dark), greaterThanOrEqualTo(4.5));
    });
  });
}
