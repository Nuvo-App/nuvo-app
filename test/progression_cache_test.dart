import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';

class _Store extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'tok';
}

Map<String, dynamic> _raw(int level) => {
      'progression': {'level': level},
    };

class _Api extends ProgressionApi {
  _Api() : super(client: null);
  final etags = <String?>[];
  int level = 3;
  bool notModified = false;

  @override
  Future<ProgressionFetch> getProgressionConditional(
    String token, {
    String? etag,
  }) async {
    etags.add(etag);
    if (notModified && etag != null) {
      return ProgressionFetch(notModified: true, etag: etag);
    }
    final raw = _raw(level);
    return ProgressionFetch(
      data: NuvoProgression.fromJson(raw['progression']! as Map<String, dynamic>),
      raw: raw,
      etag: 'W/"$level"',
    );
  }

  @override
  Future<List<NuvoBadge>> setFeatured(String token, List<String> ids) async =>
      const [];
}

ProgressionController _make(_Api api, CacheStore cache, String id) =>
    ProgressionController(api, _Store(), cache: cache, accountId: () => id);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('hydrate then 304 keeps the snapshot value', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'progression', _raw(7), etag: 'W/"7"');
    final api = _Api()..notModified = true;
    final c = _make(api, cache, 'u1');
    await c.load();
    expect(api.etags, ['W/"7"']);
    expect(c.state.valueOrNull?.level, 7);
  });

  test('200 replaces and persists; next load sends etag', () async {
    final cache = CacheStore.memory();
    final api = _Api();
    final c = _make(api, cache, 'u1');
    await c.load();
    expect(c.state.valueOrNull?.level, 3);
    final e = await cache.read('u1', 'progression');
    expect(e!.etag, 'W/"3"');
    await c.load();
    expect(api.etags, [null, 'W/"3"']);
  });

  test('mutation clears etag and snapshot', () async {
    final cache = CacheStore.memory();
    final api = _Api();
    final c = _make(api, cache, 'u1');
    await c.load();
    await c.setFeatured(const []);
    await _settle();
    expect((await cache.read('u1', 'progression'))?.data, isNull);
    await c.load();
    expect(api.etags.last, isNull);
  });

  test('clear wipes; account B never sees account A', () async {
    final cache = CacheStore.memory();
    final api = _Api();
    final a = _make(api, cache, 'uA');
    await a.load();
    a.clear();
    await _settle();
    expect(await cache.read('uA', 'progression'), isNull);

    await cache.write('uA', 'progression', _raw(9), etag: 'W/"9"');
    final b = _make(api, cache, 'uB');
    await b.load();
    expect(api.etags.last, isNull);
    expect(b.state.valueOrNull?.level, 3);
  });

  test('markStale is lazy: no fetch without listeners, fetch with', () async {
    final api = _Api();
    final c = _make(api, CacheStore.memory(), 'u1');
    c.markStale();
    await _settle();
    expect(api.etags, isEmpty);
    final remove = c.addListener((_) {});
    c.markStale();
    await _settle();
    expect(api.etags, hasLength(1));
    remove();
  });
}
