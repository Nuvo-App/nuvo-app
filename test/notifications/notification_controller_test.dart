// The crew-request ↔ inbox contract: resolving a request on the Crew screen
// must immediately retire its notification (the server already marked it read
// inside the same crew write — this is the local mirror, see
// NotificationController.resolveCrewRequest).
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

class _FakeNotifRepo implements NotificationRepository {
  int listCalls = 0;
  int markReadCalls = 0;
  int markAllReadCalls = 0;

  @override
  Future<NotificationPage> list({String? cursor}) async {
    listCalls++;
    return const NotificationPage(items: [], unreadCount: 0);
  }

  @override
  Future<void> markRead(String id) async {
    markReadCalls++;
  }

  @override
  Future<void> markAllRead() async {
    markAllReadCalls++;
  }
}

/// Inbox for the offline/presentation demo session — must never touch the
/// repository; the fixture feed is fully local.
class _DemoInbox extends NotificationController {
  _DemoInbox(NotificationRepository repo)
      : super(repo, isPresentationDemo: () => true);
}

class _Inbox extends NotificationController {
  _Inbox(NotificationRepository repo, List<NuvoNotification> items)
      : super(repo) {
    state = NotificationState(
      items: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }
}

NuvoNotification _notif({
  required String id,
  String category = 'crew_request',
  bool read = false,
  NuvoDestination? dest,
}) =>
    NuvoNotification(
      id: id,
      category: category,
      title: 'x wants to connect',
      createdAt: DateTime.now().toUtc(),
      read: read,
      destination: dest,
    );

void main() {
  group('resolveCrewRequest', () {
    test('marks the matching pending crew_request read + drops unread', () {
      final controller = _Inbox(_FakeNotifRepo(), [
        _notif(id: 'n1', dest: const ProfileDestination('sam')),
        _notif(id: 'n2', dest: const ProfileDestination('kim')),
        _notif(id: 'n3', category: 'race_joined'),
      ]);
      expect(controller.state.unreadCount, 3);

      controller.resolveCrewRequest('sam');

      final items = controller.state.items;
      expect(items[0].read, isTrue);
      expect(items[1].read, isFalse, reason: 'a different request stays unread');
      expect(items[2].read, isFalse);
      expect(controller.state.unreadCount, 2);
    });

    test('already-read and non-request categories are untouched', () {
      final controller = _Inbox(_FakeNotifRepo(), [
        _notif(id: 'n1', read: true, dest: const ProfileDestination('sam')),
        _notif(
          id: 'n2',
          category: 'crew_request_accepted',
          dest: const ProfileDestination('sam'),
        ),
      ]);
      controller.resolveCrewRequest('sam');
      expect(controller.state.items[0].read, isTrue);
      expect(controller.state.items[1].read, isFalse);
      expect(controller.state.unreadCount, 1);
    });

    test('no matching notification is a no-op', () {
      final controller = _Inbox(_FakeNotifRepo(), [
        _notif(id: 'n1', dest: const ProfileDestination('kim')),
      ]);
      controller.resolveCrewRequest('sam');
      expect(controller.state.items[0].read, isFalse);
      expect(controller.state.unreadCount, 1);
    });
  });

  group('markRead', () {
    test('is optimistic and calls the repo once', () async {
      final repo = _FakeNotifRepo();
      final controller = _Inbox(repo, [
        _notif(id: 'n1', category: 'race_joined'),
        _notif(id: 'n2', read: true, category: 'race_joined'),
      ]);
      await controller.markRead('n1');
      expect(controller.state.items[0].read, isTrue);
      expect(controller.state.unreadCount, 0);
      expect(repo.markReadCalls, 1);

      // Already-read rows must not hit the network again.
      await controller.markRead('n1');
      expect(repo.markReadCalls, 1);
    });
  });

  group('presentation demo', () {
    test('load() returns the fixture inbox without touching the repo', () async {
      final repo = _FakeNotifRepo();
      final controller = _DemoInbox(repo);
      await controller.load(force: false);

      expect(controller.state.items, isNotEmpty);
      expect(controller.state.loading, isFalse);
      expect(controller.state.error, isNull);
      expect(repo.listCalls, 0);
    });

    test('markRead/markAllRead update locally and never call the repo',
        () async {
      final repo = _FakeNotifRepo();
      final controller = _DemoInbox(repo);
      await controller.load(force: false);

      final unread =
          controller.state.items.firstWhere((n) => !n.read);
      await controller.markRead(unread.id);
      expect(controller.state.items.firstWhere((n) => n.id == unread.id).read,
          isTrue);
      expect(repo.markReadCalls, 0);

      await controller.markAllRead();
      expect(controller.state.unreadCount, 0);
      expect(repo.markAllReadCalls, 0);
    });
  });
}
