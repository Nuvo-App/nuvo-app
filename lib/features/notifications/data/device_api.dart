import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/secure_token_store.dart';

const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

/// Register / unregister an FCM device token with the Worker. Auth-injected;
/// best-effort (a failed registration must never block sign-in or a race join).
class DeviceApi {
  DeviceApi({http.Client? client, SecureTokenStore? store})
      : _client = client ?? http.Client(),
        _store = store ?? SecureTokenStore();

  final http.Client _client;
  final SecureTokenStore _store;

  Future<void> register(String pushToken, {required String platform, String? appVersion}) async {
    final auth = await _store.getAccessToken();
    if (auth == null) return;
    try {
      await _client
          .post(
            Uri.parse('$_kApiBase/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $auth',
            },
            body: jsonEncode({
              'token': pushToken,
              'platform': platform,
              'appVersion': ?appVersion,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      /* best effort */
    } on SocketException {
      /* best effort */
    } on http.ClientException {
      /* best effort */
    }
  }

  Future<void> unregister(String pushToken) async {
    final auth = await _store.getAccessToken();
    if (auth == null) return;
    try {
      await _client
          .delete(
            Uri.parse('$_kApiBase/devices/$pushToken'),
            headers: {'Authorization': 'Bearer $auth'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {/* best effort */}
  }
}
