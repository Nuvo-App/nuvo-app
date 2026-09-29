import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';

/// Tests for the Nuvo canonical race component system.
///
/// Tests structure and behavior, not pixel-perfect rendering.
void main() {
  group('RacePlacement', () {
    testWidgets('renders rank number with prefix', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RacePlacement(rank: 4, size: 16)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('#4'), findsOneWidget);
    });

    testWidgets('null rank renders nothing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RacePlacement(rank: null, size: 16)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('1st place renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RacePlacement(rank: 1, size: 16)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('#1'), findsOneWidget);
    });
  });

  group('RacePeople', () {
    testWidgets('shows filled avatars and overflow count', (tester) async {
      final avatars = [
        for (var i = 0; i < 5; i++)
          (initials: 'AB$i', photoUrl: null, id: 'user-$i'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacePeople(avatars: avatars, total: 5, size: 28, max: 4),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // With 5 total and max 4, should show 3 avatars + "+2" overflow.
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('shows empty crew slots when waiting', (tester) async {
      final avatars = [(initials: 'AB', photoUrl: null, id: 'user-1')];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacePeople(
              avatars: avatars,
              total: 1,
              emptySlots: 3,
              size: 28,
              max: 4,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Should show 1 filled avatar + 3 empty slots (add icons).
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(3));
    });

    testWidgets('empty avatars list with empty slots shows only slots', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RacePeople(
              avatars: [],
              total: 0,
              emptySlots: 2,
              size: 28,
              max: 4,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
    });
  });

  group('RaceProgressLabel', () {
    testWidgets('renders progress label and target', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RaceProgressLabel(
              progressLabel: '20 / 50 reps',
              targetLabel: '50 reps',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('20'), findsOneWidget);
      expect(find.textContaining('50 reps'), findsWidgets);
    });

    testWidgets('does not overflow with long labels at 280px width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: RaceProgressLabel(
                  progressLabel: '20 / 100 reps',
                  targetLabel: '100 reps',
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RaceWaitingSummary', () {
    testWidgets('shows race count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceWaitingSummary(
              raceCount: 3,
              totalWaitingSlots: 3,
              avatars: const [],
              expanded: false,
              onToggle: () {},
              children: const [],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Waiting for crew'), findsOneWidget);
      expect(find.textContaining('3 races'), findsOneWidget);
    });

    testWidgets('expands to show children', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceWaitingSummary(
              raceCount: 2,
              totalWaitingSlots: 2,
              avatars: const [],
              expanded: true,
              onToggle: () {},
              children: const [Text('Expanded child race row')],
            ),
          ),
        ),
      );
      expect(find.text('Expanded child race row'), findsOneWidget);
    });

    testWidgets('collapsed does not show children', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceWaitingSummary(
              raceCount: 2,
              totalWaitingSlots: 2,
              avatars: const [],
              expanded: false,
              onToggle: () {},
              children: const [Text('Expanded child race row')],
            ),
          ),
        ),
      );
      expect(find.text('Expanded child race row'), findsNothing);
    });
  });

  group('RaceFinishedSummary', () {
    testWidgets('shows race count and win count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceFinishedSummary(
              raceCount: 5,
              wonCount: 2,
              expanded: false,
              onToggle: () {},
              children: const [],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('5 races'), findsOneWidget);
      expect(find.textContaining('2 wins'), findsOneWidget);
    });
  });

  group('RaceQuickStart', () {
    testWidgets('shows movement name and target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceQuickStart(
              icon: Icons.fitness_center_rounded,
              movementName: 'Pushups',
              target: '100 reps',
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Pushups'), findsOneWidget);
      expect(find.text('100 reps'), findsOneWidget);
    });

    testWidgets('tap calls onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceQuickStart(
              icon: Icons.fitness_center_rounded,
              movementName: 'Pushups',
              target: '100 reps',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(RaceQuickStart));
      expect(tapped, isTrue);
    });
  });

  group('RaceRow', () {
    testWidgets('shows title, movement, and progress label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceRow(
              raceTitle: 'Pushup Race',
              movementLabel: 'Pushups',
              progressLabel: '45 / 100 reps',
              progressPercent: 45,
              rank: 1,
              participantCount: 3,
              avatars: const [
                (initials: 'AB', photoUrl: null, id: 'u2'),
                (initials: 'CD', photoUrl: null, id: 'u3'),
              ],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Pushup Race'), findsOneWidget);
      expect(find.textContaining('Pushups'), findsOneWidget);
      expect(find.textContaining('45'), findsOneWidget);
    });

    testWidgets('long title does not overflow at 280px', (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceRow(
              raceTitle: 'Very Long Pushup Race Title That Should Truncate',
              movementLabel: 'Pushups',
              progressLabel: '20 / 100 reps',
              progressPercent: 20,
              rank: 1,
              participantCount: 2,
              avatars: const [(initials: 'AB', photoUrl: null, id: 'u2')],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RaceResultRow', () {
    testWidgets('shows placement label, not progress percent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceResultRow(
              raceTitle: 'Pushup Race',
              movementLabel: 'Pushups',
              rank: 2,
              participantCount: 3,
              avatars: const [
                (initials: 'AB', photoUrl: null, id: 'u2'),
                (initials: 'CD', photoUrl: null, id: 'u3'),
              ],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Should show "2nd" placement, NOT a "%" progress.
      expect(find.text('2nd'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('1st place shows 1st', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceResultRow(
              raceTitle: 'Pushup Race',
              movementLabel: 'Pushups',
              rank: 1,
              participantCount: 3,
              avatars: const [],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1st'), findsOneWidget);
    });
  });

  group('RaceHero', () {
    testWidgets('shows activity, title, progress, and action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceHero(
              activityLabel: 'Pushups',
              targetLabel: '100 reps',
              raceTitle: 'Morning Pushup Race',
              progressPercent: 40,
              progressLabel: '40 / 100 reps',
              racerStack: const SizedBox(width: 28, height: 28),
              rank: 2,
              onOpen: () {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Pushups'), findsOneWidget);
      expect(find.text('Morning Pushup Race'), findsOneWidget);
      expect(find.text('2nd'), findsOneWidget);
      expect(find.text('View leaderboard'), findsOneWidget);
    });

    testWidgets('does not overflow at 375px width', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: RaceHero(
                activityLabel: 'Pushups',
                targetLabel: '100 reps',
                raceTitle: 'Morning Pushup Race With A Long Title',
                progressPercent: 40,
                progressLabel: '40 / 100 reps',
                racerStack: const SizedBox(width: 28, height: 28),
                rank: 2,
                onOpen: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Structural differentiation', () {
    testWidgets('RaceRow and RaceResultRow are structurally different', (
      tester,
    ) async {
      // Active race row: shows progress
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceRow(
              raceTitle: 'Active Race',
              movementLabel: 'Pushups',
              progressLabel: '50 / 100 reps',
              progressPercent: 50,
              rank: 1,
              participantCount: 2,
              avatars: const [],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('50'), findsOneWidget);

      // Finished race row: shows placement, NOT progress
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RaceResultRow(
              raceTitle: 'Finished Race',
              movementLabel: 'Pushups',
              rank: 1,
              participantCount: 2,
              avatars: const [],
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('1st'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  group('raceOrdinal', () {
    test('spells every rank surface identically', () {
      expect(raceOrdinal(1), '1st');
      expect(raceOrdinal(2), '2nd');
      expect(raceOrdinal(3), '3rd');
      expect(raceOrdinal(4), '4th');
      expect(raceOrdinal(8), '8th');
      expect(raceOrdinal(11), '11th');
      expect(raceOrdinal(12), '12th');
      expect(raceOrdinal(13), '13th');
      expect(raceOrdinal(21), '21st');
      expect(raceOrdinal(999), '999th');
    });
  });

  group('raceLaneGeometry', () {
    RaceParticipant racer(String id, String name, int value,
        {String joined = '2026-01-01T00:00:00Z'}) {
      return RaceParticipant(
        id: 'p-$id',
        userId: id,
        displayName: name,
        progressValue: value,
        progressPercent: value,
        joinedAt: joined,
      );
    }

    Race race({
      int? target,
      String direction = 'higher',
      List<RaceParticipant> participants = const [],
      String unit = 'reps',
    }) {
      return Race(
        id: 'r1',
        creatorId: 'me',
        title: 'Race',
        goalType: target == null ? 'best_attempt' : 'first_to_goal',
        targetValue: target,
        unit: unit,
        status: 'active',
        scoreDirection: direction,
        participants: participants,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      );
    }

    test('goal lane: marks are shares of the finish target', () {
      final geo = raceLaneGeometry(
        race(
          target: 100,
          participants: [racer('me', 'Me', 39), racer('noah', 'Noah', 42)],
        ),
        'me',
      );
      expect(geo.hasGoal, isTrue);
      expect(geo.viewer, closeTo(0.39, 0.001));
      expect(geo.rivals.single.fraction, closeTo(0.42, 0.001));
    });

    test('lower-wins golf: no goal ring, best score sits right', () {
      final geo = raceLaneGeometry(
        race(
          direction: 'lower',
          unit: 'strokes',
          participants: [
            racer('me', 'Me', 78),
            racer('noah', 'Noah', 75),
          ],
        ),
        'me',
      );
      expect(geo.hasGoal, isFalse);
      // Noah's 75 is the best score → right edge; my 78 → left edge.
      expect(geo.rivals.single.fraction, 1.0);
      expect(geo.viewer, 0.0);
    });

    test('best-attempt: no goal ring, relative spread', () {
      final geo = raceLaneGeometry(
        race(
          participants: [racer('me', 'Me', 94), racer('max', 'Max', 88)],
        ),
        'me',
      );
      expect(geo.hasGoal, isFalse);
      expect(geo.viewer, 1.0); // best of the field → right edge
      expect(geo.rivals.single.fraction, 0.0);
    });

    test('solo board: viewer only, no rivals', () {
      final geo = raceLaneGeometry(
        race(target: 50, participants: [racer('me', 'Me', 39)]),
        'me',
      );
      expect(geo.viewer, closeTo(0.78, 0.001));
      expect(geo.rivals, isEmpty);
    });
  });

  group('raceNearestRival', () {
    RaceParticipant racer(String id, int value) => RaceParticipant(
          id: 'p-$id',
          userId: id,
          displayName: id,
          progressValue: value,
          progressPercent: value,
          joinedAt: '2026-01-01T00:00:00Z',
        );

    Race race(List<RaceParticipant> participants) => Race(
          id: 'r1',
          creatorId: 'me',
          title: 'Race',
          goalType: 'first_to_goal',
          targetValue: 100,
          unit: 'reps',
          status: 'active',
          participants: participants,
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
        );

    test('chasing: returns the racer directly ahead, not the leader', () {
      // Ordered: leader 60, ahead 42, me 39 — the pass target is 42.
      final r = race([
        racer('leader', 60),
        racer('ahead', 42),
        racer('me', 39),
      ]);
      expect(raceNearestRival(r, 'me')?.userId, 'ahead');
    });

    test('leading: returns the closest chaser', () {
      final r = race([
        racer('me', 60),
        racer('chaser', 55),
        racer('last', 10),
      ]);
      expect(raceNearestRival(r, 'me')?.userId, 'chaser');
    });

    test('solo: no rival mark', () {
      final r = race([racer('me', 39)]);
      expect(raceNearestRival(r, 'me'), isNull);
    });
  });

  group('RaceRow quick view', () {
    Widget row({
      List<RaceTrackMarker>? markers,
      bool hasGoal = true,
      String? contextNote,
      int progress = 39,
      int? rank = 3,
      int racers = 8,
      String? remaining,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: RaceRow(
            raceTitle: 'Pushup Battle',
            movementLabel: 'Pushups',
            progressLabel: '$progress / 50 reps',
            progressPercent: progress,
            rank: rank,
            participantCount: racers,
            avatars: const [],
            trackMarkers: markers,
            hasGoal: hasGoal,
            contextNote: contextNote,
            remainingLabel: remaining,
            onTap: () {},
          ),
        ),
      );
    }

    testWidgets('marker lane replaces the plain bar when rivals exist', (
      tester,
    ) async {
      await tester.pumpWidget(row(markers: const [
        RaceTrackMarker(
            label: 'You',
            fraction: 0.78,
            color: Color(0xFF2E63E7),
            isViewer: true,
          ),
          RaceTrackMarker(
            label: 'Noah',
            fraction: 0.84,
            color: Color(0xFF1B2A4A),
          ),
      ]));
      expect(tester.takeException(), isNull);
      expect(find.byType(RaceMarkerTrack), findsOneWidget);
      expect(find.byType(RaceProgress), findsNothing);
    });

    testWidgets('no markers falls back to the progress bar', (tester) async {
      await tester.pumpWidget(row());
      expect(tester.takeException(), isNull);
      expect(find.byType(RaceProgress), findsOneWidget);
      expect(find.byType(RaceMarkerTrack), findsNothing);
    });

    testWidgets('compact lane carries no marker labels', (tester) async {
      await tester.pumpWidget(row(markers: const [
        RaceTrackMarker(
            label: 'You',
            fraction: 0.78,
            color: Color(0xFF2E63E7),
            isViewer: true,
          ),
          RaceTrackMarker(
            label: 'Noah',
            fraction: 0.84,
            color: Color(0xFF1B2A4A),
          ),
      ]));
      expect(find.text('You'), findsNothing);
      expect(find.text('Noah'), findsNothing);
    });

    testWidgets('start-line state shows no progress and no rank', (
      tester,
    ) async {
      await tester.pumpWidget(row(progress: 0, rank: null, racers: 8));
      expect(find.text('Start line'), findsOneWidget);
      expect(find.byType(RaceProgress), findsNothing);
      expect(find.byType(RaceMarkerTrack), findsNothing);
      expect(find.textContaining('8 racers'), findsOneWidget);
    });

    testWidgets('chase context replaces the meta line', (tester) async {
      await tester.pumpWidget(row(
        contextNote: '1 rep to pass Noah',
        remaining: '11 reps left',
      ));
      expect(find.text('1 rep to pass Noah'), findsOneWidget);
      expect(find.textContaining('11 reps left'), findsNothing);
    });

    testWidgets('long title clamps to two lines at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RaceRow(
            raceTitle:
                'First To Complete 1000 Jumping Jacks Before Friday Night',
            movementLabel: 'Alternating Reverse Walking Lunges',
            progressLabel: '999 / 1000 reps',
            progressPercent: 99,
            rank: 999,
            participantCount: 20,
            avatars: const [],
            onTap: () {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('#999'), findsOneWidget);
    });
  });
}
