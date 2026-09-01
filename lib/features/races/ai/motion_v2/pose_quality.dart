import 'dart:math' as math;

import '../../data/ai_motion_models.dart';

/// Shared camera-readiness / pose-quality evaluator.
///
/// Used by Teach Nuvo (capture + test) and — eventually — the preset AI Motion
/// Proof camera. It answers one question: *can this person be tracked reliably
/// right now, and if not, what should they do about it?*
///
/// It is deliberately permissive. It does NOT require every landmark for every
/// motion — an arm movement does not need ankles. It requires only enough body
/// structure for a stable root, a body scale, and the relevant visible limbs.
enum PoseReadiness {
  noPerson,
  tooClose,
  tooFar,
  partiallyOutOfFrame,
  lowVisibility,
  unstable,
  ready,
}

/// Understandable body regions for missing-joint reporting + region-error.
enum BodyRegion { head, leftArm, rightArm, torso, leftLeg, rightLeg }

const Map<BodyRegion, List<String>> kRegionJoints = {
  BodyRegion.head: ['nose', 'leftEar', 'rightEar', 'leftEye', 'rightEye'],
  BodyRegion.leftArm: ['leftShoulder', 'leftElbow', 'leftWrist'],
  BodyRegion.rightArm: ['rightShoulder', 'rightElbow', 'rightWrist'],
  BodyRegion.torso: ['leftShoulder', 'rightShoulder', 'leftHip', 'rightHip'],
  BodyRegion.leftLeg: ['leftHip', 'leftKnee', 'leftAnkle'],
  BodyRegion.rightLeg: ['rightHip', 'rightKnee', 'rightAnkle'],
};

String bodyRegionLabel(BodyRegion r) => switch (r) {
      BodyRegion.head => 'head',
      BodyRegion.leftArm => 'left arm',
      BodyRegion.rightArm => 'right arm',
      BodyRegion.torso => 'torso',
      BodyRegion.leftLeg => 'left leg',
      BodyRegion.rightLeg => 'right leg',
    };

class PoseQuality {
  const PoseQuality({
    required this.readiness,
    required this.guidance,
    required this.trackable,
    required this.visibleFraction,
    required this.bodyFillFraction,
    required this.missingRegions,
  });

  /// The current readiness state.
  final PoseReadiness readiness;

  /// One short instruction for the big on-screen message.
  final String guidance;

  /// True when there is enough structure (a hip/root, a scale reference, the
  /// visible limbs) to normalize and encode. Recognition should not run or
  /// count while this is false.
  final bool trackable;

  /// Fraction of the core skeleton (0..1) currently visible above threshold.
  final double visibleFraction;

  /// Visible-body bounding-box height as a fraction of the frame — the primary
  /// too-close / too-far signal.
  final double bodyFillFraction;

  /// Regions with no usable joints this frame (informational — does NOT by
  /// itself make the pose un-ready).
  final Set<BodyRegion> missingRegions;

  bool get isReady => readiness == PoseReadiness.ready;

  static const PoseQuality noFrame = PoseQuality(
    readiness: PoseReadiness.noPerson,
    guidance: 'Step into frame',
    trackable: false,
    visibleFraction: 0,
    bodyFillFraction: 0,
    missingRegions: {
      BodyRegion.head,
      BodyRegion.leftArm,
      BodyRegion.rightArm,
      BodyRegion.torso,
      BodyRegion.leftLeg,
      BodyRegion.rightLeg,
    },
  );

  Map<String, dynamic> toJson() => {
        'readiness': readiness.name,
        'guidance': guidance,
        'trackable': trackable,
        'visibleFraction': double.parse(visibleFraction.toStringAsFixed(3)),
        'bodyFillFraction': double.parse(bodyFillFraction.toStringAsFixed(3)),
        'missingRegions': [for (final r in missingRegions) bodyRegionLabel(r)],
      };
}

const List<String> _coreJoints = [
  'nose',
  'leftShoulder', 'rightShoulder',
  'leftElbow', 'rightElbow',
  'leftWrist', 'rightWrist',
  'leftHip', 'rightHip',
  'leftKnee', 'rightKnee',
  'leftAnkle', 'rightAnkle',
];

const double _minLikelihood = 0.35;

// Torso length (shoulder-center → hip-center) in image-normalized units.
const double _torsoTooFar = 0.14; // person is tiny / unreliable
const double _torsoTooClose = 0.62; // person fills the frame
const double _fillTooClose = 0.95;
const double _edge = 0.02;
const double _rootJitterUnstable = 0.05; // per-frame root move over recent window

({double x, double y})? _p(NuvoPoseFrame f, String name) {
  final pt = f.points[name];
  if (pt == null || pt.likelihood < _minLikelihood) return null;
  return (x: pt.x, y: pt.y);
}

({double x, double y})? _mid(NuvoPoseFrame f, String a, String b) {
  final pa = _p(f, a), pb = _p(f, b);
  if (pa != null && pb != null) {
    return (x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2);
  }
  return pa ?? pb;
}

/// Evaluate the newest [frame]. [recent] (a few of the latest frames, oldest
/// first) is used only for the stability check.
PoseQuality evaluatePoseQuality(
  NuvoPoseFrame? frame, {
  List<NuvoPoseFrame> recent = const [],
}) {
  if (frame == null) return PoseQuality.noFrame;

  final visible = <String, ({double x, double y})>{};
  for (final j in _coreJoints) {
    final p = _p(frame, j);
    if (p != null) visible[j] = p;
  }
  final visibleFraction = visible.length / _coreJoints.length;

  final missing = <BodyRegion>{};
  for (final entry in kRegionJoints.entries) {
    final any = entry.value.any((n) => _p(frame, n) != null);
    if (!any) missing.add(entry.key);
  }

  PoseQuality build(PoseReadiness r, String g, {bool trackable = false}) {
    // bbox fill for the report even on failure paths
    var fill = 0.0;
    if (visible.length >= 2) {
      final ys = visible.values.map((v) => v.y).toList();
      fill = (ys.reduce(math.max) - ys.reduce(math.min)).clamp(0.0, 1.0);
    }
    return PoseQuality(
      readiness: r,
      guidance: g,
      trackable: trackable,
      visibleFraction: visibleFraction,
      bodyFillFraction: fill,
      missingRegions: missing,
    );
  }

  if (visible.length < 4) {
    return build(PoseReadiness.noPerson, 'Step into frame');
  }

  final hipCenter = _mid(frame, 'leftHip', 'rightHip');
  final shoulderCenter = _mid(frame, 'leftShoulder', 'rightShoulder');
  if (hipCenter == null || shoulderCenter == null) {
    return build(PoseReadiness.lowVisibility,
        'Make sure your head, shoulders and hips are visible');
  }

  final torso = math.sqrt(
    math.pow(shoulderCenter.x - hipCenter.x, 2) +
        math.pow(shoulderCenter.y - hipCenter.y, 2),
  );

  // Body clipped at a frame edge?
  var clipped = 0;
  for (final v in visible.values) {
    if (v.x <= _edge || v.x >= 1 - _edge || v.y <= _edge || v.y >= 1 - _edge) {
      clipped++;
    }
  }
  final ys = visible.values.map((v) => v.y).toList();
  final fill = (ys.reduce(math.max) - ys.reduce(math.min)).clamp(0.0, 1.0);

  if (clipped >= 3 || fill >= _fillTooClose) {
    // A lot of the body is against the edge — either too close or off to a side.
    if (torso >= _torsoTooClose || fill >= _fillTooClose) {
      return build(PoseReadiness.tooClose, 'Move back');
    }
    return build(PoseReadiness.partiallyOutOfFrame, 'Move into frame');
  }

  if (torso < _torsoTooFar) {
    return build(PoseReadiness.tooFar, 'Step closer');
  }
  if (torso > _torsoTooClose) {
    return build(PoseReadiness.tooClose, 'Move back');
  }

  // Stability — root should not be leaping around.
  if (recent.length >= 3) {
    double maxJump = 0;
    ({double x, double y})? prev;
    for (final f in recent) {
      final r = _mid(f, 'leftHip', 'rightHip');
      if (r == null) continue;
      if (prev != null) {
        final d = math.sqrt(
          math.pow(r.x - prev.x, 2) + math.pow(r.y - prev.y, 2),
        );
        if (d > maxJump) maxJump = d;
      }
      prev = r;
    }
    if (maxJump > _rootJitterUnstable) {
      return build(PoseReadiness.unstable, 'Hold still for a moment', trackable: true);
    }
  }

  return build(PoseReadiness.ready, 'Ready', trackable: true);
}
