import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/rep_burst_controller.dart';

/// Tests the burst/streak bookkeeping WITHOUT a camera, a widget tree, or
/// real wall-clock time — reps are injected at exact synthetic timestamps.
/// This is presentation bookkeeping only: it never decides whether a rep
/// counts, so these tests assert the burst math is correct in isolation
/// from recognition.
void main() {
  group('RepBurstController', () {
    test('reps at 0ms, 300ms, 600ms (within window) -> count 3, burst +3',
        () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);

      final e1 = c.update(1, now: t0);
      final e2 = c.update(2, now: t0.add(const Duration(milliseconds: 300)));
      final e3 = c.update(3, now: t0.add(const Duration(milliseconds: 600)));

      expect(e1!.streakCount, 1);
      expect(e2!.streakCount, 2);
      expect(e3!.streakCount, 3);
      expect(e3.totalCount, 3);
      expect(e3.isOnStreak, isTrue);
      expect(c.streakCount, 3);
    });

    test('a rep after the burst window resets the burst to +1, total unaffected',
        () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);

      c.update(1, now: t0);
      c.update(2, now: t0.add(const Duration(milliseconds: 300)));
      c.update(3, now: t0.add(const Duration(milliseconds: 600)));
      expect(c.streakCount, 3);

      // Well beyond the 1400ms default window.
      final e4 =
          c.update(4, now: t0.add(const Duration(milliseconds: 2500)));
      expect(e4!.totalCount, 4);
      expect(e4.streakCount, 1);
      expect(e4.isOnStreak, isFalse);
    });

    test('sequence increments once per registered rep (for keyed animation)',
        () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      c.update(2, now: t0.add(const Duration(milliseconds: 100)));
      c.update(3, now: t0.add(const Duration(milliseconds: 200)));
      expect(c.sequence, 3);
    });

    test('no count change -> no event, no state change', () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      final e = c.update(1, now: t0.add(const Duration(milliseconds: 50)));
      expect(e, isNull);
      expect(c.streakCount, 1);
      expect(c.sequence, 1);
    });

    test('a count jump of more than 1 between observations is not lost', () {
      // e.g. two frame-processing passes coalesced and the validator's
      // count advanced by 2 between the two times the UI observed it.
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      final e =
          c.update(4, now: t0.add(const Duration(milliseconds: 100)));
      expect(e!.delta, 3);
      expect(e.streakCount, 4); // 1 (existing streak) + delta 3
      expect(e.totalCount, 4);
    });

    test('a count decrease (new attempt) resets streak state', () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      c.update(2, now: t0.add(const Duration(milliseconds: 100)));
      final reset = c.update(0, now: t0.add(const Duration(milliseconds: 200)));
      expect(reset, isNull);
      expect(c.streakCount, 0);
      final e = c.update(1, now: t0.add(const Duration(milliseconds: 300)));
      expect(e!.streakCount, 1);
    });

    test('explicit reset() clears streak, sequence, and last-seen count', () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      c.update(2, now: t0.add(const Duration(milliseconds: 100)));
      c.reset();
      expect(c.streakCount, 0);
      expect(c.sequence, 0);
      final e = c.update(1, now: t0.add(const Duration(milliseconds: 200)));
      expect(e!.streakCount, 1);
      expect(e.totalCount, 1);
    });

    test('a burst of 5 fast reps -> +1 +2 +3 +4 +5, total moves 1..5', () {
      final c = RepBurstController();
      final t0 = DateTime.utc(2026, 1, 1);
      final results = <int>[];
      for (var i = 1; i <= 5; i++) {
        final e = c.update(
          i,
          now: t0.add(Duration(milliseconds: 200 * (i - 1))),
        );
        results.add(e!.streakCount);
      }
      expect(results, [1, 2, 3, 4, 5]);
    });

    test('custom burst window is honored', () {
      final c = RepBurstController(burstWindow: const Duration(milliseconds: 400));
      final t0 = DateTime.utc(2026, 1, 1);
      c.update(1, now: t0);
      // 500ms later — outside a 400ms window.
      final e = c.update(2, now: t0.add(const Duration(milliseconds: 500)));
      expect(e!.streakCount, 1);
      expect(e.isOnStreak, isFalse);
    });
  });
}
