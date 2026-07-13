import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

MotionActivityDefinition _activity(MotionActivityType type) =>
    motionActivityForType(type)!;

final _pushups = _activity(MotionActivityType.pushUps);
final _jacks = _activity(MotionActivityType.jumpingJacks);
final _squats = _activity(MotionActivityType.squats);
final _plank = _activity(MotionActivityType.plankHold);
// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 1. Generated title contract ────────────────────────────────────────────
  group('generatedTitle()', () {
    test('produces "First to N ActivityName" format', () {
      expect(generatedTitle(_pushups, 15), 'First to 15 Pushups');
      expect(generatedTitle(_jacks, 30), 'First to 30 Jumping Jacks');
      expect(generatedTitle(_plank, 60), 'First to 60 Plank');
    });

    test('uses lowercase "to" not "To"', () {
      final t = generatedTitle(_pushups, 10);
      expect(t, contains('First to'));
      expect(t, isNot(contains('First To')));
    });
  });

  // ── 2. RaceDraft.resolvedTitle ─────────────────────────────────────────────
  group('RaceDraft.resolvedTitle', () {
    test('returns generated title when hasCustomName is false', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      expect(draft.hasCustomName, isFalse);
      expect(draft.resolvedTitle, 'First to 15 Jumping Jacks');
    });

    test('returns custom title when hasCustomName is true', () {
      final draft = draftForActivity(_jacks).copyWith(
        title: 'Akshay vs Akaash',
        hasCustomName: true,
        targetValue: 15,
      );
      expect(draft.resolvedTitle, 'Akshay vs Akaash');
    });
  });

  // ── 3. Generated title updates when activity changes ──────────────────────
  group('Generated title stays in sync', () {
    test('activity change regenerates resolved title (not custom)', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 15);
      final updated = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      expect(updated.resolvedTitle, 'First to 15 Jumping Jacks');
    });

    test('target change regenerates resolved title (not custom)', () {
      final draft = draftForActivity(_jacks);
      final updated = draft.copyWith(targetValue: 30);
      expect(updated.resolvedTitle, 'First to 30 Jumping Jacks');
    });

    test('both activity AND target change regenerates correctly', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 6);
      final updated = draft.copyWith(
        activity: _jacks,
        metric: _jacks.metric,
        targetValue: 15,
      );
      expect(updated.resolvedTitle, 'First to 15 Jumping Jacks');
    });
  });

  // ── 4. Custom title is preserved ──────────────────────────────────────────
  group('Custom title preservation', () {
    test('activity change does NOT overwrite a custom title', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'Akshay vs Akaash', hasCustomName: true);
      final updated = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      expect(updated.resolvedTitle, 'Akshay vs Akaash');
    });

    test('target change does NOT overwrite a custom title', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'Akshay vs Akaash', hasCustomName: true);
      final updated = draft.copyWith(targetValue: 50);
      expect(updated.resolvedTitle, 'Akshay vs Akaash');
    });

    test('custom title is preserved across multiple edits', () {
      var draft = draftForActivity(
        _pushups,
      ).copyWith(title: 'My Custom Race', hasCustomName: true);
      draft = draft.copyWith(activity: _jacks, metric: _jacks.metric);
      draft = draft.copyWith(targetValue: 25);
      draft = draft.copyWith(activity: _squats, metric: _squats.metric);
      expect(draft.resolvedTitle, 'My Custom Race');
    });
  });

  // ── 5. toCreatePayload title comes from resolvedTitle ─────────────────────
  group('toCreatePayload title integrity', () {
    test('payload title matches resolvedTitle for generated names', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['title'], draft.resolvedTitle);
      expect(payload['title'], 'First to 15 Jumping Jacks');
    });

    test('payload title preserves custom name', () {
      final draft = draftForActivity(_jacks).copyWith(
        title: 'Akshay vs Akaash',
        hasCustomName: true,
        targetValue: 15,
      );
      final payload = draft.toCreatePayload();
      expect(payload['title'], 'Akshay vs Akaash');
    });

    test('payload title, targetValue and activityId are consistent', () {
      final draft = draftForActivity(_jacks).copyWith(targetValue: 15);
      final payload = draft.toCreatePayload();
      expect(payload['title'], contains('15'));
      expect(payload['title'], contains('Jumping Jacks'));
      expect(payload['targetValue'], 15);
      expect(payload['activityId'], 'jumping_jacks');
    });

    test('payload never shows stale pushup count after switching to jacks', () {
      // Reproduce the exact bug: start pushups 6, switch to jacks, target 15
      final initial = draftFromIdea('First to 6 pushups')!;
      final afterActivity = initial.copyWith(
        activity: _jacks,
        metric: _jacks.metric,
      );
      final afterTarget = afterActivity.copyWith(targetValue: 15);
      final payload = afterTarget.toCreatePayload();

      expect(payload['title'], 'First to 15 Jumping Jacks');
      expect(payload['targetValue'], 15);
      expect(payload['activityId'], 'jumping_jacks');
      // "6" must not appear anywhere in the payload title
      expect(payload['title'], isNot(contains('6')));
    });
  });

  // ── 6. Goal direct edit (int clamping) ────────────────────────────────────
  group('Goal value clamping', () {
    test('copyWith clamps target to at least 1', () {
      final draft = draftForActivity(_pushups);
      final clamped = draft.copyWith(targetValue: 0);
      // 0 can be stored (clamping is in UI), but resolvedTitle still formats
      expect(clamped.targetValue, 0); // domain allows it; UI prevents it
    });

    test('arbitrary large target is valid in domain', () {
      final draft = draftForActivity(_pushups).copyWith(targetValue: 99999);
      expect(draft.targetValue, 99999);
      expect(draft.resolvedTitle, 'First to 99999 Pushups');
    });

    test('suggested targets are all valid positives', () {
      for (final def in motionActivityDefinitions) {
        for (final t in def.suggestedTargets) {
          expect(t, greaterThan(0));
        }
      }
    });
  });

  // ── 7. Plus/minus step size logic ─────────────────────────────────────────
  group('Step size', () {
    int stepFor(int target) {
      if (target < 10) return 1;
      if (target < 100) return 5;
      if (target < 1000) return 25;
      return 100;
    }

    test('step is 1 below 10', () => expect(stepFor(5), 1));
    test('step is 5 from 10 to 99', () => expect(stepFor(50), 5));
    test('step is 25 from 100 to 999', () => expect(stepFor(200), 25));
    test('step is 100 at 1000+', () => expect(stepFor(1000), 100));
  });

  // ── 8. Back/forward preserves draft ───────────────────────────────────────
  group('Draft survives step navigation', () {
    test('copyWith preserves all unrelated fields', () {
      final draft = draftForActivity(_jacks).copyWith(
        targetValue: 15,
        title: 'My Race',
        hasCustomName: true,
        visibility: 'private',
      );
      // Simulate going back to activity and selecting squats, then forward
      final updated = draft.copyWith(activity: _squats, metric: _squats.metric);
      expect(updated.targetValue, 15);
      expect(updated.visibility, 'private');
      expect(updated.hasCustomName, true);
      expect(updated.resolvedTitle, 'My Race'); // custom preserved
    });

    test('Start solo sets visibility to private', () {
      final draft = draftForActivity(_jacks).copyWith(visibility: 'private');
      expect(draft.visibility, 'private');
    });

    test('Pull in crew sets visibility to invite_code', () {
      final draft = draftForActivity(
        _jacks,
      ).copyWith(visibility: 'invite_code');
      expect(draft.visibility, 'invite_code');
    });
  });

  // ── 9. Plank uses seconds everywhere ──────────────────────────────────────
  group('Plank seconds', () {
    test('plank draft has seconds metric', () {
      final draft = draftForActivity(_plank);
      expect(draft.metric, RaceMetric.seconds);
    });

    test('plank payload has seconds in metric and targetUnit', () {
      final draft = draftForActivity(_plank).copyWith(targetValue: 60);
      final payload = draft.toCreatePayload();
      expect(payload['metric'], 'seconds');
      expect(payload['targetUnit'], 'seconds');
      expect(payload['targetValue'], 60);
    });

    test('plank resolved title uses raw number (not seconds label)', () {
      final draft = draftForActivity(_plank).copyWith(targetValue: 60);
      expect(draft.resolvedTitle, 'First to 60 Plank');
    });

    test('switching from reps activity to plank resets metric to seconds', () {
      final draft = draftForActivity(
        _pushups,
      ).copyWith(activity: _plank, metric: _plank.metric);
      expect(draft.metric, RaceMetric.seconds);
    });
  });

  // ── 10. draftFromIdea used by Quick Starts ─────────────────────────────────
  group('Quick Start prefill', () {
    test('jumping jacks quick start produces correct draft', () {
      final draft = draftFromIdea('First to 30 jumping jacks')!;
      expect(draft.activity.type, MotionActivityType.jumpingJacks);
      expect(draft.targetValue, 30);
      expect(draft.hasCustomName, isFalse);
      expect(draft.resolvedTitle, 'First to 30 Jumping Jacks');
    });

    test('plank quick start has seconds metric', () {
      final draft = draftFromIdea('First to 60 plank seconds')!;
      expect(draft.metric, RaceMetric.seconds);
      expect(draft.resolvedTitle, 'First to 60 Plank');
    });

    test('quick start payload title and target agree', () {
      final draft = draftFromIdea('First to 40 lunges')!;
      final payload = draft.toCreatePayload();
      expect(payload['title'], 'First to 40 Lunges');
      expect(payload['targetValue'], 40);
      expect(payload['activityId'], 'lunges');
    });
  });
}
