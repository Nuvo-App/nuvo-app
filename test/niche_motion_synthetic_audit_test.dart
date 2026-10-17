// Niche-motion synthetic audit.
//
// An AUDIT, not a regression gate: it never fails on accuracy. It fails only
// when a synthetic fixture cannot be built. For every niche motion it
//   1. builds a CLEAN synthetic pose sequence of N=10 reps,
//   2. feeds it through the production validator (createMotionValidator),
//   3. feeds it through the over-the-air spec runtime when a spec exists
//      (server/worker/motion_specs/<id>.json) and, when present, a candidate
//      (server/worker/motion_specs/candidates/<id>.json),
//   4. repeats the validator run on DEGRADED copies (coordinate jitter + 10%
//      dropped frames, from FixtureAugmenter, 5 seeds) to flag fragile motions,
// and prints a table. Every printed line starts with "Shell: " so
//   flutter test test/niche_motion_synthetic_audit_test.dart 2>&1 | grep '^Shell:'
// shows just the report. Set AUDIT_DEBUG=<activity id> to also dump the
// validator's debug signals for that motion's clean run.
//
// GENERATOR ASSUMPTIONS (shared)
//  * Normalized image coords, y down, 30 fps (33 ms/frame), 12 landmarks
//    (shoulders, elbows, wrists, hips, knees, ankles), likelihood 0.92.
//  * Standing body: shoulders y=.30, hips y=.50 (torso .20), knees y=.68
//    (hipToKneeRatio .90, inside the on-device 0.72-0.95 band the validators
//    were calibrated on), ankles y=.88. Front-facing camera unless a variant
//    says otherwise. "left*" landmarks sit at smaller x (factory convention).
//  * Each rep has a lead-in/lead-out of 12 standing frames.
//  * Cadence motions (marching, walking, running, treadmill, step-ups,
//    butt kicks, mountain climbers, lateral steps) count one per confirmed
//    ALTERNATION; the first step only establishes the baseline side. The
//    generators perform 10 steps, so a perfect result is 9. They are
//    reported UNDER by one on purpose: that is what a user doing "10" gets.
//  * lunge_jumps reuses SyntheticFixtureFactory.cleanLungeJump2Reps (5 copies
//    concatenated = 10 reps). No other motion has a factory generator, so the
//    rest are parametric (keyframes / IK for the side lunge) built below.
//  * basketball_shot is object-based (ball dot + hoop), not a pose validator,
//    so it is reported NO VALIDATOR.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'motion_qa/fixture_augmenter.dart';
import 'motion_qa/replay_fixture.dart';
import 'motion_qa/synthetic_fixture_factory.dart';

const _fps = 30;
const _msPerFrame = 33;
const _n = 10;

// ───────────────────────── skeleton helpers ─────────────────────────

typedef P = (double, double);

const _joints = [
  'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow', //
  'leftWrist', 'rightWrist', 'leftHip', 'rightHip',
  'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
];

class Sk {
  const Sk(this.p);
  final Map<String, P> p;

  Sk mv(Iterable<String> js, double dx, double dy) {
    final m = Map<String, P>.of(p);
    for (final j in js) {
      final (x, y) = m[j]!;
      m[j] = (x + dx, y + dy);
    }
    return Sk(m);
  }

  Sk shift(double dx, double dy) => mv(p.keys, dx, dy);

  Sk put(Map<String, P> o) => Sk({...p, ...o});

  static Sk lerp(Sk a, Sk b, double t) => Sk({
    for (final j in _joints)
      j: (
        a.p[j]!.$1 + (b.p[j]!.$1 - a.p[j]!.$1) * t,
        a.p[j]!.$2 + (b.p[j]!.$2 - a.p[j]!.$2) * t,
      ),
  });
}

Sk _standing() => const Sk({
  'leftShoulder': (.40, .30),
  'rightShoulder': (.60, .30),
  'leftElbow': (.37, .41),
  'rightElbow': (.63, .41),
  'leftWrist': (.38, .52),
  'rightWrist': (.62, .52),
  'leftHip': (.43, .50),
  'rightHip': (.57, .50),
  'leftKnee': (.43, .68),
  'rightKnee': (.57, .68),
  'leftAnkle': (.44, .88),
  'rightAnkle': (.56, .88),
});

/// 0 -> 1 -> 0 over u in [0,1], flattened at the top so the pose is held for a
/// few frames the way a person pauses at the end range.
double _plateau(double u, {double k = 1.5}) =>
    math.min(1.0, (0.5 - 0.5 * math.cos(2 * math.pi * u)) * k);

double _smooth(double t) => t * t * (3 - 2 * t);

Sk _keys(List<(double, Sk)> keys, double u) {
  for (var i = 0; i + 1 < keys.length; i++) {
    final (u0, a) = keys[i];
    final (u1, b) = keys[i + 1];
    if (u >= u0 && u <= u1) {
      return Sk.lerp(a, b, _smooth(((u - u0) / (u1 - u0)).clamp(0.0, 1.0)));
    }
  }
  return keys.last.$2;
}

List<Sk> _hold(Sk s, int frames) => List.filled(frames, s);

List<Sk> _cycles(int n, int frames, Sk Function(double u) f) => [
  for (var r = 0; r < n; r++)
    for (var i = 0; i < frames; i++) f(i / frames),
];

List<Sk> _wrap(Sk base, List<Sk> body) => [
  ..._hold(base, 12),
  ...body,
  ..._hold(base, 12),
];

/// `steps` alternating single-limb excursions, starting with the left side.
List<Sk> _alternating(
  int steps,
  int frames,
  Sk Function(bool left, double amp) pose,
) => [
  for (var s = 0; s < steps; s++)
    for (var i = 0; i < frames; i++)
      pose(s.isEven, math.sin(math.pi * i / frames)),
];

/// Two-link leg IK in image space: knee position for a hip/ankle pair.
/// `outward` = +1 puts the knee toward +x/-y of the hip-ankle line, -1 the
/// opposite. Leg segment length .19 (standing hip->ankle = .38).
P _knee(P hip, P ankle, int outward) {
  const l = .19;
  var dx = ankle.$1 - hip.$1, dy = ankle.$2 - hip.$2;
  var d = math.sqrt(dx * dx + dy * dy);
  final maxD = 2 * l - .0005;
  if (d > maxD) {
    dx *= maxD / d;
    dy *= maxD / d;
    d = maxD;
  }
  final a = d / 2;
  final h = math.sqrt(math.max(0, l * l - a * a));
  final mx = hip.$1 + dx / 2, my = hip.$2 + dy / 2;
  // unit perpendicular with positive x component
  var nx = dy / d, ny = -dx / d;
  if (nx < 0) {
    nx = -nx;
    ny = -ny;
  }
  return (mx + outward * nx * h, my + outward * ny * h);
}

// ───────────────────────── per-motion generators ─────────────────────────

List<Sk> _burpees({bool armsOverheadAtTop = true}) {
  final top = armsOverheadAtTop
      ? _standing().put({
          'leftWrist': (.41, .10),
          'rightWrist': (.59, .10),
          'leftElbow': (.40, .20),
          'rightElbow': (.60, .20),
        })
      : _standing(); // arms hanging at the sides
  final crouch = const Sk({
    'leftShoulder': (.40, .46),
    'rightShoulder': (.60, .46),
    'leftElbow': (.40, .62),
    'rightElbow': (.60, .62),
    'leftWrist': (.40, .86),
    'rightWrist': (.60, .86),
    'leftHip': (.43, .64),
    'rightHip': (.57, .64),
    'leftKnee': (.40, .70),
    'rightKnee': (.60, .70),
    'leftAnkle': (.44, .88),
    'rightAnkle': (.56, .88),
  });
  final plank = const Sk({
    'leftShoulder': (.25, .56),
    'rightShoulder': (.27, .56),
    'leftElbow': (.25, .65),
    'rightElbow': (.27, .65),
    'leftWrist': (.24, .74),
    'rightWrist': (.28, .74),
    'leftHip': (.52, .62),
    'rightHip': (.54, .62),
    'leftKnee': (.66, .66),
    'rightKnee': (.68, .66),
    'leftAnkle': (.80, .72),
    'rightAnkle': (.82, .72),
  });
  final jump = top.mv(['leftAnkle', 'rightAnkle'], 0, -.06);
  final keys = <(double, Sk)>[
    (0.00, top),
    (0.08, top),
    (0.25, crouch),
    (0.34, crouch),
    (0.46, plank),
    (0.58, plank),
    (0.68, crouch),
    (0.78, crouch),
    (0.88, jump),
    (0.95, top),
    (1.00, top),
  ];
  return _wrap(top, _cycles(_n, 60, (u) => _keys(keys, u)));
}

/// Plain bodyweight squats with arms hanging (NOT a burpee): identity check.
List<Sk> _squatsArmsHanging() {
  final up = _standing();
  final down = _standing().put({
    'leftShoulder': (.40, .42),
    'rightShoulder': (.60, .42),
    'leftElbow': (.37, .56),
    'rightElbow': (.63, .56),
    'leftWrist': (.38, .72),
    'rightWrist': (.62, .72),
    'leftHip': (.43, .62),
    'rightHip': (.57, .62),
    'leftKnee': (.40, .70),
    'rightKnee': (.60, .70),
  });
  return _wrap(up, _cycles(_n, 40, (u) => Sk.lerp(up, down, _plateau(u))));
}

List<Sk> _buttKicks({double rise = .22}) {
  final b = _standing();
  return _wrap(
    b,
    _alternating(_n, 12, (left, a) {
      final side = left ? 'left' : 'right';
      return b
          .mv(['${side}Ankle'], 0, -rise * a)
          .mv(['${side}Knee'], 0, -.02 * a);
    }),
  );
}

List<Sk> _calfRaises({double rise = .035}) {
  final b = _standing();
  return _wrap(b, _cycles(_n, 30, (u) => b.shift(0, -rise * _plateau(u))));
}

List<Sk> _kneeLift(
  int steps,
  int frames,
  double lift, {
  double xSwing = 0,
  bool sameLeg = false,
}) {
  final b = _standing();
  return _wrap(
    b,
    _alternating(steps, frames, (left, a) {
      final side = (left || sameLeg) ? 'left' : 'right';
      final dir = left ? 1.0 : -1.0;
      return b
          .mv(['${side}Knee', '${side}Ankle'], dir * xSwing * a, -lift * a)
          .mv(['${side}Ankle'], 0, -.02 * a);
    }),
  );
}

/// Side-on running: the knees swing front/back (x) with almost no vertical
/// stagger, hips overlap. This is the real-device failure that motivated
/// AlternatingGaitSignal.
List<Sk> _runningSideView() {
  final b = _standing().put({
    'leftHip': (.49, .50),
    'rightHip': (.51, .50),
    'leftShoulder': (.49, .30),
    'rightShoulder': (.51, .30),
    'leftKnee': (.50, .68),
    'rightKnee': (.50, .68),
    'leftAnkle': (.50, .88),
    'rightAnkle': (.50, .88),
  });
  // 10 steps = 5 full swing cycles of 18 frames.
  final body = _cycles(5, 18, (u) {
    final s = math.sin(2 * math.pi * u);
    return b
        .mv(['leftKnee'], .09 * s, -.012 * s.abs())
        .mv(['rightKnee'], -.09 * s, -.012 * s.abs())
        .mv(['leftAnkle'], -.10 * s, 0)
        .mv(['rightAnkle'], .10 * s, 0);
  });
  return _wrap(b, body);
}

List<Sk> _mountainClimbers() {
  // Side-on plank, head to the left.
  const ext = Sk({
    'leftShoulder': (.25, .50),
    'rightShoulder': (.27, .50),
    'leftElbow': (.25, .57),
    'rightElbow': (.27, .57),
    'leftWrist': (.24, .64),
    'rightWrist': (.26, .64),
    'leftHip': (.55, .56),
    'rightHip': (.57, .56),
    'leftKnee': (.70, .60),
    'rightKnee': (.72, .60),
    'leftAnkle': (.85, .64),
    'rightAnkle': (.87, .64),
  });
  return _wrap(
    ext,
    _alternating(_n, 10, (left, a) {
      final side = left ? 'left' : 'right';
      final k = ext.p['${side}Knee']!;
      final knee = (k.$1 + (.44 - k.$1) * a, k.$2 + (.64 - k.$2) * a);
      final an = ext.p['${side}Ankle']!;
      return ext.put({
        '${side}Knee': knee,
        '${side}Ankle': (an.$1 + (.52 - an.$1) * a, an.$2 + .02 * a),
      });
    }),
  );
}

List<Sk> _lateralSteps({double shift = .11}) {
  final b = _standing();
  final body = <Sk>[];
  for (var s = 0; s < _n; s++) {
    final dir = s.isEven ? 1.0 : -1.0;
    for (var i = 0; i < 24; i++) {
      body.add(b.shift(dir * shift * _plateau(i / 24, k: 1.6), 0));
    }
  }
  return _wrap(b, body);
}

List<Sk> _armRaises() {
  final b = _standing();
  return _wrap(
    b,
    _cycles(_n, 36, (u) {
      final a = _plateau(u);
      final wy = .52 + (.12 - .52) * a;
      final ey = .41 + (.22 - .41) * a;
      return b.put({
        'leftWrist': (.38 + .03 * a, wy),
        'rightWrist': (.62 - .03 * a, wy),
        'leftElbow': (.37 + .02 * a, ey),
        'rightElbow': (.63 - .02 * a, ey),
      });
    }),
  );
}

List<Sk> _plankHold({double seconds = 10.5}) {
  const plank = Sk({
    'leftShoulder': (.25, .50),
    'rightShoulder': (.27, .50),
    'leftElbow': (.25, .60),
    'rightElbow': (.27, .60),
    'leftWrist': (.25, .64),
    'rightWrist': (.27, .64),
    'leftHip': (.50, .53),
    'rightHip': (.52, .53),
    'leftKnee': (.65, .56),
    'rightKnee': (.67, .56),
    'leftAnkle': (.80, .60),
    'rightAnkle': (.82, .60),
  });
  return [..._hold(_standing(), 15), ..._hold(plank, (seconds * _fps).round())];
}

List<Sk> _sumoSquats() {
  final up = _standing().put({
    'leftAnkle': (.30, .88),
    'rightAnkle': (.70, .88),
    'leftKnee': (.36, .68),
    'rightKnee': (.64, .68),
  });
  final down = up.put({
    'leftShoulder': (.40, .42),
    'rightShoulder': (.60, .42),
    'leftElbow': (.37, .50),
    'rightElbow': (.63, .50),
    'leftWrist': (.40, .56),
    'rightWrist': (.60, .56),
    'leftHip': (.43, .62),
    'rightHip': (.57, .62),
    'leftKnee': (.30, .70),
    'rightKnee': (.70, .70),
  });
  return _wrap(up, _cycles(_n, 40, (u) => Sk.lerp(up, down, _plateau(u))));
}

List<Sk> _squatJacks() {
  final closed = _standing();
  final open = _standing().put({
    'leftShoulder': (.40, .40),
    'rightShoulder': (.60, .40),
    'leftElbow': (.36, .26),
    'rightElbow': (.64, .26),
    'leftWrist': (.35, .10),
    'rightWrist': (.65, .10),
    'leftHip': (.43, .60),
    'rightHip': (.57, .60),
    'leftKnee': (.35, .68),
    'rightKnee': (.65, .68),
    'leftAnkle': (.32, .88),
    'rightAnkle': (.68, .88),
  });
  return _wrap(
    closed,
    _cycles(_n, 36, (u) => Sk.lerp(closed, open, _plateau(u))),
  );
}

/// Alternating right/left side lunges, legs by IK so knee angles are
/// geometrically consistent. Bent leg ~98 deg, trailing leg straight.
List<Sk> _sideLunges() {
  final b = _standing();
  final body = <Sk>[];
  for (var r = 0; r < _n; r++) {
    final s = r.isEven ? 1 : -1; // +1 = lunge toward image right
    for (var i = 0; i < 40; i++) {
      final d = _plateau(i / 40);
      final cx = .5 + s * .08 * d;
      final hy = .50 + .13 * d;
      final sy = .30 + .13 * d;
      final lh = (cx - .07, hy), rh = (cx + .07, hy);
      // bent side ankle goes out; trailing ankle is placed at full reach.
      final outX = .5 + s * (.06 + .23 * d);
      final bentAnkle = (outX, .88);
      P trailAnkle(P hip) {
        final dy = .88 - hip.$2;
        final dx = math.sqrt(math.max(0, math.pow(.379, 2) - dy * dy));
        final base = .5 - s * .06;
        final reach = hip.$1 - s * dx;
        return (base + (reach - base) * d, .88);
      }

      final sRight = s == 1;
      final lAnkle = sRight ? trailAnkle(lh) : bentAnkle;
      final rAnkle = sRight ? bentAnkle : trailAnkle(rh);
      final lKnee = _knee(lh, lAnkle, sRight ? -1 : 1);
      final rKnee = _knee(rh, rAnkle, sRight ? 1 : -1);
      body.add(
        b.put({
          'leftShoulder': (cx - .10, sy),
          'rightShoulder': (cx + .10, sy),
          'leftElbow': (cx - .13, sy + .11),
          'rightElbow': (cx + .13, sy + .11),
          'leftWrist': (cx - .12, sy + .22),
          'rightWrist': (cx + .12, sy + .22),
          'leftHip': lh,
          'rightHip': rh,
          'leftKnee': lKnee,
          'rightKnee': rKnee,
          'leftAnkle': lAnkle,
          'rightAnkle': rAnkle,
        }),
      );
    }
  }
  return _wrap(b, body);
}

// ───────────────────────── fixture / runner plumbing ─────────────────────────

ReplayFixture _fixture(String movement, int expected, List<Sk> poses) {
  final frames = <RecordedFrame>[
    for (var i = 0; i < poses.length; i++)
      RecordedFrame(
        landmarks: {
          for (final e in poses[i].p.entries)
            e.key: RecordedLandmark(e.value.$1, e.value.$2, 0, 0.92),
        },
        frameIndex: i,
        elapsedMs: i * _msPerFrame,
      ),
  ];
  return ReplayFixture(
    id: 'audit_$movement',
    movement: movement,
    expected: FixtureExpected(reps: expected, shouldMatch: true),
    source: const FixtureSource(
      type: 'synthetic',
      name: 'niche_motion_synthetic_audit',
      cameraView: 'front',
      qualityTier: 'synthetic',
    ),
    frames: frames,
    label: 'audit',
    tags: const ['synthetic', 'audit'],
  );
}

/// Production frame with wall-clock-independent timestamps (augmenter copies
/// keep frameIndex, so dropped frames still leave their real time gap).
NuvoPoseFrame _toFrame(RecordedFrame f) => NuvoPoseFrame(
  points: {
    for (final e in f.landmarks.entries)
      e.key: NuvoPosePoint(
        x: e.value.x,
        y: e.value.y,
        z: e.value.z,
        likelihood: e.value.likelihood,
      ),
  },
  imageWidth: f.imageWidth,
  imageHeight: f.imageHeight,
  createdAt: DateTime.utc(
    2026,
    1,
    1,
  ).add(Duration(milliseconds: f.frameIndex * _msPerFrame)),
);

class _Run {
  _Run(this.count, {this.note = ''});
  final int count;
  final String note;
}

class _Gen {
  _Gen(
    this.id,
    this.label,
    this.expected,
    this.build, {
    this.countOf,
    this.note = '',
    int? ceiling,
  }) : ceiling = ceiling ?? expected;
  final String id; // activity backend id
  final String label; // row label (id or id + variant)
  final int expected;
  final ReplayFixture Function() build;
  final int Function(MotionValidator v)? countOf;
  final String note;

  /// Best count the counting rule can mechanically produce (cadence motions
  /// lose the first step to the baseline side).
  final int ceiling;
}

_Run _runValidator(_Gen g, ReplayFixture fx, {bool debug = false}) {
  final v = createMotionValidator(
    AiMotionActivity.fromBackendValue(g.id),
    100000,
  )..start();
  var i = 0;
  for (final f in fx.frames) {
    v.update(_toFrame(f));
    if (debug && i++ % 4 == 0) {
      final d = v.debugValues;
      // ignore: avoid_print
      print(
        'Shell: [dbg ${g.label}] f=${f.frameIndex} count=${v.currentValue} '
        '${d.entries.where((e) => !const {'framesAnalyzed', 'validPoseFrames', 'visibility'}.contains(e.key)).map((e) => '${e.key}=${e.value.toStringAsFixed(3)}').join(' ')}',
      );
    }
  }
  final c = g.countOf?.call(v) ?? v.currentValue;
  return _Run(
    c,
    note: g.countOf != null ? 'validator currentValue=${v.currentValue}' : '',
  );
}

int? _runSpec(String path, String id, ReplayFixture fx, {bool cycles = false}) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final spec = RemoteVerifierSpec.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    final rt = createRemoteVerifierRuntime(spec: spec, target: 100000);
    var out = 0;
    for (final f in fx.frames) {
      final u = rt.update(_toFrame(f));
      out = cycles ? (u.metrics['cycles']?.round() ?? u.count) : u.count;
    }
    return out;
  } catch (_) {
    return null;
  }
}

String _verdict(int got, int expected, int ceiling) {
  if (got == expected) return 'EXACT';
  if (got == ceiling && ceiling < expected) {
    return 'UNDER (-${expected - ceiling}, baseline step)';
  }
  return got < expected ? 'UNDER' : 'OVER';
}

ReplayFixture _lungeJumps10() {
  final one = SyntheticFixtureFactory(seed: 7).cleanLungeJump2Reps();
  final frames = <RecordedFrame>[];
  for (var c = 0; c < 5; c++) {
    for (final f in one.frames) {
      frames.add(
        RecordedFrame(
          landmarks: f.landmarks,
          frameIndex: frames.length,
          elapsedMs: frames.length * _msPerFrame,
        ),
      );
    }
  }
  return ReplayFixture(
    id: 'audit_lunge_jumps',
    movement: 'lunge_jumps',
    expected: const FixtureExpected(reps: _n, shouldMatch: true),
    source: one.source,
    frames: frames,
    label: 'audit',
    tags: const ['synthetic', 'audit'],
  );
}

void main() {
  int cyclesOf(MotionValidator v) => (v.debugValues['cycles'] ?? 0).round();

  final gens = <_Gen>[
    _Gen('burpees', 'burpees', _n, () => _fixture('burpees', _n, _burpees())),
    _Gen(
      'burpees',
      'burpees [arms at sides]',
      _n,
      () => _fixture('burpees', _n, _burpees(armsOverheadAtTop: false)),
      note: 'arms hang at sides at the top (no overhead reach)',
    ),
    _Gen(
      'burpees',
      'burpees [CONFUSER: squats, arms hanging]',
      0,
      () => _fixture('burpees', 0, _squatsArmsHanging()),
      note: 'identity check: plain squats must not count as burpees',
    ),
    _Gen(
      'mountain_climbers',
      'mountain_climbers',
      _n,
      () => _fixture('mountain_climbers', _n, _mountainClimbers()),
      note: 'side-on plank; first drive is the baseline side',
      ceiling: _n - 1,
    ),
    _Gen(
      'butt_kicks',
      'butt_kicks',
      _n,
      () => _fixture('butt_kicks', _n, _buttKicks()),
      note: 'first kick is the baseline side',
      ceiling: _n - 1,
    ),
    _Gen(
      'calf_raises',
      'calf_raises',
      _n,
      () => _fixture('calf_raises', _n, _calfRaises()),
      note: 'ankle rise .035 of frame',
    ),
    _Gen(
      'calf_raises',
      'calf_raises [small rise]',
      _n,
      () => _fixture('calf_raises', _n, _calfRaises(rise: .015)),
      note: 'ankle rise .015 of frame (shallow raise)',
    ),
    _Gen(
      'step_ups',
      'step_ups',
      _n,
      () => _fixture('step_ups', _n, _kneeLift(_n, 18, .16)),
      note: 'alternating lead leg, knee lift .16; first step is baseline',
      ceiling: _n - 1,
    ),
    _Gen(
      'step_ups',
      'step_ups [same leg x10]',
      _n,
      () => _fixture('step_ups', _n, _kneeLift(_n, 18, .16, sameLeg: true)),
      note:
          'one leg leads every rep (set of 10 per leg): the side never alternates',
    ),
    _Gen(
      'lateral_steps',
      'lateral_steps',
      _n,
      () => _fixture('lateral_steps', _n, _lateralSteps()),
      note: 'out-and-back +-.11 body shift; first step is baseline',
      ceiling: _n - 1,
    ),
    _Gen(
      'marching_in_place',
      'marching_in_place',
      _n,
      () => _fixture('marching_in_place', _n, _kneeLift(_n, 16, .15)),
      note: 'knee lift .15; first step is baseline',
      ceiling: _n - 1,
    ),
    _Gen(
      'walking_in_place',
      'walking_in_place',
      _n,
      () => _fixture('walking_in_place', _n, _kneeLift(_n, 14, .05)),
      note: 'knee lift .05; first step is baseline',
      ceiling: _n - 1,
    ),
    _Gen(
      'running_in_place',
      'running_in_place',
      _n,
      () => _fixture('running_in_place', _n, _kneeLift(_n, 9, .09)),
      note: 'front view, knee lift .09; first step is baseline',
      ceiling: _n - 1,
    ),
    _Gen(
      'running_in_place',
      'running_in_place [side view]',
      _n,
      () => _fixture('running_in_place', _n, _runningSideView()),
      note: 'side view: horizontal knee swing only',
      ceiling: _n - 1,
    ),
    _Gen(
      'treadmill_running',
      'treadmill_running',
      _n,
      () => _fixture('treadmill_running', _n, _kneeLift(_n, 9, .09)),
      countOf: cyclesOf,
      note: 'unit is metres (virtual distance); steps compared via cycles',
      ceiling: _n - 1,
    ),
    _Gen(
      'high_knees',
      'high_knees',
      _n,
      () => _fixture('high_knees', _n, _kneeLift(_n, 10, .18)),
      note: 'each knee raise counts 1',
    ),
    _Gen(
      'side_lunges',
      'side_lunges',
      _n,
      () => _fixture('side_lunges', _n, _sideLunges()),
      note: 'IK legs, alternating sides, bent knee ~98 deg',
    ),
    _Gen(
      'sumo_squats',
      'sumo_squats',
      _n,
      () => _fixture('sumo_squats', _n, _sumoSquats()),
    ),
    _Gen(
      'arm_raises',
      'arm_raises',
      _n,
      () => _fixture('arm_raises', _n, _armRaises()),
    ),
    _Gen(
      'plank_hold',
      'plank_hold (10.5 s hold)',
      _n,
      () => _fixture('plank_hold', _n, _plankHold()),
      note:
          'counts seconds; 10.5 s held so startup latency does not read as a miss',
    ),
    _Gen(
      'squat_jacks',
      'squat_jacks',
      _n,
      () => _fixture('squat_jacks', _n, _squatJacks()),
    ),
    _Gen(
      'lunge_jumps',
      'lunge_jumps',
      _n,
      _lungeJumps10,
      note: 'SyntheticFixtureFactory.cleanLungeJump2Reps x5',
    ),
  ];

  const notGeneratable = <String, String>{
    'basketball_shot':
        'object-composition motion (ball dot + hoop), no pose validator',
  };

  test(
    'niche motion synthetic audit (prints a table; fails only if a fixture cannot be built)',
    () {
      final rows = <List<String>>[];
      final notes = <String>[];

      for (final g in gens) {
        final fx = g.build(); // throws -> test fails (fixture cannot be built)
        expect(fx.frames, isNotEmpty, reason: '${g.label}: no frames built');
        for (final f in fx.frames) {
          for (final l in f.landmarks.values) {
            expect(l.x.isFinite && l.y.isFinite, isTrue, reason: g.label);
          }
        }

        final debug = Platform.environment['AUDIT_DEBUG'] == g.id;
        final clean = _runValidator(g, fx, debug: debug);

        final isCycles = g.countOf != null;
        final spec = _runSpec(
          'server/worker/motion_specs/${g.id}.json',
          g.id,
          fx,
          cycles: isCycles,
        );
        final cand = _runSpec(
          'server/worker/motion_specs/candidates/${g.id}.json',
          g.id,
          fx,
          cycles: isCycles,
        );

        final degraded = <int>[];
        for (var seed = 1; seed <= 5; seed++) {
          final jit = FixtureAugmenter(seed: seed)
              .generateVariants(fx)
              .firstWhere((v) => v.id.endsWith('__coordinate_jitter'));
          final both = FixtureAugmenter(seed: seed + 100)
              .generateVariants(jit)
              .firstWhere((v) => v.id.endsWith('__drop_frames'));
          degraded.add(_runValidator(g, both).count);
        }
        final lo = degraded.reduce(math.min), hi = degraded.reduce(math.max);
        final robust = degraded.every((c) => c == g.ceiling);

        rows.add([
          g.label,
          '${g.expected}',
          '${clean.count}',
          spec == null ? '-' : '$spec',
          cand == null ? '' : '$cand',
          _verdict(clean.count, g.expected, g.ceiling),
          lo == hi ? '$lo' : '$lo-$hi',
          robust ? 'robust' : 'FRAGILE',
        ]);
        if (g.note.isNotEmpty) notes.add('${g.label}: ${g.note}');
        if (clean.note.isNotEmpty) notes.add('${g.label}: ${clean.note}');
      }

      for (final e in notGeneratable.entries) {
        rows.add([e.key, '-', '-', '-', '', 'NO VALIDATOR', '-', '-']);
        notes.add('${e.key}: ${e.value}');
      }

      const head = [
        'motion',
        'expected',
        'validator',
        'spec',
        'cand',
        'verdict',
        'degraded(5 seeds)',
        'fragile?',
      ];
      final w = List.generate(
        head.length,
        (c) => [
          head[c],
          ...rows.map((r) => r[c]),
        ].map((s) => s.length).reduce(math.max),
      );
      String line(List<String> r) =>
          [for (var c = 0; c < r.length; c++) r[c].padRight(w[c])].join(' | ');
      // ignore: avoid_print
      print(
        'Shell: NICHE MOTION SYNTHETIC AUDIT  (N=$_n reps, 30 fps, degraded = jitter +-.01 + 10% dropped frames)',
      );
      // ignore: avoid_print
      print('Shell: ${line(head)}');
      // ignore: avoid_print
      print('Shell: ${w.map((x) => '-' * x).join('-+-')}');
      for (final r in rows) {
        // ignore: avoid_print
        print('Shell: ${line(r)}');
      }
      // ignore: avoid_print
      print(
        'Shell: cadence motions (butt kicks, climbers, steps, march/walk/run, lateral): 10 steps performed, first step only sets the baseline side, so 9 is the mechanical ceiling',
      );
      for (final n in notes) {
        // ignore: avoid_print
        print('Shell: note  $n');
      }

      // ── false positives: stand still for 10 s with +-.01 coordinate jitter ──
      // ignore: avoid_print
      print('Shell: ');
      // ignore: avoid_print
      print(
        'Shell: FALSE POSITIVES  (subject stands still in the motion\'s start pose for 10 s, jitter +-.01, 5 seeds; any count > 0 is a free rep)',
      );
      final seen = <String>{};
      final fp = <String>[];
      for (final g in gens) {
        if (g.id == 'plank_hold' || !seen.add(g.id)) continue;
        final first = g.build().frames.first;
        final still = ReplayFixture(
          id: 'still_${g.id}',
          movement: g.id,
          expected: const FixtureExpected(reps: 0, shouldMatch: false),
          source: const FixtureSource(type: 'synthetic', name: 'still'),
          frames: [
            for (var i = 0; i < 300; i++)
              RecordedFrame(landmarks: first.landmarks, frameIndex: i),
          ],
        );
        final counts = <int>[];
        for (var seed = 1; seed <= 5; seed++) {
          final jit = FixtureAugmenter(seed: seed)
              .generateVariants(still)
              .firstWhere((v) => v.id.endsWith('__coordinate_jitter'));
          counts.add(_runValidator(g, jit).count);
        }
        fp.add('${g.id.padRight(20)} counts per seed: $counts');
      }
      for (final l in fp) {
        // ignore: avoid_print
        print('Shell: $l');
      }

      // ── amplitude sweeps: smallest motion that still counts ──
      // ignore: avoid_print
      print('Shell: ');
      // ignore: avoid_print
      print(
        'Shell: AMPLITUDE SWEEP  (amplitude in frame fractions; torso = .20; "clean" = no noise, "noisy" = all 5 jitter+drop seeds reach the ceiling)',
      );
      final sweeps =
          <(String, String, int, List<double>, ReplayFixture Function(double))>[
            (
              'marching_in_place',
              'knee lift',
              _n - 1,
              [.02, .03, .04, .05, .06, .08, .10, .12, .15],
              (a) => _fixture('marching_in_place', _n, _kneeLift(_n, 16, a)),
            ),
            (
              'step_ups',
              'knee lift',
              _n - 1,
              [.02, .03, .04, .05, .06, .08, .10, .12, .15],
              (a) => _fixture('step_ups', _n, _kneeLift(_n, 18, a)),
            ),
            (
              'walking_in_place',
              'knee lift',
              _n - 1,
              [.01, .015, .02, .025, .03, .04, .05, .07],
              (a) => _fixture('walking_in_place', _n, _kneeLift(_n, 14, a)),
            ),
            (
              'running_in_place',
              'knee lift',
              _n - 1,
              [.01, .02, .03, .04, .05, .06, .08, .10],
              (a) => _fixture('running_in_place', _n, _kneeLift(_n, 9, a)),
            ),
            (
              'high_knees',
              'knee lift',
              _n,
              [.04, .06, .08, .10, .12, .14, .18],
              (a) => _fixture('high_knees', _n, _kneeLift(_n, 10, a)),
            ),
            (
              'butt_kicks',
              'ankle rise',
              _n - 1,
              [.02, .04, .06, .08, .10, .14, .22],
              (a) => _fixture('butt_kicks', _n, _buttKicks(rise: a)),
            ),
            (
              'calf_raises',
              'body rise',
              _n,
              [.010, .015, .020, .025, .030, .040, .050],
              (a) => _fixture('calf_raises', _n, _calfRaises(rise: a)),
            ),
            (
              'lateral_steps',
              'body shift',
              _n - 1,
              [.03, .05, .07, .08, .09, .11, .15],
              (a) => _fixture('lateral_steps', _n, _lateralSteps(shift: a)),
            ),
          ];
      for (final (id, what, ceil, amps, mk) in sweeps) {
        final g = gens.firstWhere((x) => x.id == id);
        double? firstClean, firstNoisy;
        final trace = <String>[];
        for (final a in amps) {
          final fx = mk(a);
          final clean = _runValidator(g, fx).count;
          final noisy = <int>[];
          for (var seed = 1; seed <= 5; seed++) {
            final jit = FixtureAugmenter(seed: seed)
                .generateVariants(fx)
                .firstWhere((v) => v.id.endsWith('__coordinate_jitter'));
            final both = FixtureAugmenter(seed: seed + 100)
                .generateVariants(jit)
                .firstWhere((v) => v.id.endsWith('__drop_frames'));
            noisy.add(_runValidator(g, both).count);
          }
          if (firstClean == null && clean == ceil) firstClean = a;
          if (firstNoisy == null && noisy.every((c) => c == ceil)) {
            firstNoisy = a;
          }
          trace.add('$a:$clean/${noisy.join(",")}');
        }
        // ignore: avoid_print
        print(
          'Shell: ${id.padRight(18)} $what: first clean-exact at '
          '${firstClean ?? 'never'} (${firstClean == null ? '-' : (firstClean / .2).toStringAsFixed(2)} torso), '
          'first noisy-exact at ${firstNoisy ?? 'never'} (${firstNoisy == null ? '-' : (firstNoisy / .2).toStringAsFixed(2)} torso)',
        );
        // ignore: avoid_print
        print('Shell:    trace amp:clean/noisy-seeds  ${trace.join('  ')}');
      }
    },
  );
}
