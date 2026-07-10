import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/animated_race_track.dart';

void main() {
  testWidgets('AnimatedRaceTrack renders race result state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedRaceTrack(
              totalGoal: 100,
              competitors: const [
                AnimatedRaceTrackCompetitor(
                  id: 'marcus',
                  name: 'Marcus',
                  initials: 'MJ',
                  progress: 0.72,
                  rank: 1,
                ),
                AnimatedRaceTrackCompetitor(
                  id: 'you',
                  name: 'Akshay',
                  initials: 'AK',
                  progress: 0.65,
                  rank: 2,
                  isCurrentUser: true,
                ),
                AnimatedRaceTrackCompetitor(
                  id: 'sam',
                  name: 'Sam',
                  initials: 'SR',
                  progress: 0.43,
                  rank: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(AnimatedRaceTrack), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('65 / 100'), findsOneWidget);
    expect(find.text('Marcus'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}
