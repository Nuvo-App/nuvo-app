// Disk hydration + conditional GET (ETag/304) for RaceController.
// See docs/agents/18-data-freshness-contract.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

Map<String, dynamic> _raw(String id) => {'id': id, 'title': 'Race $id'};

class _FakeRepo extends RaceRepository {
  _FakeRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  /// Scripted responses, consumed in order.
  final List<Conditional<List<Race>>> script = [];
  final List<String?> seenEtags = [];
  Conditional<Race>? detail;
  final List<String?> seenDetailEtags = [];
  Race? joined;

  @override
  Future<Conditional<List<Race>>> getRacesConditional({String? etag}) async {
    seenEtags.add(etag);
    return script.removeAt(0);
  }

  @override
  Future<Conditional<Race>> getRaceDetailConditional(
    String id, {
    String? etag,
  }) async {
    seenDetailEtags.add(etag);
    return detail!;
  }

  @override
  Future<Race> joinRace(String id) async => joined!;
}

Conditional<List<Race>> _ok(List<String> ids, String? etag) => Conditional(
  data: [for (final id in ids) Race.fromJson(_raw(id))],
  etag: etag,
  raw: [for (final id in ids) _raw(id)],
);

RaceController _controller(
  _FakeRepo repo,
  CacheStore cache,
  String? Function() account,
) => RaceController(repo, cache: cache, accountId: account);

void main() {
  test(
    'hydrates from disk, then revalidates with the stored etag (304 keeps state)',
    () async {
      final cache = CacheStore.memory();
      await cache.write('u1', 'races', [_raw('a')], etag: '"e1"');
      final repo = _FakeRepo()
        ..script.add(const Conditional.notModified(etag: '"e1"'));
      final c = _controller(repo, cache, () => 'u1');

      await c.hydrate();
      expect(c.state.races.map((r) => r.id), ['a']);
      expect(c.state.refreshing, isTrue);

      var notifications = 0;
      c.addListener((_) => notifications++, fireImmediately: false);
      await c.loadRaces();
      expect(repo.seenEtags, ['"e1"']);
      expect(c.state.races.map((r) => r.id), ['a']);
      expect(c.state.refreshing, isFalse);
      expect(notifications, 1); // flags settle once, no flicker
    },
  );

  test('200 replaces state and persists raw json with the new etag', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'races', [_raw('a')], etag: '"e1"');
    final repo = _FakeRepo()..script.add(_ok(['b'], '"e2"'));
    final c = _controller(repo, cache, () => 'u1');
    await c.hydrate();
    await c.loadRaces();
    expect(c.state.races.map((r) => r.id), ['b']);
    final entry = await cache.read('u1', 'races');
    expect(entry!.etag, '"e2"');
    expect((entry.data as List).single, _raw('b'));
  });

  test('server without ETag works: plain fetches, nothing sent', () async {
    final cache = CacheStore.memory();
    final repo = _FakeRepo()
      ..script.addAll([
        _ok(['a'], null),
        _ok(['a', 'b'], null),
      ]);
    final c = _controller(repo, cache, () => 'u1');
    await c.loadRaces();
    await c.loadRaces();
    expect(repo.seenEtags, [null, null]);
    expect(c.state.races.length, 2);
  });

  test(
    'a local patch clears the etag and invalidates the disk snapshot',
    () async {
      final cache = CacheStore.memory();
      final repo = _FakeRepo()
        ..script.addAll([
          _ok(['a'], '"e1"'),
          _ok(['a'], '"e2"'),
        ])
        ..joined = Race.fromJson(_raw('a'));
      final c = _controller(repo, cache, () => 'u1');
      await c.loadRaces();
      expect((await cache.read('u1', 'races'))!.etag, '"e1"');

      await c.joinRace('a');
      final entry = await cache.read('u1', 'races');
      expect(entry?.data, isNull);
      expect(entry?.etag, isNull);

      await c.loadRaces();
      expect(repo.seenEtags, [null, null]); // full fetch after the patch
    },
  );

  test('clearRaces wipes the account snapshot', () async {
    final cache = CacheStore.memory();
    final repo = _FakeRepo()..script.add(_ok(['a'], '"e1"'));
    final c = _controller(repo, cache, () => 'u1');
    await c.loadRaces();
    expect(await cache.read('u1', 'races'), isNotNull);
    c.clearRaces();
    await Future<void>.delayed(Duration.zero);
    expect(await cache.read('u1', 'races'), isNull);
    expect(c.state.races, isEmpty);
  });

  test('account B never sees account A snapshot', () async {
    final cache = CacheStore.memory();
    await cache.write('userA', 'races', [_raw('a')], etag: '"eA"');
    final repo = _FakeRepo();
    final c = _controller(repo, cache, () => 'userB');
    await c.hydrate();
    expect(c.state.races, isEmpty);
  });

  test('hydration finishing after sign-out is discarded', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'races', [_raw('a')], etag: '"e1"');
    final c = _controller(_FakeRepo(), cache, () => 'u1');
    final hydrating = c.hydrate();
    c.clearRaces();
    await hydrating;
    expect(c.state.races, isEmpty);
  });

  test('markStale is lazy: no fetch without listeners, fetch with', () async {
    final repo = _FakeRepo()
      ..script.addAll([
        _ok(['a'], null),
        _ok(['a'], null),
      ]);
    final c = _controller(repo, CacheStore.memory(), () => 'u1');
    await c.loadRaces();
    c.markStale();
    await Future<void>.delayed(Duration.zero);
    expect(repo.seenEtags.length, 1);
    c.addListener((_) {});
    c.markStale();
    await Future<void>.delayed(Duration.zero);
    expect(repo.seenEtags.length, 2);
  });

  test('race detail: 304 returns the remembered race', () async {
    final repo = _FakeRepo();
    final c = _controller(repo, CacheStore.memory(), () => 'u1');
    repo.detail = Conditional(
      data: Race.fromJson(_raw('a')),
      etag: '"d1"',
      raw: _raw('a'),
    );
    final first = await c.getRaceDetail('a');
    repo.detail = const Conditional.notModified(etag: '"d1"');
    final second = await c.getRaceDetail('a');
    expect(repo.seenDetailEtags, [null, '"d1"']);
    expect(second.id, first.id);
    expect(c.state.races.map((r) => r.id), ['a']);
  });
}
