import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_model_release.dart';
import 'package:nuvo/features/races/ai/motion_model_resolver.dart';
import 'package:nuvo/features/races/data/race_api.dart';

Map<String, dynamic> releaseJson({
  String version = 'motion_v2_encoder_fp32_2026.10.1',
  String family = kMotionV2EncoderFamily,
  String runtime = kMotionV2EncoderRuntimeFamily,
  int inputSchema = kMotionV2EncoderInputSchema,
  int? outputSchema = kMotionV2EncoderOutputSchema,
  int? minBuild,
}) => {
      'modelReleaseId': 'rel-$version',
      'modelVersion': version,
      'modelFamily': family,
      'runtimeFamily': runtime,
      'inputSchemaVersion': inputSchema,
      'outputSchemaVersion': outputSchema,
      'preprocessingVersion': 1,
      'normalizationVersion': 1,
      'embeddingSchemaVersion': 1,
      'minimumAppBuild': minBuild,
      'artifactKey': 'motion-models/$version.onnx',
      'artifactSha256': 'a' * 64,
      'artifactSizeBytes': 1000,
      'status': 'production',
      'supportedMotionIds': <String>[],
      'metadata': const {},
    };

void main() {
  group('MotionModelRelease parsing', () {
    test('parses a full release payload', () {
      final r = MotionModelRelease.fromJson(releaseJson());
      expect(r.modelVersion, 'motion_v2_encoder_fp32_2026.10.1');
      expect(r.runtimeFamily, kMotionV2EncoderRuntimeFamily);
      expect(r.embeddingSchemaVersion, 1);
      expect(r.cacheKey, 'motion_v2_encoder_fp32_2026.10.1:${'a' * 64}');
    });

    test('rejects a payload missing required fields', () {
      final bad = releaseJson()..remove('artifactSha256');
      expect(() => MotionModelRelease.fromJson(bad), throwsFormatException);
      final bad2 = releaseJson()..remove('runtimeFamily');
      expect(() => MotionModelRelease.fromJson(bad2), throwsFormatException);
    });
  });

  group('compatibility contract', () {
    const appBuild = 7;
    bool compat(Map<String, dynamic> j) => MotionModelRelease.fromJson(j)
        .isCompatibleWith(
          runtimeFamily: kMotionV2EncoderRuntimeFamily,
          inputSchemaVersion: kMotionV2EncoderInputSchema,
          outputSchemaVersion: kMotionV2EncoderOutputSchema,
          appBuild: appBuild,
        );

    test('accepts the shipped contract', () {
      expect(compat(releaseJson()), isTrue);
    });
    test('rejects an unknown runtime family', () {
      expect(compat(releaseJson(runtime: 'diffusion_3d_v9')), isFalse);
    });
    test('rejects an unknown input schema', () {
      expect(compat(releaseJson(inputSchema: 2)), isFalse);
    });
    test('rejects a newer output schema', () {
      expect(compat(releaseJson(outputSchema: 5)), isFalse);
    });
    test('rejects a release requiring a newer build', () {
      expect(compat(releaseJson(minBuild: 8)), isFalse);
      expect(compat(releaseJson(minBuild: 7)), isTrue);
    });
  });

  group('MotionV2ModelSource resolution', () {
    test('returns a compatible release', () async {
      final src = MotionV2ModelSource(
        resolveModel: (_) async => releaseJson(),
        fetchArtifact: (_) async => const MotionModelArtifactFetch(),
        appBuild: 3,
      );
      final r = await src.resolve(kMotionV2EncoderFamily);
      expect(r, isNotNull);
      expect(r!.modelVersion, 'motion_v2_encoder_fp32_2026.10.1');
    });

    test('an incompatible release resolves to null (fallback tier)', () async {
      final src = MotionV2ModelSource(
        resolveModel: (_) async => releaseJson(runtime: 'unshipped_v9'),
        fetchArtifact: (_) async => const MotionModelArtifactFetch(),
      );
      expect(await src.resolve(kMotionV2EncoderFamily), isNull);
    });

    test('an empty channel resolves to null', () async {
      final src = MotionV2ModelSource(
        resolveModel: (_) async => null,
        fetchArtifact: (_) async => const MotionModelArtifactFetch(),
      );
      expect(await src.resolve(kMotionV2EncoderFamily), isNull);
    });

    test('a wrong-family release is rejected outright', () async {
      final src = MotionV2ModelSource(
        resolveModel: (_) async => releaseJson(family: 'basketball_yolox'),
        fetchArtifact: (_) async => const MotionModelArtifactFetch(),
      );
      expect(() => src.resolve(kMotionV2EncoderFamily), throwsFormatException);
    });
  });

  group('artifact verification via source', () {
    test('accepts bytes hashing to the declared checksum', () async {
      // 'abc' hashes to ba7816bf... (see motion_model_artifact_integrity_test)
      const abc = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      final src = MotionV2ModelSource(
        resolveModel: (_) async => null,
        fetchArtifact: (_) async => MotionModelArtifactFetch(
          bytes: Uint8List.fromList([97, 98, 99]),
          modelVersion: 'm1',
          sha256: abc,
        ),
      );
      final release = MotionModelRelease.fromJson(
        releaseJson(version: 'm1')..['artifactSha256'] = abc,
      );
      final vetted = await src.fetchVerified(release);
      expect(vetted.sha256, abc);
    });

    test('a corrupt artifact is rejected before install', () async {
      final src = MotionV2ModelSource(
        resolveModel: (_) async => null,
        fetchArtifact: (_) async => MotionModelArtifactFetch(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          modelVersion: 'm1',
          sha256: 'f' * 64,
        ),
      );
      final release = MotionModelRelease.fromJson(releaseJson(version: 'm1'));
      expect(() => src.fetchVerified(release), throwsA(anything));
    });
  });
}
