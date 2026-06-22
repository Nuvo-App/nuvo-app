import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// On web: uses window.localStorage via package:web (no WebCrypto, no DomException).
// On native: stub — all paths go through flutter_secure_storage.
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
      debugPrint(
        '[TokenStore] native saveTokens failed (${e.runtimeType}) — clearing',
      );
      await _nativeClearAll();
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
        '[TokenStore] native saveAccessToken failed (${e.runtimeType}) — clearing',
      );
      await _nativeClearAll();
      rethrow;
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final token = ls.getItem(_accessKey);
      debugPrint('[TokenStore] web access token exists: ${token != null}');
      return token;
    }
    try {
      final exists = await _secureStorage.containsKey(key: _accessKey);
      debugPrint('[TokenStore] native access token exists: $exists');
      return await _secureStorage.read(key: _accessKey);
    } catch (e) {
      debugPrint(
        '[TokenStore] native access token read failed (${e.runtimeType}) — clearing',
      );
      await _nativeClearAll();
      return null;
    }
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final token = ls.getItem(_refreshKey);
      debugPrint('[TokenStore] web refresh token exists: ${token != null}');
      return token;
    }
    try {
      final exists = await _secureStorage.containsKey(key: _refreshKey);
      debugPrint('[TokenStore] native refresh token exists: $exists');
      return await _secureStorage.read(key: _refreshKey);
    } catch (e) {
      debugPrint(
        '[TokenStore] native refresh token read failed (${e.runtimeType}) — clearing',
      );
      await _nativeClearAll();
      return null;
    }
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  Future<void> clear() async {
    if (kIsWeb) {
      ls.removeItem(_accessKey);
      ls.removeItem(_refreshKey);
      debugPrint('[TokenStore] web: tokens cleared');
      return;
    }
    await _nativeClearAll();
  }

  Future<void> _nativeClearAll() async {
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      debugPrint('[TokenStore] native deleteAll failed (${e.runtimeType})');
    }
  }
}
