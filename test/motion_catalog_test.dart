import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/motion_catalog_cache.dart';
import 'package:nuvo/features/races/data/motion_catalog_repository.dart';
import 'package:nuvo/features/races/data/race_api.dart';

class _MemoryCache extends MotionCatalogCache {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async => value = next;
}

class _FakeApi extends RaceApi {
  _FakeApi(this.response);

  MotionCatalogFetch response;

  @override
  Future<MotionCatalogFetch> getMotionCatalog({String? etag}) async => response;
}

Map<String, dynamic> _catalog({String id = 'side_reaches', String engine = 'native_v1'}) => {
      'catalogVersion': '2026-09-17T00:00:00Z',
      'activities': [
        {
          'id': id,
          'displayName': 'Side Reaches',
          'category': 'full_body',
          'proofLabel': 'side reaches',
          'measurementType': 'repetitions',
          'metric': 'reps',
          'suggestedTargets': [10, 20],
          'supportedFormats': ['first_to_goal'],
          'iconKey': 'fitness_center',
          'availability': 'supported',
          'currentReleaseId': 'side-reaches-1',
          'currentReleaseChecksum': 'sha256:side-reaches-1',
          'requiredCapabilities': ['pose_landmarks_v1'],
          'minimumAppBuild': 'local',
          'engineType': engine,
        },
      ],
    };

void main() {
  test('remote activity requires a known engine and preserves its stable ID', () {
    final snapshot = MotionCatalogSnapshot.fromJson(_catalog());
    final definitions = snapshot.toDefinitions({'pose_landmarks_v1'});
    final remote = definitions.singleWhere((activity) => activity.activityId == 'side_reaches');
    expect(remote.isRemote, isTrue);
    expect(remote.activityId, 'side_reaches');
    expect(remote.releaseChecksum, 'sha256:side-reaches-1');
  });

  test('unknown engine is hidden instead of guessed', () {
    final snapshot = MotionCatalogSnapshot.fromJson(_catalog(engine: 'future_engine_v1'));
    expect(snapshot.toDefinitions({'pose_landmarks_v1'}).where((activity) => activity.isRemote), isEmpty);
  });

  test('repository keeps last-known-good data when refresh fails', () async {
    final cache = _MemoryCache();
    final api = _FakeApi(MotionCatalogFetch(json: _catalog(), etag: '"v1"'));
    final repository = MotionCatalogRepository(api, cache);
    final first = await repository.load(force: true);
    expect(first.catalogVersion, '2026-09-17T00:00:00Z');
    expect(cache.value, isNotNull);

    api.response = const MotionCatalogFetch();
    final refreshed = await MotionCatalogRepository(api, cache).load(force: true);
    expect(refreshed.fromCache, isTrue);
    expect(refreshed.activities.single.id, 'side_reaches');
  });

  test('corrupt cache falls back to the bundled catalog', () async {
    final cache = _MemoryCache()..value = '{not-json';
    final api = _FakeApi(const MotionCatalogFetch());
    final snapshot = await MotionCatalogRepository(api, cache).load(force: true);
    expect(snapshot.catalogVersion, 'bundled');
    expect(snapshot.activities, isNotEmpty);
  });
}
