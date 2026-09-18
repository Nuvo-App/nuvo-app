import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/verifier_release_cache.dart';
import 'package:nuvo/features/races/data/verifier_release_repository.dart';

class _MemoryReleaseCache extends VerifierReleaseCache {
  Map<String, dynamic> value = {};

  @override
  Future<Map<String, dynamic>> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> next) async => value = next;
}

class _FakeReleaseApi extends RaceApi {
  _FakeReleaseApi(this.response);

  MotionReleaseFetch response;
  var calls = 0;

  @override
  Future<MotionReleaseFetch> getMotionRelease(
    String releaseId, {
    String? etag,
  }) async {
    calls++;
    return response;
  }
}

Map<String, dynamic> _release({String checksum = 'sha256:v1'}) => {
  'id': 'arm_raises-remote-2026.09.1',
  'activityId': 'arm_raises',
  'engineType': 'state_machine_v1',
  'specSchemaVersion': 1,
  'checksum': checksum,
  'requiredCapabilities': [
    'pose_landmarks_v1',
    'derived_features_v1',
    'state_machine_v1',
  ],
  'minimumAppBuild': 'remote-runtime-v1',
  'spec': {
    'specSchemaVersion': 1,
    'releaseId': 'arm_raises-remote-2026.09.1',
    'activityId': 'arm_raises',
    'engineType': 'state_machine_v1',
    'measurementType': 'repetitions',
    'requiredCapabilities': [
      'pose_landmarks_v1',
      'derived_features_v1',
      'state_machine_v1',
    ],
    'requiredLandmarks': [
      'leftShoulder',
      'rightShoulder',
      'leftWrist',
      'rightWrist',
    ],
    'stableFrames': 2,
    'startRules': [
      {'point': 'leftWrist', 'axis': 'y', 'operator': 'gte', 'threshold': 0.58},
    ],
    'activeRules': [
      {'point': 'leftWrist', 'axis': 'y', 'operator': 'lte', 'threshold': 0.42},
    ],
  },
};

void main() {
  test('release repository downloads and persists a changed release', () async {
    final api = _FakeReleaseApi(
      MotionReleaseFetch(json: _release(), etag: '"v1"'),
    );
    final cache = _MemoryReleaseCache();
    final repository = VerifierReleaseRepository(api, cache);

    final first = await repository.load(
      'arm_raises-remote-2026.09.1',
      expectedChecksum: 'sha256:v1',
    );
    expect(first?.checksum, 'sha256:v1');
    expect(cache.value, contains('arm_raises-remote-2026.09.1'));
    expect(api.calls, 1);

    final second = await repository.load(
      'arm_raises-remote-2026.09.1',
      expectedChecksum: 'sha256:v1',
    );
    expect(second?.checksum, 'sha256:v1');
    expect(api.calls, 1);
  });

  test('checksum mismatch never replaces the cached release', () async {
    final api = _FakeReleaseApi(
      MotionReleaseFetch(json: _release(checksum: 'sha256:bad')),
    );
    final cache = _MemoryReleaseCache();
    final repository = VerifierReleaseRepository(api, cache);
    final release = await repository.load(
      'arm_raises-remote-2026.09.1',
      expectedChecksum: 'sha256:expected',
    );
    expect(release, isNull);
    expect(cache.value, isEmpty);
  });
}
