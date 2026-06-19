import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  static const _opts = IOSOptions(accessibility: KeychainAccessibility.first_unlock);
  static const _storage = FlutterSecureStorage(iOptions: _opts);

  static const _accessKey = 'nuvo_access_token';
  static const _refreshKey = 'nuvo_refresh_token';
  static const _userIdKey = 'nuvo_user_id';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      Future.wait([
        _storage.write(key: _accessKey, value: accessToken),
        _storage.write(key: _refreshKey, value: refreshToken),
      ]).then((_) {});

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessKey, value: token);

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> saveUserId(String id) =>
      _storage.write(key: _userIdKey, value: id);

  Future<void> clear() => _storage.deleteAll();
}
