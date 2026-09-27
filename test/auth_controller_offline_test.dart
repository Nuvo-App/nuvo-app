// AuthController state-transition coverage, focused on the offline path:
// stored credentials + an unreachable server must produce AuthStatus.offline
// (never a logout), and retryRestore() must be the one real path back to
// authenticated — or back to offline again on a second failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';

const _user = AuthUser(
  id: 'user-1',
  email: 'test@getnuvo.net',
  fullName: 'Test User',
  username: 'testuser',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

/// Repo whose restoreSession() returns whatever the test queues up next,
/// via a mutable queue — lets one controller instance be driven through
/// "fails once, then succeeds" (retry) sequences.
class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo(this._script) : super(AuthApi(), SecureTokenStore());

  final List<RestoreResult> _script;
  int _calls = 0;

  @override
  Future<RestoreResult> restoreSession() async {
    final result = _script[_calls.clamp(0, _script.length - 1)];
    _calls++;
    return result;
  }
}

Future<void> _settle(AuthController controller) async {
  // AuthController._init() is async (awaits restoreSession()) — pump the
  // microtask queue so its Future completes before assertions run.
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('AuthController', () {
    test('starts in loading before restoreSession resolves', () {
      final controller = AuthController(_ScriptedAuthRepo([const RestoreOk(_user)]));
      // Synchronously right after construction — restoreSession() is async,
      // so the very first state must be loading, never a guess.
      expect(controller.state.status, AuthStatus.loading);
      controller.dispose();
    });

    test('RestoreOk → authenticated, with the restored user attached', () async {
      final controller = AuthController(_ScriptedAuthRepo([const RestoreOk(_user)]));
      await _settle(controller);
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user?.id, 'user-1');
      controller.dispose();
    });

    test('RestoreNoSession → unauthenticated, no user', () async {
      final controller =
          AuthController(_ScriptedAuthRepo([const RestoreNoSession()]));
      await _settle(controller);
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.user, isNull);
      controller.dispose();
    });

    test('RestoreUnreachable → offline, never logged out', () async {
      final controller =
          AuthController(_ScriptedAuthRepo([const RestoreUnreachable()]));
      await _settle(controller);
      expect(controller.state.status, AuthStatus.offline);
      // Explicitly not unauthenticated — offline must never present as a
      // logout to the rest of the app (RouterNotifier, MainShell, Arena).
      expect(controller.state.status, isNot(AuthStatus.unauthenticated));
      controller.dispose();
    });

    test('an unexpected exception during restore also becomes offline, not '
        'a crash or a silent logout', () async {
      final controller = AuthController(_ThrowingAuthRepo());
      await _settle(controller);
      expect(controller.state.status, AuthStatus.offline);
      controller.dispose();
    });

    test('retryRestore(): offline then success reaches authenticated', () async {
      final repo = _ScriptedAuthRepo([
        const RestoreUnreachable(),
        const RestoreOk(_user),
      ]);
      final controller = AuthController(repo);
      await _settle(controller);
      expect(controller.state.status, AuthStatus.offline);

      await controller.retryRestore();
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user?.id, 'user-1');
      controller.dispose();
    });

    test('retryRestore(): offline then a second failure stays offline, '
        'still not logged out', () async {
      final repo = _ScriptedAuthRepo([
        const RestoreUnreachable(),
        const RestoreUnreachable(),
      ]);
      final controller = AuthController(repo);
      await _settle(controller);
      expect(controller.state.status, AuthStatus.offline);

      await controller.retryRestore();
      expect(controller.state.status, AuthStatus.offline);
      expect(controller.state.status, isNot(AuthStatus.unauthenticated));
      controller.dispose();
    });

    test('offline demo sentinel restores locally — no network, no retry loop',
        () async {
      final store = _FakeStore()..refresh = kOfflineDemoRefreshToken;
      final repo = AuthRepository(AuthApi(), store);
      final result = await repo.restoreSession();
      expect(result, isA<RestoreOk>());
      expect((result as RestoreOk).user.id, 'offline-demo-user');
      expect(result.user.isDemo, isTrue);
    });

    test('signInReviewer transport failure falls back to a local demo session',
        () async {
      final repo = _OfflineSignInRepo();
      final controller = AuthController(repo);
      await _settle(controller);

      await controller.signInReviewer('team@getnuvo.net', 'pw');
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user?.id, 'offline-demo-user');
      expect(repo.offlineDemoCalls, 1);
      controller.dispose();
    });

    test('signInReviewer 401 is a real rejection — never a silent demo session',
        () async {
      final repo = _OfflineSignInRepo(unreachable: false);
      final controller = AuthController(repo);
      await _settle(controller);

      await expectLater(
        controller.signInReviewer('team@getnuvo.net', 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(repo.offlineDemoCalls, 0);
      expect(controller.state.status, isNot(AuthStatus.authenticated));
      controller.dispose();
    });
  });

  group('AuthRepository offline restore fallback', () {
    test('team@ session + unreachable restore lands in the local demo '
        'session — tokens kept, never a logout', () async {
      final store = _FakeStore()
        ..refresh = 'real-refresh'
        ..email = 'team@getnuvo.net';
      final repo = AuthRepository(_UnreachableApi(), store);

      final result = await repo.restoreSession();
      expect(result, isA<RestoreOk>());
      expect((result as RestoreOk).user.id, 'offline-demo-user');
      expect(store.refresh, 'real-refresh');
    });

    test('team@ reviewer session falls back in debug builds', () async {
      final store = _FakeStore()
        ..refresh = 'real-refresh'
        ..email = 'team@getnuvo.net';
      final repo = AuthRepository(_UnreachableApi(), store);

      final result = await repo.restoreSession();
      expect(result, isA<RestoreOk>());
      expect((result as RestoreOk).user.isDemo, isTrue);
    });

    test('a normal account + unreachable stays offline — restore contract '
        'unchanged', () async {
      final store = _FakeStore()
        ..refresh = 'real-refresh'
        ..email = 'someone@example.com';
      final repo = AuthRepository(_UnreachableApi(), store);

      final result = await repo.restoreSession();
      expect(result, isA<RestoreUnreachable>());
      expect(store.refresh, 'real-refresh');
    });

    test('a session that predates email persistence (no stored email) falls '
        'back to the demo in debug builds', () async {
      final store = _FakeStore()..refresh = 'real-refresh';
      final repo = AuthRepository(_UnreachableApi(), store);

      final result = await repo.restoreSession();
      expect(result, isA<RestoreOk>());
      expect((result as RestoreOk).user.id, 'offline-demo-user');
    });
  });
}

/// In-memory token store — the platform channel never runs in tests.
class _FakeStore extends SecureTokenStore {
  String? refresh;
  String? access;
  String? email;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getAccountEmail() async => email;
  @override
  Future<void> saveAccountEmail(String accountEmail) async {
    email = accountEmail;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    email = null;
  }
}

/// API whose refresh call is always a transport failure — drives the
/// repository's unreachable path.
class _UnreachableApi extends AuthApi {
  @override
  Future<String> refreshSession(String refreshToken) =>
      Future.error(const ApiException(0, 'unreachable'));
}

/// Repo whose reviewer sign-in always fails — transport-shaped or a real 401 —
/// and counts offline-demo fallbacks.
class _OfflineSignInRepo extends AuthRepository {
  _OfflineSignInRepo({this.unreachable = true})
      : super(AuthApi(), _FakeStore());

  final bool unreachable;
  int offlineDemoCalls = 0;

  @override
  Future<AuthUser> signInReviewer(String email, String password) {
    return Future.error(
      unreachable
          ? const ApiException(0, 'unreachable')
          : const ApiException(401, 'Invalid review credentials'),
    );
  }

  @override
  Future<AuthUser> signInOfflineDemo() async {
    offlineDemoCalls++;
    return offlineDemoUser();
  }
}

class _ThrowingAuthRepo extends AuthRepository {
  _ThrowingAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async {
    throw StateError('boom');
  }
}
