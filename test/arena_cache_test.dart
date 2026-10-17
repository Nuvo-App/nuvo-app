// Disk hydration + conditional GET + lazy markStale for ArenaController.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/arena/data/arena_api.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/data/arena_repository.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';

Map<String, dynamic> _raw(String pulse) => {
  'mode': 'real',
  'headerPulse': pulse,
};

class _FakeRepo extends ArenaRepository {
  _FakeRepo() : super(ArenaApi(), SecureTokenStore(), AuthApi());
  final List<Conditional<ArenaSnapshot>> script = [];
  final List<String?> seenEtags = [];

  @override
  Future<Conditional<ArenaSnapshot>> getArenaSnapshotConditional({
    String? etag,
  }) async {
    seenEtags.add(etag);
    return script.removeAt(0);
  }
}

Conditional<ArenaSnapshot> _ok(String pulse, String? etag) => Conditional(
  data: ArenaSnapshot.fromJson(_raw(pulse)),
  etag: etag,
  raw: _raw(pulse),
);

ArenaController _controller(
  _FakeRepo repo,
  CacheStore cache,
  String? Function() account,
) => ArenaController(repo, cache: cache, accountId: account);

void main() {
  test('hydrate then 304 keeps the snapshot', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'arena', _raw('cached'), etag: '"a1"');
    final repo = _FakeRepo()
      ..script.add(const Conditional.notModified(etag: '"a1"'));
    final c = _controller(repo, cache, () => 'u1');
    await c.hydrate();
    expect(c.state.snapshot?.headerPulse, 'cached');
    expect(c.state.refreshing, isTrue);
    await c.loadSnapshot();
    expect(repo.seenEtags, ['"a1"']);
    expect(c.state.snapshot?.headerPulse, 'cached');
    expect(c.state.refreshing, isFalse);
  });

  test('200 replaces and persists', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'arena', _raw('cached'), etag: '"a1"');
    final repo = _FakeRepo()..script.add(_ok('fresh', '"a2"'));
    final c = _controller(repo, cache, () => 'u1');
    await c.hydrate();
    await c.loadSnapshot();
    expect(c.state.snapshot?.headerPulse, 'fresh');
    final entry = await cache.read('u1', 'arena');
    expect(entry!.etag, '"a2"');
    expect(entry.data, _raw('fresh'));
  });

  test('clearSnapshot wipes; account B never sees account A', () async {
    final cache = CacheStore.memory();
    await cache.write('userA', 'arena', _raw('A'), etag: '"x"');
    final b = _controller(_FakeRepo(), cache, () => 'userB');
    await b.hydrate();
    expect(b.state.snapshot, isNull);

    final repo = _FakeRepo()..script.add(_ok('A2', '"y"'));
    final a = _controller(repo, cache, () => 'userA');
    await a.loadSnapshot();
    a.clearSnapshot();
    await Future<void>.delayed(Duration.zero);
    expect(await cache.read('userA', 'arena'), isNull);
  });

  test('hydration finishing after sign-out is discarded', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'arena', _raw('cached'));
    final c = _controller(_FakeRepo(), cache, () => 'u1');
    final hydrating = c.hydrate();
    c.clearSnapshot();
    await hydrating;
    expect(c.state.snapshot, isNull);
  });

  test('markStale is lazy: no fetch without listeners, fetch with', () async {
    final repo = _FakeRepo()..script.addAll([_ok('a', null), _ok('b', null)]);
    final c = _controller(repo, CacheStore.memory(), () => 'u1');
    await c.loadSnapshot();
    c.markStale();
    await Future<void>.delayed(Duration.zero);
    expect(repo.seenEtags.length, 1);
    c.addListener((_) {});
    c.markStale();
    await Future<void>.delayed(Duration.zero);
    expect(repo.seenEtags.length, 2);
  });
}
