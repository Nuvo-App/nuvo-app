import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/presentation/movement_preview/side_rig_movement_sequences.dart';

void main() {
  test('every previously unanimated movement has a finite side sequence', () {
    for (final movement in sideRigMovementPreviewActivities) {
      final sequence = sideRigMovementSequenceFor(movement);
      expect(sequence.duration.inMilliseconds, greaterThan(0));
      for (final time in <double>[0, 0.25, 0.5, 0.75, 0.999, 1, double.nan]) {
        final pose = sequence.poseAt(time);
        expect(pose.isFinite, isTrue, reason: movement.backendValue);
      }
      expect(
        sequence.poseAt(1).frontHipAngle,
        closeTo(sequence.poseAt(0).frontHipAngle, 0.001),
      );
    }
  });
}
