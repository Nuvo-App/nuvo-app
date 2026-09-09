import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  GoRouter? _router;

  bool get isAvailable => _available;

  /// Call once from app start, after the router exists.
  Future<void> start(GoRouter router) async {
    if (_started) return;
    _started = true;
    _router = router;
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
    final token = _lastToken;
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

  void _routeFromMessage(RemoteMessage message) {
    final data = message.data;
    String? nn(Object? v) => (v is String && v.isNotEmpty) ? v : null;
    final dest = NuvoDestination.fromDescriptor({
      'type': nn(data['destType']),
      'id': nn(data['destId']),
      'context': nn(data['destContext']),
    });
    if (dest == null) return;
    _ref.read(notificationControllerProvider.notifier).markStale();
    _router?.go(dest.location);
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
