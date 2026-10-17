// Crew disk snapshot + conditional GET at the controller layer: hydrate then
// revalidate, 304 keeps state, 200 replaces and persists, mutations drop the
// validator, sign-out wipes, accounts never see each other's data.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

Map<String, dynamic> _user(String id) => {
  'id': id,
  'displayName': 'User $id',
  'initials': id.toUpperCase(),
};

Map<String, dynamic> _crewRaw(List<String> ids) => {
  'crew': [for (final id in ids) _user(id)],
};

Map<String, dynamic> _snapshot(List<String> ids) => {
  'crew': _crewRaw(ids),
  'requests': {'requests': <Object>[], 'outgoing': <Object>[]},
};

class _Repo implements CrewRepository, CrewConditionalSource {
  Conditional<List<PublicUser>> next = Conditional(
    data: [PublicUser.fromJson(_user('z'))],
    etag: 'new',
    raw: _crewRaw(['z']),
  );
  Completer<void>? gate;
  final seenEtags = <String?>[];

  @override
  Future<Conditional<List<PublicUser>>> getCrewConditional({String? etag}) async {
    seenEtags.add(etag);
    await gate?.future;
    return next;
  }

  @override
  Future<List<PublicUser>> getCrew() async => next.data ?? const [];

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<void> acceptRequest(String userId) async {}
  @override
  Future<ConnectOutcome> add(String userId) async => ConnectOutcome.active;
  @override
  Future<void> declineRequest(String userId) async {}
  @override
  Future<void> remove(String userId) async {}
  @override
  Future<List<CrewSearchResult>> search(String query) async => const [];
  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();
  @override
  Future<void> reportUser(String userId, {String? reason}) async {}
  @override
  Future<void> reportRace(String raceId, {String? reason}) async {}
  @override
  Future<void> reportContent(String contentId, {String? reason}) async {}
  @override
  Future<void> blockUser(String userId) async {}
  @override
  Future<void> unblockUser(String userId) async {}
}

CrewController _controller(_Repo repo, CacheStore cache, String? Function() account) =>
    CrewController(repo, cache: cache, accountId: account);

void main() {
  test('hydrates from disk, then revalidates with the stored etag', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a', 'b']), etag: 'e1');
    final repo = _Repo()..gate = Completer<void>();
    final c = _controller(repo, cache, () => 'u1');

    unawaited(c.load(force: false));
    await pumpEventQueue();
    expect(c.state.members.map((m) => m.id), ['a', 'b']);
    expect(c.state.refreshing, isTrue);
    expect(repo.seenEtags, ['e1']);

    repo.next = const Conditional.notModified(etag: 'e1');
    repo.gate!.complete();
    await pumpEventQueue();
    expect(c.state.members.map((m) => m.id), ['a', 'b']);
    expect(c.state.refreshing, isFalse);
  });

  test('304 keeps state and bumps the loaded time (no refetch)', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a']), etag: 'e1');
    final repo = _Repo()..next = const Conditional.notModified(etag: 'e1');
    final c = _controller(repo, cache, () => 'u1');
    await c.load(force: true);
    expect(c.state.members.map((m) => m.id), ['a']);
    await c.load(force: false); // fresh enough: served from memory
    expect(repo.seenEtags, ['e1']);
  });

  test('200 replaces state and persists the raw JSON + etag', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a']), etag: 'e1');
    final repo = _Repo();
    final c = _controller(repo, cache, () => 'u1');
    await c.load(force: true);
    await pumpEventQueue();
    expect(c.state.members.map((m) => m.id), ['z']);
    final entry = await cache.read('u1', 'crew');
    expect(entry?.etag, 'new');
    expect((entry!.data as Map)['crew'], _crewRaw(['z']));
  });

  test('a mutation clears the etag and the persisted snapshot', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a']), etag: 'e1');
    final repo = _Repo()..next = const Conditional.notModified(etag: 'e1');
    final c = _controller(repo, cache, () => 'u1');
    await c.load(force: true);
    await c.remove('a');
    await pumpEventQueue();
    expect((await cache.read('u1', 'crew'))?.data, isNull);
    repo.next = Conditional(data: const [], etag: 'e2', raw: _crewRaw([]));
    await c.load(force: true);
    expect(repo.seenEtags.last, isNull);
  });

  test('clear with a wipe id deletes the account cache', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a']), etag: 'e1');
    final c = _controller(_Repo(), cache, () => 'u1');
    c.clear(wipeAccountId: 'u1');
    await pumpEventQueue();
    expect(await cache.read('u1', 'crew'), isNull);
  });

  test('account B never sees account A data', () async {
    final cache = CacheStore.memory();
    await cache.write('uA', 'crew', _snapshot(['a']), etag: 'eA');
    final repo = _Repo()..gate = Completer<void>();
    final c = _controller(repo, cache, () => 'uB');
    unawaited(c.load(force: false));
    await pumpEventQueue();
    expect(c.state.members, isEmpty);
    expect(repo.seenEtags, [null]);
  });

  test('a late hydration after clear is discarded', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew', _snapshot(['a']), etag: 'e1');
    final repo = _Repo()..gate = Completer<void>();
    final c = _controller(repo, cache, () => 'u1');
    unawaited(c.load(force: false));
    c.clear(); // sign-out before the disk read resolves
    await pumpEventQueue();
    expect(c.state.members, isEmpty);
  });

  test('feed: hydrates, then sends the stored etag; 304 keeps items', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'crew_feed', {'items': <Object>[]}, etag: 'f1');
    final repo = _FeedRepo();
    final c = CrewActivityController(
      repo,
      cache: cache,
      accountId: () => 'u1',
    );
    await c.load(force: true);
    expect(repo.seenEtags, ['f1']);
    expect(c.state.error, isNull);
    expect(c.state.refreshing, isFalse);
  });
}

class _FeedRepo implements CrewActivityRepository, CrewActivityConditionalSource {
  final seenEtags = <String?>[];

  @override
  Future<Conditional<List<CrewActivityItem>>> getFeedConditional({
    int limit = 40,
    String? etag,
  }) async {
    seenEtags.add(etag);
    return Conditional.notModified(etag: etag);
  }

  @override
  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) async =>
      const [];
  @override
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) =>
      throw UnimplementedError();
  @override
  Future<ReactionSummary> unreact(CrewActivityItem item) =>
      throw UnimplementedError();
}
