import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';

/// Practice-mode auth: a stand-in AuthController that holds a throwaway
/// local user. It never touches the repository, the token store, the
/// network or the real session — nothing here can write to an account.
/// Any AuthController method it does not implement throws (no silent calls).
class SandboxAuth extends StateNotifier<AuthState> implements AuthController {
  SandboxAuth() : super(const AuthState(status: AuthStatus.unauthenticated));

  static const _email = 'practice@nuvo.invalid';

  void _signedIn() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      user: AuthUser(
        id: 'practice',
        email: _email,
        onboardingComplete: false,
        hasMemberPass: false,
        termsAccepted: false,
      ),
    );
  }

  @override
  Future<void> startEmailAuth(String email) async {}

  @override
  Future<void> verifyEmailCode(String email, String code) async => _signedIn();

  @override
  Future<void> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async => _signedIn();

  @override
  Future<void> signInWithGoogle(String idToken) async => _signedIn();

  @override
  Future<bool> checkUsername(String username) async =>
      username.toLowerCase() != 'taken';

  @override
  Future<void> acceptTerms() async {}

  @override
  Future<void> attestAge() async {}

  @override
  Future<void> saveProfile({String? fullName, String? username}) async {
    final u = state.user;
    if (u == null) return;
    state = AuthState(
      status: AuthStatus.authenticated,
      user: u.copyWith(fullName: fullName, username: username),
    );
  }

  @override
  Future<void> completeOnboarding() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
