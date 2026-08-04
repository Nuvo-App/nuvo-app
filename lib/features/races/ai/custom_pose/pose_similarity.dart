import 'dart:math' as math;

import 'normalized_pose.dart';

class PoseSimilarity {
  const PoseSimilarity({this.minValidFeatureRatio = 0.45});

  final double minValidFeatureRatio;

  PoseSimilarityResult compare(NormalizedPose a, NormalizedPose b) {
    if (!a.isValid || !b.isValid) {
      return PoseSimilarityResult.invalid(
        reason: a.invalidReason ?? b.invalidReason ?? 'invalid_pose',
      );
    }

    final keys = <String>{...a.features.values.keys, ...b.features.values.keys};
    if (keys.isEmpty) {
      return const PoseSimilarityResult.invalid(reason: 'no_features');
    }

    final contributions = <String, PoseFeatureSimilarity>{};
    var compared = 0;
    var missing = 0;
    var weightedScore = 0.0;
    var weightTotal = 0.0;

    for (final key in keys.toList()..sort()) {
      final left = a.features.values[key];
      final right = b.features.values[key];
      if (left == null || right == null || !left.valid || !right.valid) {
        missing++;
        continue;
      }
      compared++;
      final distance = (left.value - right.value).abs();
      final tolerance = _toleranceFor(left.kind);
      final contribution = (1 - distance / tolerance).clamp(0.0, 1.0);
      final weight = math
          .min(left.confidence, right.confidence)
          .clamp(0.0, 1.0);
      weightedScore += contribution * weight;
      weightTotal += weight;
      contributions[key] = PoseFeatureSimilarity(
        featureId: key,
        distance: distance,
        contribution: contribution,
        weight: weight,
      );
    }

    final validRatio = compared / keys.length;
    if (compared == 0 || weightTotal <= 0) {
      return PoseSimilarityResult.invalid(
        reason: 'no_comparable_features',
        comparedFeatureCount: compared,
        missingFeatureCount: missing,
        validFeatureRatio: validRatio,
        featureSimilarities: contributions,
      );
    }
    final score = (weightedScore / weightTotal).clamp(0.0, 1.0);
    return PoseSimilarityResult(
      similarity: validRatio < minValidFeatureRatio ? 0 : score,
      validFeatureRatio: validRatio,
      comparedFeatureCount: compared,
      missingFeatureCount: missing,
      isValid: validRatio >= minValidFeatureRatio,
      invalidReason: validRatio >= minValidFeatureRatio
          ? null
          : 'insufficient_valid_features',
      featureSimilarities: contributions,
    );
  }

  double _toleranceFor(String kind) {
    return switch (kind) {
      'coord' => 0.35,
      'angle' => 0.22,
      'distance' => 0.45,
      _ => 0.35,
    };
  }
}

class PoseSimilarityResult {
  const PoseSimilarityResult({
    required this.similarity,
    required this.validFeatureRatio,
    required this.comparedFeatureCount,
    required this.missingFeatureCount,
    required this.isValid,
    required this.invalidReason,
    required this.featureSimilarities,
  });

  const PoseSimilarityResult.invalid({
    required String reason,
    double validFeatureRatio = 0,
    int comparedFeatureCount = 0,
    int missingFeatureCount = 0,
    Map<String, PoseFeatureSimilarity> featureSimilarities = const {},
  }) : this(
         similarity: 0,
         validFeatureRatio: validFeatureRatio,
         comparedFeatureCount: comparedFeatureCount,
         missingFeatureCount: missingFeatureCount,
         isValid: false,
         invalidReason: reason,
         featureSimilarities: featureSimilarities,
       );

  final double similarity;
  final double validFeatureRatio;
  final int comparedFeatureCount;
  final int missingFeatureCount;
  final bool isValid;
  final String? invalidReason;
  final Map<String, PoseFeatureSimilarity> featureSimilarities;
}

class PoseFeatureSimilarity {
  const PoseFeatureSimilarity({
    required this.featureId,
    required this.distance,
    required this.contribution,
    required this.weight,
  });

  final String featureId;
  final double distance;
  final double contribution;
  final double weight;
}
