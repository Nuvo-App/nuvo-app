import 'dart:async';

import 'package:flutter/foundation.dart';

/// Gets this device's FCM token onto the server, and keeps it there.
///
/// Pure Dart (every dependency injected) so the lifecycle is unit-tested
/// without Firebase. It exists because a token that never reaches the server is
/// silent: nothing errors, no notification ever arrives. The failure modes it
/// covers:
///
///  * `getToken` throws `apns-token-not-set` until iOS hands over the APNs
///    token — retried with backoff instead of given up on;
///  * the user signs in before Firebase finished starting — [syncNow] after
///    start picks it up;
///  * the registration request fails (offline, expired session, 5xx) — retried,
///    and the token is only marked synced after the server accepted it;
///  * the token rotates — the old one is detached from this account;
///  * sign-out detaches the token while the session is still valid.
class PushTokenSync {
  PushTokenSync({
    required this.fetchToken,
    required this.register,
    required this.unregister,
    required this.isSignedIn,
    this.delays = const [
      Duration(seconds: 2),
      Duration(seconds: 6),
      Duration(seconds: 15),
      Duration(seconds: 40),
    ],
    Future<void> Function(Duration)? sleep,
    void Function(String message)? log,
  }) : _sleep = sleep ?? Future.delayed,
       _log = log ?? ((m) => debugPrint('[Push] $m'));

  /// The platform token — may throw (e.g. `apns-token-not-set`) or return null.
  final Future<String?> Function() fetchToken;

  /// POST the token to the server; true only when the server accepted it.
  final Future<bool> Function(String token) register;

  /// Detach a token from this account (best effort).
  final Future<void> Function(String token) unregister;

  final bool Function() isSignedIn;

  /// Wait before attempt 2, 3, … (so `delays.length + 1` attempts in total).
  final List<Duration> delays;

  final Future<void> Function(Duration) _sleep;
  final void Function(String) _log;

  /// The token the server last accepted for this signed-in session.
  String? registeredToken;

  /// The latest token seen (registered or not) — used to detach on sign-out.
  String? knownToken;

  /// Why the last [syncNow] did not register, for diagnostics.
  String? lastFailure;

  Future<bool>? _inFlight;

  /// Fetch (if needed) and register. Concurrent calls share one run. Returns
  /// whether the server has the token afterwards.
  Future<bool> syncNow({String? token}) {
    if (token != null) knownToken = token;
    return _inFlight ??= _run(token).whenComplete(() => _inFlight = null);
  }

  /// Platform reported a new token (first generation or rotation).
  void onTokenRefresh(String token) {
    knownToken = token;
    unawaited(syncNow(token: token));
  }

  Future<bool> _run(String? given) async {
    if (!isSignedIn()) {
      lastFailure = 'not_signed_in';
      _log('token not synced: not signed in yet');
      return false;
    }
    var token = given ?? knownToken;

    // 1. Obtain the token (APNs registration can take a moment on a cold start).
    for (var attempt = 0; token == null; attempt++) {
      try {
        token = await fetchToken();
      } catch (e) {
        lastFailure = 'token_unavailable: $e';
      }
      if (token != null) break;
      if (attempt >= delays.length) {
        _log(
          'no push token after ${attempt + 1} attempts (${lastFailure ?? 'null'})',
        );
        return false;
      }
      await _sleep(delays[attempt]);
      if (!isSignedIn()) return false;
    }
    knownToken = token;
    if (registeredToken == token) return true;

    // 2. Register it; only a server acceptance counts.
    for (var attempt = 0; ; attempt++) {
      var ok = false;
      try {
        ok = await register(token);
      } catch (e) {
        lastFailure = 'register_error: $e';
      }
      if (ok) {
        final previous = registeredToken;
        registeredToken = token;
        lastFailure = null;
        _log('token registered');
        if (previous != null && previous != token) {
          unawaited(unregister(previous));
        }
        return true;
      }
      lastFailure ??= 'register_rejected';
      if (attempt >= delays.length) {
        _log(
          'token NOT registered after ${attempt + 1} attempts ($lastFailure)',
        );
        return false;
      }
      await _sleep(delays[attempt]);
      if (!isSignedIn()) return false;
    }
  }

  /// Detach this device from the account — call while the session is valid.
  Future<void> signOut() async {
    final token = registeredToken ?? knownToken;
    registeredToken = null;
    if (token != null) await unregister(token);
  }
}
