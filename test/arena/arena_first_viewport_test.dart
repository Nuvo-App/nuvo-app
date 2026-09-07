import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// The intended Arena first composition:
///   header → YOUR NEXT MOVE → [big card] → actions → LEADERBOARD → (fold)
/// RECENT ACTIVITY must begin below the first viewport on normal phones, and
/// the card must gain vertical authority without shrinking the chunky pieces.
void main() {
  Future<void> pumpArena(WidgetTester tester, Size size,
      {double bottomInset = 34}) async {
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
    testWidgets('${entry.key}: first composition ends on the leaderboard',
        (tester) async {
      final size = entry.value;
      await pumpArena(tester, size);

      expect(tester.takeException(), isNull);
      expect(find.text('YOUR NEXT MOVE'), findsOneWidget);
      expect(find.text('LEADERBOARD'), findsOneWidget);

      final foldY = size.height - 34; // above the home indicator / nav

      // Leaderboard label is within the first viewport.
      final lbY = tester.getTopLeft(find.text('LEADERBOARD')).dy;
      expect(lbY, lessThan(foldY), reason: '${entry.key}: leaderboard visible');

      // The card carries real height — not a thin info strip.
      final cardBox = tester.getSize(
        find.byType(PageView).first,
      );
      if (size.height >= 800) {
        expect(cardBox.height, greaterThan(300),
            reason: '${entry.key}: card has vertical authority');
      }

      // Chunky action buttons survive (not shrunk to fit).
      final submitBtn = tester.widget<NuvoPrimaryButton>(
        find.byType(NuvoPrimaryButton),
      );
      expect(submitBtn.height, greaterThanOrEqualTo(56),
          reason: '${entry.key}: submit stays chunky');

      // RECENT ACTIVITY begins below the first composition on normal phones —
      // either not laid out yet (lazy sliver, well past the fold) or, if
      // built, positioned below it.
      if (size.height >= 800) {
        final raFinder = find.text('RECENT ACTIVITY');
        if (raFinder.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(raFinder).dy, greaterThan(foldY),
              reason: '${entry.key}: Recent Activity is below the fold');
        }
        // else: not even built — definitively below the first viewport.
      }
    });
  }

  testWidgets('no global compact mode — card proportion holds across sizes',
      (tester) async {
    await pumpArena(tester, const Size(390, 844));
    final h390 = tester.getSize(find.byType(PageView).first).height;
    await pumpArena(tester, const Size(430, 932));
    final h430 = tester.getSize(find.byType(PageView).first).height;
    // A wider/taller phone gets a bigger card, not the same clamped pixel.
    expect(h430, greaterThan(h390));
  });
}
