import 'dart:typed_data';

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

    final String accessToken;
    try {
      accessToken = await _api.refreshSession(refreshToken);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _store.clear();
        return const RestoreNoSession();
      }
      return const RestoreUnreachable();
    } catch (_) {
      return const RestoreUnreachable();
    }

    await _store.saveAccessToken(accessToken);

    try {
      final user = await _api.getMe(accessToken);
      return RestoreOk(user);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) {
        await _store.clear();
        return const RestoreNoSession();
      }
      return const RestoreUnreachable();
    } catch (_) {
      return const RestoreUnreachable();
    }
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
    return res.user;
  }

  Future<AuthUser> signInWithGoogle(String idToken) async {
    final res = await _api.signInWithGoogle(idToken);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    return res.user;
  }

  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
  }) async {
    final res = await _api.signInWithApple(idToken, fullName: fullName);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    return res.user;
  }

  Future<AuthUser> signInReviewer(String email, String password) async {
    final res = await _api.signInReviewer(email, password);
    await _store.saveTokens(
      accessToken: res.accessToken,
      refreshToken: res.refreshToken,
    );
    return res.user;
  }

  Future<AuthUser> getMe() => _withRefresh(_api.getMe);

  Future<void> acceptTerms() => _withRefresh(_api.acceptTerms);

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
    } on ApiException {
      // Best-effort server logout; always clear local tokens.
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
