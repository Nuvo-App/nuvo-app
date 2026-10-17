// A sign-up from an invite link stashes its destination while logged out. The
// auth listener in NuvoApp must drain it once the account is authenticated AND
// onboarded — including when onboardingComplete flips false -> true on an
// already-authenticated session.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/app/app.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';

AuthUser _user({required bool onboarded}) => AuthUser(
  id: 'u1',
  email: 'a@example.com',
  onboardingComplete: onboarded,
  hasMemberPass: true,
  termsAccepted: true,
);

AuthState _authed({required bool onboarded}) =>
    AuthState(status: AuthStatus.authenticated, user: _user(onboarded: onboarded));

const _out = AuthState(status: AuthStatus.unauthenticated);

void main() {
  test('becoming authenticated with onboarding done drains (existing path)', () {
    expect(shouldDrainPendingDestination(_out, _authed(onboarded: true)), isTrue);
    expect(shouldDrainPendingDestination(null, _authed(onboarded: true)), isTrue);
  });

  test('becoming authenticated while setup is owed does not drain', () {
    expect(shouldDrainPendingDestination(_out, _authed(onboarded: false)), isFalse);
  });

  test('onboardingComplete flipping false -> true drains the invite', () {
    expect(
      shouldDrainPendingDestination(
        _authed(onboarded: false),
        _authed(onboarded: true),
      ),
      isTrue,
    );
  });

  test('other authenticated updates do not drain again', () {
    expect(
      shouldDrainPendingDestination(
        _authed(onboarded: true),
        _authed(onboarded: true),
      ),
      isFalse,
    );
    expect(
      shouldDrainPendingDestination(
        _authed(onboarded: false),
        _authed(onboarded: false),
      ),
      isFalse,
    );
  });

  test('signing out never drains', () {
    expect(shouldDrainPendingDestination(_authed(onboarded: true), _out), isFalse);
  });
}
