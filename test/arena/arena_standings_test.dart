// Arena standings adapt to field size — one racer gets a compact leader
// card, two get head-to-head rows, three-plus get the full podium — and the
// page's last row must scroll fully clear of the floating dock.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/widgets/nuvo_podium.dart';
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

/// The removed ice-blue stage geometry (step slabs + floor bands) that used
/// to sit under solo and head-to-head standings — `panelLight` appears
/// nowhere else in the Arena tree, so this finder is the stage itself and
/// must stay empty.
Finder _iceStagePieces() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).color == NuvoColors.panelLight,
);

void main() {
  testWidgets('one racer: compact leader card, no three-slot podium', (
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

    expect(tester.takeException(), isNull);
    expect(find.byType(NuvoPodium), findsNothing);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('39 / 50'), findsOneWidget);
    // No stage geometry: the standing is badge + avatar + name + score on
    // the page — no slab, no floor band, nothing behind it.
    expect(_iceStagePieces(), findsNothing);
  });

  testWidgets('two racers: head-to-head rows, no podium', (tester) async {
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
    expect(find.byType(NuvoPodium), findsNothing);
    expect(find.text('Noah W.'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('41 / 50'), findsOneWidget);
    expect(find.text('39 / 50'), findsOneWidget);
    // Head-to-head stands clean too — no slabs, no shared floor band.
    expect(_iceStagePieces(), findsNothing);
  });

  testWidgets('three-plus racers: full podium plus rank rows', (tester) async {
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
    expect(find.byType(NuvoPodium), findsOneWidget);
    // Rank 4 renders as an ordinary scroll row, not a podium slot.
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

  group('first viewport ends on the leaderboard', () {
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
      '3+ racers': [
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
        testWidgets('${w.key} / ${r.key}: activity starts at or below the '
            'dock, then scrolls fully clear', (tester) async {
          await _pump(tester, _snapshot(r.value), size: w.value);
          expect(tester.takeException(), isNull);

          final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
          final raLabel = find.text('Recent activity');
          if (raLabel.evaluate().isNotEmpty) {
            expect(
              tester.getTopLeft(raLabel).dy,
              greaterThanOrEqualTo(navTop),
              reason:
                  '${w.key}/${r.key}: nothing from the next section peeks '
                  'above the dock at rest',
            );
          }

          // Scroll: the section reveals and its last row clears the dock.
          final lastRow = find.text('activity row 3');
          await tester.scrollUntilVisible(
            lastRow,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(raLabel).dy,
            lessThan(navTop),
            reason: '${w.key}/${r.key}: Recent activity reveals on scroll',
          );
          expect(
            tester.getBottomLeft(lastRow).dy,
            lessThan(navTop),
            reason: '${w.key}/${r.key}: last row clears the dock',
          );
        });
      }
    }
  });

  testWidgets('final activity row scrolls fully above the floating dock', (
    tester,
  ) async {
    await _pump(tester, _snapshot(const [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '39 / 50',
        isCurrentUser: true,
      ),
    ]));

    final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
    final lastRow = find.text('activity row 3');
    await tester.scrollUntilVisible(
      lastRow,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      tester.getBottomLeft(lastRow).dy,
      lessThan(navTop),
      reason: 'the last content row must clear the dock, not hide behind it',
    );
  });

  testWidgets('hero stays inside its share of the usable viewport', (
    tester,
  ) async {
    await _pump(tester, _snapshot(const [
      ArenaMiniLeaderboardRow(
        label: 'You',
        value: '39 / 50',
        isCurrentUser: true,
      ),
    ]));

    final card = tester.getSize(find.byType(PageView).first).height;
    final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
    final usable = navTop - 47;
    expect(
      card / usable,
      lessThan(0.44),
      reason:
          'hero anchors the page instead of owning half of it '
          '(measured ${(card / usable * 100).toStringAsFixed(1)}%)',
    );
    expect(card, greaterThan(200), reason: 'hero still has visual authority');
  });
}
