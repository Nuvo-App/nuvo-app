 // Post-auth convergence coverage — the invariant from docs/agents/10 §B2:
// the authenticated destination depends ONLY on account state
// (AuthUser.onboardingComplete), never on which provider or which route the
// sign-in originated from. Email verify, Google, Apple and reviewer sign-in
// must converge identically, and a mid-session re-restore must not bounce the
// user onto the blank /splash loading canvas.
//
// Drives the REAL RouterNotifier redirect through a minimal GoRouter shaped
// like the app's route table — same technique as
// test/router_offline_routing_test.dart — so the assertions exercise the
// actual redirect-resolution loop, not a copy of it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';

const _completeUser = AuthUser(
  id: 'user-complete',
  email: 'member@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

/// New INTERNAL account — canonical @getnuvo.net email, setup owed.
const _incompleteUser = AuthUser(
  id: 'user-new',
  email: 'newuser@getnuvo.net',
  onboardingComplete: false,
  hasMemberPass: false,
  termsAccepted: false,
);

/// Returning INTERNAL account — questionnaire already completed.
const _internalDoneUser = AuthUser(
  id: 'user-internal-done',
  email: 'vet@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

/// New PUBLIC account — setup owed server-side but the questionnaire is the
/// internal/demo path, so public accounts skip it entirely.
const _publicNewUser = AuthUser(
  id: 'user-public-new',
  email: 'public@gmail.com',
  onboardingComplete: false,
  hasMemberPass: false,
  termsAccepted: false,
);

/// Scripted repository: every sign-in channel returns the same user object so
/// any difference in destination is attributable to routing, not data.
class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo({required this.user})
    : super(AuthApi(), SecureTokenStore());

  final AuthUser user;

  /// What the next restoreSession() returns. Mutable so a test can sign in
  /// from a cold (no-session) start and only then arm the re-restore result.
  RestoreResult? restoreResult;
  final calls = <String>[];

  @override
  Future<RestoreResult> restoreSession() async =>
      restoreResult ?? const RestoreNoSession();

  @override
  Future<AuthUser> verifyEmailCode(String email, String code) async {
    calls.add('email:$email');
    return user;
  }

  @override
  Future<AuthUser> signInWithGoogle(String idToken) async {
    calls.add('google');
    return user;
  }

  @override
  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async {
    calls.add('apple');
    return user;
  }

  @override
  Future<AuthUser> signInReviewer(String email, String password) async {
    calls.add('reviewer');
    return user;
  }

  // The real logout/clearSession hit FlutterSecureStorage's platform channel,
  // which is unmocked in widget tests and never returns. Routing is what is
  // under test, not secure storage.
  @override
  Future<void> logout() async {
    calls.add('logout');
  }

  @override
  Future<void> clearSession() async {
    calls.add('clearSession');
  }
}

/// Same scripted surface as [_ScriptedAuthRepo], but resolves the user
/// through a getter so a test can swap accounts across a logout/login cycle.
class _MutableUserRepo extends AuthRepository {
  _MutableUserRepo(this._user) : super(AuthApi(), SecureTokenStore());

  final AuthUser Function() _user;

  @override
  Future<RestoreResult> restoreSession() async => const RestoreNoSession();

  @override
  Future<AuthUser> verifyEmailCode(String email, String code) async => _user();

  @override
  Future<AuthUser> signInWithGoogle(String idToken) async => _user();

  @override
  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
    String? authorizationCode,
  }) async =>
      _user();

  @override
  Future<AuthUser> signInReviewer(String email, String password) async =>
      _user();

  @override
  Future<void> logout() async {}

  @override
  Future<void> clearSession() async {}
}

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

// Mirrors lib/app/router.dart's auth-relevant shape: the pre-auth routes the
// guard special-cases plus one protected destination per family.
({GoRouter router, ProviderContainer container}) _buildRouter({
  required AuthRepository repo,
  required String initialLocation,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
    ],
  );
  final notifier = container.read(routerNotifierProvider);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Screen('splash')),
      GoRoute(
        path: '/welcome/intro',
        builder: (_, _) => const _Screen('intro'),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const _Screen('welcome')),
      GoRoute(
        path: '/auth/email',
        builder: (_, _) => const _Screen('email'),
      ),
      GoRoute(
        path: '/auth/verify',
        builder: (_, _) => const _Screen('verify'),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (_, _) => const _Screen('profile-setup'),
      ),
      GoRoute(path: '/arena', builder: (_, _) => const _Screen('arena')),
      GoRoute(path: '/compete', builder: (_, _) => const _Screen('compete')),
      GoRoute(path: '/profile', builder: (_, _) => const _Screen('profile')),
    ],
  );
  return (router: router, container: container);
}

Future<({GoRouter router, ProviderContainer container})> _pumpAt(
  WidgetTester tester, {
  required AuthRepository repo,
  required String location,
}) async {
  final built = _buildRouter(repo: repo, initialLocation: location);
  addTearDown(built.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(routerConfig: built.router),
    ),
  );
  await tester.pumpAndSettle();
  return built;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

// Every sign-in channel the app exposes, driven through the real
// AuthController so the provider is the only variable under test.
const _channels = ['email', 'google', 'apple', 'reviewer'];

Future<void> _signIn(
  ProviderContainer container,
  String channel, {
  String email = 'member@example.com',
}) {
  final auth = container.read(authControllerProvider.notifier);
  return switch (channel) {
    'email' => auth.verifyEmailCode(email, '123456'),
    'google' => auth.signInWithGoogle('token'),
    'apple' => auth.signInWithApple('token'),
    'reviewer' => auth.signInReviewer('team@getnuvo.net', 'pw'),
    _ => throw ArgumentError(channel),
  };
}

AuthUser _userWithEmail(String email, {bool complete = false}) => AuthUser(
  id: 'u',
  email: email,
  onboardingComplete: complete,
  hasMemberPass: complete,
  termsAccepted: complete,
);

void main() {
  group('isInternalNuvoAccount', () {
    test('accepts only the exact getnuvo.net domain', () {
      expect(
        isInternalNuvoAccount(_userWithEmail('person@getnuvo.net')),
        isTrue,
      );
      expect(
        isInternalNuvoAccount(_userWithEmail('PERSON@GETNUVO.NET')),
        isTrue,
      );
      expect(
        isInternalNuvoAccount(_userWithEmail('  person@getnuvo.net  ')),
        isTrue,
      );
    });

    test('rejects lookalike, foreign, and relay domains', () {
      for (final email in [
        'public@gmail.com',
        'person@yahoo.com',
        'person@getnuvo.net.evil.com',
        'person@fakegetnuvo.net',
        'getnuvo.net@otherdomain.com',
        'x@privaterelay.appleid.com',
        'no-at-sign',
        '@getnuvo.net',
        'person@getnuvo.netx',
      ]) {
        expect(
          isInternalNuvoAccount(_userWithEmail(email)),
          isFalse,
          reason: email,
        );
      }
      expect(isInternalNuvoAccount(null), isFalse);
    });
  });

  group('post-auth convergence', () {
    for (final channel in _channels) {
      testWidgets('complete account via $channel from /welcome → /arena', (
        tester,
      ) async {
        final repo = _ScriptedAuthRepo(user: _completeUser);
        final built = await _pumpAt(
          tester,
          repo: repo,
          location: '/welcome',
        );
        await _signIn(built.container, channel);
        await tester.pumpAndSettle();
        expect(_path(built.router), '/arena');
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'new internal account via $channel from /welcome → /onboarding/profile',
        (tester) async {
          final repo = _ScriptedAuthRepo(user: _incompleteUser);
          final built = await _pumpAt(
            tester,
            repo: repo,
            location: '/welcome',
          );
          await _signIn(built.container, channel);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/onboarding/profile');
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'complete account via $channel from a pushed /auth/verify → /arena',
        (tester) async {
          final repo = _ScriptedAuthRepo(user: _completeUser);
          final built = await _pumpAt(
            tester,
            repo: repo,
            location: '/welcome',
          );
          built.router.push('/auth/verify');
          await tester.pumpAndSettle();
          await _signIn(built.container, channel);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/arena');
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'new internal account via $channel from /welcome/intro → /onboarding/profile',
        (tester) async {
          final repo = _ScriptedAuthRepo(user: _incompleteUser);
          final built = await _pumpAt(
            tester,
            repo: repo,
            location: '/welcome/intro',
          );
          await _signIn(built.container, channel);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/onboarding/profile');
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final channel in _channels) {
      testWidgets(
        'returning internal account via $channel → /arena (no re-setup)',
        (tester) async {
          final repo = _ScriptedAuthRepo(user: _internalDoneUser);
          final built = await _pumpAt(
            tester,
            repo: repo,
            location: '/welcome',
          );
          await _signIn(built.container, channel);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/arena');
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'new public account via $channel also gets onboarding → /onboarding/profile',
        (tester) async {
          final repo = _ScriptedAuthRepo(user: _publicNewUser);
          final built = await _pumpAt(
            tester,
            repo: repo,
            location: '/welcome',
          );
          await _signIn(built.container, channel);
          await tester.pumpAndSettle();
          expect(_path(built.router), '/onboarding/profile');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'internal incomplete user on a protected route bounces to setup',
      (tester) async {
        // e.g. splash hands a restored incomplete session to /arena — the
        // questionnaire must still win so internal setup cannot be skipped.
        final repo = _ScriptedAuthRepo(user: _incompleteUser);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        await _signIn(built.container, 'google');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');

        built.router.go('/arena');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'public incomplete user on a protected route bounces to setup, same '
      'as internal',
      (tester) async {
        final repo = _ScriptedAuthRepo(user: _publicNewUser);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        await _signIn(built.container, 'apple');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');

        built.router.go('/arena');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'account switch: internal sign-out → public sign-in still gets '
      'onboarding',
      (tester) async {
        var user = _incompleteUser;
        // Rebind the scripted user through a mutable holder so the "second
        // account" can differ after logout.
        final mutableRepo = _MutableUserRepo(() => user);
        final built = await _pumpAt(tester, repo: mutableRepo, location: '/welcome');
        await _signIn(built.container, 'email');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');

        await built.container.read(authControllerProvider.notifier).logout();
        await tester.pumpAndSettle();
        expect(_path(built.router), '/welcome');

        user = _publicNewUser;
        await _signIn(built.container, 'google');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'account switch: public sign-out → internal sign-in gets questionnaire',
      (tester) async {
        var user = _publicNewUser;
        final mutableRepo = _MutableUserRepo(() => user);
        final built = await _pumpAt(tester, repo: mutableRepo, location: '/welcome');
        await _signIn(built.container, 'google');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');

        await built.container.read(authControllerProvider.notifier).logout();
        await tester.pumpAndSettle();

        user = _incompleteUser;
        await _signIn(built.container, 'apple');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/onboarding/profile');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('equivalent account states converge identically', (
      tester,
    ) async {
      // The matrix above is the per-channel proof; this pins the invariant
      // that a completed profile lands identically regardless of channel AND
      // never routes through the first-race guide for a returning user.
      final repo = _ScriptedAuthRepo(user: _completeUser);
      final built = await _pumpAt(tester, repo: repo, location: '/welcome');
      await _signIn(built.container, 'google');
      await tester.pumpAndSettle();
      expect(_path(built.router), '/arena');
      expect(
        built.container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.idle,
        reason:
            'A fresh sign-in must not arm the first-race tutorial — it is '
            'demo-replay state, not a property of the account.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('logout from a protected route returns to /welcome', (
      tester,
    ) async {
      final repo = _ScriptedAuthRepo(user: _completeUser);
      final built = await _pumpAt(tester, repo: repo, location: '/welcome');
      await _signIn(built.container, 'email');
      await tester.pumpAndSettle();
      expect(_path(built.router), '/arena');

      await built.container.read(authControllerProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(_path(built.router), '/welcome');
      expect(
        built.container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      're-restore while authenticated never publishes loading '
      '(no /splash white-screen bounce)',
      (tester) async {
        final repo = _ScriptedAuthRepo(user: _completeUser);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        await _signIn(built.container, 'google');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/arena');

        // The retry must resolve back to the same session — with the
        // default RestoreNoSession the user would correctly be signed out.
        repo.restoreResult = const RestoreOk(_completeUser);

        // Arena's offline retry calls retryRestore(). While it runs, the
        // guard must not see AuthStatus.loading — that is what ripped the
        // user onto splash's empty scaffold.
        final statuses = <AuthStatus>[];
        built.container.listen(
          authControllerProvider,
          (_, next) => statuses.add(next.status),
        );
        await built.container
            .read(authControllerProvider.notifier)
            .retryRestore();
        await tester.pumpAndSettle();

        expect(statuses, isNot(contains(AuthStatus.loading)));
        expect(_path(built.router), '/arena');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
