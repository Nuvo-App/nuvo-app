import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/demo/presentation_demo.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

void main() {
  const user = AuthUser(
    id: 'presentation-user',
    email: presentationDemoEmail,
    fullName: 'Real Account Name',
    username: 'real-account',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  );

  test(
    'presentation account keeps auth identity but uses filler display data '
    'once the toggle is on',
    () async {
      // presentationDemoEmail is a real account now — presentation mode is
      // opt-in (Profile settings), off by default, so the toggle must be
      // explicitly enabled for this account to see fixture data.
      addTearDown(() => setPresentationModeEnabled(false));
      expect(isPresentationDemoUser(user), isFalse);
      await setPresentationModeEnabled(true);
      expect(isPresentationDemoUser(user), isTrue);
      final displayed = presentedUser(user);
      expect(displayed.id, user.id);
      expect(displayed.email, user.email);
      expect(displayed.fullName, 'Maya Chen');
      expect(displayed.username, 'maya');
    },
  );

  test(
    'the dedicated store-testing identity is always presentation mode, no '
    'toggle needed',
    () {
      const reviewer = AuthUser(
        id: 'reviewer-user',
        email: 'testing@getnuvo.net',
        fullName: 'Reviewer',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      );
      expect(isPresentationDemoUser(reviewer), isTrue);
    },
  );

  test('Arena and Compete fixtures share one six-race presentation set', () {
    final races = PresentationDemoData.races(user.id);
    final snapshot = PresentationDemoData.arenaSnapshot(user.id);
    final boardIds = [
      snapshot.focusBoard?.id,
      ...snapshot.liveBoards.map((board) => board.id),
    ];
    final boards = [
      if (snapshot.focusBoard != null) snapshot.focusBoard!,
      ...snapshot.liveBoards,
    ];

    expect(races, hasLength(8));
    expect(races.where(raceIsActive), hasLength(4));
    expect(races.where(raceIsCompleted), hasLength(3));
    expect(boardIds, containsAll(races.take(4).map((race) => race.id)));
    expect(races.every((race) => race.participantFor(user.id) != null), isTrue);
    // Full leaderboards everywhere except the one deliberate 1v1 battle
    // (burpees vs Jules — head-to-head reads cleaner in Recent results).
    expect(
      races.where((race) => race.participants.length < 8),
      hasLength(1),
    );
    expect(
      races.every(
        (race) => race.participants.every(
          (participant) => participant.profilePhotoUrl?.isNotEmpty == true,
        ),
      ),
      isTrue,
    );
    expect(
      boards
          .expand((board) => board.miniLeaderboard)
          .every((row) => row.profilePhotoUrl?.isNotEmpty == true),
      isTrue,
    );
  });

  test(
    'only presentation-created race IDs are eligible for local TTL cleanup',
    () {
      expect(
        isPresentationDemoCreatedRace(
          '${presentationDemoCreatedRacePrefix}123',
        ),
        isTrue,
      );
      expect(
        isPresentationDemoCreatedRace('${presentationDemoRacePrefix}pushups'),
        isFalse,
      );
      expect(isPresentationDemoCreatedRace('server-race-123'), isFalse);
    },
  );

  test('presentation race creation does not call the race API', () async {
    final controller = RaceController(
      RaceRepository(RaceApi(), SecureTokenStore(), AuthApi()),
      isPresentationDemo: () => true,
      presentationUserId: () => user.id,
    );
    await controller.loadRaces();
    final created = await controller.createRace(
      title: 'First To 20 Pushups',
      targetValue: 20,
      activityId: 'pushups',
      unit: 'reps',
    );

    expect(isPresentationDemoCreatedRace(created.id), isTrue);
    expect(controller.state.races, hasLength(9));
    controller.clearRaces();
  });

  test(
    'presentation-created race stays local through detail and proof',
    () async {
      final controller = RaceController(
        RaceRepository(RaceApi(), SecureTokenStore(), AuthApi()),
        isPresentationDemo: () => true,
        presentationUserId: () => user.id,
      );
      await controller.loadRaces();
      final created = await controller.createRace(
        title: 'First To 20 Pushups',
        targetValue: 20,
        activityId: 'pushups',
        unit: 'reps',
      );

      final loaded = await controller.getRaceDetail(created.id);
      final updated = await controller.submitAiMotionProof(
        created.id,
        result: const AiMotionResult(
          activity: AiMotionActivity.pushUps,
          targetReps: 20,
          detectedReps: 6,
          confidence: 0.82,
          verificationStatus: 'ai_verified',
          verificationSummary: 'Detected 6 push-ups from live pose tracking.',
          framesAnalyzed: 40,
          validPoseFrames: 36,
          durationMs: 4000,
          validatorVersion: 'nuvo-ai-motion-v2',
        ),
        clientSubmissionId: 'presentation-demo-proof-1',
        metric: 'reps',
      );

      expect(loaded.id, created.id);
      expect(updated.participantFor(user.id)?.progressValue, 6);
      expect(updated.recentProofs, hasLength(1));
      expect(updated.recentProofs.first.verificationStatus, 'ai_verified');
      controller.clearRaces();
    },
  );
}
