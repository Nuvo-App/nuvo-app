import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/arena/presentation/track_view/track_view_fixture.dart';
import 'package:nuvo/features/arena/presentation/track_view/track_view_geometry.dart';

void main() {
  group('TrackViewGeometry', () {
    test('normalizes and clamps progress', () {
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 0, goal: 100),
        0,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 41, goal: 100),
        0.41,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 68, goal: 100),
        0.68,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 100, goal: 100),
        1,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: -1, goal: 100),
        0,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 101, goal: 100),
        1,
      );
    });

    test('handles invalid goals safely', () {
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 10, goal: 0),
        0,
      );
      expect(
        TrackViewGeometry.normalizeProgress(completedAmount: 10, goal: -1),
        0,
      );
    });

    test('maps world x from start to finish monotonically', () {
      const width = 2400.0;
      final start = TrackViewGeometry.worldXForProgress(
        normalizedProgress: 0,
        worldWidth: width,
      );
      final midpoint = TrackViewGeometry.worldXForProgress(
        normalizedProgress: 0.5,
        worldWidth: width,
      );
      final finish = TrackViewGeometry.worldXForProgress(
        normalizedProgress: 1,
        worldWidth: width,
      );

      expect(start, TrackViewGeometry.horizontalEdgePadding(worldWidth: width));
      expect(midpoint, width / 2);
      expect(
        finish,
        width - TrackViewGeometry.horizontalEdgePadding(worldWidth: width),
      );
      expect(start, lessThan(midpoint));
      expect(midpoint, lessThan(finish));
    });

    test('fixture racers are ordered horizontally by progress', () {
      const width = 1800.0;
      for (final race in trackViewFixtures) {
        final positions = [
          for (final participant in race.participants)
            TrackViewGeometry.worldXForProgress(
              normalizedProgress: TrackViewGeometry.normalizeProgress(
                completedAmount: participant.completedAmount,
                goal: race.goal,
              ),
              worldWidth: width,
            ),
        ];

        for (var index = 1; index < positions.length; index++) {
          expect(
            positions[index],
            greaterThanOrEqualTo(positions[index - 1]),
            reason: race.title,
          );
        }
      }
    });

    test('keeps decorative y within safe bounds deterministically', () {
      const height = 720.0;
      final firstPass = <double>[];
      final secondPass = <double>[];
      for (var index = 0; index <= 100; index++) {
        final progress = index / 100;
        firstPass.add(
          TrackViewGeometry.worldYForProgress(
            normalizedProgress: progress,
            availableHeight: height,
          ),
        );
        secondPass.add(
          TrackViewGeometry.worldYForProgress(
            normalizedProgress: progress,
            availableHeight: height,
          ),
        );
      }

      expect(firstPass, secondPass);
      for (final y in firstPass) {
        expect(y, inInclusiveRange(height * 0.16, height * 0.84));
      }
    });
  });
}
