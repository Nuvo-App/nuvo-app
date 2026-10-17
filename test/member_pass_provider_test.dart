import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/pass/application/member_pass_provider.dart';

PassInfo _pass(String id) =>
    PassInfo(memberId: id, passSlug: 's$id', shareUrl: 'https://x/$id');

void main() {
  test('loads once per account across two screen opens', () async {
    var calls = 0;
    final c = MemberPassController(
      fetch: () async => _pass('A${++calls}'),
      cache: CacheStore.memory(),
      accountId: 'uA',
    );
    await c.ensureLoaded(); // first open
    await c.ensureLoaded(); // second open
    expect(calls, 1);
    expect(c.state.info?.memberId, 'A1');
    await c.refresh();
    expect(calls, 2);
  });

  test('returns cached data immediately, then refreshes in background', () async {
    final cache = CacheStore.memory();
    await cache.write('uA', 'member_pass', {
      'memberId': 'old',
      'passSlug': 'so',
      'shareUrl': 'https://x/old',
    });
    final gate = Completer<void>();
    final c = MemberPassController(
      fetch: () async {
        await gate.future;
        return _pass('new');
      },
      cache: cache,
      accountId: 'uA',
    );
    final done = c.ensureLoaded();
    await pumpEventQueue();
    expect(c.state.info?.memberId, 'old');
    gate.complete();
    await done;
    expect(c.state.info?.memberId, 'new');
    expect((await cache.read('uA', 'member_pass'))?.data, containsPair('memberId', 'new'));
  });

  test("account B never sees account A's pass", () async {
    final cache = CacheStore.memory();
    await cache.write('uA', 'member_pass', {
      'memberId': 'a',
      'passSlug': 'sa',
      'shareUrl': 'https://x/a',
    });
    final b = MemberPassController(
      fetch: () async => throw Exception('offline'),
      cache: cache,
      accountId: 'uB',
    );
    await b.ensureLoaded();
    expect(b.state.info, isNull);
    expect(b.state.failed, isTrue);
  });

  test('a failed refresh keeps the cached pass', () async {
    final cache = CacheStore.memory();
    await cache.write('uA', 'member_pass', {
      'memberId': 'a',
      'passSlug': 'sa',
      'shareUrl': 'https://x/a',
    });
    final c = MemberPassController(
      fetch: () async => throw Exception('offline'),
      cache: cache,
      accountId: 'uA',
    );
    await c.ensureLoaded();
    expect(c.state.info?.memberId, 'a');
    expect(c.state.failed, isFalse);
  });
}
