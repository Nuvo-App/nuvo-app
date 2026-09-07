import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/virtual_distance_estimator.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';

/// Drives the estimator with a synthetic gait: one step every [stepMs] with a
/// fixed knee-swing amplitude, for [durationMs].
VirtualDistanceEstimator _drive({
  required int startMs,
  required int durationMs,
  required int stepMs,
  double swing = 0.10,
  double torso = 0.20,
  VirtualDistanceEstimator? into,
}) {
  final e = into ?? VirtualDistanceEstimator();
  var nextStep = startMs;
  for (var t = startMs; t < startMs + durationMs; t += 33) {
    e.onFrame(t);
    if (t >= nextStep) {
      e.onStep(swingAmplitude: swing, torsoHeight: torso, elapsedMs: t);
      nextStep += stepMs;
    }
  }
  return e;
}

void main() {
  test('standing still adds zero — no steps, no distance', () {
    final e = VirtualDistanceEstimator();
    for (var t = 0; t < 15000; t += 33) {
      e.onFrame(t);
    }
    expect(e.metres, 0);
    expect(e.paceSecondsPerMile, isNull);
    expect(e.intensityLabel, 'Ready');
  });

  test('a run accumulates distance; idle before and after adds nothing', () {
    final e = VirtualDistanceEstimator();
    for (var t = 0; t < 3000; t += 33) {
      e.onFrame(t); // idle
    }
    expect(e.metres, 0);

    _drive(startMs: 3000, durationMs: 10000, stepMs: 450, into: e); // ~2.2/s
    final afterRun = e.metres;
    expect(afterRun, greaterThan(8));
    final runningPace = e.paceSecondsPerMile;
    expect(runningPace, isNotNull);
    expect(formatPacePerMile(runningPace), isNotNull);

    for (var t = 13000; t < 22000; t += 33) {
      e.onFrame(t); // idle again
    }
    expect(e.metres, afterRun, reason: 'distance freezes when steps stop');
    expect(e.paceSecondsPerMile, isNull, reason: 'pace goes stale');
  });

  test('faster / harder running covers more ground per unit time', () {
    final slow = _drive(
      startMs: 0,
      durationMs: 20000,
      stepMs: 600,
      swing: 0.05,
    ).metres; // ~1.7/s shuffle
    final fast = _drive(
      startMs: 0,
      durationMs: 20000,
      stepMs: 300,
      swing: 0.14,
    ).metres; // ~3.3/s hard drive
    expect(fast, greaterThan(slow * 1.6));
  });

  test('distance never jumps on a single step (bounded stride)', () {
    final e = VirtualDistanceEstimator();
    var last = 0.0;
    for (var t = 0; t < 12000; t += 33) {
      e.onFrame(t);
      if (t % 350 < 33) {
        e.onStep(swingAmplitude: 0.12, torsoHeight: 0.2, elapsedMs: t);
        expect(e.metres - last, lessThan(1.6),
            reason: 'one step adds at most ~one stride');
        last = e.metres;
      }
    }
  });

  test('dropped frames (sparse onFrame) still produce a sane estimate', () {
    final e = VirtualDistanceEstimator();
    // ~10 fps instead of 30, steps still land
    var nextStep = 0;
    for (var t = 0; t < 12000; t += 100) {
      e.onFrame(t);
      if (t >= nextStep) {
        e.onStep(swingAmplitude: 0.10, torsoHeight: 0.2, elapsedMs: t);
        nextStep += 450;
      }
    }
    expect(e.metres, greaterThan(10));
    expect(e.metres, lessThan(120));
    expect(e.cadenceStepsPerMinute, greaterThan(90));
    expect(e.cadenceStepsPerMinute, lessThan(220));
  });

  test('reset clears everything', () {
    final e = _drive(startMs: 0, durationMs: 8000, stepMs: 400);
    expect(e.metres, greaterThan(0));
    e.reset();
    expect(e.metres, 0);
    expect(e.paceSecondsPerMile, isNull);
  });

  test('formatMiles / formatPacePerMile round sensibly', () {
    expect(formatMiles(1609), '1');
    expect(formatMiles(402), '0.25');
    expect(formatMiles(805), '0.5');
    expect(formatMiles(5000), '3.11');
    expect(formatPacePerMile(522), '8:42');
    expect(formatPacePerMile(60), isNull, reason: 'absurdly fast -> hidden');
    expect(formatPacePerMile(null), isNull);
  });
}
