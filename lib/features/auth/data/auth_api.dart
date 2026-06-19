import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_models.dart';

// Compile-time injectable base URL.
// Run with: flutter run --dart-define=NUVO_API_BASE_URL=http://localhost:8787
const _kApiBase = String.fromEnvironment(
  'NUVO_API_BASE_URL',
  defaultValue: 'https://nuvo-api.getnuvoapp.workers.dev',
);

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException $statusCode: $message';
}

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers({String? accessToken}) => {
    'Content-Type': 'application/json',
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final res = await _client.post(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode(body),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> _get(String path, {String? accessToken}) async {
    final res = await _client.get(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(accessToken: accessToken),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    String? accessToken,
  }) async {
    final res = await _client.delete(
      Uri.parse('$_kApiBase$path'),
      headers: _headers(accessToken: accessToken),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        json['error'] as String? ?? 'Request failed',
      );
    }
    return json;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> startEmailAuth(String email) =>
      _post('/auth/email/start', {'email': email});

  Future<AuthResponse> verifyEmailCode(String email, String code) async {
    final json = await _post('/auth/email/verify', {
      'email': email,
      'code': code,
    });
    return AuthResponse.fromJson(json);
  }

  Future<AuthResponse> signInWithGoogle(String idToken) async {
    final json = await _post('/auth/google', {'idToken': idToken});
    return AuthResponse.fromJson(json);
  }

  Future<String> refreshSession(String refreshToken) async {
    final json = await _post('/auth/refresh', {'refreshToken': refreshToken});
    return json['accessToken'] as String;
  }

  Future<void> logout(String accessToken) =>
      _post('/auth/logout', {}, accessToken: accessToken);

  Future<AuthUser> getMe(String accessToken) async {
    final json = await _get('/auth/me', accessToken: accessToken);
    return AuthUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> deleteAccount(String accessToken) =>
      _delete('/auth/account', accessToken: accessToken);

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<void> saveProfile(
    String accessToken, {
    String? fullName,
    String? username,
    bool? privateProfile,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (username != null) body['username'] = username;
    if (privateProfile != null) body['privateProfile'] = privateProfile;
    await _post('/profile', body, accessToken: accessToken);
  }

  Future<bool> checkUsername(String accessToken, String username) async {
    final json = await _post('/profile/username/check', {
      'username': username,
    }, accessToken: accessToken);
    return json['available'] as bool? ?? false;
  }

  Future<void> completeOnboarding(String accessToken) =>
      _post('/onboarding/complete', {}, accessToken: accessToken);

  // ── Pass ──────────────────────────────────────────────────────────────────

  Future<PassInfo> getMemberPass(String accessToken) async {
    final json = await _get('/pass/me', accessToken: accessToken);
    return PassInfo.fromJson(json);
  }
}
