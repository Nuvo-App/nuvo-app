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
  Future<CrewRequestPage> getRequestPage() => _withRefresh(_api.getRequestPage);
  Future<List<CrewSearchResult>> search(String query) =>
      _withRefresh((token) => _api.search(token, query));
  Future<PublicProfileCard> getUser(String userId) =>
      _withRefresh((t) => _api.getUser(t, userId));
  Future<ConnectOutcome> add(String userId) =>
      _withRefresh((t) => _api.add(t, userId));
  Future<void> acceptRequest(String userId) =>
      _withRefresh((t) => _api.acceptRequest(t, userId));
  Future<void> declineRequest(String userId) =>
      _withRefresh((t) => _api.declineRequest(t, userId));
  Future<void> remove(String userId) => _withRefresh((t) => _api.remove(t, userId));

  Future<void> reportUser(String userId, {String? reason}) =>
      _withRefresh((t) => _api.reportUser(t, userId, reason: reason));
  Future<void> reportRace(String raceId, {String? reason}) =>
      _withRefresh((t) => _api.reportRace(t, raceId, reason: reason));
  Future<void> reportContent(String contentId, {String? reason}) =>
      _withRefresh((t) => _api.reportContent(t, contentId, reason: reason));
  Future<void> blockUser(String userId) =>
      _withRefresh((t) => _api.blockUser(t, userId));
  Future<void> unblockUser(String userId) =>
      _withRefresh((t) => _api.unblockUser(t, userId));

  Future<T> _withRefresh<T>(Future<T> Function(String token) call) async {
    final token = await _store.getAccessToken();
    if (token == null) throw const ApiException(401, 'Not authenticated');
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      // Never refresh an old request into a newly signed-in account.
      if (await _store.getAccessToken() != token) {
        throw const ApiException(409, 'Your account changed. Try again.');
      }
      final refresh = await _store.getRefreshToken();
      if (refresh == null) rethrow;
      final fresh = await _authApi.refreshSession(refresh);
      if (await _store.getRefreshToken() != refresh) {
        throw const ApiException(409, 'Your account changed. Try again.');
      }
      final currentToken = await _store.getAccessToken();
      if (currentToken != token) {
        if (currentToken == null) {
          throw const ApiException(409, 'Your account changed. Try again.');
        }
        return await call(currentToken);
      }
      await _store.saveAccessToken(fresh);
      return await call(fresh);
    }
  }
}
