import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/rep_inactivity_watch.dart';

/// S6 gap 16 — 30 s without a counted rep during recording asks "Are you
/// still there?". Keep going resets the clock; Finish resolves to the same
/// end as Done. Holds and timed windows never arm the watch (the camera
/// screen gates those before arming), so the policy itself is tested here.
void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  group('S6 gap 16 — rep inactivity prompt', () {
    test('test_gap16_rep_inactivity_prompt_appears_after_30s', () {
      final watch = RepInactivityWatch();
      // Not armed — nothing can fire.
      expect(watch.isSilent(t0.add(const Duration(minutes: 5))), isFalse);

      watch.arm(t0);
      expect(watch.isSilent(t0.add(const Duration(seconds: 29))), isFalse);
      expect(watch.isSilent(t0.add(const Duration(seconds: 30))), isTrue);

      // Once it fires it stays fired until a rep lands — no prompt spam.
      watch.markPrompted();
      expect(watch.isSilent(t0.add(const Duration(seconds: 60))), isFalse);

      // A rep re-arms the clock for the next quiet stretch.
      watch.noteCounted(t0.add(const Duration(seconds: 70)));
      expect(watch.isSilent(t0.add(const Duration(seconds: 99))), isFalse);
      expect(watch.isSilent(t0.add(const Duration(seconds: 100))), isTrue);
    });

    test('test_gap16_keep_going_resets_inactivity_timer', () {
      final watch = RepInactivityWatch();
      watch.arm(t0);

      final promptAt = t0.add(const Duration(seconds: 30));
      expect(watch.isSilent(promptAt), isTrue);
      watch.markPrompted();

      // Keep going — the clock restarts from the answer, not from take
      // start and not from the last rep.
      final resolution = watch.resolve(
        RepInactivityChoice.keepGoing,
        promptAt,
      );
      expect(resolution, RepInactivityResolution.resume);
      expect(
        watch.isSilent(promptAt.add(const Duration(seconds: 29))),
        isFalse,
      );
      expect(
        watch.isSilent(promptAt.add(const Duration(seconds: 30))),
        isTrue,
      );

      // A rep landing mid-silence also resets — and a stale echo of the
      // same rep does not count twice.
      final watch2 = RepInactivityWatch();
      watch2.arm(t0);
      watch2.noteCounted(t0.add(const Duration(seconds: 10)));
      watch2.noteCounted(t0.add(const Duration(seconds: 10)));
      expect(
        watch2.isSilent(t0.add(const Duration(seconds: 40))),
        isTrue,
      );
      watch2.noteCounted(t0.add(const Duration(seconds: 41)));
      expect(
        watch2.isSilent(t0.add(const Duration(seconds: 70))),
        isFalse,
      );
      expect(
        watch2.isSilent(t0.add(const Duration(seconds: 71))),
        isTrue,
      );
    });

    test('test_gap16_finish_choice_ends_recording', () {
      final watch = RepInactivityWatch();
      watch.arm(t0);

      final promptAt = t0.add(const Duration(seconds: 30));
      expect(watch.isSilent(promptAt), isTrue);
      watch.markPrompted();

      // Finish resolves to the same end as Done — the take is over and
      // the watch is disarmed, so nothing can fire again.
      final resolution = watch.resolve(
        RepInactivityChoice.finish,
        promptAt,
      );
      expect(resolution, RepInactivityResolution.endTake);
      expect(
        watch.isSilent(promptAt.add(const Duration(minutes: 5))),
        isFalse,
      );

      // A dismissed prompt resolves as resume — never ends a take.
      final watch2 = RepInactivityWatch();
      watch2.arm(t0);
      expect(
        watch2.resolve(null, t0.add(const Duration(seconds: 30))),
        RepInactivityResolution.resume,
      );
    });
  });
}
