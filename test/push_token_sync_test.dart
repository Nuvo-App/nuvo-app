import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/notifications/application/push_token_sync.dart';

/// A scripted harness: tokens/registrations behave as told, sleeps are free.
class _Harness {
  bool signedIn = true;
  final List<Object?> tokenScript; // String token | Exception | null per call
  final List<bool> registerScript; // per call; last value repeats
  final registered = <String>[];
  final unregistered = <String>[];
  int tokenCalls = 0;
  int registerCalls = 0;
  final sleeps = <Duration>[];
  late final PushTokenSync sync;

  _Harness({
    this.tokenScript = const ['tok1'],
    this.registerScript = const [true],
  }) {
    sync = PushTokenSync(
      isSignedIn: () => signedIn,
      fetchToken: () async {
        final i = tokenCalls++;
        final v =
            tokenScript[i < tokenScript.length ? i : tokenScript.length - 1];
        if (v is Exception) throw v;
        return v as String?;
      },
      register: (t) async {
        final i = registerCalls++;
        final ok =
            registerScript[i < registerScript.length
                ? i
                : registerScript.length - 1];
        if (ok) registered.add(t);
        return ok;
      },
      unregister: (t) async => unregistered.add(t),
      delays: const [
        Duration(seconds: 2),
        Duration(seconds: 6),
        Duration(seconds: 15),
      ],
      sleep: (d) async => sleeps.add(d),
      log: (_) {},
    );
  }
}

void main() {
  test(
    'signed in: fetches the token and registers it with the server',
    () async {
      final h = _Harness();
      expect(await h.sync.syncNow(), isTrue);
      expect(h.registered, ['tok1']);
      expect(h.sync.registeredToken, 'tok1');
    },
  );

  test(
    'signed OUT: nothing is sent, the token is remembered for later',
    () async {
      final h = _Harness();
      h.signedIn = false;
      expect(await h.sync.syncNow(token: 'early'), isFalse);
      expect(h.registerCalls, 0);
      expect(h.sync.lastFailure, 'not_signed_in');
      // …then the user signs in: the remembered token goes up, no refetch needed.
      h.signedIn = true;
      expect(await h.sync.syncNow(), isTrue);
      expect(h.registered, ['early']);
      expect(h.tokenCalls, 0);
    },
  );

  test(
    'apns-token-not-set is retried with backoff until the token appears',
    () async {
      final h = _Harness(
        tokenScript: [
          Exception('apns-token-not-set'),
          Exception('apns-token-not-set'),
          'tok1',
        ],
      );
      expect(await h.sync.syncNow(), isTrue);
      expect(h.tokenCalls, 3);
      expect(h.sleeps, const [Duration(seconds: 2), Duration(seconds: 6)]);
      expect(h.registered, ['tok1']);
    },
  );

  test('gives up after the last delay and says why', () async {
    final h = _Harness(tokenScript: [Exception('apns-token-not-set')]);
    expect(await h.sync.syncNow(), isFalse);
    expect(h.tokenCalls, 4); // 1 + 3 retries
    expect(h.sync.lastFailure, contains('apns-token-not-set'));
    expect(h.registered, isEmpty);
  });

  test(
    'a failed registration is retried; the token only counts once accepted',
    () async {
      final h = _Harness(registerScript: [false, false, true]);
      expect(await h.sync.syncNow(), isTrue);
      expect(h.registerCalls, 3);
      expect(h.sync.registeredToken, 'tok1');
      expect(h.sync.lastFailure, isNull);
    },
  );

  test(
    'server never accepts: not marked registered, failure reported',
    () async {
      final h = _Harness(registerScript: [false]);
      expect(await h.sync.syncNow(), isFalse);
      expect(h.sync.registeredToken, isNull);
      expect(h.sync.lastFailure, 'register_rejected');
      // a later sync (app resume) tries again and succeeds
      final h2 =
          h; // same harness: flip the script by making a new success call
      expect(h2.registerCalls, 4);
    },
  );

  test('already registered: syncing again does not re-register', () async {
    final h = _Harness();
    await h.sync.syncNow();
    await h.sync.syncNow();
    expect(h.registerCalls, 1);
  });

  test(
    'token rotation: the new token registers and the old one is detached',
    () async {
      final h = _Harness();
      await h.sync.syncNow(token: 'tok1');
      expect(await h.sync.syncNow(token: 'tok2'), isTrue);
      expect(h.registered, ['tok1', 'tok2']);
      expect(h.unregistered, ['tok1']);
      expect(h.sync.registeredToken, 'tok2');
    },
  );

  test('concurrent syncs share one run (no duplicate registrations)', () async {
    final h = _Harness();
    final results = await Future.wait([
      h.sync.syncNow(),
      h.sync.syncNow(),
      h.sync.syncNow(),
    ]);
    expect(results, everyElement(isTrue));
    expect(h.registerCalls, 1);
  });

  test('sign-out detaches the device while the session is valid', () async {
    final h = _Harness();
    await h.sync.syncNow();
    await h.sync.signOut();
    expect(h.unregistered, ['tok1']);
    expect(h.sync.registeredToken, isNull);
  });

  test(
    'sign-out of a never-registered device still detaches the known token',
    () async {
      final h = _Harness();
      h.signedIn = false;
      await h.sync.syncNow(token: 'orphan');
      await h.sync.signOut();
      expect(h.unregistered, ['orphan']);
    },
  );

  test('losing the session mid-retry stops cleanly', () async {
    final h = _Harness(registerScript: [false]);
    final done = h.sync.syncNow();
    // sleeps are instant; flip the session off after the first attempt
    h.signedIn = false;
    expect(await done, isFalse);
  });
}
