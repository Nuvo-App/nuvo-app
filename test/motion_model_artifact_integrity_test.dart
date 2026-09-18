import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_model_artifact_integrity.dart';

void main() {
  final expectedSha256 =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  test('accepts bytes whose version and SHA-256 match', () {
    final artifact = MotionModelArtifactIntegrity.verify(
      requestedModelVersion: 'basketball-yolox-s-800',
      bytes: Uint8List.fromList(utf8.encode('abc')),
      artifactModelVersion: 'basketball-yolox-s-800',
      expectedSha256: 'sha256:$expectedSha256',
    );

    expect(artifact.modelVersion, 'basketball-yolox-s-800');
    expect(artifact.sha256, expectedSha256);
    expect(artifact.bytes, utf8.encode('abc'));
  });

  test('rejects a model version mismatch', () {
    expect(
      () => MotionModelArtifactIntegrity.verify(
        requestedModelVersion: 'basketball-yolox-s-800',
        bytes: Uint8List.fromList(utf8.encode('abc')),
        artifactModelVersion: 'different-model',
        expectedSha256: expectedSha256,
      ),
      throwsA(isA<MotionModelArtifactIntegrityException>()),
    );
  });

  test('rejects a checksum mismatch or malformed checksum', () {
    final bytes = Uint8List.fromList(utf8.encode('abc'));
    expect(
      () => MotionModelArtifactIntegrity.verify(
        requestedModelVersion: 'basketball-yolox-s-800',
        bytes: bytes,
        artifactModelVersion: 'basketball-yolox-s-800',
        expectedSha256: '0' * 64,
      ),
      throwsA(isA<MotionModelArtifactIntegrityException>()),
    );
    expect(
      () => MotionModelArtifactIntegrity.verify(
        requestedModelVersion: 'basketball-yolox-s-800',
        bytes: bytes,
        artifactModelVersion: 'basketball-yolox-s-800',
        expectedSha256: 'not-a-digest',
      ),
      throwsA(isA<MotionModelArtifactIntegrityException>()),
    );
  });
}
