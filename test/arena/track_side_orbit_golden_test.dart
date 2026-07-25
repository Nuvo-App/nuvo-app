import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/track_side_orbit.dart';

void main() {
  testWidgets('TrackSideOrbit renders the canonical fixture', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    const participants = [
      TrackSideOrbitParticipant(
        id: 'me',
        name: 'You',
        initials: 'YO',
        rank: 1,
        progressValue: 65,
        isCurrentUser: true,
      ),
      TrackSideOrbitParticipant(
        id: 'alex',
        name: 'Alex R.',
        initials: 'AR',
        rank: 2,
        progressValue: 48,
      ),
      TrackSideOrbitParticipant(
        id: 'maya',
        name: 'Maya L.',
        initials: 'ML',
        rank: 3,
        progressValue: 31,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            devicePixelRatio: 1.0,
            disableAnimations: true,
          ),
          child: SizedBox(
            width: 390,
            height: 844,
            child: ColoredBox(
              color: Color(0xFF071B35),
              child: Stack(
                children: [
                  Positioned(
                    left: 22,
                    top: 176,
                    child: TrackSideOrbit(
                      scale: 1.0,
                      totalGoal: 100,
                      currentUserValue: 65,
                      currentUserRank: 1,
                      participants: participants,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TrackSideOrbit),
      matchesGoldenFile('goldens/track_side_orbit.png'),
    );
  });
}
