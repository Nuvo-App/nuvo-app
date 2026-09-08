import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import 'invite_api.dart';
import 'invite_models.dart';

/// Token injection + 401 refresh for the invite endpoints, mirroring
/// RaceRepository. Preview works with or without a session.
class InviteRepository {
  InviteRepository(this._api, this._store, this._authApi);

  final InviteApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<InvitePreview> preview(String token) async {
    final auth = await _store.getAccessToken();
    return _api.preview(token, authToken: auth);
  }

  Future<InviteAcceptResult> accept(String token) =>
      _withRefresh((auth) => _api.accept(token, auth));

  Future<MintedInvite> mintRaceInvite(String raceId) => _withRefresh(
        (auth) => _api.mint(auth, kind: 'race_join', targetId: raceId),
      );

  Future<MintedInvite> mintMyCrewInvite() =>
      _withRefresh((auth) => _api.mint(auth, kind: 'crew_connect'));

  Future<void> revoke(String token) =>
      _withRefresh((auth) => _api.revoke(token, auth));

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
