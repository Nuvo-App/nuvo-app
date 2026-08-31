import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// On web: uses window.localStorage via package:web (no WebCrypto, no DomException).
// On native: stub — all paths go through flutter_secure_storage.
//
// RULE (pitfall B1, docs/agents/10-pitfalls-and-fixes.md §B): storage errors are
// transient. Retry a read once; NEVER wipe tokens on a read/write error. clear()
// deletes only the two Nuvo keys — never deleteAll() / the whole Keychain. A
// single flaky Keychain read used to log every user out on cold launch.
import '_ls_stub.dart' if (dart.library.html) '_ls_web.dart' as ls;

class SecureTokenStore {
  static const _accessKey = 'nuvo_access_token';
  static const _refreshKey = 'nuvo_refresh_token';

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    if (kIsWeb) {
      ls.setItem(_accessKey, accessToken);
      ls.setItem(_refreshKey, refreshToken);
      final readback = ls.getItem(_accessKey);
      debugPrint(
        '[TokenStore] web saveTokens — readback ok: ${readback != null}',
      );
      return;
    }
    try {
      await Future.wait([
        _secureStorage.write(key: _accessKey, value: accessToken),
        _secureStorage.write(key: _refreshKey, value: refreshToken),
      ]);
    } catch (e) {
      // Do NOT wipe storage here — a transient Keychain error while writing
      // must not also destroy an existing valid session.
      debugPrint('[TokenStore] native saveTokens failed (${e.runtimeType})');
      rethrow;
    }
  }

  Future<void> saveAccessToken(String token) async {
    if (kIsWeb) {
      ls.setItem(_accessKey, token);
      debugPrint('[TokenStore] web saveAccessToken ok');
      return;
    }
    try {
      await _secureStorage.write(key: _accessKey, value: token);
    } catch (e) {
      debugPrint(
        '[TokenStore] native saveAccessToken failed (${e.runtimeType})',
      );
      rethrow;
    }
  }

  /// Read a key, retrying once on a transient Keychain error before giving up.
  /// Never wipes storage.
  Future<String?> _readNative(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      debugPrint('[TokenStore] native read($key) failed once (${e.runtimeType})');
      try {
        return await _secureStorage.read(key: key);
      } catch (e2) {
        debugPrint('[TokenStore] native read($key) failed twice (${e2.runtimeType})');
        return null;
      }
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final token = ls.getItem(_accessKey);
      debugPrint('[TokenStore] web access token exists: ${token != null}');
      return token;
    }
    return _readNative(_accessKey);
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final token = ls.getItem(_refreshKey);
      debugPrint('[TokenStore] web refresh token exists: ${token != null}');
      return token;
    }
    return _readNative(_refreshKey);
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  Future<void> clear() async {
    if (kIsWeb) {
      ls.removeItem(_accessKey);
      ls.removeItem(_refreshKey);
      debugPrint('[TokenStore] web: tokens cleared');
      return;
    }
    try {
      await Future.wait([
        _secureStorage.delete(key: _accessKey),
        _secureStorage.delete(key: _refreshKey),
      ]);
    } catch (e) {
      debugPrint('[TokenStore] native clear failed (${e.runtimeType})');
    }
  }
}
