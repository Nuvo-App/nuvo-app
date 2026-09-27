import 'dart:math' as math;

import 'package:rive/rive.dart';

/// A pose for the side-view treadmill rig.
///
/// The side asset uses degrees for angles and the exported Normalize bindings
/// use 100 as the authored neutral scale. [rootYOffset] is presentation-only;
/// rootX/rootY are initialized once to the authored neutral position because
/// this asset exports both properties with zero data-binding defaults.
class SideRigPose {
  const SideRigPose({
    required this.torsoAngle,
    required this.frontShoulderAngle,
    required this.frontElbowAngle,
    required this.backShoulderAngle,
    required this.backElbowAngle,
    required this.frontHipAngle,
    required this.frontKneeAngle,
    required this.backHipAngle,
    required this.backKneeAngle,
    required this.frontUpperArmScale,
    required this.frontLowerArmScale,
    required this.backUpperArmScale,
    required this.backLowerArmScale,
    required this.frontUpperLegScale,
    required this.frontLowerLegScale,
    required this.backUpperLegScale,
    required this.backLowerLegScale,
    required this.torsoScaleY,
    this.rootYOffset = 0,
  });

  static const base = SideRigPose(
    torsoAngle: 0,
    frontShoulderAngle: 90,
    frontElbowAngle: 0,
    backShoulderAngle: 90,
    backElbowAngle: 0,
    frontHipAngle: 90,
    frontKneeAngle: 0,
    backHipAngle: 90,
    backKneeAngle: 0,
    frontUpperArmScale: 100,
    frontLowerArmScale: 100,
    backUpperArmScale: 100,
    backLowerArmScale: 100,
    frontUpperLegScale: 100,
    frontLowerLegScale: 100,
    backUpperLegScale: 100,
    backLowerLegScale: 100,
    torsoScaleY: 100,
  );

  final double torsoAngle;
  final double frontShoulderAngle;
  final double frontElbowAngle;
  final double backShoulderAngle;
  final double backElbowAngle;
  final double frontHipAngle;
  final double frontKneeAngle;
  final double backHipAngle;
  final double backKneeAngle;
  final double frontUpperArmScale;
  final double frontLowerArmScale;
  final double backUpperArmScale;
  final double backLowerArmScale;
  final double frontUpperLegScale;
  final double frontLowerLegScale;
  final double backUpperLegScale;
  final double backLowerLegScale;
  final double torsoScaleY;
  final double rootYOffset;

  /// Parses a remotely-fetched keyframe. Missing/invalid fields fall back to
  /// [base]'s value for that field — this only ever drives a decorative
  /// preview, so a partial/malformed remote keyframe degrades to a plausible
  /// pose rather than throwing.
  factory SideRigPose.fromJson(Map<String, dynamic> json) {
    double field(String key, double fallback) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble() : fallback;
    }

    return SideRigPose(
      torsoAngle: field('torsoAngle', base.torsoAngle),
      frontShoulderAngle: field('frontShoulderAngle', base.frontShoulderAngle),
      frontElbowAngle: field('frontElbowAngle', base.frontElbowAngle),
      backShoulderAngle: field('backShoulderAngle', base.backShoulderAngle),
      backElbowAngle: field('backElbowAngle', base.backElbowAngle),
      frontHipAngle: field('frontHipAngle', base.frontHipAngle),
      frontKneeAngle: field('frontKneeAngle', base.frontKneeAngle),
      backHipAngle: field('backHipAngle', base.backHipAngle),
      backKneeAngle: field('backKneeAngle', base.backKneeAngle),
      frontUpperArmScale: field('frontUpperArmScale', base.frontUpperArmScale),
      frontLowerArmScale: field('frontLowerArmScale', base.frontLowerArmScale),
      backUpperArmScale: field('backUpperArmScale', base.backUpperArmScale),
      backLowerArmScale: field('backLowerArmScale', base.backLowerArmScale),
      frontUpperLegScale: field('frontUpperLegScale', base.frontUpperLegScale),
      frontLowerLegScale: field('frontLowerLegScale', base.frontLowerLegScale),
      backUpperLegScale: field('backUpperLegScale', base.backUpperLegScale),
      backLowerLegScale: field('backLowerLegScale', base.backLowerLegScale),
      torsoScaleY: field('torsoScaleY', base.torsoScaleY),
      rootYOffset: field('rootYOffset', base.rootYOffset),
    );
  }

  Map<String, double> toJson() => {
    'torsoAngle': torsoAngle,
    'frontShoulderAngle': frontShoulderAngle,
    'frontElbowAngle': frontElbowAngle,
    'backShoulderAngle': backShoulderAngle,
    'backElbowAngle': backElbowAngle,
    'frontHipAngle': frontHipAngle,
    'frontKneeAngle': frontKneeAngle,
    'backHipAngle': backHipAngle,
    'backKneeAngle': backKneeAngle,
    'frontUpperArmScale': frontUpperArmScale,
    'frontLowerArmScale': frontLowerArmScale,
    'backUpperArmScale': backUpperArmScale,
    'backLowerArmScale': backLowerArmScale,
    'frontUpperLegScale': frontUpperLegScale,
    'frontLowerLegScale': frontLowerLegScale,
    'backUpperLegScale': backUpperLegScale,
    'backLowerLegScale': backLowerLegScale,
    'torsoScaleY': torsoScaleY,
    'rootYOffset': rootYOffset,
  };

  SideRigPose lerp(SideRigPose other, double t) {
    final amount = t.isFinite ? t.clamp(0.0, 1.0) : 0.0;
    return SideRigPose(
      torsoAngle: _lerp(torsoAngle, other.torsoAngle, amount),
      frontShoulderAngle: _lerp(
        frontShoulderAngle,
        other.frontShoulderAngle,
        amount,
      ),
      frontElbowAngle: _lerp(frontElbowAngle, other.frontElbowAngle, amount),
      backShoulderAngle: _lerp(
        backShoulderAngle,
        other.backShoulderAngle,
        amount,
      ),
      backElbowAngle: _lerp(backElbowAngle, other.backElbowAngle, amount),
      frontHipAngle: _lerp(frontHipAngle, other.frontHipAngle, amount),
      frontKneeAngle: _lerp(frontKneeAngle, other.frontKneeAngle, amount),
      backHipAngle: _lerp(backHipAngle, other.backHipAngle, amount),
      backKneeAngle: _lerp(backKneeAngle, other.backKneeAngle, amount),
      frontUpperArmScale: _lerp(
        frontUpperArmScale,
        other.frontUpperArmScale,
        amount,
      ),
      frontLowerArmScale: _lerp(
        frontLowerArmScale,
        other.frontLowerArmScale,
        amount,
      ),
      backUpperArmScale: _lerp(
        backUpperArmScale,
        other.backUpperArmScale,
        amount,
      ),
      backLowerArmScale: _lerp(
        backLowerArmScale,
        other.backLowerArmScale,
        amount,
      ),
      frontUpperLegScale: _lerp(
        frontUpperLegScale,
        other.frontUpperLegScale,
        amount,
      ),
      frontLowerLegScale: _lerp(
        frontLowerLegScale,
        other.frontLowerLegScale,
        amount,
      ),
      backUpperLegScale: _lerp(
        backUpperLegScale,
        other.backUpperLegScale,
        amount,
      ),
      backLowerLegScale: _lerp(
        backLowerLegScale,
        other.backLowerLegScale,
        amount,
      ),
      torsoScaleY: _lerp(torsoScaleY, other.torsoScaleY, amount),
      rootYOffset: _lerp(rootYOffset, other.rootYOffset, amount),
    );
  }

  bool get isFinite => [
    torsoAngle,
    frontShoulderAngle,
    frontElbowAngle,
    backShoulderAngle,
    backElbowAngle,
    frontHipAngle,
    frontKneeAngle,
    backHipAngle,
    backKneeAngle,
    frontUpperArmScale,
    frontLowerArmScale,
    backUpperArmScale,
    backLowerArmScale,
    frontUpperLegScale,
    frontLowerLegScale,
    backUpperLegScale,
    backLowerLegScale,
    torsoScaleY,
    rootYOffset,
  ].every((value) => value.isFinite);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Cached property handles for the side-view View Model.
class SideRigPoseController {
  SideRigPoseController(ViewModelInstance instance) : _instance = instance {
    for (final name in _requiredProperties) {
      if (_read(instance, name) == null) missingProperties.add(name);
    }
  }

  static const _requiredProperties = [
    'torsoAngle',
    'frontShoulderAngle',
    'frontElbowAngle',
    'backShoulderAngle',
    'backElbowAngle',
    'frontHipAngle',
    'frontKneeAngle',
    'backHipAngle',
    'backKneeAngle',
    'frontUpperArmScale',
    'frontLowerArmScale',
    'backUpperArmScale',
    'backLowerArmScale',
    'frontUpperLegScale',
    'frontLowerLegScale',
    'backUpperLegScale',
    'backLowerLegScale',
    'torsoScaleY',
  ];

  static const _baseRootX = 244.5;
  static const _baseRootY = 277.0;

  final ViewModelInstance _instance;
  final missingProperties = <String>[];

  late final ViewModelInstanceNumber? _torsoAngle = _read(
    _instance,
    'torsoAngle',
  );
  late final ViewModelInstanceNumber? _frontShoulderAngle = _read(
    _instance,
    'frontShoulderAngle',
  );
  late final ViewModelInstanceNumber? _frontElbowAngle = _read(
    _instance,
    'frontElbowAngle',
  );
  late final ViewModelInstanceNumber? _backShoulderAngle = _read(
    _instance,
    'backShoulderAngle',
  );
  late final ViewModelInstanceNumber? _backElbowAngle = _read(
    _instance,
    'backElbowAngle',
  );
  late final ViewModelInstanceNumber? _frontHipAngle = _read(
    _instance,
    'frontHipAngle',
  );
  late final ViewModelInstanceNumber? _frontKneeAngle = _read(
    _instance,
    'frontKneeAngle',
  );
  late final ViewModelInstanceNumber? _backHipAngle = _read(
    _instance,
    'backHipAngle',
  );
  late final ViewModelInstanceNumber? _backKneeAngle = _read(
    _instance,
    'backKneeAngle',
  );
  late final ViewModelInstanceNumber? _frontUpperArmScale = _read(
    _instance,
    'frontUpperArmScale',
  );
  late final ViewModelInstanceNumber? _frontLowerArmScale = _read(
    _instance,
    'frontLowerArmScale',
  );
  late final ViewModelInstanceNumber? _backUpperArmScale = _read(
    _instance,
    'backUpperArmScale',
  );
  late final ViewModelInstanceNumber? _backLowerArmScale = _read(
    _instance,
    'backLowerArmScale',
  );
  late final ViewModelInstanceNumber? _frontUpperLegScale = _read(
    _instance,
    'frontUpperLegScale',
  );
  late final ViewModelInstanceNumber? _frontLowerLegScale = _read(
    _instance,
    'frontLowerLegScale',
  );
  late final ViewModelInstanceNumber? _backUpperLegScale = _read(
    _instance,
    'backUpperLegScale',
  );
  late final ViewModelInstanceNumber? _backLowerLegScale = _read(
    _instance,
    'backLowerLegScale',
  );
  late final ViewModelInstanceNumber? _torsoScaleY = _read(
    _instance,
    'torsoScaleY',
  );
  late final ViewModelInstanceNumber? _rootX = _read(_instance, 'rootX');
  late final ViewModelInstanceNumber? _rootY = _read(_instance, 'rootY');
  var _rootPositionInitialized = false;

  bool get isUsable => missingProperties.isEmpty;

  void apply(SideRigPose pose) {
    if (!pose.isFinite || !isUsable) return;
    if (!_rootPositionInitialized) {
      _rootX?.value = _baseRootX;
      _rootY?.value = _baseRootY;
      _rootPositionInitialized = true;
    }
    _torsoAngle!.value = pose.torsoAngle;
    _frontShoulderAngle!.value = pose.frontShoulderAngle;
    _frontElbowAngle!.value = pose.frontElbowAngle;
    _backShoulderAngle!.value = pose.backShoulderAngle;
    _backElbowAngle!.value = pose.backElbowAngle;
    _frontHipAngle!.value = pose.frontHipAngle;
    _frontKneeAngle!.value = pose.frontKneeAngle;
    _backHipAngle!.value = pose.backHipAngle;
    _backKneeAngle!.value = pose.backKneeAngle;
    _frontUpperArmScale!.value = pose.frontUpperArmScale;
    _frontLowerArmScale!.value = pose.frontLowerArmScale;
    _backUpperArmScale!.value = pose.backUpperArmScale;
    _backLowerArmScale!.value = pose.backLowerArmScale;
    _frontUpperLegScale!.value = pose.frontUpperLegScale;
    _frontLowerLegScale!.value = pose.frontLowerLegScale;
    _backUpperLegScale!.value = pose.backUpperLegScale;
    _backLowerLegScale!.value = pose.backLowerLegScale;
    _torsoScaleY!.value = pose.torsoScaleY;
    _instance.requestAdvance();
  }

  ViewModelInstanceNumber? _read(ViewModelInstance instance, String name) =>
      instance.number(name);
}

/// One representative treadmill gait cycle derived from Nuvo's real fixture:
/// 890 frames over 38.8 seconds and roughly 77 alternating steps, or about a
/// one-second full gait cycle. Seven static poses preserve the passing and
/// reversal phases instead of reducing running to two poses.
///
/// The side rig's front/back arm controls are authored as mirrored chains. The
/// elbow values therefore intentionally use opposite signs: applying the same
/// sign to both elbows makes both forearms fold toward the same side of the
/// silhouette instead of producing a running arm swing.
class TreadmillRunningSideSequence {
  static const duration = Duration(milliseconds: 1000);

  static final _keyframes = <SideRigPose>[
    _pose(
      frontHipAngle: 128,
      frontKneeAngle: 18,
      backHipAngle: 52,
      backKneeAngle: 32,
      frontShoulderAngle: 58,
      frontElbowAngle: -42,
      backShoulderAngle: 122,
      backElbowAngle: 42,
    ),
    _pose(
      frontHipAngle: 136,
      frontKneeAngle: 28,
      backHipAngle: 44,
      backKneeAngle: 38,
      frontShoulderAngle: 52,
      frontElbowAngle: -48,
      backShoulderAngle: 128,
      backElbowAngle: 48,
    ),
    _pose(
      frontHipAngle: 90,
      frontKneeAngle: 22,
      backHipAngle: 90,
      backKneeAngle: 22,
      frontShoulderAngle: 78,
      frontElbowAngle: -30,
      backShoulderAngle: 102,
      backElbowAngle: 30,
    ),
    _pose(
      frontHipAngle: 52,
      frontKneeAngle: 38,
      backHipAngle: 128,
      backKneeAngle: 18,
      frontShoulderAngle: 122,
      frontElbowAngle: 42,
      backShoulderAngle: 58,
      backElbowAngle: -42,
    ),
    _pose(
      frontHipAngle: 44,
      frontKneeAngle: 38,
      backHipAngle: 136,
      backKneeAngle: 28,
      frontShoulderAngle: 128,
      frontElbowAngle: 48,
      backShoulderAngle: 52,
      backElbowAngle: -48,
    ),
    _pose(
      frontHipAngle: 90,
      frontKneeAngle: 22,
      backHipAngle: 90,
      backKneeAngle: 22,
      frontShoulderAngle: 102,
      frontElbowAngle: 30,
      backShoulderAngle: 78,
      backElbowAngle: -30,
    ),
    _pose(
      frontHipAngle: 128,
      frontKneeAngle: 18,
      backHipAngle: 52,
      backKneeAngle: 32,
      frontShoulderAngle: 58,
      frontElbowAngle: -42,
      backShoulderAngle: 122,
      backElbowAngle: 42,
    ),
  ];

  SideRigPose poseAt(double normalizedTime) {
    final t = normalizedTime.isFinite
        ? normalizedTime - normalizedTime.floorToDouble()
        : 0.0;
    final scaled = t * (_keyframes.length - 1);
    final index = scaled.floor().clamp(0, _keyframes.length - 2);
    final local = _smoothstep(scaled - index);
    final pose = _keyframes[index].lerp(_keyframes[index + 1], local);
    final bounce = math.sin(2 * math.pi * t);
    return SideRigPose(
      torsoAngle: pose.torsoAngle,
      frontShoulderAngle: pose.frontShoulderAngle,
      frontElbowAngle: pose.frontElbowAngle,
      backShoulderAngle: pose.backShoulderAngle,
      backElbowAngle: pose.backElbowAngle,
      frontHipAngle: pose.frontHipAngle,
      frontKneeAngle: pose.frontKneeAngle,
      backHipAngle: pose.backHipAngle,
      backKneeAngle: pose.backKneeAngle,
      frontUpperArmScale: pose.frontUpperArmScale,
      frontLowerArmScale: pose.frontLowerArmScale,
      backUpperArmScale: pose.backUpperArmScale,
      backLowerArmScale: pose.backLowerArmScale,
      frontUpperLegScale: pose.frontUpperLegScale,
      frontLowerLegScale: pose.frontLowerLegScale,
      backUpperLegScale: pose.backUpperLegScale,
      backLowerLegScale: pose.backLowerLegScale,
      torsoScaleY: pose.torsoScaleY,
      rootYOffset: -6 * bounce * bounce,
    );
  }
}

SideRigPose _pose({
  double torsoAngle = 0,
  double frontShoulderAngle = 90,
  double frontElbowAngle = 20,
  double backShoulderAngle = 90,
  double backElbowAngle = 20,
  double frontHipAngle = 90,
  double frontKneeAngle = 20,
  double backHipAngle = 90,
  double backKneeAngle = 20,
}) => SideRigPose(
  torsoAngle: torsoAngle,
  frontShoulderAngle: frontShoulderAngle,
  frontElbowAngle: frontElbowAngle,
  backShoulderAngle: backShoulderAngle,
  backElbowAngle: backElbowAngle,
  frontHipAngle: frontHipAngle,
  frontKneeAngle: frontKneeAngle,
  backHipAngle: backHipAngle,
  backKneeAngle: backKneeAngle,
  frontUpperArmScale: 100,
  frontLowerArmScale: 100,
  backUpperArmScale: 100,
  backLowerArmScale: 100,
  frontUpperLegScale: 100,
  frontLowerLegScale: 100,
  backUpperLegScale: 100,
  backLowerLegScale: 100,
  torsoScaleY: 100,
);

double _smoothstep(double t) {
  final amount = t.clamp(0.0, 1.0);
  return amount * amount * (3 - 2 * amount);
}
