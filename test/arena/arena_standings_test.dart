// Arena standings adapt to field size — the first screen shows the top 3
// (1-3 places; empty seats simply don't render), ranks 4+ are folded behind
// the curtain until it is unfolded — and the last row must scroll fully clear
// of the floating dock.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

ArenaSnapshot _snapshot(List<ArenaMiniLeaderboardRow> rows) => ArenaSnapshot(
  mode: 'real',
  headerPulse: '${rows.length} moving',
  focusBoard: ArenaBoard(
    id: 'standings-race',
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
    for (var i = 0; i < 4; i++)
      ArenaActivity(
        id: 'a$i',
        actorName: 'Maya',
        text: 'activity row $i',
        timeLabel: '${i + 1}h',
        type: 'proof_submitted',
      ),
  ],
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

void main() {
  testWidgets('one racer: podium composition, no generic list', (tester) async {
    await _pump(
      tester,
      _snapshot(const [
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('39 / 50'), findsOneWidget);
    expect(find.text('See full leaderboard'), findsNothing);
  });

  testWidgets('two racers: podium composition preserves ranking', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(const [
        ArenaMiniLeaderboardRow(label: 'Noah W.', value: '41 / 50'),
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Noah W.'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('41 / 50'), findsOneWidget);
    expect(find.text('39 / 50'), findsOneWidget);
    expect(find.text('See full leaderboard'), findsNothing);
  });

  testWidgets('four racers: top 3 shown, rank 4 behind the curtain', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(const [
        ArenaMiniLeaderboardRow(label: 'Noah W.', value: '41 / 50'),
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
        ArenaMiniLeaderboardRow(label: 'Lena O.', value: '30 / 50'),
        ArenaMiniLeaderboardRow(label: 'Theo M.', value: '22 / 50'),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Noah W.'), findsOneWidget);
    expect(find.text('Lena O.'), findsOneWidget);
    expect(find.text('Theo M.'), findsNothing);
    await tester.tap(find.text('See full leaderboard'));
    await tester.pumpAndSettle();
    expect(find.text('Theo M.'), findsOneWidget);
    expect(find.text('22 / 50'), findsOneWidget);
  });

  testWidgets('long race title ellipsizes inside the hero without overflow', (
    tester,
  ) async {
    final snapshot = _snapshot(const [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '39 / 50',
        isCurrentUser: true,
      ),
    ]);
    await _pump(
      tester,
      ArenaSnapshot(
        mode: snapshot.mode,
        headerPulse: snapshot.headerPulse,
        focusBoard: ArenaBoard(
          id: 'long-title',
          source: 'demo',
          title:
              'An Extremely Long Race Title That Should Wrap And Ellipsize '
              'Gracefully',
          progressLabel: '39 / 50 reps',
          boardContext: '',
          primaryActionLabel: 'Submit proof',
          primaryActionType: 'submit_proof',
          progressPercent: 78,
          racerCount: 1,
          isResult: false,
          miniLeaderboard: snapshot.focusBoard!.miniLeaderboard,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(PageView), findsOneWidget);
  });

  group('first viewport ends on the top 3', () {
    const racerCounts = <String, List<ArenaMiniLeaderboardRow>>{
      '1 racer': [
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
      ],
      '2 racers': [
        ArenaMiniLeaderboardRow(label: 'Noah W.', value: '41 / 50'),
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
      ],
      '4 racers': [
        ArenaMiniLeaderboardRow(label: 'Noah W.', value: '41 / 50'),
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
        ArenaMiniLeaderboardRow(label: 'Lena O.', value: '30 / 50'),
        ArenaMiniLeaderboardRow(label: 'Theo M.', value: '22 / 50'),
      ],
    };

    const widths = <String, Size>{
      'small': Size(375, 667),
      'standard': Size(390, 844),
      'large': Size(430, 932),
    };

    for (final w in widths.entries) {
      for (final r in racerCounts.entries) {
        testWidgets('${w.key} / ${r.key}: top 3 above the dock, nothing '
            'scrolls while folded', (tester) async {
          await _pump(tester, _snapshot(r.value), size: w.value);
          expect(tester.takeException(), isNull);

          final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
          expect(find.text('Recent activity'), findsNothing);
          final last = r.value.length >= 3 ? 'Lena O.' : r.value.last.label;
          expect(
            tester.getBottomLeft(find.text(last)).dy,
            lessThanOrEqualTo(navTop),
            reason: '${w.key}/${r.key}: top 3 fully above the dock',
          );
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          expect(scrollable.position.maxScrollExtent, 0);
          expect(find.text('Theo M.'), findsNothing);
          expect(
            find.text('See full leaderboard'),
            r.value.length >= 4 ? findsOneWidget : findsNothing,
          );
        });
      }
    }
  });

  testWidgets('the last standings row scrolls fully above the dock', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(const [
        ArenaMiniLeaderboardRow(label: 'Noah W.', value: '41 / 50'),
        ArenaMiniLeaderboardRow(label: 'Lena O.', value: '30 / 50'),
        ArenaMiniLeaderboardRow(label: 'Theo M.', value: '22 / 50'),
        ArenaMiniLeaderboardRow(label: 'Zed Q.', value: '5 / 50'),
      ]),
    );

    final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
    await tester.tap(find.text('See full leaderboard'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('Zed Q.')).dy,
      lessThan(navTop),
      reason: 'the last content row must clear the dock, not hide behind it',
    );
  });

  testWidgets('hero stays inside its share of the usable viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot(const [
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '39 / 50',
          isCurrentUser: true,
        ),
      ]),
    );

    final card = tester.getSize(find.byType(PageView).first).height;
    final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
    final usable = navTop - 47;
    // The first-screen contract (header + hero + action row fill the visible
    // area; standings begin below the fold) lets the hero own a little more of
    // the page than the old 44% cap. It must still be a card, not the page.
    expect(
      card / usable,
      lessThan(0.50),
      reason:
          'hero anchors the page instead of owning half of it '
          '(measured ${(card / usable * 100).toStringAsFixed(1)}%)',
    );
    expect(card, greaterThan(200), reason: 'hero still has visual authority');
  });
}
