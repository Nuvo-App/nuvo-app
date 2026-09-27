// Push-tap routing coverage — the Phase 1A invariant: a push tap takes the
// SAME canonical path as every other inbound link.
//
//   push tap → NuvoDestination → DeepLinkController.handleDestination
//     → requiresAuth? → pending destination → auth → correct screen
//
// The previous path called `router.go(dest.location)` directly, which skipped
// requiresAuth and the pending-destination store — a logged-out tap (or a tap
// delivered around an account switch) could land on a screen that assumed an
// authenticated session. These tests pin the whole chain end-to-end:
//
//   payload → destinationFromPushData → handleDestination → router/pending

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/notifications/application/push_service.dart';
import 'package:nuvo/features/social/application/deep_link_controller.dart';
import 'package:nuvo/features/social/data/pending_destination_store.dart';
import 'package:nuvo/features/social/domain/nuvo_destination.dart';

/// In-memory pending store — the real one is secure-storage backed, which has
/// no method channel in tests. Same semantics: put → peek → consume-once.
class _FakePending extends PendingDestinationStore {
  String? stored;

  @override
  Future<void> put(NuvoDestination destination) async {
    stored = destination.location;
  }

  @override
  Future<String?> peek() async => stored;

  @override
  Future<String?> consume() async {
    final value = stored;
    stored = null;
    return value;
  }

  @override
  Future<void> clear() async {
    stored = null;
  }
}

/// No-plugin AppLinks — DeepLinkController.start() calls these members; the
/// real implementations would touch method channels. AppLinks is a singleton
/// (private constructor), so the fake implements the interface instead.
class _FakeAppLinks implements AppLinks {
  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();

  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Records `go()` calls. A GoRouter doesn't navigate headless (no widget
/// tree attaches the delegate to a RouteInformationProvider), so the unit
/// under test is the controller's contract — which location it asks the
/// router for — rather than the router's own matching.
class _SpyRouter implements GoRouter {
  final went = <String>[];

  @override
  void go(String location, {Object? extra}) {
    went.add(location);
  }

  String get last => went.last;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

_SpyRouter _router() => _SpyRouter();

DeepLinkController _controller(_FakePending pending) =>
    DeepLinkController(appLinks: _FakeAppLinks(), pending: pending);

void main() {
  group('PushService.destinationFromPushData', () {
    test('server descriptor payload → structured destination', () {
      final dest = PushService.destinationFromPushData({
        'destType': 'race',
        'destId': 'r-42',
        'destContext': 'review',
      });
      expect(dest, isA<RaceDestination>());
      expect(dest!.location, '/race/r-42/settings');
    });

    test('invite payload → non-auth destination', () {
      final dest = PushService.destinationFromPushData({
        'destType': 'invite',
        'destId': 'tok-9',
      });
      expect(dest, isA<InviteDestination>());
      expect(dest!.requiresAuth, isFalse);
      expect(dest.location, '/invite/tok-9');
    });

    test('notifications payload → inbox', () {
      final dest = PushService.destinationFromPushData({
        'destType': 'notifications',
      });
      expect(dest, isA<NotificationsDestination>());
      expect(dest!.location, '/notifications');
    });

    test('deleted/garbage destination → null (tap no-ops)', () {
      // A race or profile that no longer exists still parses — but a payload
      // with no resolvable destination must not navigate anywhere.
      expect(PushService.destinationFromPushData({}), isNull);
      expect(
        PushService.destinationFromPushData({'destType': 'unknown-kind'}),
        isNull,
      );
      expect(
        PushService.destinationFromPushData({'destType': 'race'}),
        isNull, // missing destId
      );
    });
  });

  group('DeepLinkController.handleDestination (push tap path)', () {
    test('warm app, signed in → navigates straight to the race', () async {
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      await c.handleDestination(
        const RaceDestination('r-7'),
        authed: true,
      );
      expect(router.last, '/race/r-7');
      expect(pending.stored, isNull);
    });

    test('warm app, signed out, auth-required → stash + /welcome', () async {
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      await c.handleDestination(
        const RaceDestination('r-7'),
        authed: false,
      );
      expect(router.last, '/welcome');
      expect(pending.stored, '/race/r-7');
    });

    test('signed out + non-auth destination (invite) → routes directly',
        () async {
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      await c.handleDestination(
        const InviteDestination('tok-1'),
        authed: false,
      );
      expect(router.last, '/invite/tok-1');
      expect(pending.stored, isNull);
    });

    test('cold start — router not wired yet → stash, never crash', () async {
      final pending = _FakePending();
      final c = _controller(pending); // start() never called — no router yet.

      await c.handleDestination(
        const NotificationsDestination(),
        authed: false,
      );
      expect(pending.stored, '/notifications');
    });

    test('account switch — pending survives the sign-in handoff once',
        () async {
      // Account A taps while logged out → race is stashed, /welcome shown.
      // Account B signs in → auth gate consumes the stashed location exactly
      // once. The store holds only a route string — no account-A data can
      // leak into account B's session beyond "where the tap wanted to go".
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      await c.handleDestination(
        const RaceDestination('r-9'),
        authed: false,
      );
      expect(pending.stored, '/race/r-9');

      // … auth gate on account B's authenticated transition:
      final stashed = await pending.consume();
      expect(stashed, '/race/r-9');
      expect(await pending.consume(), isNull); // consumed exactly once
    });
  });

  group('end-to-end: payload → destination → handleDestination', () {
    test('logged-in tap on a race_finished push lands on the race', () async {
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      final dest = PushService.destinationFromPushData({
        'destType': 'race',
        'destId': 'r-77',
      });
      expect(dest, isNotNull);
      await c.handleDestination(dest!, authed: true);
      expect(router.last, '/race/r-77');
    });

    test('unresolvable payload never touches the router or the store',
        () async {
      final pending = _FakePending();
      final router = _router();
      final c = _controller(pending);
      await c.start(router);

      final dest = PushService.destinationFromPushData({
        'destType': 'legacy-route',
        'destId': '/race/deleted',
      });
      // Mirrors PushService._routeFromMessage: null destination → bail out
      // before markStale / handleDestination — nothing navigates, nothing is
      // stashed for a destination that doesn't exist.
      expect(dest, isNull);
      if (dest != null) await c.handleDestination(dest);
      expect(router.went, isEmpty);
      expect(pending.stored, isNull);
    });
  });
}
