import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../../core/network/conditional.dart';
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

  String? _lastEtag;
  Object? _lastRaw;

  Future<ArenaSnapshot> getArenaSnapshot() async {
    final result = await _withRefresh((t) => _api.fetchArenaSnapshot(t));
    _lastEtag = result.etag;
    _lastRaw = result.raw;
    return result.data!;
  }

  /// Conditional fetch. With no [etag] this is a plain [getArenaSnapshot]
  /// (and reports that fetch's ETag); with one it sends If-None-Match and
  /// returns a not-modified result on 304.
  Future<Conditional<ArenaSnapshot>> getArenaSnapshotConditional({
    String? etag,
  }) async {
    if (etag == null) {
      final snapshot = await getArenaSnapshot();
      return Conditional(data: snapshot, etag: _lastEtag, raw: _lastRaw);
    }
    return _withRefresh((t) => _api.fetchArenaSnapshot(t, etag: etag));
  }
}
