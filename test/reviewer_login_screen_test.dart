import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthApi(), SecureTokenStore());

  int reviewerCalls = 0;
  int otpCalls = 0;
  String? reviewerEmail;
  String? reviewerPassword;

  @override
  Future<AuthUser?> restoreSession() async => null;

  @override
  Future<void> startEmailAuth(String email) async {
    otpCalls += 1;
  }

  @override
  Future<AuthUser> signInReviewer(String email, String password) async {
    reviewerCalls += 1;
    reviewerEmail = email;
    reviewerPassword = password;
    return const AuthUser(
      id: 'reviewer-user',
      email: 'testing@getnuvo.net',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeAuthRepository repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: EmailStartScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reviewer password field appears only for exact normalized email', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pumpScreen(tester, repo);

    expect(find.text('Reviewer password'), findsNothing);

    await tester.enterText(find.byType(TextField).first, ' Testing@GetNuvo.Net ');
    await tester.pump();

    expect(find.text('Reviewer password'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'person@getnuvo.net');
    await tester.pump();

    expect(find.text('Reviewer password'), findsNothing);
  });

  testWidgets('reviewer submit uses reviewer auth and skips OTP request', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await _pumpScreen(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'testing@getnuvo.net');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'local-test-password');
    await tester.pump();

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(repo.reviewerCalls, 1);
    expect(repo.otpCalls, 0);
    expect(repo.reviewerEmail, 'testing@getnuvo.net');
    expect(repo.reviewerPassword, 'local-test-password');
  });
}
