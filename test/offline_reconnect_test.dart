// Offline cold open + reconnect without relaunch.
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/offline/auth_load.dart';
import 'package:nuvo/core/offline/reachability.dart';
import 'package:nuvo/core/offline/user_snapshot.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';

const _me = AuthUser(
  id: 'u-akshay',
  email: 'owner@example.com',
  fullName: 'Akshay Sanjai',
  username: 'akshay',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  profilePhotoUrl: 'https://example.com/a.png',
);

class _Repo extends AuthRepository {
  _Repo(this._script) : super(AuthApi(), SecureTokenStore());
  final List<RestoreResult> _script;
  int _i = 0;
  @override
  Future<RestoreResult> restoreSession() async =>
      _script[(_i++).clamp(0, _script.length - 1)];
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('cold open with no network shows the saved user, not "Nuvo member"',
      () async {
    final snap = UserSnapshotStore.memory();
    await snap.write(_me);
    final c = AuthController(
      _Repo([const RestoreUnreachable()]),
      offlineUser: snap.read,
    );
    await _settle();
    expect(c.state.status, AuthStatus.offline); // never a logout
    expect(c.state.user?.username, 'akshay');
    expect(c.state.user?.fullName, 'Akshay Sanjai');
    expect(c.state.user?.profilePhotoUrl, 'https://example.com/a.png');
    expect(authCanLoad(c.state), isTrue); // screens hydrate from cache
    c.dispose();
  });

  test('offline with no saved user stays empty and does not load', () async {
    final c = AuthController(
      _Repo([const RestoreUnreachable()]),
      offlineUser: UserSnapshotStore.memory().read,
    );
    await _settle();
    expect(c.state.status, AuthStatus.offline);
    expect(c.state.user, isNull);
    expect(authCanLoad(c.state), isFalse);
    c.dispose();
  });

  test('back online: retryRestore → authenticated (no relaunch)', () async {
    final snap = UserSnapshotStore.memory()..write(_me);
    final c = AuthController(
      _Repo([const RestoreUnreachable(), const RestoreOk(_me)]),
      offlineUser: snap.read,
    );
    await _settle();
    expect(c.state.status, AuthStatus.offline);
    await c.retryRestore();
    expect(c.state.status, AuthStatus.authenticated);
    c.dispose();
  });

  test('reachability flips offline → online and fires onReconnect once',
      () async {
    var up = false;
    var reconnects = 0;
    final m = ReachabilityMonitor(probe: () async => up)
      ..onReconnect = () async => reconnects++;
    m.reportOffline();
    expect(m.online, isFalse);
    await m.check(); // still down
    expect(m.online, isFalse);
    expect(reconnects, 0);
    up = true;
    await m.check(); // network back, no relaunch
    expect(m.online, isTrue);
    expect(reconnects, 1);
    await m.check(); // stays online — no duplicate reconnect
    expect(reconnects, 1);
    m.dispose();
  });

  test('snapshot round-trips and clears on sign-out', () async {
    final snap = UserSnapshotStore.memory();
    await snap.write(_me);
    expect((await snap.read())?.email, 'owner@example.com');
    await snap.clear();
    expect(await snap.read(), isNull);
  });
}
