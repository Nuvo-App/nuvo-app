import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import '../../races/data/race_models.dart' show PublicUser;
import 'crew_api.dart';

/// Token injection + 401 refresh for the crew endpoints (mirrors RaceRepository).
class CrewRepository {
  CrewRepository(this._api, this._store, this._authApi);

  final CrewApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<List<PublicUser>> getCrew() => _withRefresh(_api.getCrew);
  Future<List<PublicUser>> getRequests() => _withRefresh(_api.getRequests);
  Future<PublicProfileCard> getUser(String userId) =>
      _withRefresh((t) => _api.getUser(t, userId));
  Future<ConnectOutcome> add(String userId) =>
      _withRefresh((t) => _api.add(t, userId));
  Future<void> acceptRequest(String userId) =>
      _withRefresh((t) => _api.acceptRequest(t, userId));
  Future<void> declineRequest(String userId) =>
      _withRefresh((t) => _api.declineRequest(t, userId));
  Future<void> remove(String userId) => _withRefresh((t) => _api.remove(t, userId));

  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      final refresh = await _store.getRefreshToken();
      if (refresh == null) {
        await _store.clear();
        rethrow;
      }
      final fresh = await _authApi.refreshSession(refresh);
      await _store.saveAccessToken(fresh);
      return await call(fresh);
    }
  }
}
