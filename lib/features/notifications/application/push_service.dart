import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../arena/presentation/arena_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../crew/application/crew_controller.dart';
import '../../profile/application/activity_controller.dart';
import '../../social/data/crew_activity.dart';
import '../../profile/application/progression_controller.dart';
import '../../races/presentation/race_controller.dart';
import '../../social/application/deep_link_controller.dart';
import '../../social/domain/nuvo_destination.dart';
import '../data/device_api.dart';
import '../domain/push_invalidation.dart';
import 'push_token_sync.dart';
import 'notification_controller.dart';

/// Push transport (docs/agents/19 §10). Push is DELIVERY; the notification
/// record (NotificationController) is the product state.
///
/// DORMANT until Firebase is configured. `Firebase.initializeApp()` throws
/// without `GoogleService-Info.plist` / `google-services.json`; that is caught
/// and the whole service becomes a set of no-ops. Everything else in the app
/// keeps working; the in-app inbox is unaffected.
class PushService {
  PushService(this._ref, {DeviceApi? deviceApi})
      : _deviceApi = deviceApi ?? DeviceApi();

  final Ref _ref;
  final DeviceApi _deviceApi;

  bool _available = false;
  bool _started = false;
  final Completer<void> _startDone = Completer<void>();
  _ResumeObserver? _resumeObserver;

  /// Owns getting this device's token onto the server (and keeping it there).
  late final PushTokenSync _sync = PushTokenSync(
    fetchToken: () => FirebaseMessaging.instance.getToken(),
    register: (token) => _deviceApi.register(
      token,
      platform: Platform.isIOS ? 'ios' : 'android',
    ),
    unregister: _deviceApi.unregister,
    isSignedIn: () =>
        _ref.read(authControllerProvider).status == AuthStatus.authenticated,
  );

  /// Latest reason a token did not reach the server (null when it did).
  String? get lastTokenFailure => _sync.lastFailure;

  bool get isAvailable => _available;

  /// Call once from app start, after the router exists (the router itself
  /// lives on DeepLinkController — taps route through it, not here).
  Future<void> start(GoRouter router) async {
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      _available = true;
    } catch (e) {
      debugPrint('[Push] Firebase not configured — push disabled ($e)');
      _startDone.complete();
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // A tap that cold-started the app.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _routeFromMessage(initial);

    FirebaseMessaging.onMessageOpenedApp.listen(_routeFromMessage);

    // Foreground receipt — the OS won't show a banner, but the inbox should
    // reflect it immediately.
    FirebaseMessaging.onMessage.listen((m) => _invalidateFor(m.data));

    messaging.onTokenRefresh.listen(_sync.onTokenRefresh);

    // A user who was already signed in when the app launched becomes
    // "authenticated" BEFORE Firebase finished starting, so onSignedIn was a
    // no-op and nothing else would ever sync their token. Do it now, and again
    // every time the app returns to the foreground.
    _startDone.complete();
    unawaited(_sync.syncNow());
    _resumeObserver = _ResumeObserver(() => unawaited(_sync.syncNow()));
    WidgetsBinding.instance.addObserver(_resumeObserver!);
  }

  /// The OS notification authorization state — the only honest source for
  /// "can we notify". Never inferred from whether a device token exists
  /// (a token says delivery plumbing worked once, not that the user
  /// currently allows alerts). Null when push transport is unavailable.
  Future<AuthorizationStatus?> notificationAuthorizationStatus() async {
    if (!_available) return null;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus;
    } catch (_) {
      return null;
    }
  }

  /// Contextual permission prompt — call it the first time push is relevant
  /// (after a first race join / first crew connection), never on cold launch.
  Future<bool> requestPermissionInContext() async {
    if (!_available) return false;
    final settings = await FirebaseMessaging.instance.requestPermission();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (granted) {
      unawaited(_reportedSync());
    } else {
      _ref.read(analyticsProvider).pushRegisterFailed(reason: 'denied');
    }
    return granted;
  }

  /// `push_registered` when the token lands on the server,
  /// `push_register_failed` when the sync reports a failure reason.
  Future<void> _reportedSync() async {
    await _sync.syncNow();
    final a = _ref.read(analyticsProvider);
    if (_sync.lastFailure == null) {
      a.pushRegistered();
    } else {
      a.pushRegisterFailed(reason: 'error');
    }
  }

  /// Re-sync the token after sign-in (a token minted while logged out isn't
  /// attached to any user yet). getToken throws apns-token-not-set until the
  /// APNs token materializes (always on simulator, briefly on device) — a
  /// missed sync here is harmless: onTokenRefresh re-syncs the moment it does.
  Future<void> onSignedIn() async {
    // Wait for Firebase to finish starting — signing in first used to make
    // this a silent no-op.
    await _startDone.future;
    if (!_available) return;
    await _sync.syncNow();
  }

  Future<void> onSignedOut() async {
    // The in-memory token is gone after an app restart between token sync and
    // sign-out — ask the SDK for the live one so this device's backend row is
    // really detached.
    if (_sync.knownToken == null && _available) {
      try {
        _sync.knownToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    await _sync.signOut();
  }

  /// Parse a push payload's data block into a destination — pure, so the
  /// mapping is testable without a RemoteMessage.
  static NuvoDestination? destinationFromPushData(Map<String, dynamic> data) {
    String? nn(Object? v) => (v is String && v.isNotEmpty) ? v : null;
    return NuvoDestination.fromDescriptor({
      'type': nn(data['destType']),
      'id': nn(data['destId']),
      'context': nn(data['destContext']),
    });
  }

  /// A push is a signal, not state: mark the affected domains stale so the
  /// owning controllers refetch (docs/agents/22 §5.5).
  void _invalidateFor(Map<String, dynamic> data) {
    final cat = data['category'];
    final dt = data['destType'];
    final domains = pushDomainsFor(
      cat is String ? cat : null,
      destType: dt is String ? dt : null,
    );
    void safe(void Function() f) {
      try {
        f();
      } catch (e) {
        debugPrint('[Push] invalidate failed ($e)');
      }
    }

    for (final d in domains) {
      switch (d) {
        case PushDomain.notifications:
          safe(() => _ref.read(notificationControllerProvider.notifier).markStale());
        case PushDomain.races:
          safe(() => _ref.read(raceControllerProvider.notifier).markStale());
        case PushDomain.arena:
          safe(() => _ref.read(arenaControllerProvider.notifier).markStale());
        case PushDomain.crew:
          safe(() => _ref.read(crewControllerProvider.notifier).markStale());
        case PushDomain.activity:
          // The crew feed, and the profile heat map (a proof lands in both).
          safe(() => _ref.read(crewActivityProvider.notifier).markStale());
          safe(() => _ref.invalidate(profileActivityProvider));
        case PushDomain.progression:
          safe(() => unawaited(
              _ref.read(progressionControllerProvider.notifier).load(force: true)));
      }
    }
  }

  void _routeFromMessage(RemoteMessage message) {
    _invalidateFor(message.data);
    final dest = destinationFromPushData(message.data);
    if (dest == null) return;
    // Notification open — the payload's destType enum ('race', 'crew', …),
    // never the notification body.
    final type = message.data['destType'];
    _ref
        .read(analyticsProvider)
        .notifOpened(type: type is String ? type : 'unknown');
    // Push taps take the same canonical path as every other inbound link:
    // auth-aware, pending-destination stashed when logged out — never a raw
    // router.go (which skipped requiresAuth and could leak a stale account's
    // destination into a logged-out or different account's session).
    final authed =
        _ref.read(authControllerProvider).status == AuthStatus.authenticated;
    unawaited(
      _ref.read(deepLinkControllerProvider).handleDestination(
            dest,
            authed: authed,
          ),
    );
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);
  final VoidCallback _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}
