import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';

Map<String, dynamic> _raw(String id, {int unread = 1, String? cursor}) => {
      'notifications': [
        {
          'id': id,
          'category': 'x',
          'title': 'T $id',
          'createdAt': '2026-09-08T09:00:00Z',
          'read': false,
        },
      ],
      'unreadCount': unread,
      'nextCursor': ?cursor,
    };

class _Repo implements NotificationRepository {
  final etags = <String?>[];
  Map<String, dynamic> body = _raw('n1', cursor: 'CUR');
  String? etag = 'W/"1"';
  bool notModified = false;

  @override
  Future<NotificationPage> list({String? cursor, String? etag}) async {
    etags.add(etag);
    if (notModified && etag != null) {
      return NotificationPage.notModified(etag: etag);
    }
    return NotificationPage.fromJson(body, etag: this.etag);
  }

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

NotificationController _make(_Repo repo, CacheStore cache, String? id) =>
    NotificationController(repo, cache: cache, accountId: () => id);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('hydrates from disk then revalidates with the stored etag', () async {
    final cache = CacheStore.memory();
    await cache.write('u1', 'notifications', _raw('old', cursor: 'C0'),
        etag: 'W/"0"');
    final repo = _Repo()..notModified = true;
    final c = _make(repo, cache, 'u1');
    await c.load();
    expect(repo.etags, ['W/"0"']);
    expect(c.state.items.single.id, 'old'); // 304 kept the snapshot
    expect(c.state.nextCursor, 'C0');
    expect(c.state.refreshing, isFalse);
    expect(c.state.error, isNull);
  });

  test('200 replaces state and persists raw json + etag', () async {
    final cache = CacheStore.memory();
    final repo = _Repo();
    final c = _make(repo, cache, 'u1');
    await c.load();
    expect(repo.etags, [null]);
    expect(c.state.items.single.id, 'n1');
    final e = await cache.read('u1', 'notifications');
    expect(e!.etag, 'W/"1"');
    expect((e.data as Map)['unreadCount'], 1);
    // Next load sends the etag.
    await c.load();
    expect(repo.etags.last, 'W/"1"');
  });

  test('mutation nulls the etag and drops the snapshot', () async {
    final cache = CacheStore.memory();
    final repo = _Repo();
    final c = _make(repo, cache, 'u1');
    await c.load();
    await c.markRead('n1');
    await _settle();
    expect((await cache.read('u1', 'notifications'))?.data, isNull);
    await c.load();
    expect(repo.etags.last, isNull);
  });

  test('clear wipes the account snapshot', () async {
    final cache = CacheStore.memory();
    final c = _make(_Repo(), cache, 'u1');
    await c.load();
    c.clear();
    await _settle();
    expect(await cache.read('u1', 'notifications'), isNull);
    expect(c.state.hasData, isFalse);
  });

  test('account B never sees account A data', () async {
    final cache = CacheStore.memory();
    await cache.write('uA', 'notifications', _raw('a-only'), etag: 'W/"a"');
    final repo = _Repo();
    final c = _make(repo, cache, 'uB');
    await c.load();
    expect(repo.etags, [null]);
    expect(c.state.items.map((n) => n.id), ['n1']);
  });

  test('invalid account id skips the disk cache', () async {
    final cache = CacheStore.memory();
    final repo = _Repo();
    final c = _make(repo, cache, '../evil');
    await c.load();
    expect(c.state.items.single.id, 'n1');
  });

  test('markStale is lazy: no fetch without listeners, fetch with', () async {
    final repo = _Repo();
    final c = _make(repo, CacheStore.memory(), 'u1');
    c.markStale();
    await _settle();
    expect(repo.etags, isEmpty);
    final remove = c.addListener((_) {});
    c.markStale();
    await _settle();
    expect(repo.etags, hasLength(1));
    remove();
  });
}
