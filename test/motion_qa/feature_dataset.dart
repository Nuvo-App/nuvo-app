import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'replay_fixture.dart';
import 'motion_intelligence.dart';

// ============================================================================
// M1.2 PHASE 1: FEATURE DATASET
// ============================================================================
// Extracts a comprehensive numerical feature vector from each frame
// of every pose fixture. Persists to JSON for reuse across model experiments.
// ============================================================================

/// All 12 landmark names in canonical order.
const kLandmarkNames = [
  'leftShoulder', 'rightShoulder',
  'leftElbow', 'rightElbow',
  'leftWrist', 'rightWrist',
  'leftHip', 'rightHip',
  'leftKnee', 'rightKnee',
  'leftAnkle', 'rightAnkle',
];

/// Feature vector extracted from a single frame.
class FrameFeatures {
  final String clipId;
  final int frameIndex;
  final String movement;
  final bool isTarget;
  final String split;
  final List<double> features;
  final List<String> featureNames;

  FrameFeatures({
    required this.clipId,
    required this.frameIndex,
    required this.movement,
    required this.isTarget,
    required this.split,
    required this.features,
    required this.featureNames,
  });

  Map<String, double> asMap() {
    final m = <String, double>{};
    for (var i = 0; i < featureNames.length && i < features.length; i++) {
      m[featureNames[i]] = features[i];
    }
    return m;
  }
}

/// Feature extraction pipeline.
class FeatureExtractor {
  final List<String> featureNames = [];
  bool _namesInitialized = false;

  /// Extract features from a single pose frame.
  /// Returns a fixed-length feature vector.
  List<double> extract(NuvoPoseFrame frame, List<NuvoPoseFrame> history) {
    final features = <double>[];

    // Helper to get point or NaN
    NuvoPosePoint? p(String name) => frame.point(name);
    double px(String name) => p(name)?.x ?? double.nan;
    double py(String name) => p(name)?.y ?? double.nan;
    double pl(String name) => p(name)?.likelihood ?? 0.0;

    // Previous frame for velocity
    NuvoPoseFrame? prev = history.isNotEmpty ? history.last : null;
    double ppy(String name) => prev?.point(name)?.y ?? double.nan;

    // Frame 2 frames ago for acceleration
    NuvoPoseFrame? prev2 = history.length > 1 ? history[history.length - 2] : null;
    double p2y(String name) => prev2?.point(name)?.y ?? double.nan;

    // === POSE GEOMETRY (normalized coordinates) ===
    // Raw coordinates (12 landmarks x 3 = 36)
    for (final name in kLandmarkNames) {
      features.add(px(name));
      features.add(py(name));
      features.add(pl(name)); // likelihood instead of z for usefulness
    }

    // === TORSO-RELATIVE COORDINATES ===
    // Center = midpoint of hips
    final hipCx = (px('leftHip') + px('rightHip')) / 2;
    final hipCy = (py('leftHip') + py('rightHip')) / 2;
    for (final name in kLandmarkNames) {
      features.add(px(name) - hipCx); // relative X
      features.add(py(name) - hipCy); // relative Y
    }

    // === HIP-RELATIVE COORDINATES (lower body) ===
    for (final name in ['leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle']) {
      features.add(px(name) - px('leftHip'));   // relative to left hip
      features.add(py(name) - py('leftHip'));
      features.add(px(name) - px('rightHip'));  // relative to right hip
      features.add(py(name) - py('rightHip'));
    }

    // === SHOULDER-RELATIVE COORDINATES ===
    final shldrCx = (px('leftShoulder') + px('rightShoulder')) / 2;
    final shldrCy = (py('leftShoulder') + py('rightShoulder')) / 2;
    for (final name in ['leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle']) {
      features.add(px(name) - shldrCx);
      features.add(py(name) - shldrCy);
    }

    // === ANGLES ===
    // Knee angles (hip-knee-ankle)
    features.add(_angle(px('leftHip'), py('leftHip'), px('leftKnee'), py('leftKnee'), px('leftAnkle'), py('leftAnkle')));
    features.add(_angle(px('rightHip'), py('rightHip'), px('rightKnee'), py('rightKnee'), px('rightAnkle'), py('rightAnkle')));
    // Hip angles (shoulder-hip-knee)
    features.add(_angle(px('leftShoulder'), py('leftShoulder'), px('leftHip'), py('leftHip'), px('leftKnee'), py('leftKnee')));
    features.add(_angle(px('rightShoulder'), py('rightShoulder'), px('rightHip'), py('rightHip'), px('rightKnee'), py('rightKnee')));
    // Torso angle (hip midpoint to shoulder midpoint)
    features.add(_angle2(hipCx, hipCy, shldrCx, shldrCy));

    // === VELOCITY ===
    // Torso velocity
    final torsoVy = _safeDelta(hipCy, _prevVal(prev, 'leftHip', 'y', 'rightHip', 'y'));
    final torsoVx = _safeDelta(hipCx, _prevVal(prev, 'leftHip', 'x', 'rightHip', 'x'));
    features.add(torsoVx);
    features.add(torsoVy);

    // Hip velocity
    features.add(_safeDelta(py('leftHip'), ppy('leftHip')));
    features.add(_safeDelta(py('rightHip'), ppy('rightHip')));

    // Shoulder velocity
    features.add(_safeDelta(shldrCy, _prevVal(prev, 'leftShoulder', 'y', 'rightShoulder', 'y')));
    features.add(_safeDelta(shldrCx, _prevVal(prev, 'leftShoulder', 'x', 'rightShoulder', 'x')));

    // Ankle velocity
    features.add(_safeDelta(py('leftAnkle'), ppy('leftAnkle')));
    features.add(_safeDelta(py('rightAnkle'), ppy('rightAnkle')));
    final ankleCy = (py('leftAnkle') + py('rightAnkle')) / 2;
    features.add(_safeDelta(ankleCy, _prevVal(prev, 'leftAnkle', 'y', 'rightAnkle', 'y')));

    // Knee velocity
    features.add(_safeDelta(py('leftKnee'), ppy('leftKnee')));
    features.add(_safeDelta(py('rightKnee'), ppy('rightKnee')));

    // === BODY-RELATIVE VELOCITY (minus torso) ===
    features.add(_safeDelta(py('leftAnkle'), ppy('leftAnkle')) - torsoVy);
    features.add(_safeDelta(py('rightAnkle'), ppy('rightAnkle')) - torsoVy);
    features.add(_safeDelta(ankleCy, _prevVal(prev, 'leftAnkle', 'y', 'rightAnkle', 'y')) - torsoVy);
    features.add(_safeDelta(py('leftHip'), ppy('leftHip')) - torsoVy);
    features.add(_safeDelta(py('rightHip'), ppy('rightHip')) - torsoVy);

    // Foot center minus torso velocity
    final footCx = (px('leftAnkle') + px('rightAnkle')) / 2;
    features.add(_safeDelta(footCx, _prevVal(prev, 'leftAnkle', 'x', 'rightAnkle', 'x')) - torsoVx);

    // === ACCELERATION ===
    // Vertical acceleration (hip)
    final hipVy = _safeDelta(py('leftHip'), ppy('leftHip'));
    final prevHipVy = prev2 != null ? _safeDelta(ppy('leftHip'), p2y('leftHip')) : 0.0;
    features.add(hipVy - prevHipVy);

    // Relative vertical acceleration (ankle minus torso)
    final ankleVy = _safeDelta(ankleCy, _prevVal(prev, 'leftAnkle', 'y', 'rightAnkle', 'y'));
    final prevAnkleVy = prev2 != null
        ? _safeDelta(_prevVal(prev2, 'leftAnkle', 'y', 'rightAnkle', 'y'),
                     _prevVal2(prev2, 'leftAnkle', 'y', 'rightAnkle', 'y'))
        : 0.0;
    features.add((ankleVy - torsoVy) - (prevAnkleVy - prevHipVy));

    // === STANCE ===
    final footSep = (px('leftAnkle') - px('rightAnkle')).abs();
    final torsoH = (hipCy - shldrCy).abs().clamp(0.12, 0.6);
    final normStanceWidth = footSep / torsoH;
    features.add(footSep);
    features.add(normStanceWidth);

    // Stance width velocity
    final prevFootSep = prev != null
        ? ((prev.point('leftAnkle')?.x ?? 0) - (prev.point('rightAnkle')?.x ?? 0)).abs()
        : footSep;
    features.add(footSep - prevFootSep);

    // Split-stance score (asymmetry in foot X)
    final footAsym = ((px('leftAnkle') + px('rightAnkle')) / 2 - hipCx).abs();
    features.add(footAsym);

    // === COMPRESSION ===
    final kneeCy = (py('leftKnee') + py('rightKnee')) / 2;
    final kneeCompression = (kneeCy - hipCy).abs(); // knee-hip distance
    features.add(kneeCompression);

    final hipDescent = hipCy; // absolute Y (higher = lower in image = more descent)
    features.add(hipDescent);

    final bodyHeight = torsoH; // torso-normalized body height
    features.add(bodyHeight);

    // Compression velocity (hip descent rate)
    features.add(torsoVy); // already computed, but include as compression velocity

    // HKR (hip-knee ratio) — key concept feature
    final hkr = ((kneeCy - hipCy) / torsoH).clamp(-2.0, 3.0);
    features.add(hkr);

    // === TEMPORAL (rolling statistics over last N frames) ===
    final h5 = history.length > 5 ? history.sublist(history.length - 5) : history;
    final h10 = history.length > 10 ? history.sublist(history.length - 10) : history;

    // Rolling mean of hip Y
    features.add(_rollingMean(h5, 'leftHip', 'y', 'rightHip', 'y'));
    // Rolling variance of hip Y
    features.add(_rollingVar(h5, 'leftHip', 'y', 'rightHip', 'y'));
    // Rolling mean of ankle Y
    features.add(_rollingMean(h5, 'leftAnkle', 'y', 'rightAnkle', 'y'));
    // Recent min of hip Y (highest point)
    features.add(_recentMin(h10, 'leftHip', 'y', 'rightHip', 'y'));
    // Recent max of hip Y (lowest point)
    features.add(_recentMax(h10, 'leftHip', 'y', 'rightHip', 'y'));
    // Delta over 5 frames (hip Y)
    features.add(_deltaN(h5, 'leftHip', 'y', 'rightHip', 'y'));
    // Direction changes in hip Y over last 10 frames
    features.add(_directionChanges(h10, 'leftHip', 'y', 'rightHip', 'y'));
    // Local peaks in hip Y over last 10 frames
    features.add(_localPeaks(h10, 'leftHip', 'y', 'rightHip', 'y'));

    // === POSE QUALITY ===
    // Average landmark confidence
    double totalConf = 0;
    int confCount = 0;
    for (final name in kLandmarkNames) {
      final lp = pl(name);
      if (lp == lp) { // not NaN
        totalConf += lp;
        confCount++;
      }
    }
    features.add(confCount > 0 ? totalConf / confCount : 0);

    // Missing landmark count
    int missing = 0;
    for (final name in kLandmarkNames) {
      if (p(name) == null) missing++;
    }
    features.add(missing.toDouble());

    // Temporal jitter (frame-to-frame landmark displacement variance)
    if (prev != null) {
      double jitter = 0;
      int jCount = 0;
      for (final name in kLandmarkNames) {
        final cp = p(name);
        final pp = prev.point(name);
        if (cp != null && pp != null) {
          jitter += ((cp.x - pp.x).abs() + (cp.y - pp.y).abs());
          jCount++;
        }
      }
      features.add(jCount > 0 ? jitter / jCount : 0);
    } else {
      features.add(0.0);
    }

    // Body-scale stability (torso height variance over last 5 frames)
    features.add(_torsoHeightVar(h5));

    // === CAMERA/GLOBAL MOTION ===
    // Estimated global translation (shoulder midpoint velocity)
    features.add(torsoVx); // global X translation
    features.add(torsoVy); // global Y translation
    // Residual motion after subtraction (ankle velocity minus torso velocity)
    features.add((ankleVy - torsoVy).abs());

    // === EXISTING CONCEPTS ===
    // Compression confidence (how deep the squat is)
    features.add(hkr < 0.50 ? 1.0 : 0.0);
    // Ascent confidence (hip moving up rapidly)
    features.add(torsoVy < -0.010 ? 1.0 : 0.0);
    // Airborne confidence (ankle above baseline)
    features.add(ankleCy < hipCy - torsoH * 0.15 ? 1.0 : 0.0);
    // Landing confidence (ankle descending after airborne)
    features.add(ankleVy > 0.005 ? 1.0 : 0.0);
    // Standing confidence
    features.add(hkr > 0.55 ? 1.0 : 0.0);
    // Foot separation concept (wide stance = jumping jack)
    features.add(normStanceWidth > 0.3 ? 1.0 : 0.0);

    // Initialize names on first call
    if (!_namesInitialized) {
      _initNames();
    }

    return features;
  }

  void _initNames() {
    featureNames.clear();

    // Pose geometry (12 x 3)
    for (final name in kLandmarkNames) {
      featureNames.add('${name}_x');
      featureNames.add('${name}_y');
      featureNames.add('${name}_conf');
    }
    // Torso-relative (12 x 2)
    for (final name in kLandmarkNames) {
      featureNames.add('${name}_relTorsoX');
      featureNames.add('${name}_relTorsoY');
    }
    // Hip-relative (4 x 4)
    for (final name in ['leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle']) {
      featureNames.add('${name}_relLeftHipX');
      featureNames.add('${name}_relLeftHipY');
      featureNames.add('${name}_relRightHipX');
      featureNames.add('${name}_relRightHipY');
    }
    // Shoulder-relative (6 x 2)
    for (final name in ['leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle']) {
      featureNames.add('${name}_relShldrX');
      featureNames.add('${name}_relShldrY');
    }
    // Angles (5)
    featureNames.addAll(['leftKneeAngle', 'rightKneeAngle', 'leftHipAngle', 'rightHipAngle', 'torsoAngle']);
    // Velocity (12)
    featureNames.addAll([
      'torsoVx', 'torsoVy', 'leftHipVy', 'rightHipVy',
      'shoulderVy', 'shoulderVx', 'leftAnkleVy', 'rightAnkleVy',
      'ankleCyVy', 'leftKneeVy', 'rightKneeVy',
    ]);
    // Body-relative velocity (6)
    featureNames.addAll([
      'leftAnkleRelVy', 'rightAnkleRelVy', 'ankleCyRelVy',
      'leftHipRelVy', 'rightHipRelVy', 'footCxRelVx',
    ]);
    // Acceleration (2)
    featureNames.addAll(['hipAccel', 'relAnkleAccel']);
    // Stance (5)
    featureNames.addAll(['footSep', 'normStanceWidth', 'stanceVel', 'splitStanceScore']);
    // Compression (5)
    featureNames.addAll(['kneeCompression', 'hipDescent', 'bodyHeight', 'compressionVel', 'hkr']);
    // Temporal (8)
    featureNames.addAll([
      'hipYRollMean5', 'hipYRollVar5', 'ankleYRollMean5',
      'hipYRecentMin10', 'hipYRecentMax10', 'hipYDelta5',
      'hipYDirChanges10', 'hipYLocalPeaks10',
    ]);
    // Pose quality (4)
    featureNames.addAll(['avgConfidence', 'missingLandmarks', 'temporalJitter', 'bodyScaleStability']);
    // Camera/global motion (3)
    featureNames.addAll(['globalTransX', 'globalTransY', 'residualMotion']);
    // Concepts (6)
    featureNames.addAll([
      'compressionConf', 'ascentConf', 'airborneConf',
      'landingConf', 'standingConf', 'footSepConf',
    ]);

    _namesInitialized = true;
  }

  // Helper methods

  double _angle(double ax, double ay, double bx, double by, double cx, double cy) {
    if (ax.isNaN || ay.isNaN || bx.isNaN || by.isNaN || cx.isNaN || cy.isNaN) return 180;
    final v1x = ax - bx, v1y = ay - by;
    final v2x = cx - bx, v2y = cy - by;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180;
    final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }

  double _angle2(double ax, double ay, double bx, double by) {
    if (ax.isNaN || ay.isNaN || bx.isNaN || by.isNaN) return 0;
    return math.atan2(by - ay, bx - ax) * 180 / math.pi;
  }

  double _safeDelta(double curr, double prev) {
    if (curr.isNaN || prev.isNaN) return 0;
    return curr - prev;
  }

  double _prevVal(NuvoPoseFrame? prev, String n1, String axis, String n2, String axis2) {
    if (prev == null) return double.nan;
    final p1 = prev.point(n1);
    final p2 = prev.point(n2);
    if (p1 == null || p2 == null) return double.nan;
    return ((axis == 'x' ? p1.x : p1.y) + (axis2 == 'x' ? p2.x : p2.y)) / 2;
  }

  double _prevVal2(NuvoPoseFrame? prev2, String n1, String axis, String n2, String axis2) {
    return _prevVal(prev2, n1, axis, n2, axis2);
  }

  double _rollingMean(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    if (frames.isEmpty) return 0;
    double sum = 0;
    int count = 0;
    for (final f in frames) {
      final v = _frameVal(f, n1, axis, n2, axis2);
      if (!v.isNaN) { sum += v; count++; }
    }
    return count > 0 ? sum / count : 0;
  }

  double _rollingVar(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    if (frames.length < 2) return 0;
    final mean = _rollingMean(frames, n1, axis, n2, axis2);
    double sumSq = 0;
    int count = 0;
    for (final f in frames) {
      final v = _frameVal(f, n1, axis, n2, axis2);
      if (!v.isNaN) { sumSq += (v - mean) * (v - mean); count++; }
    }
    return count > 1 ? sumSq / count : 0;
  }

  double _frameVal(NuvoPoseFrame f, String n1, String axis, String n2, String axis2) {
    final p1 = f.point(n1);
    final p2 = f.point(n2);
    if (p1 == null || p2 == null) return double.nan;
    return ((axis == 'x' ? p1.x : p1.y) + (axis2 == 'x' ? p2.x : p2.y)) / 2;
  }

  double _recentMin(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    double min = double.infinity;
    for (final f in frames) {
      final v = _frameVal(f, n1, axis, n2, axis2);
      if (!v.isNaN && v < min) min = v;
    }
    return min.isFinite ? min : 0;
  }

  double _recentMax(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    double max = double.negativeInfinity;
    for (final f in frames) {
      final v = _frameVal(f, n1, axis, n2, axis2);
      if (!v.isNaN && v > max) max = v;
    }
    return max.isFinite ? max : 0;
  }

  double _deltaN(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    if (frames.length < 2) return 0;
    final first = _frameVal(frames.first, n1, axis, n2, axis2);
    final last = _frameVal(frames.last, n1, axis, n2, axis2);
    if (first.isNaN || last.isNaN) return 0;
    return last - first;
  }

  double _directionChanges(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    if (frames.length < 3) return 0;
    int changes = 0;
    double? prevDelta;
    for (var i = 1; i < frames.length; i++) {
      final curr = _frameVal(frames[i], n1, axis, n2, axis2);
      final prev = _frameVal(frames[i - 1], n1, axis, n2, axis2);
      if (curr.isNaN || prev.isNaN) continue;
      final delta = curr - prev;
      if (prevDelta != null && (delta > 0) != (prevDelta > 0) && delta.abs() > 0.001) {
        changes++;
      }
      prevDelta = delta;
    }
    return changes.toDouble();
  }

  double _localPeaks(List<NuvoPoseFrame> frames, String n1, String axis, String n2, String axis2) {
    if (frames.length < 3) return 0;
    int peaks = 0;
    for (var i = 1; i < frames.length - 1; i++) {
      final prev = _frameVal(frames[i - 1], n1, axis, n2, axis2);
      final curr = _frameVal(frames[i], n1, axis, n2, axis2);
      final next = _frameVal(frames[i + 1], n1, axis, n2, axis2);
      if (prev.isNaN || curr.isNaN || next.isNaN) continue;
      if (curr > prev && curr > next && (curr - prev).abs() > 0.002) {
        peaks++;
      }
    }
    return peaks.toDouble();
  }

  double _torsoHeightVar(List<NuvoPoseFrame> frames) {
    if (frames.length < 2) return 0;
    final heights = <double>[];
    for (final f in frames) {
      final lh = f.point('leftHip');
      final rh = f.point('rightHip');
      final ls = f.point('leftShoulder');
      final rs = f.point('rightShoulder');
      if (lh != null && rh != null && ls != null && rs != null) {
        final hipY = (lh.y + rh.y) / 2;
        final shldrY = (ls.y + rs.y) / 2;
        heights.add((hipY - shldrY).abs());
      }
    }
    if (heights.length < 2) return 0;
    final mean = heights.reduce((a, b) => a + b) / heights.length;
    final var_ = heights.map((h) => (h - mean) * (h - mean)).reduce((a, b) => a + b) / heights.length;
    return var_;
  }
}

// ============================================================================
// FEATURE DATASET — All frames from all clips
// ============================================================================

class FeatureDataset {
  final List<FrameFeatures> allFrames;
  final List<String> featureNames;
  final Map<String, String> clipMovements;
  final Map<String, bool> clipIsTarget;
  final Map<String, String> clipSplits;

  FeatureDataset({
    required this.allFrames,
    required this.featureNames,
    required this.clipMovements,
    required this.clipIsTarget,
    required this.clipSplits,
  });

  List<FrameFeatures> framesForClip(String clipId) =>
      allFrames.where((f) => f.clipId == clipId).toList();

  List<FrameFeatures> framesForSplit(String split) =>
      allFrames.where((f) => f.split == split).toList();

  List<String> clipsForSplit(String split) =>
      clipSplits.entries.where((e) => e.value == split).map((e) => e.key).toList();

  Map<String, dynamic> toJson() => {
    'featureNames': featureNames,
    'frameCount': allFrames.length,
    'clipCount': clipMovements.length,
    'clipMovements': clipMovements,
    'clipIsTarget': clipIsTarget,
    'clipSplits': clipSplits,
  };
}

/// Build feature dataset from all fixtures.
FeatureDataset buildFeatureDataset({
  required String fixtureDir,
  required DatasetManifest manifest,
}) {
  final extractor = FeatureExtractor();
  final allFrames = <FrameFeatures>[];
  final clipMovements = <String, String>{};
  final clipIsTarget = <String, bool>{};
  final clipSplits = <String, String>{};

  for (final clip in manifest.clips) {
    final fixturePath = '$fixtureDir/${clip.clipId}.json';
    final file = File(fixturePath);
    if (!file.existsSync()) continue;

    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final fixture = ReplayFixture.fromJson(json);
    final frames = fixture.frames.map((f) => f.toPoseFrame()).toList();

    clipMovements[clip.clipId] = clip.movement;
    clipIsTarget[clip.clipId] = clip.isTarget;
    clipSplits[clip.clipId] = clip.split;

    final history = <NuvoPoseFrame>[];
    for (var i = 0; i < frames.length; i++) {
      final features = extractor.extract(frames[i], List.unmodifiable(history));
      allFrames.add(FrameFeatures(
        clipId: clip.clipId,
        frameIndex: i,
        movement: clip.movement,
        isTarget: clip.isTarget,
        split: clip.split,
        features: features,
        featureNames: extractor.featureNames,
      ));
      history.add(frames[i]);
    }
  }

  return FeatureDataset(
    allFrames: allFrames,
    featureNames: extractor.featureNames,
    clipMovements: clipMovements,
    clipIsTarget: clipIsTarget,
    clipSplits: clipSplits,
  );
}

// ============================================================================
// M1.2 PHASE 3: TEMPORAL WINDOW DATASET
// ============================================================================

class WindowSample {
  final String clipId;
  final String movement;
  final bool isTarget;
  final String split;
  final int startFrame;
  final int windowSize;
  final List<List<double>> features; // T x F
  final int label; // 1 = jump_squat, 0 = not

  WindowSample({
    required this.clipId,
    required this.movement,
    required this.isTarget,
    required this.split,
    required this.startFrame,
    required this.windowSize,
    required this.features,
    required this.label,
  });
}

class WindowDataset {
  final List<WindowSample> samples;
  final int windowSize;
  final int featureCount;
  final List<String> featureNames;

  WindowDataset({
    required this.samples,
    required this.windowSize,
    required this.featureCount,
    required this.featureNames,
  });

  int get positiveCount => samples.where((s) => s.label == 1).length;
  int get negativeCount => samples.where((s) => s.label == 0).length;

  List<WindowSample> forSplit(String split) =>
      samples.where((s) => s.split == split).toList();
}

/// Build temporal window dataset from feature dataset.
/// Windows are created with stride to avoid excessive overlap.
/// Windows from the same clip stay in the same split (no leakage).
WindowDataset buildWindowDataset({
  required FeatureDataset featureDataset,
  required int windowSize,
  required int stride,
  required String targetMovement,
}) {
  final samples = <WindowSample>[];
  final featureNames = featureDataset.featureNames;

  // Group frames by clip
  final clipFrames = <String, List<FrameFeatures>>{};
  for (final f in featureDataset.allFrames) {
    clipFrames.putIfAbsent(f.clipId, () => []).add(f);
  }
  // Sort by frame index
  for (final frames in clipFrames.values) {
    frames.sort((a, b) => a.frameIndex.compareTo(b.frameIndex));
  }

  for (final entry in clipFrames.entries) {
    final clipId = entry.key;
    final frames = entry.value;
    final movement = featureDataset.clipMovements[clipId] ?? '';
    final isTarget = featureDataset.clipIsTarget[clipId] ?? false;
    final split = featureDataset.clipSplits[clipId] ?? 'dev';
    final label = isTarget ? 1 : 0;

    // Slide window
    for (var start = 0; start + windowSize <= frames.length; start += stride) {
      final windowFrames = frames.sublist(start, start + windowSize);
      final windowFeatures = windowFrames.map((f) => f.features).toList();
      samples.add(WindowSample(
        clipId: clipId,
        movement: movement,
        isTarget: isTarget,
        split: split,
        startFrame: start,
        windowSize: windowSize,
        features: windowFeatures,
        label: label,
      ));
    }
  }

  return WindowDataset(
    samples: samples,
    windowSize: windowSize,
    featureCount: featureNames.length,
    featureNames: featureNames,
  );
}

// ============================================================================
// M1.2 PHASE 2: FEATURE SEPARABILITY ANALYSIS
// ============================================================================

class FeatureSeparability {
  final String featureName;
  final double jumpSquatMean;
  final double confuserMean;
  final double effectSize; // Cohen's d
  final double separabilityScore;
  final Map<String, double> perMovementMeans;

  FeatureSeparability({
    required this.featureName,
    required this.jumpSquatMean,
    required this.confuserMean,
    required this.effectSize,
    required this.separabilityScore,
    required this.perMovementMeans,
  });
}

/// Analyze feature separability between jump_squat and confuser movements.
List<FeatureSeparability> analyzeSeparability(FeatureDataset dataset) {
  final results = <FeatureSeparability>[];
  final featureNames = dataset.featureNames;

  // Group frames by movement
  final byMovement = <String, List<FrameFeatures>>{};
  for (final f in dataset.allFrames) {
    byMovement.putIfAbsent(f.movement, () => []).add(f);
  }

  final jumpSquatFrames = byMovement['jump_squats'] ?? [];
  final confuserFrames = dataset.allFrames.where((f) => !f.isTarget).toList();

  for (var fi = 0; fi < featureNames.length; fi++) {
    final name = featureNames[fi];

    // Jump squat values
    final jsVals = jumpSquatFrames
        .map((f) => fi < f.features.length ? f.features[fi] : double.nan)
        .where((v) => !v.isNaN)
        .toList();
    if (jsVals.isEmpty) continue;

    // Confuser values
    final confVals = confuserFrames
        .map((f) => fi < f.features.length ? f.features[fi] : double.nan)
        .where((v) => !v.isNaN)
        .toList();
    if (confVals.isEmpty) continue;

    final jsMean = _mean(jsVals);
    final confMean = _mean(confVals);
    final jsStd = _std(jsVals, jsMean);
    final confStd = _std(confVals, confMean);

    // Cohen's d
    final pooledStd = math.sqrt((jsStd * jsStd + confStd * confStd) / 2);
    final d = pooledStd > 0 ? (jsMean - confMean).abs() / pooledStd : 0.0;

    // Per-movement means
    final perMovement = <String, double>{};
    for (final entry in byMovement.entries) {
      final vals = entry.value
          .map((f) => fi < f.features.length ? f.features[fi] : double.nan)
          .where((v) => !v.isNaN)
          .toList();
      if (vals.isNotEmpty) {
        perMovement[entry.key] = _mean(vals);
      }
    }

    results.add(FeatureSeparability(
      featureName: name,
      jumpSquatMean: jsMean,
      confuserMean: confMean,
      effectSize: d,
      separabilityScore: d, // higher = more separable
      perMovementMeans: perMovement,
    ));
  }

  // Sort by effect size descending
  results.sort((a, b) => b.effectSize.compareTo(a.effectSize));
  return results;
}

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _std(List<double> values, double mean) {
  if (values.length < 2) return 0;
  final var_ = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
  return math.sqrt(var_);
}
