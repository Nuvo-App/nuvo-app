import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_pose_features.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/data/motion_capabilities.dart';

/// sequence_match_v1 — the first multi-phase remote engine.
///
/// The fixture below is a knee-bend sequence: standing → crouch → extension.
/// It deliberately lives only as data — the activity ID `seq_test_motion`
/// appears in no enum, catalog, or switch.
const sequenceSpec = <String, dynamic>{
  'specSchemaVersion': 1,
  'releaseId': 'seq_test-2026.10.0',
  'activityId': 'seq_test_motion',
  'engineType': 'sequence_match_v1',
  'measurementType': 'repetitions',
  'requiredCapabilities': [
    'pose_landmarks_v1',
    'derived_features_v1',
    'sequence_match_v1',
  ],
  'requiredLandmarks': ['leftHip', 'leftKnee', 'leftAnkle', 'leftWrist'],
  'stableFrames': 2,
  'repTimeoutMs': 8000,
  'lostPoseMs': 1500,
  'phases': [
    {
      'id': 'standing',
      'predicates': [
        {
          'kind': 'angle',
          'a': 'leftHip',
          'b': 'leftKnee',
          'c': 'leftAnkle',
          'operator': 'gte',
          'degrees': 160,
        },
      ],
      'next': 'crouch',
    },
    {
      'id': 'crouch',
      'predicates': [
        {
          'kind': 'angle',
          'a': 'leftHip',
          'b': 'leftKnee',
          'c': 'leftAnkle',
          'operator': 'lte',
          'degrees': 110,
        },
      ],
      'next': 'extension',
    },
    {
      'id': 'extension',
      'predicates': [
        {
          'kind': 'angle',
          'a': 'leftHip',
          'b': 'leftKnee',
          'c': 'leftAnkle',
          'operator': 'gte',
          'degrees': 160,
        },
        {
          'kind': 'landmark_axis',
          'point': 'leftWrist',
          'axis': 'y',
          'operator': 'lt',
          'threshold': 0.45,
        },
      ],
      'next': 'complete',
    },
  ],
};

/// A frame whose hip–knee–ankle interior angle equals [degrees], built from
/// a straight down knee→ankle segment and a rotated knee→hip segment.
/// [wristY] positions the left wrist (down = 0.8, raised overhead = 0.3).
NuvoPoseFrame _kneeFrame(double degrees, int ms, {double wristY = 0.8}) {
  final radians = degrees * math.pi / 180;
  const knee = (0.5, 0.7);
  final hip = (knee.$1 + math.sin(radians) * 0.2, knee.$2 + math.cos(radians) * 0.2);
  NuvoPosePoint p(double x, double y, [double likelihood = 0.95]) =>
      NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);
  return NuvoPoseFrame(
    points: {
      'leftHip': p(hip.$1, hip.$2),
      'leftKnee': p(knee.$1, knee.$2),
      'leftAnkle': p(0.5, 1.0),
      'leftWrist': p(0.5, wristY),
    },
    imageWidth: 640,
    imageHeight: 480,
    createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
  );
}

/// A frame with the required landmarks missing (e.g. ankle out of frame).
NuvoPoseFrame _poselessFrame(int ms) => NuvoPoseFrame(
      points: const {},
      imageWidth: 640,
      imageHeight: 480,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    );

RemoteVerifierRuntime _runtime({int target = 5}) =>
    createRemoteVerifierRuntime(
      spec: RemoteVerifierSpec.fromJson(sequenceSpec),
      target: target,
    );

/// Poses that satisfy no phase (135° fails both the 160° and 110° bounds) —
/// two consecutive misses reset any begun sequence back to phase 0.
void _settle(RemoteVerifierRuntime rt, int startMs) {
  for (var i = 0; i < 3; i++) {
    rt.update(_kneeFrame(135, startMs + i * 33));
  }
}

/// One full valid rep: standing ×2 → crouch ×2 → extension (wrist up) ×2.
RemoteVerifierUpdate _rep(RemoteVerifierRuntime rt, int startMs) {
  var update = rt.update(_kneeFrame(175, startMs));
  update = rt.update(_kneeFrame(175, startMs + 33));
  update = rt.update(_kneeFrame(90, startMs + 66));
  update = rt.update(_kneeFrame(90, startMs + 99));
  update = rt.update(_kneeFrame(175, startMs + 132, wristY: 0.3));
  update = rt.update(_kneeFrame(175, startMs + 165, wristY: 0.3));
  return update;
}

void main() {
  group('sequence_match_v1 spec parsing', () {
    test('parses engine, phases, and timing bounds', () {
      final spec = RemoteVerifierSpec.fromJson(sequenceSpec);
      expect(spec.engine, RemoteEngineType.sequenceMatchV1);
      expect(spec.activityId, 'seq_test_motion');
      expect(spec.phases, hasLength(3));
      expect(spec.phases[0].id, 'standing');
      expect(spec.phases[0].minDwellFrames, 2); // inherits stableFrames
      expect(spec.phases[0].breakToleranceFrames, 1);
      expect(spec.phases[2].completesRep, isTrue);
      expect(spec.repTimeoutMs, 8000);
      expect(spec.lostPoseMs, 1500);
    });

    test('capability is advertised', () {
      expect(MotionCapabilities.current(), contains('sequence_match_v1'));
    });

    test('rejects unknown predicate kinds', () {
      final bad = _specWithPhasePredicate({
        'kind': 'velocity_expr',
        'a': 'leftHip',
        'operator': 'gt',
      });
      expect(
        () => RemoteVerifierSpec.fromJson(bad),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('rejects predicate fields the kind does not own', () {
      final bad = _specWithPhasePredicate({
        'kind': 'angle',
        'a': 'leftHip',
        'b': 'leftKnee',
        'c': 'leftAnkle',
        'operator': 'gte',
        'degrees': 160,
        'expression': 'a + b', // smuggling an expression fails closed
      });
      expect(
        () => RemoteVerifierSpec.fromJson(bad),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('enforces a strict linear chain — no skips', () {
      final bad = _specWithPhases([
        _phase('a', [{'kind': 'landmark_axis', 'point': 'nose', 'axis': 'y', 'operator': 'lt', 'threshold': 0.5}], 'c'),
        _phase('b', [{'kind': 'landmark_axis', 'point': 'nose', 'axis': 'y', 'operator': 'lt', 'threshold': 0.5}], 'c'),
        _phase('c', [{'kind': 'landmark_axis', 'point': 'nose', 'axis': 'y', 'operator': 'lt', 'threshold': 0.5}], 'complete'),
      ]);
      expect(
        () => RemoteVerifierSpec.fromJson(bad),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('enforces a strict linear chain — no backward edge, no missing complete', () {
      final backward = _specWithPhases([
        _phase('a', [_noseRule()], 'b'),
        _phase('b', [_noseRule()], 'a'),
      ]);
      expect(
        () => RemoteVerifierSpec.fromJson(backward),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
      final noComplete = _specWithPhases([
        _phase('a', [_noseRule()], 'b'),
        _phase('b', [_noseRule()], 'b'),
      ]);
      expect(
        () => RemoteVerifierSpec.fromJson(noComplete),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('bounds phase count, predicates, and ids', () {
      expect(
        () => RemoteVerifierSpec.fromJson(
          _specWithPhases([_phase('a', [_noseRule()], 'complete')]),
        ),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
      expect(
        () => RemoteVerifierSpec.fromJson(
          _specWithPhases([
            for (var i = 0; i < 9; i++)
              _phase('p$i', [_noseRule()], i == 8 ? 'complete' : 'p${i + 1}'),
          ]),
        ),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
      expect(
        () => RemoteVerifierSpec.fromJson(
          _specWithPhases([
            _phase('a', [_noseRule()], 'b'),
            _phase('a', [_noseRule()], 'complete'),
          ]),
        ),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('sequence fields are engine-scoped', () {
      final wrongEngine = Map<String, dynamic>.from(sequenceSpec)
        ..['engineType'] = 'alternating_rep_v1'
        ..['leftRules'] = const [
          {'point': 'nose', 'axis': 'y', 'operator': 'lt', 'threshold': 0.5},
        ]
        ..['rightRules'] = const [
          {'point': 'nose', 'axis': 'y', 'operator': 'lt', 'threshold': 0.5},
        ];
      expect(
        () => RemoteVerifierSpec.fromJson(wrongEngine),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
      final duration = Map<String, dynamic>.from(sequenceSpec)
        ..['measurementType'] = 'duration';
      expect(
        () => RemoteVerifierSpec.fromJson(duration),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });
  });

  group('sequence_match_v1 runtime', () {
    test('one full ordered sequence counts exactly one rep', () {
      final rt = _runtime();
      final update = _rep(rt, 0);
      expect(update.state, RemoteRuntimeState.repAccepted);
      expect(rt.count, 1);
    });

    test('a later-phase pose alone can never count', () {
      final rt = _runtime();
      // The extension pose (straight leg + wrist up) satisfies phase 0's
      // standing predicate, but the machine can only advance 0→1→2 — it
      // reaches phase 1, then resets when crouch never arrives.
      for (var i = 0; i < 20; i++) {
        rt.update(_kneeFrame(175, i * 33, wristY: 0.3));
      }
      expect(rt.count, 0);
    });

    test('skipping a required phase does not count', () {
      final rt = _runtime();
      // standing → crouch → standing again: the extension phase (wrist
      // raised) was required, so landing back in a plain standing pose
      // breaks the sequence instead of completing it.
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66));
      rt.update(_kneeFrame(90, 99));
      for (var i = 0; i < 4; i++) {
        rt.update(_kneeFrame(175, 132 + i * 33)); // wrist stays down
      }
      expect(rt.count, 0);
      // A full sequence still works afterwards (settle first — the break
      // above leaves the machine mid-chain).
      _settle(rt, 900);
      final update = _rep(rt, 1000);
      expect(rt.count, 1);
      expect(update.state, RemoteRuntimeState.repAccepted);
    });

    test('a broken mid-sequence resets', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66)); // crouch entered
      // Sustained break at crouch (> tolerance 1) → reset to phase 0.
      RemoteVerifierUpdate update = rt.update(_kneeFrame(175, 99));
      update = rt.update(_kneeFrame(175, 132));
      expect(update.diagnostic, 'sequence_phase_lost');
      // Crouch + extension now can't complete — machine is back at standing.
      rt.update(_kneeFrame(90, 165));
      rt.update(_kneeFrame(90, 198));
      rt.update(_kneeFrame(175, 231));
      rt.update(_kneeFrame(175, 264));
      expect(rt.count, 0);
    });

    test('lost pose pauses the machine, then resets past lostPoseMs', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66)); // began
      var update = rt.update(_poselessFrame(99));
      expect(update.diagnostic, 'sequence_pose_pause');
      // Dwell is frozen while pose is gone — resume inside the window and the
      // sequence continues where it left off.
      rt.update(_kneeFrame(90, 1099));
      rt.update(_kneeFrame(175, 1132, wristY: 0.3));
      update = rt.update(_kneeFrame(175, 1165, wristY: 0.3));
      expect(rt.count, 1);
    });

    test('lost pose beyond lostPoseMs resets the sequence', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66));
      final diagnostics = <String>{};
      for (var i = 1; i <= 20; i++) {
        diagnostics.add(rt.update(_poselessFrame(66 + i * 100)).diagnostic);
      }
      expect(diagnostics, contains('sequence_pose_lost'));
      // Extension pose alone can't complete — machine reset to standing.
      rt.update(_kneeFrame(175, 2100));
      rt.update(_kneeFrame(175, 2133));
      rt.update(_kneeFrame(175, 2166));
      expect(rt.count, 0);
    });

    test('rep timeout resets a begun sequence', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66)); // began at t=33
      // Stalemate at crouch: alternating hold/miss means the dwell never
      // accumulates and the miss never exceeds tolerance — the machine sits
      // mid-sequence until repTimeoutMs forces a reset.
      final diagnostics = <String>{};
      for (var i = 1; i <= 40; i++) {
        diagnostics.add(
          rt.update(_kneeFrame(i.isEven ? 90 : 175, 66 + i * 500)).diagnostic,
        );
      }
      expect(diagnostics, contains('sequence_rep_timeout'));
      expect(rt.count, 0);
    });

    test('threshold oscillation stalls without chatter or reset', () {
      final rt = _runtime();
      // Hover 159°/162° around the 160° standing bound — flicker never
      // accumulates the two consecutive holds phase 0 needs, and the
      // interleaved misses never exceed tolerance, so no reset either.
      for (var i = 0; i < 40; i++) {
        final update = rt.update(_kneeFrame(i.isEven ? 159 : 162, i * 33));
        expect(update.diagnostic, 'sequence_phase_0');
      }
      expect(rt.count, 0);
    });

    test('a flicker inside break tolerance delays but does not reset', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33)); // advanced to crouch
      rt.update(_kneeFrame(90, 66)); // dwell 1
      rt.update(_kneeFrame(175, 99)); // miss 1 (tolerated), dwell resets
      var update = rt.update(_kneeFrame(90, 132)); // dwell 1 again
      expect(update.diagnostic, contains('sequence_phase'));
      update = rt.update(_kneeFrame(90, 165)); // dwell 2 → advance
      expect(update.diagnostic, 'sequence_phase_advance');
      update = rt.update(_kneeFrame(175, 198, wristY: 0.3));
      update = rt.update(_kneeFrame(175, 231, wristY: 0.3));
      expect(rt.count, 1);
    });

    test('repeated partial movements count nothing', () {
      final rt = _runtime();
      for (var i = 0; i < 30; i++) {
        rt.update(_kneeFrame(90, i * 33)); // crouch only, never enters chain
      }
      expect(rt.count, 0);
    });

    test('consecutive reps accumulate', () {
      final rt = _runtime();
      _rep(rt, 0);
      _rep(rt, 1000);
      expect(rt.count, 2);
    });

    test('pose lost at the completion boundary pauses, then completes', () {
      final rt = _runtime();
      rt.update(_kneeFrame(175, 0));
      rt.update(_kneeFrame(175, 33));
      rt.update(_kneeFrame(90, 66));
      rt.update(_kneeFrame(90, 99));
      rt.update(_kneeFrame(175, 132, wristY: 0.3)); // extension dwell 1 of 2
      rt.update(_poselessFrame(165)); // paused mid-completion
      final update =
          rt.update(_kneeFrame(175, 198, wristY: 0.3)); // resumes → rep
      expect(update.state, RemoteRuntimeState.repAccepted);
      expect(rt.count, 1);
    });

    test('reaching the target reports completed', () {
      final rt = _runtime(target: 1);
      final update = _rep(rt, 0);
      expect(update.state, RemoteRuntimeState.completed);
      expect(update.progress, 1);
    });
  });

  group('derived feature math (canonical, fail-closed)', () {
    NuvoPosePoint p(double x, double y, [double likelihood = 0.95]) =>
        NuvoPosePoint(x: x, y: y, z: 0, likelihood: likelihood);

    test('angle computes known geometry', () {
      // Right angle at the knee: hip right of knee, ankle below.
      final right = RemotePoseFeatures.angle(
        a: p(0.7, 0.7),
        b: p(0.5, 0.7),
        c: p(0.5, 1.0),
      );
      expect(right, closeTo(90, 1));
      // Straight leg → 180.
      final straight = RemotePoseFeatures.angle(
        a: p(0.5, 0.4),
        b: p(0.5, 0.7),
        c: p(0.5, 1.0),
      );
      expect(straight, closeTo(180, 0.5));
    });

    test('angle fails closed on degenerate geometry', () {
      expect(
        RemotePoseFeatures.angle(a: p(0.5, 0.7), b: p(0.5, 0.7), c: p(0.5, 1)),
        isNull,
      );
      expect(
        RemotePoseFeatures.angle(a: null, b: p(0.5, 0.7), c: p(0.5, 1)),
        isNull,
      );
      expect(
        RemotePoseFeatures.angle(
          a: p(0.5, 0.4, 0.1),
          b: p(0.5, 0.7),
          c: p(0.5, 1),
        ),
        isNull,
      );
    });

    test('segment ratio fails closed on zero-length reference', () {
      expect(
        RemotePoseFeatures.segmentRatio(
          a: p(0.5, 0.4),
          b: p(0.5, 0.7),
          refA: p(0.3, 0.5),
          refB: p(0.3, 0.5),
        ),
        isNull,
      );
      expect(
        RemotePoseFeatures.segmentRatio(
          a: p(0.5, 0.4),
          b: p(0.5, 0.7),
          refA: p(0.3, 0.5),
          refB: p(0.7, 0.5),
        ),
        closeTo(0.75, 0.01),
      );
    });
  });
}

Map<String, dynamic> _noseRule() => {
      'kind': 'landmark_axis',
      'point': 'nose',
      'axis': 'y',
      'operator': 'lt',
      'threshold': 0.5,
    };

Map<String, dynamic> _phase(
  String id,
  List<Map<String, dynamic>> predicates,
  String next,
) =>
    {'id': id, 'predicates': predicates, 'next': next};

Map<String, dynamic> _specWithPhases(List<Map<String, dynamic>> phases) =>
    Map<String, dynamic>.from(sequenceSpec)..['phases'] = phases;

Map<String, dynamic> _specWithPhasePredicate(Map<String, dynamic> predicate) =>
    _specWithPhases([
      _phase('a', [predicate], 'b'),
      _phase('b', [_noseRule()], 'complete'),
    ]);
