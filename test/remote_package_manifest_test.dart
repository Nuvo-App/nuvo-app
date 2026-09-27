import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/data/motion_package.dart';

/// MotionPackage V1 bounds — the package envelope is data, never code, and
/// every field is allowlisted + bounded. Anything malformed is rejected, not
/// repaired.
void main() {
  const sha =
      'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

  Map<String, dynamic> validManifest() => {
    'packageSchemaVersion': 1,
    'assets': [
      {
        'id': 'preview',
        'type': 'preview_v1',
        'sha256': sha,
        'url': 'https://assets.example/preview.json',
        'bytes': 4096,
        'required': false,
      },
    ],
  };

  group('RemoteActivityInfo', () {
    test('parses a well-formed activity block', () {
      final info = RemoteActivityInfo.tryParse({
        'displayName': 'Reach Taps',
        'measurementType': 'repetitions',
        'defaultTarget': 10,
        'preferredCameraView': 'side',
        'instructions': ['Step one.', 'Step two.'],
        'unit': 'reach taps',
        'coachingTextActive': 'Keep reaching',
        'coachingTextIncomplete': 'Get in frame',
      });
      expect(info, isNotNull);
      expect(info!.displayName, 'Reach Taps');
      expect(info.defaultTarget, 10);
      expect(info.preferredCameraView, 'side');
      expect(info.unit, 'reach taps');
      expect(info.isDuration, isFalse);
    });

    test('rejects bad shapes instead of guessing', () {
      expect(RemoteActivityInfo.tryParse(null), isNull);
      expect(RemoteActivityInfo.tryParse('reach taps'), isNull);
      expect(
        RemoteActivityInfo.tryParse({'displayName': 'X', 'measurementType': 'repetitions', 'nope': 1}),
        isNull,
      );
      expect(
        RemoteActivityInfo.tryParse({'measurementType': 'repetitions'}),
        isNull,
      );
      expect(
        RemoteActivityInfo.tryParse({
          'displayName': 'X',
          'measurementType': 'reps', // must be repetitions|duration
        }),
        isNull,
      );
      expect(
        RemoteActivityInfo.tryParse({
          'displayName': 'X',
          'measurementType': 'repetitions',
          'preferredCameraView': 'underwater',
        }),
        isNull,
      );
      expect(
        RemoteActivityInfo.tryParse({
          'displayName': 'X',
          'measurementType': 'repetitions',
          'instructions': List.filled(7, 'step'), // bounded at 6
        }),
        isNull,
      );
    });
  });

  group('MotionPackageManifest', () {
    test('parses a valid manifest', () {
      final manifest = MotionPackageManifest.tryParse(validManifest());
      expect(manifest, isNotNull);
      expect(manifest!.packageSchemaVersion, 1);
      expect(manifest.assets, hasLength(1));
      expect(manifest.assets.first.type, 'preview_v1');
      expect(manifest.requiredAssets, isEmpty);
    });

    test('rejects malformed manifests — fail closed', () {
      expect(MotionPackageManifest.tryParse('x'), isNull);
      expect(
        MotionPackageManifest.tryParse({'packageSchemaVersion': 2, 'assets': []}),
        isNull,
      );
      expect(
        MotionPackageManifest.tryParse({...validManifest(), 'extra': true}),
        isNull,
      );
      expect(
        MotionPackageManifest.tryParse({'packageSchemaVersion': 1}),
        isNull,
      );
      // Unknown asset type.
      expect(
        MotionPackageManifest.tryParse({
          'packageSchemaVersion': 1,
          'assets': [
            {...validManifest()['assets']![0], 'type': 'executable_dart'},
          ],
        }),
        isNull,
      );
      // Invalid checksum.
      expect(
        MotionPackageManifest.tryParse({
          'packageSchemaVersion': 1,
          'assets': [
            {...validManifest()['assets']![0], 'sha256': 'not-hex'},
          ],
        }),
        isNull,
      );
      // Bytes over the per-type cap.
      expect(
        MotionPackageManifest.tryParse({
          'packageSchemaVersion': 1,
          'assets': [
            {...validManifest()['assets']![0], 'bytes': 512 * 1024},
          ],
        }),
        isNull,
      );
      // Duplicate asset IDs.
      final dup = validManifest();
      (dup['assets'] as List).add(dup['assets']![0]);
      expect(MotionPackageManifest.tryParse(dup), isNull);
      // Unknown asset key.
      expect(
        MotionPackageManifest.tryParse({
          'packageSchemaVersion': 1,
          'assets': [
            {...validManifest()['assets']![0], 'onInstall': 'rm -rf /'},
          ],
        }),
        isNull,
      );
    });
  });

  group('spec envelope', () {
    Map<String, dynamic> baseSpec() => {
      'specSchemaVersion': 1,
      'releaseId': 'rel-1',
      'activityId': 'some_remote_motion',
      'engineType': 'alternating_rep_v1',
      'measurementType': 'repetitions',
      'requiredLandmarks': ['leftWrist', 'rightWrist'],
      'leftRules': [
        {'point': 'leftWrist', 'axis': 'y', 'operator': 'lt', 'threshold': 0.35},
      ],
      'rightRules': [
        {'point': 'rightWrist', 'axis': 'y', 'operator': 'lt', 'threshold': 0.35},
      ],
    };

    test('activity + package blocks ride inside the spec', () {
      final spec = RemoteVerifierSpec.fromJson({
        ...baseSpec(),
        'activity': {
          'displayName': 'Side Reaches',
          'measurementType': 'repetitions',
        },
        'package': validManifest(),
      });
      expect(spec.activity?.displayName, 'Side Reaches');
      expect(spec.package?.assets, hasLength(1));
    });

    test('a malformed package is fail-closed', () {
      expect(
        () => RemoteVerifierSpec.fromJson({
          ...baseSpec(),
          'package': {'packageSchemaVersion': 99, 'assets': []},
        }),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });

    test('a malformed activity degrades to null without killing the spec', () {
      final spec = RemoteVerifierSpec.fromJson({
        ...baseSpec(),
        'activity': {'unexpected': true},
      });
      expect(spec.activity, isNull);
      expect(spec.activityId, 'some_remote_motion');
    });

    test('unknown top-level keys remain rejected', () {
      expect(
        () => RemoteVerifierSpec.fromJson({...baseSpec(), 'dartCode': 'evil'}),
        throwsA(isA<RemoteVerifierSpecException>()),
      );
    });
  });
}
