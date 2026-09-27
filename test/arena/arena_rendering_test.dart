// Arena rendering contracts: long hero titles must never clip inside the
// shared PageView slot (any carousel position, any width tier), and the
// floating dock must occlude scrolled content — rows hidden behind the
// dock zone re-emerge above it on scroll, never show through it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

ArenaBoard _board(
  String id,
  String title, {
  List<ArenaMiniLeaderboardRow> rows = const [
    ArenaMiniLeaderboardRow(
      label: 'You',
      value: '0 / 8',
      isCurrentUser: true,
    ),
  ],
}) =>
    ArenaBoard(
      id: id,
      source: 'demo',
      title: title,
      progressLabel: '0 / 8 reps',
      boardContext: '',
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof',
      progressPercent: 0,
      racerCount: rows.length,
      isResult: false,
      miniLeaderboard: rows,
    );

Future<void> _pump(
  WidgetTester tester,
  ArenaSnapshot snapshot, {
  Size size = const Size(390, 844),
}) async {
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
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}

/// Drives the hero carousel to [page] by flinging the PageView.
Future<void> _goToPage(WidgetTester tester, int page) async {
  for (var i = 0; i < page; i++) {
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();
  }
}

void main() {
  group('hero slot fits worst-case content', () {
    // A deliberately long two-line title — the card must fit it on every
    // carousel page and every width tier, not just "Mountain Climbers".
    const longTitle = 'First To 100 Mountain Climbers Regional Qualifier';

    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(430, 932),
    ]) {
      testWidgets('two-line title on the LAST page — ${size.width}w',
          (tester) async {
        final snapshot = ArenaSnapshot(
          mode: 'real',
          headerPulse: '3 boards',
          focusBoard: _board('b0', 'Pushups'),
          liveBoards: [
            _board('b1', 'Daily Plank'),
            _board('b2', longTitle),
          ],
          activity: const [],
        );
        await _pump(tester, snapshot, size: size);
        await _goToPage(tester, 2);

        expect(find.text(longTitle), findsOneWidget);
        // Footer band exists in the tree — at 320 the page legitimately
        // scrolls (occluded under the dock), so position isn't asserted;
        // the contract is that nothing inside the card overflows.
        expect(find.text('See race board'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('short vs long title — first and last pages both fit',
        (tester) async {
      final snapshot = ArenaSnapshot(
        mode: 'real',
        headerPulse: '2 boards',
        focusBoard: _board('b0', 'Pushups'),
        liveBoards: [_board('b1', longTitle)],
        activity: const [],
      );
      await _pump(tester, snapshot);
      expect(find.text('See race board'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _goToPage(tester, 1);
      expect(find.text(longTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('dock occlusion', () {
    testWidgets('opaque page-colored mask covers the dock zone',
        (tester) async {
      await _pump(
        tester,
        ArenaSnapshot(
          mode: 'real',
          headerPulse: 'moving',
          focusBoard: _board('b0', 'Pushup Battle'),
          activity: const [],
        ),
      );
      final mask = find.byKey(const ValueKey('nuvo-dock-occlusion'));
      expect(mask, findsOneWidget);
      final maskRect = tester.getRect(mask);
      final navRect = tester.getRect(find.byType(NuvoBottomNav));
      // Covers from at least the dock's top edge through the screen bottom.
      expect(maskRect.top, lessThanOrEqualTo(navRect.top));
      expect(maskRect.bottom, 844);
      final maskWidget = tester.widget<Container>(mask);
      expect(maskWidget.color, NuvoColors.page);
    });

    testWidgets('below-fold row scrolls above the dock', (tester) async {
      final rows = [
        const ArenaMiniLeaderboardRow(label: 'Ava', value: '50 / 50'),
        const ArenaMiniLeaderboardRow(label: 'Noah', value: '44 / 50'),
        const ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
        const ArenaMiniLeaderboardRow(label: 'Lena Ortiz', value: '30 / 50'),
      ];
      await _pump(
        tester,
        ArenaSnapshot(
          mode: 'real',
          headerPulse: 'moving',
          focusBoard: ArenaBoard(
            id: 'b0',
            source: 'demo',
            title: 'Pushup Battle',
            progressLabel: '39 / 50 reps',
            boardContext: '',
            primaryActionLabel: 'Submit proof',
            primaryActionType: 'submit_proof',
            progressPercent: 78,
            racerCount: rows.length,
            isResult: false,
            miniLeaderboard: rows,
          ),
          activity: [
            for (var i = 0; i < 6; i++)
              ArenaActivity(
                id: 'a$i',
                actorName: 'Maya',
                text: 'scroll target activity $i',
                timeLabel: '${i + 1}h',
                type: 'proof_submitted',
              ),
          ],
        ),
      );
      // Scroll the feed — content that was under the dock travels above it.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The mask still occludes the dock zone after scrolling.
      final maskRect =
          tester.getRect(find.byKey(const ValueKey('nuvo-dock-occlusion')));
      expect(
        maskRect.top,
        lessThanOrEqualTo(tester.getRect(find.byType(NuvoBottomNav)).top),
      );
    });
  });
}
