import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

/// Regression guard built from a REAL failed cloud session
/// (`ms_64c7b6eec7de438c9d2a4842cb38f3f4`, 2026-09-07): ~37s of continuous
/// treadmill-style running toward a goal of 50 that the old vertical
/// knee-height cadence signal counted as **2**.
///
/// The pose stream contains ~77 clean alternating cycles, almost entirely as
/// a horizontal knee swing — the old signal keyed on Δy vs a hip-width
/// threshold, and hip width had collapsed to ~0.02 so the threshold floored
/// well above the entire signal. [AlternatingGaitSignal] normalizes against
/// torso height and follows whichever axis carries the stride.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/treadmill_running_session_ms_64c7b6ee.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;

  final frames = <NuvoPoseFrame>[
    for (final row in (fixture['frames'] as List).cast<Map<String, dynamic>>())
      NuvoPoseFrame(
        points: {
          for (final e in row.entries)
            if (e.key != 't')
              e.key: NuvoPosePoint(
                x: (e.value[0] as num).toDouble(),
                y: (e.value[1] as num).toDouble(),
                z: 0,
                likelihood: (e.value[2] as num).toDouble(),
              ),
        },
        imageWidth: 1000,
        imageHeight: 1000,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((row['t'] as num).toInt()),
      ),
  ];

  int replay(AiMotionActivity activity) {
    final v = createMotionValidator(activity, 50)..start();
    for (final f in frames) {
      v.update(f);
    }
    return v.currentValue;
  }

  test('fixture is the expected session', () {
    expect(fixture['activityId'], 'treadmill_running');
    expect(fixture['localCount'], 2); // what the old signal scored
    expect(frames.length, 890);
  });

  test('treadmill running now counts a real continuous run', () {
    final count = replay(AiMotionActivity.treadmillRunning);
    // Independent analysis of the landmark stream: ~77 alternating steps in
    // ~37s. Anything in this band means the cadence is genuinely tracked
    // (not the old stall at 2); the upper cap guards against a runaway
    // double-count.
    expect(count, greaterThanOrEqualTo(30));
    expect(count, lessThanOrEqualTo(90));
  });

  test('running in place shares the fixed signal', () {
    final count = replay(AiMotionActivity.runningInPlace);
    expect(count, greaterThanOrEqualTo(30));
    expect(count, lessThanOrEqualTo(90));
  });

  test('the session is horizontal-swing dominant (why the old signal starved)',
      () {
    // Locks in the observed signal shape from this real run: the vertical
    // knee stagger stays tiny while the horizontal one swings wide.
    var maxAbsDy = 0.0;
    var maxAbsDx = 0.0;
    var minHipWidth = 1.0;
    for (final f in frames) {
      final lk = f.point('leftKnee'), rk = f.point('rightKnee');
      final lh = f.point('leftHip'), rh = f.point('rightHip');
      if (lk == null || rk == null || lh == null || rh == null) continue;
      maxAbsDy = [(rk.y - lk.y).abs(), maxAbsDy].reduce((a, b) => a > b ? a : b);
      maxAbsDx = [(rk.x - lk.x).abs(), maxAbsDx].reduce((a, b) => a > b ? a : b);
      minHipWidth = [
        (lh.x - rh.x).abs(),
        minHipWidth,
      ].reduce((a, b) => a < b ? a : b);
    }
    expect(minHipWidth, lessThan(0.05)); // hip width collapsed -> old threshold floored
    expect(maxAbsDx, greaterThan(0.30)); // wide horizontal knee swing
    expect(maxAbsDx, greaterThan(maxAbsDy * 2)); // horizontal-dominant
  });

  test('the finished result verifies against a goal of 50', () {
    final v = createMotionValidator(AiMotionActivity.treadmillRunning, 50)
      ..start();
    for (final f in frames) {
      v.update(f);
    }
    final result = v.finish();
    expect(result.detectedReps, greaterThanOrEqualTo(30));
  });
}
