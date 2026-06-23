import 'dart:typed_data';

import 'auth_api.dart';
import 'auth_models.dart';
import 'secure_token_store.dart';

class AuthRepository {
  AuthRepository(this._api, this._store);

  final AuthApi _api;
  final SecureTokenStore _store;

  // Attempts to restore a session from stored refresh token.
  // Returns the authenticated user or null if no stored session.
  Future<AuthUser?> restoreSession() async {
    final refreshToken = await _store.getRefreshToken();
    if (refreshToken == null) return null;
    try {
      final accessToken = await _api.refreshSession(refreshToken);
      await _store.saveAccessToken(accessToken);
      return await _api.getMe(accessToken);
    } on ApiException {
      await _store.clear();
      return null;
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

  Future<AuthUser> getMe() => _withRefresh(_api.getMe);

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

  Future<({String uploadUrl, String publicUrl, String key})> requestPhotoUploadUrl({
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
