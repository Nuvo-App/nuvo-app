// Widget coverage for the redesigned inbox: compact header (icon mark-all-
// read + unread count), the grouped row stack, and the inline Accept/Decline
// on a pending crew request — which must resolve through the crew controller
// and retire the notification without leaving the screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/notifications/presentation/notifications_screen.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

class _FakeNotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: [], unreadCount: 0);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> markAllRead() async {}
}

class _Inbox extends NotificationController {
  _Inbox(List<NuvoNotification> items) : super(_FakeNotifRepo()) {
    state = NotificationState(
      items: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }

  // The screen calls load() on mount — hold the seeded fixture instead of
  // refetching (the fake repo returns an empty page).
  @override
  Future<void> load({bool force = true}) => Future.value();
}

class _StubCrewRepo extends CrewRepository {
  _StubCrewRepo() : super(CrewApi(), SecureTokenStore(), AuthApi());

  final accepted = <String>[];
  final declined = <String>[];

  @override
  Future<List<PublicUser>> getCrew() async => const [];

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<void> acceptRequest(String userId) async => accepted.add(userId);

  @override
  Future<void> declineRequest(String userId) async => declined.add(userId);
}

NuvoNotification _notif({
  required String id,
  required String category,
  String? actorName,
  bool read = false,
  NuvoDestination? dest,
}) =>
    NuvoNotification(
      id: id,
      category: category,
      title: actorName == null ? 'A thing happened' : '$actorName did a thing',
      body: 'Some context',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 8)),
      read: read,
      actorName: actorName,
      destination: dest,
    );

Widget _app(NotificationController inbox, _StubCrewRepo crewRepo) {
  late NotificationController inboxRef;
  inboxRef = inbox;
  return ProviderScope(
    overrides: [
      notificationControllerProvider.overrideWith((_) => inboxRef),
      crewControllerProvider.overrideWith(
        (ref) => CrewController(
          crewRepo,
          onRequestResolved: (id) =>
              ref
                  .read(notificationControllerProvider.notifier)
                  .resolveCrewRequest(id),
        ),
      ),
    ],
    child: const MaterialApp(home: NotificationsScreen()),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('compact header: title, unread count, icon mark-all-read',
      (tester) async {
    final inbox = _Inbox([
      _notif(id: 'a', category: 'race_joined', actorName: 'Maya'),
      _notif(id: 'b', category: 'race_completed', actorName: 'Riley'),
      _notif(id: 'c', category: 'proof_accepted', read: true),
    ]);
    await tester.pumpWidget(_app(inbox, _StubCrewRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('2 unread'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    // The text button is gone — the icon carries the action.
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('pending crew request shows inline Accept/Decline; accept '
      'retires the row', (tester) async {
    final crewRepo = _StubCrewRepo();
    final inbox = _Inbox([
      _notif(
        id: 'req',
        category: 'crew_request',
        actorName: 'Sam',
        dest: const ProfileDestination('sam-id'),
      ),
      _notif(id: 'other', category: 'race_joined', actorName: 'Maya'),
    ]);
    await tester.pumpWidget(_app(inbox, crewRepo));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(crewRepo.accepted, ['sam-id']);
    expect(inbox.state.items.first.read, isTrue);
    expect(inbox.state.unreadCount, 1);
    // Resolved request: action row collapses.
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('read crew_request is not actionable', (tester) async {
    final inbox = _Inbox([
      _notif(
        id: 'req',
        category: 'crew_request',
        actorName: 'Sam',
        read: true,
        dest: const ProfileDestination('sam-id'),
      ),
    ]);
    await tester.pumpWidget(_app(inbox, _StubCrewRepo()));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('mark all read icon clears the unread count', (tester) async {
    final inbox = _Inbox([
      _notif(id: 'a', category: 'race_joined', actorName: 'Maya'),
      _notif(id: 'b', category: 'race_starting', read: true),
    ]);
    await tester.pumpWidget(_app(inbox, _StubCrewRepo()));
    await tester.pumpAndSettle();
    expect(find.text('1 unread'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.done_all_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('unread'), findsNothing);
    expect(find.byIcon(Icons.done_all_rounded), findsNothing);
  });
}
