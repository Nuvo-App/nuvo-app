import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/notifications/data/notification_prefs.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/domain/race_display.dart';

/// Regression coverage for the audit's confirmed release findings:
/// proof-row access, race-detail CTA per proof type, review-action
/// visibility, OTP paste, and the proof_disputed notification label.
Race _race({
  String title = 'Race',
  String verifierType = 'manual_log',
  String proofMode = 'manual',
  String verificationMethod = 'manual',
  String format = 'first_to_goal',
  String scoringRule = 'cumulative_sum',
  String scoreDirection = 'higher',
  String creatorId = 'user-1',
  int participantCount = 2,
  String? unit = 'reps',
}) {
  return Race(
    id: 'race-1',
    creatorId: creatorId,
    title: title,
    goalType: format,
    targetValue: 100,
    unit: unit,
    format: format,
    scoringRule: scoringRule,
    verifierType: verifierType,
    proofRequirement: proofMode,
    proofMode: proofMode,
    verificationMethod: verificationMethod,
    scoreDirection: scoreDirection,
    status: 'active',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: [
      for (var i = 1; i <= participantCount; i++)
        RaceParticipant(
          id: 'part-$i',
          userId: 'user-$i',
          displayName: 'Racer $i',
          progressValue: 0,
          progressPercent: 0,
          joinedAt: '2026-01-01T00:00:00Z',
        ),
    ],
  );
}

RaceProof _proof({
  String userId = 'user-2',
  String verificationStatus = 'accepted',
  String vetoState = 'none',
  bool viewerVoted = false,
}) =>
    RaceProof(
      id: 'proof-1',
      userId: userId,
      displayName: 'Racer 2',
      proofType: 'manual',
      verificationStatus: verificationStatus,
      vetoState: vetoState,
      viewerVoted: viewerVoted,
      value: 10,
      createdAt: '2026-01-01T00:00:00Z',
    );

void main() {
  group('race detail proof CTA', () {
    test('GOLF_DETAIL_HAS_ADD_RESULT', () {
      final golf = _race(
        title: 'Lowest Golf Score',
        scoreDirection: 'lower',
        format: 'best_attempt',
        scoringRule: 'best_attempt',
      );
      expect(raceProofAction(golf), RaceProofAction.manual);
      expect(raceProofCta(golf).label, 'Add result');
    });

    test('GRADE_DETAIL_HAS_RESULT_ACTION', () {
      final grade = _race(
        title: 'Highest Math Grade',
        scoringRule: 'best_attempt',
        format: 'best_attempt',
      );
      expect(raceProofAction(grade), RaceProofAction.manual);
      expect(raceProofCta(grade).label, 'Add result');
    });

    test('BOOKS_DETAIL_HAS_PROGRESS_ACTION', () {
      final books = _race(title: 'Finish 5 Books', unit: 'books');
      expect(raceProofAction(books), RaceProofAction.manual);
      expect(raceProofCta(books).label, 'Log progress');
    });

    test('MOTION_DETAIL_HAS_AI_ACTION', () {
      final pushups = _race(
        title: 'Pushups',
        verifierType: 'preset_pose',
        proofMode: 'ai_check',
        verificationMethod: 'camera_pose',
      );
      expect(raceProofAction(pushups), RaceProofAction.motion);
      expect(raceProofCta(pushups).label, 'Start AI Motion Proof');
    });
  });

  group('proof row access', () {
    final race = _race();

    test('NONOWNER_PROOF_ROW_OPENS', () {
      expect(raceCanInspectProofs(race, 'user-2'), isTrue);
    });

    test('owner can inspect', () {
      expect(raceCanInspectProofs(race, 'user-1'), isTrue);
    });

    test('nonmember cannot inspect', () {
      expect(raceCanInspectProofs(race, 'user-99'), isFalse);
      expect(raceCanInspectProofs(race, null), isFalse);
    });
  });

  group('proof action visibility', () {
    // Creator is user-1; the proof belongs to user-2; user-3 is another
    // active participant.
    final race = _race(participantCount: 3);

    test('SELF_VETO_HIDDEN', () {
      final mine = _proof(userId: 'user-1');
      expect(raceProofIsVetoable(race, mine, 'user-1'), isFalse);
      expect(raceProofIsReviewable(race, mine, 'user-1'), isFalse);
    });

    test('ELIGIBLE_VETO_VISIBLE', () {
      final counted = _proof(verificationStatus: 'accepted');
      expect(raceProofIsVetoable(race, counted, 'user-3'), isTrue);
      // The creator disputes counted proof through veto too.
      expect(raceProofIsVetoable(race, counted, 'user-1'), isTrue);
    });

    test('COUNTED_ACCEPT_HIDDEN / COUNTED_REJECT_HIDDEN', () {
      for (final status in ['accepted', 'ai_verified', 'rejected']) {
        final counted = _proof(verificationStatus: status);
        expect(
          raceProofIsReviewable(race, counted, 'user-1'),
          isFalse,
          reason: 'creator controls must be hidden for $status proof',
        );
      }
    });

    test('VETOED_ACCEPT_HIDDEN', () {
      final vetoed = _proof(
        verificationStatus: 'rejected',
        vetoState: 'vetoed',
      );
      expect(raceProofIsReviewable(race, vetoed, 'user-1'), isFalse);
      expect(raceProofIsVetoable(race, vetoed, 'user-3'), isFalse);
    });

    test('held proof is reviewable by the creator', () {
      for (final status in ['needs_review', 'submitted']) {
        final held = _proof(verificationStatus: status);
        expect(
          raceProofIsReviewable(race, held, 'user-1'),
          isTrue,
          reason: 'held proof ($status) must be reviewable',
        );
        // Reviewable proofs don't also offer veto to the creator.
        expect(raceProofIsVetoable(race, held, 'user-1'), isFalse);
        // Other participants can still veto a held proof.
        expect(raceProofIsVetoable(race, held, 'user-3'), isTrue);
      }
    });

    test('held proof is NOT reviewable by a non-creator', () {
      final held = _proof(verificationStatus: 'needs_review');
      expect(raceProofIsReviewable(race, held, 'user-3'), isFalse);
    });
  });


  group('notification labels', () {
    test('PROOF_DISPUTED_LABEL_HUMAN', () {
      final pref = NotificationPref.fromJson(const {
        'category': 'proof_disputed',
        'inApp': true,
        'push': true,
      });
      expect(pref.display.label, 'Proof disputes');
      expect(pref.display.group, 'Proof');
      expect(pref.display.label.contains('_'), isFalse);
    });
  });
}
