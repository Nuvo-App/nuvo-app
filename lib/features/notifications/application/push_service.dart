import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../social/application/deep_link_controller.dart';
import '../../social/domain/nuvo_destination.dart';
import '../data/device_api.dart';
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
  String? _lastToken;

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
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // A tap that cold-started the app.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _routeFromMessage(initial);

    FirebaseMessaging.onMessageOpenedApp.listen(_routeFromMessage);

    // Foreground receipt — the OS won't show a banner, but the inbox should
    // reflect it immediately.
    FirebaseMessaging.onMessage.listen((_) {
      _ref.read(notificationControllerProvider.notifier).markStale();
    });

    messaging.onTokenRefresh.listen(_syncToken);
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
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _syncToken(token);
    }
    return granted;
  }

  /// Re-sync the token after sign-in (a token minted while logged out isn't
  /// attached to any user yet).
  Future<void> onSignedIn() async {
    if (!_available) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _syncToken(token);
  }

  Future<void> onSignedOut() async {
    // _lastToken is in-memory only — after an app restart between token sync
    // and sign-out it's null, so ask the SDK for the live token to make sure
    // this device's backend row is really detached.
    var token = _lastToken;
    if (token == null && _available) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    if (token != null) await _deviceApi.unregister(token);
    _lastToken = null;
  }

  Future<void> _syncToken(String token) async {
    _lastToken = token;
    await _deviceApi.register(
      token,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
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

  void _routeFromMessage(RemoteMessage message) {
    final dest = destinationFromPushData(message.data);
    if (dest == null) return;
    _ref.read(notificationControllerProvider.notifier).markStale();
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
