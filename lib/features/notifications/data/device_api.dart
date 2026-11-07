import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../auth/data/secure_token_store.dart';
import '../../../core/network/api_base.dart';


/// Register / unregister an FCM device token with the Worker. Auth-injected;
/// best-effort (a failed registration must never block sign-in or a race join).
class DeviceApi {
  DeviceApi({http.Client? client, SecureTokenStore? store})
      : _client = client ?? http.Client(),
        _store = store ?? SecureTokenStore();

  final http.Client _client;
  final SecureTokenStore _store;

  /// True only when the server accepted the registration (2xx). A silent
  /// failure here means that device never receives a push, so the caller
  /// retries rather than assuming it worked.
  Future<bool> register(
    String pushToken, {
    required String platform,
    String? appVersion,
  }) async {
    final auth = await _store.getAccessToken();
    if (auth == null) return false;
    try {
      final res = await _client
          .post(
            Uri.parse('$kNuvoApiBase/devices'),
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
      return res.statusCode >= 200 && res.statusCode < 300;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    }
  }

  Future<void> unregister(String pushToken) async {
    final auth = await _store.getAccessToken();
    if (auth == null) return;
    try {
      await _client
          .delete(
            Uri.parse('$kNuvoApiBase/devices/$pushToken'),
            headers: {'Authorization': 'Bearer $auth'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {/* best effort */}
  }
}
