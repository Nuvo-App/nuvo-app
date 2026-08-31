import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/custom_pose/pose_normalizer.dart';
import 'package:nuvo/features/races/data/race_models.dart';

import 'fixtures/pose_fixtures.dart';

/// Verifies the Flutter custom-race POST body matches the server's
/// `customConfigFromBody` parser expectations in
/// `server/worker/src/domain/raceValidation.ts`.
///
/// This test does NOT call the server — it checks the payload structure
/// that `RaceApi.createCustomRace` would send.
void main() {
  CustomPoseVerifierSpec buildSpec() {
    final pose = const PoseNormalizer().normalize(neutralStandingPose());
    return CustomPoseVerifierSpec(
      schemaVersion: customPoseVerifierSpecSchemaVersion,
      verifierType: customPoseVerifierType,
      movementName: 'Overhead wave',
      measurementType: customPoseMeasurementType,
      startPose: pose,
      completionPose: pose,
      completionStrategy: CustomPoseCompletionStrategy.completionAtTerminalPose,
      canonicalSequence: [
        const PoseTemplateFrame(
          position: 0.0,
          features: {
            'landmark.leftWrist.x': PoseTemplateFeature(
              value: 0.3,
              confidence: 0.9,
              reliability: 0.8,
              allowedVariation: 0.2,
              contributingDemonstrationCount: 3,
              kind: 'coord',
            ),
          },
        ),
        const PoseTemplateFrame(
          position: 1.0,
          features: {
            'landmark.leftWrist.x': PoseTemplateFeature(
              value: 0.8,
              confidence: 0.9,
              reliability: 0.8,
              allowedVariation: 0.2,
              contributingDemonstrationCount: 3,
              kind: 'coord',
            ),
          },
        ),
      ],
      requiredFeatureIds: const ['landmark.leftWrist.x'],
      activeFeatureIds: const ['landmark.leftWrist.x'],
      sequenceSimilarityThreshold: 0.7,
      completionSimilarityThreshold: 0.8,
      resetSimilarityThreshold: 0.8,
      minimumValidFeatureRatio: 0.6,
      minimumVisibility: 0.6,
      cooldownMs: 500,
      expectedSequenceFrameCount: 2,
      calibrationSummary: const CustomPoseCalibrationSummary(
        sourceCalibrationSchemaVersion: 1,
        demonstrationCount: 3,
        selectedActiveFeatureCount: 1,
        requiredFeatureCount: 1,
        canonicalSequenceLength: 2,
        pairwiseSimilarityScores: {},
        overallConsistencyScore: 0.8,
        lowestPairwiseSimilarityScore: 0.8,
        sequenceSimilarityThreshold: 0.7,
        completionSimilarityThreshold: 0.8,
        resetSimilarityThreshold: 0.8,
        minimumValidFeatureRatio: 0.6,
        minimumVisibility: 0.6,
        cooldownMs: 500,
        completionStrategy:
            CustomPoseCompletionStrategy.completionAtTerminalPose,
        builderVersion: 'v1',
      ),
    );
  }

  /// Reconstructs the exact POST body that `RaceApi.createCustomRace` sends.
  Map<String, dynamic> buildCustomRacePayload({
    required String title,
    required int targetValue,
    required String customActivityName,
    required CustomPoseVerifierSpec verifierSpec,
  }) {
    return {
      'title': title,
      'goalType': 'first_to_goal',
      'targetValue': targetValue,
      'unit': 'reps',
      'targetUnit': 'reps',
      'metric': 'reps',
      'proofRequirement': 'ai_check',
      'proofReviewMode': 'auto_accept',
      'proofMode': 'ai_check',
      'verificationMethod': 'ai',
      'visibility': 'private',
      'verifierType': customPoseVerifierType,
      'verifierVersion': customPoseVerifierSpecSchemaVersion,
      'customActivityName': customActivityName,
      'verifierSpec': verifierSpec.toJson(),
    };
  }

  group('custom race payload contract', () {
    test('payload has all fields the server customConfigFromBody expects', () {
      final spec = buildSpec();
      final payload = buildCustomRacePayload(
        title: 'My wave race',
        targetValue: 10,
        customActivityName: 'Overhead wave',
        verifierSpec: spec,
      );

      // Server reads these fields:
      expect(payload['verifierType'], 'custom_pose_sequence');
      expect(payload['verifierVersion'], 1);
      expect(payload['customActivityName'], 'Overhead wave');
      expect(payload['targetValue'], 10);
      expect(payload['verifierSpec'], isA<Map<String, dynamic>>());
    });

    test(
      'verifierSpec JSON has fields the server validateCustomVerifierSpec expects',
      () {
        final spec = buildSpec();
        final specJson = spec.toJson();

        // Server checks:
        expect(specJson['version'], 1); // CUSTOM_VERIFIER_VERSION
        expect(specJson['verifierType'], 'custom_pose_sequence');
        expect(specJson['measurementType'], 'count');
        expect(specJson['movementName'], 'Overhead wave');
        expect(specJson['startPose'], isA<Map<String, dynamic>>());
        expect(specJson['completionPose'], isA<Map<String, dynamic>>());
        expect(specJson['completionStrategy'], 'completionAtTerminalPose');
        expect(specJson['canonicalSequence'], isA<List>());
        expect((specJson['canonicalSequence'] as List).isNotEmpty, isTrue);
        expect(specJson['requiredFeatureIds'], isA<List>());
        expect((specJson['requiredFeatureIds'] as List).isNotEmpty, isTrue);
        expect(specJson['activeFeatureIds'], isA<List>());
        expect((specJson['activeFeatureIds'] as List).isNotEmpty, isTrue);
        expect(specJson['expectedSequenceFrameCount'], 2);
        expect(specJson['cooldownMs'], 500);
        expect(specJson['sequenceSimilarityThreshold'], isA<double>());
        expect(specJson['completionSimilarityThreshold'], isA<double>());
        expect(specJson['resetSimilarityThreshold'], isA<double>());
        expect(specJson['minimumValidFeatureRatio'], isA<double>());
        expect(specJson['minimumVisibility'], isA<double>());
      },
    );

    test(
      'movementName in verifierSpec matches customActivityName in payload',
      () {
        final spec = buildSpec();
        final payload = buildCustomRacePayload(
          title: 'My wave race',
          targetValue: 10,
          customActivityName: 'Overhead wave',
          verifierSpec: spec,
        );

        final specJson = payload['verifierSpec'] as Map<String, dynamic>;
        expect(specJson['movementName'], payload['customActivityName']);
      },
    );

    test(
      'canonicalSequence frames have position and features with required fields',
      () {
        final spec = buildSpec();
        final specJson = spec.toJson();
        final sequence = specJson['canonicalSequence'] as List;

        for (final rawFrame in sequence) {
          final frame = rawFrame as Map<String, dynamic>;
          expect(frame['position'], isA<double>());
          expect(frame['features'], isA<Map>());
          final features = frame['features'] as Map<String, dynamic>;
          for (final feature in features.values) {
            final f = feature as Map<String, dynamic>;
            expect(f['value'], isA<double>());
            expect(f['confidence'], isA<double>());
            expect(f['reliability'], isA<double>());
            expect(f['allowedVariation'], isA<double>());
            expect(f['contributingDemonstrationCount'], isA<int>());
            expect(f['kind'], isA<String>());
          }
        }
      },
    );

    test('serialized verifierSpec is valid JSON and finite', () {
      final spec = buildSpec();
      final encoded = jsonEncode(spec.toJson());
      expect(() => jsonDecode(encoded), returnsNormally);

      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      // Server's hasOnlyFiniteNumbers check
      void checkFinite(dynamic value) {
        if (value is num) {
          expect(value.isFinite, isTrue);
        } else if (value is List) {
          for (final v in value) {
            checkFinite(v);
          }
        } else if (value is Map) {
          for (final v in value.values) {
            checkFinite(v);
          }
        }
      }

      checkFinite(decoded);
    });
  });

  group('custom race round-trip deserialization', () {
    test(
      'Race.fromJson parses custom verifier fields from server response',
      () {
        final spec = buildSpec();
        final specJson = spec.toJson();

        // Simulate a server response (buildRaceResponse output)
        final raceJson = {
          'id': 'race_123',
          'creatorId': 'user_1',
          'title': 'My wave race',
          'description': null,
          'goalType': 'first_to_goal',
          'targetValue': 10,
          'unit': 'reps',
          'metric': 'reps',
          'format': 'first_to_goal',
          'scoringRule': 'cumulative_sum',
          'verificationMethod': 'ai',
          'verifierType': 'custom_pose_sequence',
          'verifierVersion': 1,
          'verifierSpec': specJson,
          'customActivityName': 'Overhead wave',
          'status': 'active',
          'visibility': 'private',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'participants': [],
          'recentProofs': [],
          'finalStandings': [],
        };

        final race = Race.fromJson(raceJson);

        expect(race.isCustomVerifierRace, isTrue);
        expect(race.verifierType, 'custom_pose_sequence');
        expect(race.verifierVersion, 1);
        expect(race.customActivityName, 'Overhead wave');
        expect(race.customVerifierSpec, isNotNull);
        expect(race.customVerifierSpec!.movementName, 'Overhead wave');
        expect(race.verifierInvalidReason, isNull);
      },
    );

    test('Race.fromJson handles missing verifierSpec gracefully', () {
      final raceJson = {
        'id': 'race_123',
        'creatorId': 'user_1',
        'title': 'My wave race',
        'goalType': 'first_to_goal',
        'targetValue': 10,
        'unit': 'reps',
        'verifierType': 'custom_pose_sequence',
        'status': 'active',
        'visibility': 'private',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'participants': [],
        'recentProofs': [],
        'finalStandings': [],
      };

      final race = Race.fromJson(raceJson);

      expect(race.isCustomVerifierRace, isTrue);
      expect(race.customVerifierSpec, isNull);
      expect(race.verifierInvalidReason, isNotNull);
    });

    test('preset race does not decode custom verifier spec', () {
      final raceJson = {
        'id': 'race_456',
        'creatorId': 'user_1',
        'title': 'Pushup race',
        'goalType': 'first_to_goal',
        'targetValue': 50,
        'unit': 'reps',
        'aiActivityType': 'push_ups',
        'verifierType': 'preset_pose',
        'status': 'active',
        'visibility': 'private',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'participants': [],
        'recentProofs': [],
        'finalStandings': [],
      };

      final race = Race.fromJson(raceJson);

      expect(race.isCustomVerifierRace, isFalse);
      expect(race.customVerifierSpec, isNull);
    });
  });
}
