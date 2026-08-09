import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    final url = '$_kApiBase$path';
    try {
      final res = await _client.post(
        Uri.parse(url),
        headers: _headers(accessToken: accessToken),
        body: jsonEncode(body),
      );
      debugPrint('[AuthApi] POST $path → ${res.statusCode}');
      if (res.statusCode >= 400) {
        final snippet = res.body.length > 200
            ? res.body.substring(0, 200)
            : res.body;
        debugPrint('[AuthApi] error body: $snippet');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(
          res.statusCode,
          json['error'] as String? ?? 'Request failed',
        );
      }
      return json;
    } catch (e) {
      if (e is ApiException) rethrow;
      // Network-level failure (CORS blocked, no connectivity, etc.)
      debugPrint('[AuthApi] POST $path network error (${e.runtimeType}): $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _get(String path, {String? accessToken}) async {
    try {
      final res = await _client.get(
        Uri.parse('$_kApiBase$path'),
        headers: _headers(accessToken: accessToken),
      );
      debugPrint('[AuthApi] GET $path → ${res.statusCode}');
      if (res.statusCode >= 400) {
        final snippet = res.body.length > 200
            ? res.body.substring(0, 200)
            : res.body;
        debugPrint('[AuthApi] error body: $snippet');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException(
          res.statusCode,
          json['error'] as String? ?? 'Request failed',
        );
      }
      return json;
    } catch (e) {
      if (e is ApiException) rethrow;
      debugPrint('[AuthApi] GET $path network error (${e.runtimeType}): $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    String? accessToken,
  }) async {
    final url = '$_kApiBase$path';
    try {
      final res = await _client.delete(
        Uri.parse(url),
        headers: _headers(accessToken: accessToken),
      );
      debugPrint('[AuthApi] DELETE $path → ${res.statusCode}');
      if (res.statusCode >= 400) {
        final snippet = res.body.length > 200
            ? res.body.substring(0, 200)
            : res.body;
        debugPrint('[AuthApi] error body: $snippet');
      }
      if (res.statusCode >= 400) {
        // Don't let a non-JSON error body mask the original API error.
        String message;
        try {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          message = json['error'] as String? ?? 'Request failed';
        } catch (_) {
          message = 'Request failed';
        }
        throw ApiException(res.statusCode, message);
      }
      try {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        throw ApiException(res.statusCode, 'Request failed');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      // Network-level failure (CORS blocked, no connectivity, etc.)
      debugPrint('[AuthApi] DELETE $path network error (${e.runtimeType}): $e');
      rethrow;
    }
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

  Future<AuthResponse> signInReviewer(String email, String password) async {
    final json = await _post('/auth/reviewer', {
      'email': email,
      'password': password,
    });
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

  Future<void> acceptTerms(String accessToken) =>
      _post('/auth/terms', {}, accessToken: accessToken);

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<void> saveProfile(
    String accessToken, {
    String? fullName,
    String? username,
    bool? privateProfile,
    String? profilePhotoUrl,
    bool removePhoto = false,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (username != null) body['username'] = username;
    if (privateProfile != null) body['privateProfile'] = privateProfile;
    if (removePhoto) {
      body['profilePhotoUrl'] = null;
    } else if (profilePhotoUrl != null) {
      body['profilePhotoUrl'] = profilePhotoUrl;
    }
    if (body.containsKey('profilePhotoUrl')) {
      debugPrint('PATCH_PROFILE_PHOTO_URL: ${body['profilePhotoUrl']}');
    }
    await _post('/profile', body, accessToken: accessToken);
  }

  /// Step 1 of photo upload: ask the backend for a signed upload URL.
  /// Returns { uploadUrl: "...", publicUrl: "...", key: "..." }.
  Future<({String uploadUrl, String publicUrl, String key})>
  requestPhotoUploadUrl(
    String accessToken, {
    required String fileName,
    required String contentType,
  }) async {
    final json = await _post('/profile/photo/upload-url', {
      'fileName': fileName,
      'contentType': contentType,
    }, accessToken: accessToken);
    final publicUrl = json['publicUrl'] as String;
    debugPrint('UPLOAD_PUBLIC_URL: $publicUrl');
    return (
      uploadUrl: json['uploadUrl'] as String,
      publicUrl: publicUrl,
      key: json['key'] as String,
    );
  }

  /// Step 2: PUT the image bytes directly to the signed R2 URL.
  /// No auth header — the signature in the URL is the credential.
  Future<void> uploadBytesToSignedUrl(
    String signedUrl,
    Uint8List bytes,
    String contentType,
  ) async {
    final res = await _client.put(
      Uri.parse(signedUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Photo upload failed');
    }
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
