import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_api.dart';
import '../data/auth_models.dart';
import '../data/auth_repository.dart';
import '../data/secure_token_store.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({required this.status, this.user, this.error});
  final AuthStatus status;
  final AuthUser? user;
  final String? error;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo)
      : super(const AuthState(status: AuthStatus.loading)) {
    _init();
  }

  final AuthRepository _repo;

  Future<void> _init() async {
    try {
      final user = await _repo.restoreSession();
      if (mounted) {
        state = user != null
            ? AuthState(status: AuthStatus.authenticated, user: user)
            : const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (_) {
      if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> startEmailAuth(String email) => _repo.startEmailAuth(email);

  Future<void> verifyEmailCode(String email, String code) async {
    final user = await _repo.verifyEmailCode(email, code);
    if (mounted) state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> signInWithGoogle(String idToken) async {
    final user = await _repo.signInWithGoogle(idToken);
    if (mounted) state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<void> saveProfile({
    String? fullName,
    String? username,
    bool? privateProfile,
  }) async {
    await _repo.saveProfile(
      fullName: fullName,
      username: username,
      privateProfile: privateProfile,
    );
    final user = await _repo.getMe();
    if (mounted) state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<bool> checkUsername(String username) => _repo.checkUsername(username);

  Future<void> completeOnboarding() async {
    await _repo.completeOnboarding();
    final user = await _repo.getMe();
    if (mounted) state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  Future<PassInfo> getMemberPass() => _repo.getMemberPass();

  Future<void> logout() async {
    await _repo.logout();
    if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final secureTokenStoreProvider = Provider<SecureTokenStore>((_) => SecureTokenStore());

final authApiProvider = Provider<AuthApi>((_) => AuthApi());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(secureTokenStoreProvider),
  );
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});
