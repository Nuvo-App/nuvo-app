// R1 (docs/statements/demo-account.md): if the LAST account signed in on this
// device was testing@getnuvo.net, a cold start opens completely clean.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/demo_account_marker.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';

const _member = AuthUser(
  id: 'm1',
  email: 'member@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
  int cleared = 0;
  int restored = 0;
  @override
  Future<RestoreResult> restoreSession() async {
    restored++;
    return const RestoreOk(_member);
  }

  @override
  Future<void> clearSession() async => cleared++;
}

void main() {
  test('R1: marker set -> cold start is signed out, session + local onboarding '
      'state wiped, session not even restored', () async {
    final repo = _Repo();
    final marker = MemoryDemoAccountMarker(value: true);
    final c = AuthController(repo, demoMarker: marker);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.state.status, AuthStatus.unauthenticated);
    expect(repo.cleared, 1);
    expect(repo.restored, 0);
    expect(marker.wipes, 1);
    c.dispose();
  });

  test('R1: marker not set -> normal restore, nothing wiped', () async {
    final repo = _Repo();
    final marker = MemoryDemoAccountMarker();
    final c = AuthController(repo, demoMarker: marker);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.state.status, AuthStatus.authenticated);
    expect(marker.wipes, 0);
    expect(repo.cleared, 0);
    c.dispose();
  });
}
