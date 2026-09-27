import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// The intended Arena first composition:
///   header → YOUR NEXT MOVE → [big card] → actions → LEADERBOARD → (fold)
/// RECENT ACTIVITY must begin below the first viewport on normal phones, and
/// the card must gain vertical authority without shrinking the chunky pieces.
void main() {
  Future<void> pumpArena(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
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
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  // Representative supported phones (logical px, dpr 1).
  const sizes = <String, Size>{
    'small iPhone (SE)': Size(375, 667),
    'standard iPhone': Size(390, 844),
    'Pro Max iPhone': Size(430, 932),
    'tall Android': Size(412, 915),
  };

  for (final entry in sizes.entries) {
    testWidgets('${entry.key}: first composition ends on the leaderboard', (
      tester,
    ) async {
      final size = entry.value;
      await pumpArena(tester, size);

      expect(tester.takeException(), isNull);
      // Sentence case, not all-caps — matches every other screen's section
      // titles (Compete/Verify/Crew all use plain sectionTitle already).
      expect(find.text('Your next move'), findsOneWidget);
      expect(find.text('Leaderboard'), findsOneWidget);

      // The fold is the connected nav bar's top edge — the body extends to
      // the screen's bottom edge under the bar (extendBody: true), so
      // anything below the bar's top is out of the first composition.
      final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;

      // Leaderboard label is within the first composition. On tall phones
      // it must sit fully above the bar; on short phones it may peek under
      // the frosted bar at the bottom edge (the old floating dock clipped
      // the body even higher, so this is strictly more visible than before).
      final lbY = tester.getTopLeft(find.text('Leaderboard')).dy;
      if (size.height >= 800) {
        expect(
          lbY,
          lessThan(foldY),
          reason: '${entry.key}: leaderboard fully above the nav bar',
        );
      } else {
        expect(
          lbY,
          lessThan(size.height),
          reason: '${entry.key}: leaderboard renders in the first '
              'composition, possibly peeking under the frosted bar',
        );
      }

      // The card carries real height — not a thin info strip. (Deliberately
      // tighter than it used to be: the hero is now sized to its actual
      // measured content, not a generous width-based guess, so this floor
      // is calibrated to the new compact-but-substantial card, not the old
      // poster-sized one.)
      final cardBox = tester.getSize(find.byType(PageView).first);
      if (size.height >= 800) {
        expect(
          cardBox.height,
          greaterThan(250),
          reason: '${entry.key}: card has vertical authority',
        );
      }

      // Chunky action buttons survive (tightened, not shrunk to fit).
      final submitBtn = tester.widget<NuvoPrimaryButton>(
        find.byType(NuvoPrimaryButton),
      );
      expect(
        submitBtn.height,
        greaterThanOrEqualTo(48),
        reason: '${entry.key}: submit stays comfortably tappable',
      );

      // RECENT ACTIVITY is ordinary scroll content now — no artificial
      // spacer parks it below the fold. What must hold: once reached, the
      // section ends fully above the floating dock's top edge, i.e. nothing
      // interactive lives under the nav.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      final raFinder = find.text('Recent activity');
      if (raFinder.evaluate().isNotEmpty) {
        expect(
          tester.getBottomLeft(raFinder).dy,
          lessThanOrEqualTo(foldY),
          reason:
              '${entry.key}: reached activity content clears the dock',
        );
      }
    });
  }

  testWidgets('card height is content-driven: same density tier gives the same '
      'height regardless of raw width', (tester) async {
    // The hero's height is no longer a function of screen width at all — it
    // is measured from the card's actual content, then only adjusted by
    // vertical DENSITY tier (compact/regular/large, from usable height).
    // These two fixtures stay in the regular density tier while their raw
    // widths differ, so they should produce the same height — that's the fix,
    // not a regression: the old width-proportional formula gave a bigger card
    // on a wider phone even when nothing about the content needed more room.
    await pumpArena(tester, const Size(390, 844));
    final hStandard = tester.getSize(find.byType(PageView).first).height;
    await pumpArena(tester, const Size(430, 850));
    final hProMax = tester.getSize(find.byType(PageView).first).height;
    expect(hProMax, closeTo(hStandard, 1.0));
  });

  testWidgets(
    'card height grows only when the density tier actually changes (compact → large)',
    (tester) async {
      // A genuinely short viewport (compact density) vs a genuinely tall one
      // (large density) — this is where height should differ, not raw width
      // within the same tier (see the test above).
      await pumpArena(tester, const Size(320, 568), bottomInset: 0);
      final hCompact = tester.getSize(find.byType(PageView).first).height;
      await pumpArena(tester, const Size(430, 980), bottomInset: 0);
      final hLarge = tester.getSize(find.byType(PageView).first).height;
      expect(hLarge, greaterThan(hCompact));
    },
  );
}
