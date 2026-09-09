import '../../auth/data/auth_api.dart';
import '../../auth/data/secure_token_store.dart';
import 'notification_api.dart';
import 'notification_models.dart';

class NotificationRepository {
  NotificationRepository(this._api, this._store, this._authApi);

  final NotificationApi _api;
  final SecureTokenStore _store;
  final AuthApi _authApi;

  Future<NotificationPage> list({String? cursor}) =>
      _withRefresh((t) => _api.list(t, cursor: cursor));
  Future<void> markRead(String id) => _withRefresh((t) => _api.markRead(t, id));
  Future<void> markAllRead() => _withRefresh(_api.markAllRead);

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
