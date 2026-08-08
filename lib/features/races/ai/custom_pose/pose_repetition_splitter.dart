import 'normalized_pose.dart';
import 'pose_calibration_models.dart';
import 'pose_sequence_frame.dart';
import 'pose_similarity.dart';

class PoseRepetitionSplitter {
  const PoseRepetitionSplitter();

  List<PoseDemonstration> split({
    required List<PoseSequenceFrame> frames,
    required NormalizedPose startPose,
  }) {
    const similarity = PoseSimilarity(minValidFeatureRatio: 0.30);
    final validFrames = frames
        .where((frame) => frame.pose.isValid)
        .toList(growable: false);

    final demonstrations = <PoseDemonstration>[];
    var i = 0;
    var index = 1;

    while (i < validFrames.length && demonstrations.length < 3) {
      int? departure;
      for (; i < validFrames.length; i++) {
        final result = similarity.compare(startPose, validFrames[i].pose);
        if (result.isValid && result.similarity < 0.94) {
          departure = i;
          break;
        }
      }
      if (departure == null) break;

      final start = departure > 0 ? departure - 1 : departure;
      var returnEnd = -1;
      var consecutive = 0;
      int? firstReturn;

      for (var j = departure + 1; j < validFrames.length; j++) {
        final result = similarity.compare(startPose, validFrames[j].pose);
        if (result.isValid && result.similarity >= 0.98) {
          consecutive++;
          firstReturn ??= j;
          if (consecutive >= 2) {
            returnEnd = j;
            break;
          }
        } else {
          consecutive = 0;
          firstReturn = null;
        }
      }

      if (returnEnd == -1) break;

      final raw = validFrames.sublist(start, returnEnd);
      if (raw.length >= 4) {
        demonstrations.add(_buildDemonstration(raw, index++));
      }

      i = returnEnd;
    }

    return demonstrations;
  }

  PoseDemonstration _buildDemonstration(
    List<PoseSequenceFrame> raw,
    int index,
  ) {
    final first = raw.first;
    final baseElapsed = first.elapsedMs;
    final lastElapsed = raw.last.elapsedMs - baseElapsed;

    final rebased = List<PoseSequenceFrame>.generate(raw.length, (i) {
      final source = raw[i];
      return PoseSequenceFrame(
        schemaVersion: normalizedPoseSchemaVersion,
        position: raw.length == 1 ? 0.0 : i / (raw.length - 1),
        elapsedMs: source.elapsedMs - baseElapsed,
        pose: source.pose,
      );
    }, growable: false);

    final validCount = rebased.where((frame) => frame.pose.isValid).length;

    return PoseDemonstration(
      index: index,
      frames: rebased,
      durationMs: lastElapsed,
      processedFrameCount: rebased.length,
      validFrameCount: validCount,
      validFrameRatio: validCount / rebased.length,
      averageVisibility: _averageCoverage(rebased.map((frame) => frame.pose)),
      accepted: true,
    );
  }

  double _averageCoverage(Iterable<NormalizedPose> poses) {
    final values = poses
        .map(
          (pose) => pose.features.values.isEmpty
              ? 0.0
              : pose.validFeatureCount / pose.features.values.length,
        )
        .toList(growable: false);
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
