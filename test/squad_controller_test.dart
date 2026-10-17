import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart' show ApiException;
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';

Map<String, dynamic> _g(String id, {String name = 'Crew', int races = 0}) => {
  'id': id,
  'name': name,
  'joinCode': 'CODE$id',
  'isOwner': true,
  'memberCount': 2,
  'raceCount': races,
};

Map<String, dynamic> _list(List<Map<String, dynamic>> g) => {'squads': g};

Map<String, dynamic> _detail(String id) => {
  'squad': _g(id, name: 'Detail $id'),
  'races': [],
  'standings': [],
};

class _FakeRepo implements SquadRepository {
  Map<String, dynamic> listBody = _list([_g('a')]);
  String? listEtagOut = 'L1';
  String? detailEtagOut = 'D1';
  bool listFails = false;
  int? detailFailStatus;
  final List<String?> listEtagsSeen = [];
  final List<String?> detailEtagsSeen = [];
  int detailCalls = 0;
  Completer<void>? gate;

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) async {
    listEtagsSeen.add(etag);
    if (gate != null) await gate!.future;
    if (listFails) throw const ApiException(500, 'boom');
    if (etag != null && etag == listEtagOut) {
      return Conditional.notModified(etag: etag);
    }
    return Conditional(
      data: parseCrewGroupList(listBody),
      etag: listEtagOut,
      raw: listBody,
    );
  }

  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) async {
    detailCalls++;
    detailEtagsSeen.add(etag);
    if (detailFailStatus != null) {
      throw ApiException(detailFailStatus!, 'detail failed');
    }
    if (etag != null && etag == detailEtagOut) {
      return Conditional.notModified(etag: etag);
    }
    final raw = _detail(id);
    return Conditional(
      data: CrewGroupDetail.fromJson(raw),
      etag: detailEtagOut,
      raw: raw,
    );
  }

  @override
  Future<CrewGroup> create(String name) async => CrewGroup.fromJson(_g('n', name: name));

  @override
  Future<void> join(String code) async {
    listBody = _list([_g('a'), _g('j')]);
    listEtagOut = 'L2';
  }

  @override
  Future<int> addRace(String id, String raceId) async => 1;

  @override
  Future<void> leave(String id) async {}

  @override
  Future<void> deleteCrew(String id) async {}

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> setRole(String id, String userId, String role) async {}

  @override
  Future<void> removeMember(String id, String userId) async {}

  @override
  Future<void> removeRace(String id, String raceId) async {}
}

SquadController _make(_FakeRepo repo, CacheStore store, {String? account = 'u1'}) =>
    SquadController(repo, store, accountId: () => account);

void main() {
  test('hydrates from disk then revalidates; 304 keeps state', () async {
    final store = CacheStore.memory();
    await store.write('u1', 'squads', _list([_g('a', name: 'Cached')]), etag: 'L1');
    final repo = _FakeRepo();
    final c = _make(repo, store);
    final f = c.load();
    await f;
    // Sent the stored etag; server said 304; hydrated data stays.
    expect(repo.listEtagsSeen, ['L1']);
    expect(c.state.groups!.single.name, 'Cached');
    expect(c.state.refreshing, isFalse);
    expect(c.state.error, isNull);
  });

  test('200 persists raw json + etag; failed refresh keeps data', () async {
    final store = CacheStore.memory();
    final repo = _FakeRepo();
    final c = _make(repo, store);
    await c.load();
    await Future<void>.delayed(Duration.zero);
    final e = await store.read('u1', 'squads');
    expect(e!.etag, 'L1');
    expect((e.data as Map)['squads'], hasLength(1));
    repo.listFails = true;
    await c.refresh();
    expect(c.state.groups, hasLength(1));
    expect(c.state.error, isNull);
  });

  test('error with no data surfaces; single-flight shares one request', () async {
    final repo = _FakeRepo()..listFails = true;
    final c = _make(repo, CacheStore.memory());
    await Future.wait([c.load(), c.load()]);
    expect(repo.listEtagsSeen, hasLength(1));
    expect(c.state.groups, isNull);
    expect(c.state.error, 'boom');
  });

  test('mutation clears etag and refetches', () async {
    final repo = _FakeRepo();
    final c = _make(repo, CacheStore.memory());
    await c.load();
    await c.join('CODE');
    expect(repo.listEtagsSeen.last, isNull);
    expect(c.state.groups!.map((g) => g.id), ['a', 'j']);
    await c.create('New');
    expect(c.state.groups!.first.id, 'n');
  });

  test('leave removes crew and its detail snapshot', () async {
    final store = CacheStore.memory();
    final c = _make(_FakeRepo(), store);
    await c.load();
    await c.loadDetail('a');
    await Future<void>.delayed(Duration.zero);
    expect((await store.read('u1', 'squad_a'))!.data, isNotNull);
    await c.leave('a');
    await Future<void>.delayed(Duration.zero);
    expect(c.state.groups, isEmpty);
    expect(c.state.details, isEmpty);
    expect((await store.read('u1', 'squad_a'))!.data, isNull);
  });

  for (final status in [404, 403]) {
    test('detail $status drops the cached crew and surfaces an error', () async {
      final store = CacheStore.memory();
      final repo = _FakeRepo();
      final c = _make(repo, store);
      await c.load();
      await c.loadDetail('a');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.details.containsKey('a'), isTrue);
      expect((await store.read('u1', 'squad_a'))!.data, isNotNull);

      repo.detailFailStatus = status;
      await c.refreshDetail('a');
      await Future<void>.delayed(Duration.zero);
      expect(c.state.details.containsKey('a'), isFalse);
      expect(c.state.detailErrors['a'], isNotNull);
      expect(c.state.groups, isEmpty);
      expect((await store.read('u1', 'squad_a'))?.data, isNull);
      expect(
        ((await store.read('u1', 'squads'))!.data as Map)['squads'],
        isEmpty,
      );
    });
  }

  test('other detail errors keep the cached crew', () async {
    final repo = _FakeRepo();
    final c = _make(repo, CacheStore.memory());
    await c.load();
    await c.loadDetail('a');
    repo.detailFailStatus = 500;
    await c.refreshDetail('a');
    expect(c.state.details.containsKey('a'), isTrue);
    expect(c.state.detailErrors['a'], isNull);
    expect(c.state.groups, hasLength(1));
  });

  test('detail cached per id; second call within window is a no-op', () async {
    final repo = _FakeRepo();
    final c = _make(repo, CacheStore.memory());
    await c.loadDetail('a');
    await c.loadDetail('b');
    await c.loadDetail('a');
    expect(repo.detailCalls, 2);
    expect(c.state.details.keys, containsAll(['a', 'b']));
    await c.refreshDetail('a');
    expect(repo.detailEtagsSeen.last, 'D1');
    expect(c.state.details['a']!.group.name, 'Detail a');
  });

  test('clear wipes memory and disk', () async {
    final store = CacheStore.memory();
    final c = _make(_FakeRepo(), store);
    await c.load();
    await Future<void>.delayed(Duration.zero);
    await c.clear();
    expect(c.state.groups, isNull);
    expect(await store.read('u1', 'squads'), isNull);
  });

  test('account isolation', () async {
    final store = CacheStore.memory();
    await store.write('u1', 'squads', _list([_g('a', name: 'Mine')]), etag: 'L1');
    final repo = _FakeRepo()..listBody = _list([_g('z', name: 'Theirs')]);
    var account = 'u2';
    final c = SquadController(repo, store, accountId: () => account);
    await c.load();
    expect(c.state.groups!.single.name, 'Theirs');
    expect(repo.listEtagsSeen.first, isNull);
    // Switching account resets in-memory state.
    account = 'u1';
    final f = c.load(force: true);
    await f;
    expect(c.state.groups!.single.name, 'Mine');
    expect(repo.listEtagsSeen.last, 'L1');
    expect((await store.read('u1', 'squads'))!.data, isNotNull);
  });

  testWidgets('screen renders cached crews immediately', (tester) async {
    final store = CacheStore.memory();
    await store.write('u1', 'squads', _list([_g('a', name: 'Sunrise Crew')]), etag: 'L1');
    final repo = _FakeRepo()..gate = Completer<void>();
    final c = _make(repo, store);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squadControllerProvider.overrideWith((ref) => c)],
        child: const MaterialApp(home: CrewGroupsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('Sunrise Crew'), findsOneWidget);
    repo.gate!.complete();
    await tester.pump();
    expect(find.text('Sunrise Crew'), findsOneWidget);
  });
}
