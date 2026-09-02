import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/pose_track.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'fixtures/pose_fixtures.dart';

NuvoPoseFrame _at(NuvoPoseFrame f, DateTime t) => NuvoPoseFrame(
      points: f.points,
      imageWidth: f.imageWidth,
      imageHeight: f.imageHeight,
      createdAt: t,
    );

NuvoPoseFrame _drop(NuvoPoseFrame f, Set<String> names, DateTime t) {
  final pts = {
    for (final e in f.points.entries)
      if (!names.contains(e.key)) e.key: e.value,
  };
  return NuvoPoseFrame(
      points: pts, imageWidth: f.imageWidth, imageHeight: f.imageHeight,
      createdAt: t);
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  DateTime tick(int i) => t0.add(Duration(milliseconds: 66 * i));

  group('temporal readiness + hysteresis', () {
    test('acquires READY after a run of good frames', () {
      final tr = PoseTrack();
      for (var i = 0; i < 14; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i));
      }
      expect(tr.isReady, isTrue);
      expect(tr.readyConfidence, greaterThan(0.6));
    });

    test('a single bad frame does NOT drop READY', () {
      final tr = PoseTrack();
      for (var i = 0; i < 14; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i));
      }
      expect(tr.isReady, isTrue);
      tr.update(null, tick(15)); // one dropped frame
      expect(tr.isReady, isTrue, reason: 'one bad frame must not lose READY');
      tr.update(_at(neutralStandingPose(), tick(16)), tick(16));
      expect(tr.isReady, isTrue);
    });

    test('sustained bad quality eventually loses READY', () {
      final tr = PoseTrack();
      for (var i = 0; i < 14; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i));
      }
      expect(tr.isReady, isTrue);
      for (var i = 15; i < 30; i++) {
        tr.update(null, tick(i));
      }
      expect(tr.isReady, isFalse);
    });
  });

  group('missing-landmark grace', () {
    test('a wrist missing for 2 frames is carried forward, then dropped', () {
      final tr = PoseTrack();
      for (var i = 0; i < 6; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i));
      }
      // wrist gone for 2 frames — still present (carried, damped confidence)
      var s = tr.update(_drop(neutralStandingPose(), {'leftWrist'}, tick(6)), tick(6));
      expect(s!.points.containsKey('leftWrist'), isTrue);
      expect(s.points['leftWrist']!.likelihood, lessThan(0.95));
      s = tr.update(_drop(neutralStandingPose(), {'leftWrist'}, tick(7)), tick(7));
      expect(s!.points.containsKey('leftWrist'), isTrue);
      // gone well past the grace window — now dropped
      for (var i = 8; i < 14; i++) {
        s = tr.update(_drop(neutralStandingPose(), {'leftWrist'}, tick(i)), tick(i));
      }
      expect(s!.points.containsKey('leftWrist'), isFalse);
      // readiness survived the flicker
      expect(tr.isReady, isTrue);
    });
  });

  group('One Euro smoothing', () {
    test('reduces jitter on a still joint but follows a real move', () {
      final tr = PoseTrack();
      final rng = math.Random(1);
      double lastNoseY = 0;
      final jitterAmp = <double>[];
      for (var i = 0; i < 30; i++) {
        // still pose + detector jitter on every landmark
        final base = neutralStandingPose();
        final noisy = NuvoPoseFrame(
          points: {
            for (final e in base.points.entries)
              e.key: NuvoPosePoint(
                x: e.value.x + (rng.nextDouble() - 0.5) * 0.02,
                y: e.value.y + (rng.nextDouble() - 0.5) * 0.02,
                z: 0,
                likelihood: 0.95,
              ),
          },
          imageWidth: base.imageWidth,
          imageHeight: base.imageHeight,
          createdAt: tick(i),
        );
        final s = tr.update(noisy, tick(i))!;
        if (i > 5) jitterAmp.add((s.points['nose']!.y - lastNoseY).abs());
        lastNoseY = s.points['nose']!.y;
      }
      final meanJitter = jitterAmp.reduce((a, b) => a + b) / jitterAmp.length;
      // smoothed frame-to-frame movement of a *still* joint should be well
      // below the injected ±0.01 jitter.
      expect(meanJitter, lessThan(0.006));
    });
  });

  group('articulation-energy motion start', () {
    test('standing still after READY does not fire motionStarted', () {
      final tr = PoseTrack()..armForCapture();
      for (var i = 0; i < 25; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i));
      }
      expect(tr.isReady, isTrue);
      expect(tr.motionStarted, isFalse);
    });

    test('walking sideways into position (no articulation) does not fire', () {
      final tr = PoseTrack()..armForCapture();
      for (var i = 0; i < 25; i++) {
        // whole body translating — same pose, shifting dx. Root-normalised out.
        tr.update(neutralStandingPose(dx: 0.01 * i, createdAt: tick(i)), tick(i));
      }
      expect(tr.motionStarted, isFalse,
          reason: 'walking into position must not count as the movement');
    });

    test('raising the arms fires motionStarted', () {
      final tr = PoseTrack()..armForCapture();
      for (var i = 0; i < 15; i++) {
        tr.update(_at(neutralStandingPose(), tick(i)), tick(i)); // settle
      }
      expect(tr.isReady, isTrue);
      for (var i = 15; i < 30; i++) {
        // interpolate neutral -> arms overhead
        final w = (i - 15) / 14;
        final a = neutralStandingPose();
        final b = armsOverheadPose();
        final blended = NuvoPoseFrame(
          points: {
            for (final k in a.points.keys)
              k: NuvoPosePoint(
                x: a.points[k]!.x * (1 - w) + b.points[k]!.x * w,
                y: a.points[k]!.y * (1 - w) + b.points[k]!.y * w,
                z: 0,
                likelihood: 0.95,
              ),
          },
          imageWidth: a.imageWidth,
          imageHeight: a.imageHeight,
          createdAt: tick(i),
        );
        tr.update(blended, tick(i));
      }
      expect(tr.motionStarted, isTrue);
      expect(tr.motionStartedAt, isNotNull);
    });
  });
}
