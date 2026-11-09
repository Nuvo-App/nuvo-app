// R3: "Create account" with the demo email is allowed even though the
// account exists — the sign-up intent reaches the server as 'signup', which
// resets the account so it walks onboarding like a brand-new user.
// R2: "Sign in" reaches it as 'signin' and keeps the seeded account.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/demo_account_marker.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';

const _u = AuthUser(
  id: 'r',
  email: 'testing@getnuvo.net',
  onboardingComplete: false,
  hasMemberPass: true,
  termsAccepted: false,
);

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
  final intents = <String>[];
  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();
  @override
  Future<AuthUser> signInReviewer(
    String email,
    String password, {
    String intent = 'signin',
  }) async {
    intents.add('$email|$password|$intent');
    return _u;
  }
}

void main() {
  test('R3: Create account with testing@getnuvo.net is allowed (signup)', () async {
    final repo = _Repo();
    final marker = MemoryDemoAccountMarker();
    final c = AuthController(repo, demoMarker: marker);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await c.signInReviewer(
      'testing@getnuvo.net',
      'testing123',
      intent: AuthIntent.signUp,
    );
    expect(repo.intents, ['testing@getnuvo.net|testing123|signup']);
    expect(c.state.status, AuthStatus.authenticated);
    expect(c.state.user!.onboardingComplete, isFalse);
    expect(marker.value, isTrue, reason: 'R1 marker set for the next cold start');
    c.dispose();
  });

  test('R2: Sign in with testing@getnuvo.net / testing123 uses signin', () async {
    final repo = _Repo();
    final c = AuthController(repo, demoMarker: MemoryDemoAccountMarker());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await c.signInReviewer(
      'testing@getnuvo.net',
      'testing123',
      intent: AuthIntent.signIn,
    );
    expect(repo.intents, ['testing@getnuvo.net|testing123|signin']);
    c.dispose();
  });
}
