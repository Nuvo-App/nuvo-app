import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_models.dart';
import 'secure_token_store.dart';

/// Outcome of an attempt to restore a session on launch.
sealed class RestoreResult {
  const RestoreResult();
}

/// A valid session was restored.
class RestoreOk extends RestoreResult {
  const RestoreOk(this.user);
  final AuthUser user;
}

/// There is definitively no session (no stored token, or the server rejected
/// the refresh/identity with a 401/404). Tokens have been cleared.
class RestoreNoSession extends RestoreResult {
  const RestoreNoSession();
}

/// We hold a refresh token but could not reach the server (offline, timeout,
/// 5xx). Tokens are KEPT — the caller should show a retry affordance, never
/// log the user out.
class RestoreUnreachable extends RestoreResult {
  const RestoreUnreachable();
}

/// Refresh-token sentinel marking a debug-only offline demo session. Real
/// tokens never carry this prefix, so restore can short-circuit on it
/// instead of hitting the network.
const kOfflineDemoRefreshToken = 'offline-demo-refresh';

class AuthRepository {
  AuthRepository(this._api, this._store);

  final AuthApi _api;
  final SecureTokenStore _store;

  /// Attempts to restore a session from the stored refresh token.
  ///
  /// Only clears tokens on a *definitive* rejection (401/404). Transient
  /// failures (network, 5xx) return [RestoreUnreachable] and keep the tokens so
  /// a launch with no connectivity does not silently sign the user out.
  Future<RestoreResult> restoreSession() async {
    final refreshToken = await _store.getRefreshToken();
    if (refreshToken == null) return const RestoreNoSession();
    // Debug-only offline demo session — skip the network entirely.
    if (refreshToken == kOfflineDemoRefreshToken) {
      return RestoreOk(offlineDemoUser());
    }

    final String accessToken;
    try {
      accessToken = await _api.refreshSession(refreshToken);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _store.clear();
        return const RestoreNoSession();
      }
      return _unreachableOrDemo();
    } catch (_) {
      return _unreachableOrDemo();
    }

    await _store.saveAccessToken(accessToken);

    try {
      final user = await _api.getMe(accessToken);
      // Stamp the account email so a later offline launch can prove this
      // session belongs to the reviewer/demo identity.
      await _store.saveAccountEmail(user.email);
      return RestoreOk(user);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) {
        await _store.clear();
        return const RestoreNoSession();
      }
      return _unreachableOrDemo();
    } catch (_) {
      return _unreachableOrDemo();
    }
  }

  /// Whether the stored session may fall back to the fully local demo
  /// session when the server can't be reached. Same rule as
  /// AuthController._offlineDemoAllowed, keyed off the stored account email
  /// (the only identity an offline restore has): the dedicated store-review
  /// credential always qualifies; in debug builds the presentation-toggle
  /// account and sessions that predate email persistence (no stored email)
  /// qualify too — a dead retry screen helps no one while developing or
  /// demoing.
  bool _offlineDemoAllowedForEmail(String? email) {
    final e = email?.trim().toLowerCase();
    if (e == 'team@getnuvo.net') return true;
    if (!kDebugMode) return false;
    return e == null ||
        e.isEmpty ||
        e == 'sideswifter2010@gmail.com';
  }

  /// Unreachable restore for a session that belongs to the reviewer/demo
  /// identity lands in the local demo session instead of the offline
  /// retry — that account is fixture-only anyway. Everyone else keeps the
  /// tokens + retry contract unchanged.
  Future<RestoreResult> _unreachableOrDemo() async {
    if (_offlineDemoAllowedForEmail(await _store.getAccountEmail())) {
      return RestoreOk(offlineDemoUser());
    }
    return const RestoreUnreachable();
  }

  // Wraps an authenticated API call. On 401 silently refreshes the access
  // token once and retries, then propagates any further failures.
  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final refreshToken = await _store.getRefreshToken();
      if (refreshToken == null) {
        await _store.clear();
        rethrow;
      }
      final newToken = await _api.refreshSession(refreshToken);
      await _store.saveAccessToken(newToken);
      return await call(newToken);
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<void> startEmailAuth(String email) => _api.startEmailAuth(email);

  Future<AuthUser> verifyEmailCode(String email, String code) async {
    final res = await _api.verifyEmailCode(email, code);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    await _store.saveAccountEmail(res.user.email);
    return res.user;
  }

  Future<AuthUser> signInWithGoogle(String idToken) async {
    final res = await _api.signInWithGoogle(idToken);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    await _store.saveAccountEmail(res.user.email);
    return res.user;
  }

  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async {
    final res = await _api.signInWithApple(
      idToken,
      fullName: fullName,
      authorizationCode: authorizationCode,
    );
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    await _store.saveAccountEmail(res.user.email);
    return res.user;
  }

  Future<AuthUser> signInReviewer(String email, String password) async {
    final res = await _api.signInReviewer(email, password);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    await _store.saveAccountEmail(res.user.email);
    return res.user;
  }

  /// Debug-only: local session for the dedicated store-testing identity when
  /// the API is unreachable. Writes sentinel tokens so cold-start restore
  /// re-enters the same offline session instead of bouncing to a retry.
  Future<AuthUser> signInOfflineDemo() async {
    final user = offlineDemoUser();
    await _store.saveTokens(
      accessToken: 'offline-demo-access',
      refreshToken: kOfflineDemoRefreshToken,
    );
    await _store.saveAccountEmail(user.email);
    return user;
  }

  Future<AuthUser> getMe() => _withRefresh(_api.getMe);

  Future<void> acceptTerms() => _withRefresh(_api.acceptTerms);

  Future<void> attestAge() => _withRefresh(_api.attestAge);

  Future<Map<String, dynamic>> getMotionConsent() =>
      _withRefresh(_api.getMotionConsent);

  Future<Map<String, dynamic>> setMotionConsent({required bool consented}) =>
      _withRefresh(
        (token) => _api.setMotionConsent(token, consented: consented),
      );

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<void> saveProfile({
    String? fullName,
    String? username,
    bool? privateProfile,
    String? profilePhotoUrl,
    bool removePhoto = false,
  }) => _withRefresh(
    (token) => _api.saveProfile(
      token,
      fullName: fullName,
      username: username,
      privateProfile: privateProfile,
      profilePhotoUrl: profilePhotoUrl,
      removePhoto: removePhoto,
    ),
  );

  Future<({String uploadUrl, String publicUrl, String key})>
  requestPhotoUploadUrl({
    required String fileName,
    required String contentType,
  }) => _withRefresh(
    (token) => _api.requestPhotoUploadUrl(
      token,
      fileName: fileName,
      contentType: contentType,
    ),
  );

  Future<void> uploadBytesToSignedUrl(
    String signedUrl,
    Uint8List bytes,
    String contentType,
  ) => _api.uploadBytesToSignedUrl(signedUrl, bytes, contentType);

  Future<bool> checkUsername(String username) =>
      _withRefresh((token) => _api.checkUsername(token, username));

  Future<void> completeOnboarding() => _withRefresh(_api.completeOnboarding);

  // ── Pass ──────────────────────────────────────────────────────────────────

  Future<PassInfo> getMemberPass() => _withRefresh(_api.getMemberPass);

  // ── Session management ────────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await _withRefresh(_api.logout);
    } catch (_) {
      // Best-effort server logout; always clear local tokens. Transport
      // failures (offline, TLS) must not escape — logout is always local-first.
    }
    await _store.clear();
  }

  // Clears stored tokens without attempting a server-side logout.
  // Use this when the server already rejected the session (401) so we don't
  // make a pointless API call that will fail.
  Future<void> clearSession() => _store.clear();

  Future<void> deleteAccount() async {
    await _withRefresh(_api.deleteAccount);
    await _store.clear();
  }
}
