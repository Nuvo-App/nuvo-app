// FlexiRace → create payload proof-contract corpus.
//
// Launch invariant: NUVO IS A PROOF-BASED COMPETITION PRODUCT. If the camera
// cannot automatically verify the activity, photo evidence is required — the
// create payload must therefore carry proofRequirement 'photo_video' (server
// persists verification_type 'photo'). Camera-verifiable activities keep
// 'ai_check'. Unknown/ambiguous/GPS-intended activities NEVER fake
// verification and NEVER default to Pushups — they become photo races.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';

void main() {
  String? proofRequirementFor(String prompt) {
    final draft = draftFromIdea(prompt);
    expect(draft, isNotNull, reason: 'no draft for "$prompt"');
    return draft!.toCreatePayload()['proofRequirement'] as String?;
  }

  group('automated — AI Motion Proof stays camera-verified', () {
    for (final prompt in [
      'First to 100 pushups',
      'First to 50 squats',
      'Most jumping jacks in 60 seconds',
    ]) {
      test(prompt, () {
        expect(proofRequirementFor(prompt), 'ai_check');
      });
    }
  });

  group('non-automated — entered result + required photo', () {
    for (final prompt in [
      // Non-automated result
      'Highest math grade',
      'Lowest golf score',
      'Highest bench press',
      // Cumulative progress
      'First to read 5 books',
      'Most steps this week',
      // Generic numeric / unknown / ambiguous
      'First to 100 points',
      'Best banana bread recipe',
      'Competitive underwater basket weaving',
      // Timed result without an authoritative verifier
      'Fastest mile wins',
      'Fastest 5k',
      'Who can run 10k fastest',
      // Distance + GPS-intended — camera cannot verify a route
      'First to run 20 miles this week',
      'Most miles run by Sunday',
    ]) {
      test(prompt, () {
        expect(proofRequirementFor(prompt), 'photo_video');
      });
    }
  });

  group('mandatory failures — these interpretations must never ship', () {
    test('grade is never AI Motion Proof', () {
      expect(proofRequirementFor('Highest math grade'), isNot('ai_check'));
    });

    test('golf is never camera reps', () {
      final draft = draftFromIdea('Lowest golf score')!;
      expect(draft.isManual, isTrue);
      expect(draft.toCreatePayload()['aiActivityType'], isNull);
    });

    test('unknown activity never defaults to pushups', () {
      final draft = draftFromIdea('Competitive underwater basket weaving')!;
      expect(draft.isManual, isTrue);
      expect(draft.activity.activityId, isNot('pushups'));
      expect(draft.toCreatePayload()['aiActivityType'], isNull);
    });

    test('distance never fakes working GPS', () {
      final draft = draftFromIdea('Fastest mile wins')!;
      expect(draft.isManual, isTrue);
      // No camera verifier is claimed — the payload carries no automated
      // verification fields at all.
      expect(draft.toCreatePayload()['aiActivityType'], isNull);
      expect(draft.toCreatePayload()['proofRequirement'], 'photo_video');
    });

    test('generic result is never evidence-free manual', () {
      expect(proofRequirementFor('First to 100 points'), isNot('manual'));
      expect(proofRequirementFor('First to 100 points'), 'photo_video');
    });
  });

  group('scoring direction survives the proof contract', () {
    test('lowest golf score stays lower-wins', () {
      final draft = draftFromIdea('Lowest golf score')!;
      expect(draft.scoreDirection, 'lower');
      expect(draft.toCreatePayload()['scoreDirection'], 'lower');
    });
  });
}
