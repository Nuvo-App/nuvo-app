import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import 'arena_api.dart';
import 'arena_models.dart';

class ArenaRepository {
  ArenaRepository(this._api, this._store, this._authApi);

  final ArenaApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

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
      final newToken = await _authApi.refreshSession(refreshToken);
      await _store.saveAccessToken(newToken);
      return await call(newToken);
    }
  }

  Future<ArenaSnapshot> getArenaSnapshot() =>
      _withRefresh(_api.fetchArenaSnapshot);
}
