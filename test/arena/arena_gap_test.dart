// Structural composition coverage for Arena's "one product module" fix:
// hero card → dots → action row → Leaderboard should read as one continuous
// flow with tight, deliberate gaps — not a hero card floating detached from
// its own controls. This guards the actual regression (a large, unbounded
// gap between the card and the dots caused by an oversized height estimate)
// rather than asserting exact pixel values.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

Future<void> _pumpArena(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
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
          GoRoute(path: '/arena', builder: (c, s) => const ArenaScreen(preview: true)),
        ],
      ),
    ],
  );
  await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  const sizes = {
    // 375x667 (iPhone SE-class), matching the compact reference size used
    // elsewhere in the suite (arena_first_viewport_test.dart). A genuinely
    // extreme short viewport (e.g. 320x568) can legitimately require a
    // scroll to reach the action row — that's normal sliver behavior, not a
    // composition bug this test should assert against.
    'compact': Size(375, 667),
    'standard': Size(390, 844),
    'large': Size(430, 932),
  };

  for (final entry in sizes.entries) {
    testWidgets(
      '${entry.key}: gap between hero card and Submit proof row is tight, not a detached module',
      (tester) async {
        await _pumpArena(tester, entry.value);

        final cardBottom = tester.getBottomLeft(find.byType(PageView).first).dy;
        final submitProofTop = tester
            .getTopLeft(find.widgetWithText(NuvoPrimaryButton, 'Submit proof'))
            .dy;
        final gap = submitProofTop - cardBottom;

        // Generous bound: covers the dots row (when present) plus small
        // deliberate spacing, but rules out the old "huge empty gap" bug
        // (which measured well over 100px).
        expect(
          gap,
          inInclusiveRange(0.0, 70.0),
          reason:
              '${entry.key}: hero → dots → actions should read as one module, not float apart (measured gap: $gap)',
        );
      },
    );

    testWidgets(
      '${entry.key}: gap between the action row and Leaderboard is tight',
      (tester) async {
        await _pumpArena(tester, entry.value);

        final submitProofBottom = tester
            .getBottomLeft(find.widgetWithText(NuvoPrimaryButton, 'Submit proof'))
            .dy;
        final leaderboardTop = tester.getTopLeft(find.text('Leaderboard')).dy;
        final gap = leaderboardTop - submitProofBottom;

        // The leaderboard is intentionally separated from the action row —
        // the standings section centers itself in the leftover lower
        // region. It must never be glued to the buttons (< 20px) nor
        // drifting arbitrarily far below them.
        expect(
          gap,
          inInclusiveRange(20.0, 320.0),
          reason:
              '${entry.key}: the leaderboard breathes below the actions — '
              'not glued, not floating loose (measured gap: $gap)',
        );
      },
    );
  }
}
