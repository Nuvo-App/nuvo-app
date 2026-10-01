import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_flip_text.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nuvo/features/auth/presentation/welcome_auth_screen.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';
import 'package:nuvo/features/auth/presentation/email_verify_screen.dart';

class _AuthTestRepository extends AuthRepository {
  _AuthTestRepository() : super(AuthApi(), SecureTokenStore());

  final emails = <String>[];
  final reviewers = <String>[];
  final googleTokens = <String>[];
  final appleTokens = <String>[];
  final appleAuthCodes = <String?>[];
  Completer<void>? pendingEmail;
  bool failEmail = false;
  static const user = AuthUser(
    id: 'auth-test',
    email: 'member@example.com',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  );

  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();

  @override
  Future<void> startEmailAuth(String email) async {
    emails.add(email);
    if (pendingEmail != null) await pendingEmail!.future;
    if (failEmail) throw StateError('Test send failure');
  }

  @override
  Future<AuthUser> signInReviewer(String email, String password, {String intent = 'signin'}) async {
    reviewers.add(email);
    return user;
  }

  @override
  Future<AuthUser> signInWithGoogle(String idToken) async {
    googleTokens.add(idToken);
    return user;
  }

  @override
  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async {
    appleTokens.add(idToken);
    appleAuthCodes.add(authorizationCode);
    return user;
  }
}

Future<GoRouter> _pumpAuth(
  WidgetTester tester, {
  bool login = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  _AuthTestRepository? repository,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  final router = GoRouter(
    initialLocation: '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, _) => WelcomeAuthScreen(initialLogin: login),
      ),
      GoRoute(path: '/auth/email', builder: (_, _) => const EmailStartScreen()),
      GoRoute(
        path: '/auth/verify',
        builder: (_, state) => Scaffold(body: Text('code for ${state.extra}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(repository ?? _AuthTestRepository()),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// The auth headline is now a [NuvoFlipText] — per-character cells, not one
/// Text — so assert on the widget carrying the copy instead of `find.text`.
Finder _flipText(String text) =>
    find.byWidgetPredicate((w) => w is NuvoFlipText && w.text == text);

void main() {
  testWidgets('signup has a clear primary action without legacy branding', (
    tester,
  ) async {
    await _pumpAuth(tester);
    expect(_flipText('Ready to start\nyour first race?'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.textContaining('Training for:'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('login presents the existing email-code form inline', (
    tester,
  ) async {
    await _pumpAuth(tester, login: true);
    expect(_flipText('Welcome back.'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets(
    'signup uses secondary providers, legal links, and reversible login mode',
    (tester) async {
      final router = await _pumpAuth(tester);
      expect(find.byType(NuvoPrimaryButton), findsOneWidget);
      expect(find.byType(NuvoOutlineButton), findsNWidgets(2));
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(
        tester.getSize(find.byType(NuvoOutlineButton).first).height,
        tester.getSize(find.byType(NuvoOutlineButton).last).height,
      );
      expect(find.text('By continuing, you agree to our'), findsOneWidget);
      expect(find.text('Terms'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      final toggle = find.byKey(const ValueKey('auth-mode-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(_flipText('Welcome back.'), findsOneWidget);
      expect(find.text("Don't have an account? Sign up"), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/welcome');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Create account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Create account opens email entry without starting authentication',
    (tester) async {
      final repository = _AuthTestRepository();
      final router = await _pumpAuth(tester, repository: repository);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/auth/email',
      );
      expect(find.byType(EmailStartScreen), findsOneWidget);
      expect(repository.emails, isEmpty);
      expect(repository.googleTokens, isEmpty);
      expect(repository.appleTokens, isEmpty);
    },
  );

  testWidgets(
    'email login preserves validation, normalization and the code route',
    (tester) async {
      final repository = _AuthTestRepository();
      final router = await _pumpAuth(
        tester,
        login: true,
        repository: repository,
      );
      expect(
        tester
            .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'not-an-email');
      await tester.pump();
      expect(
        tester
            .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '  MEMBER@example.com  ');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType, TextInputType.emailAddress);
      expect(field.autofillHints, contains(AutofillHints.email));
      await tester.ensureVisible(find.text('Log in'));
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(repository.emails, ['member@example.com']);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/auth/verify',
      );
      expect(find.text('code for member@example.com'), findsOneWidget);
    },
  );

  testWidgets(
    'reviewer password stays conditional and uses the existing reviewer action',
    (tester) async {
      final repository = _AuthTestRepository();
      await _pumpAuth(tester, login: true, repository: repository);
      await tester.enterText(find.byType(TextField), 'testing@getnuvo.net');
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
      final password = tester.widget<TextField>(find.byType(TextField).last);
      expect(password.obscureText, isTrue);
      expect(password.autofillHints, contains(AutofillHints.password));
      expect(password.autocorrect, isFalse);
      expect(
        tester
            .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField).last, 'test-only-password');
      await tester.pump();
      await tester.ensureVisible(find.text('Log in'));
      await tester.tap(find.text('Log in'));
      await tester.pump();
      // The shared review credential is the only email routed to the
      // reviewer action — every other account goes through normal
      // email-code auth.
      expect(repository.reviewers, ['testing@getnuvo.net']);
      expect(repository.emails, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email loading stays in the button and an expanded error permits retry',
    (tester) async {
      final repository = _AuthTestRepository()
        ..pendingEmail = Completer<void>()
        ..failEmail = true;
      await _pumpAuth(
        tester,
        login: true,
        size: const Size(320, 568),
        textScale: 1.3,
        repository: repository,
      );
      await tester.enterText(find.byType(TextField), 'member@example.com');
      await tester.pump();
      await tester.ensureVisible(find.text('Log in'));
      await tester.tap(find.text('Log in'));
      await tester.pump();
      final primary = tester.widget<NuvoPrimaryButton>(
        find.byType(NuvoPrimaryButton),
      );
      expect(primary.loading, isTrue);
      expect(primary.onPressed, isNull);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
      repository.pendingEmail!.complete();
      await tester.pump();
      expect(
        find.text('Could not send code. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton))
            .loading,
        isFalse,
      );
      await tester.ensureVisible(find.text('Log in'));
      expect(find.text('Log in').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'social providers do not start automatically and preserve their callbacks',
    (tester) async {
      final repository = _AuthTestRepository();
      final methods = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/google_sign_in'),
        (call) async {
          methods.add(call.method);
          return switch (call.method) {
            'signIn' => {
              'id': 'test-id',
              'email': 'member@example.com',
              'displayName': 'Test Member',
            },
            'getTokens' => {
              'idToken': 'test-google-token',
              'accessToken': 'test-access',
            },
            'isSignedIn' => false,
            _ => null,
          };
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple'),
        (call) async {
          methods.add(call.method);
          return {
            'type': 'appleid',
            'authorizationCode': 'test-code',
            'identityToken': 'test-apple-token',
            'givenName': 'Test',
            'familyName': 'Member',
          };
        },
      );
      await _pumpAuth(tester, repository: repository);
      expect(methods, isEmpty);
      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();
      await tester.pump();
      expect(repository.appleTokens, ['test-apple-token']);
      expect(repository.appleAuthCodes, ['test-code']);
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump();
      expect(repository.googleTokens, ['test-google-token']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider loading and cancellation remain local and readable', (
    tester,
  ) async {
    final response = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.aboutyou.dart_packages.sign_in_with_apple'),
          (_) => response.future,
        );
    await _pumpAuth(tester, login: true, size: const Size(320, 568));
    await tester.ensureVisible(find.text('Continue with Apple'));
    await tester.tap(find.text('Continue with Apple'));
    await tester.pump();
    expect(
      tester
          .widget<NuvoOutlineButton>(find.byType(NuvoOutlineButton).first)
          .onPressed,
      isNull,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.completeError(PlatformException(code: 'test-cancelled'));
    await tester.pump();
    expect(find.text('Apple Sign In was cancelled or failed.'), findsOneWidget);
    expect(
      tester
          .widget<NuvoOutlineButton>(find.byType(NuvoOutlineButton).first)
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
  ]) {
    for (final login in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '${login ? 'login' : 'signup'} fits $size at text scale $scale',
          (tester) async {
            await _pumpAuth(tester, login: login, size: size, textScale: scale);
            for (final label in [
              login ? 'Log in' : 'Create account',
              'Continue with Apple',
              'Continue with Google',
              'Terms',
              'Privacy Policy',
            ]) {
              final target = find.text(label);
              await tester.ensureVisible(target);
              expect(target.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            final toggle = find.byKey(const ValueKey('auth-mode-toggle'));
            await tester.ensureVisible(toggle);
            expect(toggle.hitTestable(), findsOneWidget);
            expect(find.byType(Image), findsNothing);
          },
        );
      }
    }
    testWidgets(
      'login fields and action remain reachable with keyboard at $size',
      (tester) async {
        await _pumpAuth(tester, login: true, size: size, textScale: 1.3);
        await tester.enterText(find.byType(TextField), 'testing@getnuvo.net');
        await tester.pump();
        await tester.ensureVisible(find.byType(TextField).last);
        await tester.showKeyboard(find.byType(TextField).last);
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final field = tester.getRect(find.byType(TextField).last);
        expect(field.bottom, lessThanOrEqualTo(size.height - 240));
        expect(field.top, greaterThanOrEqualTo(44));
        await tester.enterText(
          find.byType(TextField).last,
          'test-only-password',
        );
        await tester.pump();
        await tester.ensureVisible(find.text('Log in'));
        expect(find.text('Log in').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('Email Start layout', () {
    testWidgets('CTA visible without scroll on normal iPhone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: EmailStartScreen()));
      // Pump a few frames to let flutter_animate finish.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // CTA should be visible (pinned at bottom)
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('CTA visible on small iPhone', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: EmailStartScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('no overflow at small viewport', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const MaterialApp(home: EmailStartScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });

  group('Email Verify layout', () {
    testWidgets('CTA visible without scroll on normal iPhone', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(home: EmailVerifyScreen(email: 'test@getnuvo.net')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Verify code'), findsOneWidget);
    });

    testWidgets('CTA visible on small iPhone', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(home: EmailVerifyScreen(email: 'test@getnuvo.net')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Verify code'), findsOneWidget);
    });

    testWidgets('no overflow at small viewport', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(home: EmailVerifyScreen(email: 'test@getnuvo.net')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  });
}
