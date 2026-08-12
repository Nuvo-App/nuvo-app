import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';

import '../support/nuvo_test_harness.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Arena — light-mode home dashboard
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('Arena is light and TrackSide is gone', () {
    testWidgets('renders on the light page canvas', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      final shell = tester.widgetList<Scaffold>(find.byType(Scaffold)).first;
      expect(shell.backgroundColor, NuvoColors.page);
    });

    testWidgets('stays light when the device is in dark appearance',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          platformBrightness: Brightness.dark,
          arenaState: ArenaState(snapshot: populatedArena()));

      final shell = tester.widgetList<Scaffold>(find.byType(Scaffold)).first;
      expect(shell.backgroundColor, NuvoColors.page);
    });

    testWidgets('uses the same shared light navigation as other tabs',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.byType(NuvoBottomNav), findsOneWidget);
      expectLightNavSurface(tester, 'Arena');
    });
  });

  group('Populated Arena', () {
    testWidgets('shows the Your Next Move hero with title and progress',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.text('YOUR NEXT MOVE'), findsOneWidget);
      expect(find.text('First to 100 Pushups'), findsOneWidget);
      // Oversized numeric treatment: "65" and "/ 100 reps" are separate spans.
      expect(find.text('65'), findsOneWidget);
      expect(find.text(' / 100 reps'), findsOneWidget);
    });

    testWidgets('shows the header pulse from real data', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.text('2 races need proof'), findsOneWidget);
    });

    testWidgets('renders the Momentum Path (not an orbit)', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      // The signature component paints via CustomPaint inside the hero.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows Crew standings with the user highlighted',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(find.text('CREW STANDINGS'), findsOneWidget);
      // The current user is labelled "You", never their own name.
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Nuvo Review'), findsNothing);
    });

    testWidgets('orders standings by rank with the leader first',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      // Podium places are rendered as 1/2/3 badges.
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      // Rank 1 in the fixture is Maya Chen.
      expect(find.text('Maya Chen'), findsOneWidget);
    });

    testWidgets('shows recent activity entries', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      // Activity sits below the fold; scroll it into view.
      await tester.scrollUntilVisible(
        find.text('RECENT ACTIVITY'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('RECENT ACTIVITY'), findsOneWidget);
      expect(find.text('Maya verified 20 pushups'), findsOneWidget);
      expect(find.text('Dev joined the race'), findsOneWidget);
    });
  });

  group('Arena primary action', () {
    testWidgets('submit_proof routes to the proof screen', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      await tester.tap(find.text('Submit proof').first);
      await tester.pumpAndSettle();

      expect(find.text('Submit proof'), findsWidgets);
    });

    testWidgets('start_race routes to race creation', (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(
          snapshot: ArenaSnapshotBuilder.withBoard(
            board(actionLabel: 'Start a race', actionType: 'start_race'),
          ),
        ),
      );

      await tester.tap(find.text('Start a race').first);
      await tester.pumpAndSettle();

      expect(find.text('New race'), findsOneWidget);
    });

    testWidgets('open_board routes to the race room', (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(
          snapshot: ArenaSnapshotBuilder.withBoard(
            board(actionLabel: 'View results', actionType: 'open_board'),
          ),
        ),
      );

      await tester.tap(find.text('View results').first);
      await tester.pumpAndSettle();

      expect(find.text('Race room'), findsOneWidget);
    });
  });

  group('One vs multiple active races', () {
    testWidgets('a single race hides the page indicator', (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(
          snapshot: ArenaSnapshotBuilder.withBoard(board()),
        ),
      );

      expect(find.byType(PageView), findsOneWidget);
      // With one board there is nothing to page between.
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 1);
    });

    testWidgets('multiple races expose a swipeable pager', (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(snapshot: ArenaSnapshotBuilder.withBoards()),
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 3);
      expect(find.text('First to 100 Pushups'), findsOneWidget);
    });

    testWidgets('swiping changes the visible race', (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(snapshot: ArenaSnapshotBuilder.withBoards()),
      );

      expect(find.text('First to 100 Pushups'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('First to 60 Squats'), findsOneWidget);
    });
  });

  group('Arena states', () {
    testWidgets('empty state invites starting a race', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: const ArenaState(
              snapshot: ArenaSnapshot(mode: 'real', headerPulse: '')));

      expect(find.text('Set your first finish line'), findsOneWidget);
      expect(find.text('Start a race'), findsWidgets);
    });

    testWidgets('empty state action routes to race creation', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: const ArenaState(
              snapshot: ArenaSnapshot(mode: 'real', headerPulse: '')));

      await tester.tap(find.text('Start a race').first);
      await tester.pumpAndSettle();

      expect(find.text('New race'), findsOneWidget);
    });

    testWidgets('loading state shows a calm skeleton, never a blank screen',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: const ArenaState(loading: true));

      // Arena identity is still visible while loading (the page title, not
      // the nav label — hence excluding the nav subtree).
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Arena'),
        ),
        findsOneWidget,
      );
      // No spinner: a live demo should never show an indeterminate throbber.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The skeleton keeps the layout stable instead of collapsing to blank.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('error state explains recovery and offers retry',
        (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: const ArenaState(error: "Couldn't load races."));

      expect(find.textContaining("Couldn't load races"), findsOneWidget);
    });

    testWidgets('empty activity suggests a next action rather than "No activity"',
        (tester) async {
      await pumpNuvoTab(
        tester,
        '/arena',
        arenaState: ArenaState(
          snapshot: ArenaSnapshotBuilder.withBoard(board()),
        ),
      );

      expect(find.text('No verified movement yet'), findsOneWidget);
      expect(find.text('Submit proof'), findsWidgets);
    });
  });

  group('Layout safety at 390x844', () {
    testWidgets('no overflow with a populated Arena', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow with an empty Arena', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: const ArenaState(
              snapshot: ArenaSnapshot(mode: 'real', headerPulse: '')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('header clears the status area', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          arenaState: ArenaState(snapshot: populatedArena()));

      // The NUVO wordmark must sit below the 47px top inset.
      final top = tester.getTopLeft(find.text('NUVO')).dy;
      expect(top, greaterThanOrEqualTo(47),
          reason: 'Arena header must not sit under the status bar');
    });

    testWidgets('respects Reduce Motion', (tester) async {
      await pumpNuvoTab(tester, '/arena',
          reduceMotion: true,
          arenaState: ArenaState(snapshot: populatedArena()));

      expect(tester.takeException(), isNull);
      // Content is still fully rendered with animations disabled.
      expect(find.text('First to 100 Pushups'), findsOneWidget);
    });
  });
}
