import 'dart:math' as math;

import '../../data/ai_motion_models.dart';
import 'normalized_pose.dart';

class PoseNormalizer {
  const PoseNormalizer({this.minConfidence = 0.35});

  final double minConfidence;

  NormalizedPose normalize(NuvoPoseFrame frame) {
    final origin = _chooseOrigin(frame);
    final scale = _chooseScale(frame);
    if (origin == null || scale == null || scale.value <= 0) {
      return _invalidPose(
        origin: origin,
        scale: scale,
        reason: origin == null
            ? 'missing_origin_landmarks'
            : 'missing_scale_landmarks',
      );
    }

    final landmarks = <String, NormalizedPoseLandmark>{};
    for (final id in canonicalPoseLandmarkIds) {
      final point = frame.point(id);
      if (point == null || point.likelihood < minConfidence) continue;
      final x = (point.x - origin.x) / scale.value;
      final y = (point.y - origin.y) / scale.value;
      final z = point.z / scale.value;
      if (![x, y, z].every((value) => value.isFinite)) continue;
      landmarks[id] = NormalizedPoseLandmark(
        x: x,
        y: y,
        z: z,
        confidence: point.likelihood.clamp(0.0, 1.0),
        valid: true,
      );
    }

    final features = _featuresFrom(landmarks);
    return NormalizedPose(
      schemaVersion: normalizedPoseSchemaVersion,
      landmarks: Map.unmodifiable(landmarks),
      features: PoseFeatureVector(Map.unmodifiable(features)),
      originX: origin.x,
      originY: origin.y,
      scale: scale.value,
      originReference: origin.reference,
      scaleReference: scale.reference,
      validLandmarkCount: landmarks.length,
      validFeatureCount: features.values.where((value) => value.valid).length,
    );
  }

  NormalizedPose _invalidPose({
    required _ReferencePoint? origin,
    required _ScaleReference? scale,
    required String reason,
  }) {
    return NormalizedPose(
      schemaVersion: normalizedPoseSchemaVersion,
      landmarks: const {},
      features: const PoseFeatureVector({}),
      originX: origin?.x ?? 0,
      originY: origin?.y ?? 0,
      scale: scale?.value ?? 1,
      originReference: origin?.reference ?? 'none',
      scaleReference: scale?.reference ?? 'none',
      validLandmarkCount: 0,
      validFeatureCount: 0,
      invalidReason: reason,
    );
  }

  _ReferencePoint? _chooseOrigin(NuvoPoseFrame frame) {
    final hips = _midpoint(frame, 'leftHip', 'rightHip');
    if (hips != null) {
      return _ReferencePoint(hips.x, hips.y, 'hip_midpoint');
    }
    final shoulders = _midpoint(frame, 'leftShoulder', 'rightShoulder');
    if (shoulders != null) {
      return _ReferencePoint(shoulders.x, shoulders.y, 'shoulder_midpoint');
    }
    return null;
  }

  _ScaleReference? _chooseScale(NuvoPoseFrame frame) {
    final shoulderWidth = _distance(frame, 'leftShoulder', 'rightShoulder');
    if (shoulderWidth != null && shoulderWidth > 0.0001) {
      return _ScaleReference(shoulderWidth, 'shoulder_width');
    }
    final shoulderMid = _midpoint(frame, 'leftShoulder', 'rightShoulder');
    final hipMid = _midpoint(frame, 'leftHip', 'rightHip');
    if (shoulderMid != null && hipMid != null) {
      final torsoLength = distance2d(
        shoulderMid.x,
        shoulderMid.y,
        hipMid.x,
        hipMid.y,
      );
      if (torsoLength > 0.0001) {
        return _ScaleReference(torsoLength, 'torso_length');
      }
    }
    final hipWidth = _distance(frame, 'leftHip', 'rightHip');
    if (hipWidth != null && hipWidth > 0.0001) {
      return _ScaleReference(hipWidth, 'hip_width');
    }
    return null;
  }

  _RawPoint? _midpoint(NuvoPoseFrame frame, String a, String b) {
    final pa = _validPoint(frame, a);
    final pb = _validPoint(frame, b);
    if (pa == null || pb == null) return null;
    return _RawPoint((pa.x + pb.x) / 2, (pa.y + pb.y) / 2);
  }

  double? _distance(NuvoPoseFrame frame, String a, String b) {
    final pa = _validPoint(frame, a);
    final pb = _validPoint(frame, b);
    if (pa == null || pb == null) return null;
    return distance2d(pa.x, pa.y, pb.x, pb.y);
  }

  NuvoPosePoint? _validPoint(NuvoPoseFrame frame, String name) {
    final point = frame.point(name);
    if (point == null || point.likelihood < minConfidence) return null;
    return point;
  }

  Map<String, PoseFeatureValue> _featuresFrom(
    Map<String, NormalizedPoseLandmark> landmarks,
  ) {
    final features = <String, PoseFeatureValue>{};
    for (final entry in landmarks.entries) {
      final landmark = entry.value;
      features['landmark.${entry.key}.x'] = _feature(
        landmark.x,
        landmark.confidence,
        'coord',
      );
      features['landmark.${entry.key}.y'] = _feature(
        landmark.y,
        landmark.confidence,
        'coord',
      );
    }

    void addAngle(String id, String a, String b, String c) {
      final angle = _angle(landmarks[a], landmarks[b], landmarks[c]);
      if (angle == null) return;
      features['angle.$id'] = _feature(
        angle.value / 180,
        angle.confidence,
        'angle',
      );
    }

    addAngle('left_elbow', 'leftShoulder', 'leftElbow', 'leftWrist');
    addAngle('right_elbow', 'rightShoulder', 'rightElbow', 'rightWrist');
    addAngle('left_shoulder', 'leftElbow', 'leftShoulder', 'leftHip');
    addAngle('right_shoulder', 'rightElbow', 'rightShoulder', 'rightHip');
    addAngle('left_hip', 'leftShoulder', 'leftHip', 'leftKnee');
    addAngle('right_hip', 'rightShoulder', 'rightHip', 'rightKnee');
    addAngle('left_knee', 'leftHip', 'leftKnee', 'leftAnkle');
    addAngle('right_knee', 'rightHip', 'rightKnee', 'rightAnkle');

    void addDistance(String id, String a, String b) {
      final pa = landmarks[a];
      final pb = landmarks[b];
      if (pa == null || pb == null || !pa.valid || !pb.valid) return;
      final value = distance2d(pa.x, pa.y, pb.x, pb.y);
      features['distance.$id'] = _feature(
        value,
        math.min(pa.confidence, pb.confidence),
        'distance',
      );
    }

    addDistance('hand_separation', 'leftWrist', 'rightWrist');
    addDistance('foot_separation', 'leftAnkle', 'rightAnkle');
    addDistance('left_wrist_to_shoulder', 'leftWrist', 'leftShoulder');
    addDistance('right_wrist_to_shoulder', 'rightWrist', 'rightShoulder');
    addDistance('left_wrist_to_hip', 'leftWrist', 'leftHip');
    addDistance('right_wrist_to_hip', 'rightWrist', 'rightHip');
    addDistance('left_knee_to_hip', 'leftKnee', 'leftHip');
    addDistance('right_knee_to_hip', 'rightKnee', 'rightHip');

    return features;
  }

  PoseFeatureValue _feature(double value, double confidence, String kind) {
    return PoseFeatureValue(
      value: value.isFinite ? value : 0,
      confidence: confidence.clamp(0.0, 1.0),
      valid: value.isFinite,
      kind: kind,
    );
  }

  _Angle? _angle(
    NormalizedPoseLandmark? a,
    NormalizedPoseLandmark? b,
    NormalizedPoseLandmark? c,
  ) {
    if (a == null || b == null || c == null) return null;
    final abx = a.x - b.x;
    final aby = a.y - b.y;
    final cbx = c.x - b.x;
    final cby = c.y - b.y;
    final dot = abx * cbx + aby * cby;
    final ab = math.sqrt(abx * abx + aby * aby);
    final cb = math.sqrt(cbx * cbx + cby * cby);
    if (ab < 0.0001 || cb < 0.0001) return null;
    final cosine = (dot / (ab * cb)).clamp(-1.0, 1.0);
    final angle = math.acos(cosine) * 180 / math.pi;
    return _Angle(
      angle,
      math.min(a.confidence, math.min(b.confidence, c.confidence)),
    );
  }
}

class _RawPoint {
  const _RawPoint(this.x, this.y);

  final double x;
  final double y;
}

class _ReferencePoint extends _RawPoint {
  const _ReferencePoint(super.x, super.y, this.reference);

  final String reference;
}

class _ScaleReference {
  const _ScaleReference(this.value, this.reference);

  final double value;
  final String reference;
}

class _Angle {
  const _Angle(this.value, this.confidence);

  final double value;
  final double confidence;
}
