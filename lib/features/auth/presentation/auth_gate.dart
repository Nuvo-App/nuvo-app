// The route guard. See docs/NAVIGATION_MAP.md rules 7-8 and
// docs/agents/10-pitfalls-and-fixes.md §B2.
//
// RULE: the authenticated landing destination depends ONLY on
// user.onboardingComplete + authState.guideFirstRace — NEVER on which route
// sign-in started from. Email (/auth/verify), Google and Apple (/welcome) must
// all land in the same place. Do not reintroduce a `loc.startsWith('/auth/')`
// branch — that was bug B2 ("email login behaves differently from Google").
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';
import '../../onboarding/presentation/first_use_guide.dart';

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
    _ref = ref;
  }

  late final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authControllerProvider);
    final loc = state.matchedLocation;

    // While auth is genuinely unresolved, never render protected routes
    // (they would hit secure storage concurrently with the restore and can
    // corrupt the session on web). Send them to /splash, which shows the
    // loading state.
    if (authState.status == AuthStatus.loading) {
      final dest = _isProtected(loc) ? '/splash' : null;
      debugPrint('[Router] loading → $loc : redirect=$dest');
      return dest;
    }

    // Stored credentials exist but the server was unreachable on restore —
    // NOT logged out (AuthState.user is null here; never dereference it in
    // this branch). SplashScreen finishes its launch animation and sends the
    // user straight to /arena, which owns the in-page "no connection" /
    // retry experience with the normal header and nav intact. Every other
    // protected destination bounces back to Arena instead — one offline
    // home, not a dead end on whatever screen last happened to be loading.
    if (authState.status == AuthStatus.offline) {
      if (loc == '/splash' || loc == '/arena') return null;
      final dest = _isProtected(loc) ? '/arena' : null;
      debugPrint('[Router] offline → $loc : redirect=$dest');
      return dest;
    }

    if (loc == '/splash') return null;

    if (authState.status == AuthStatus.unauthenticated) {
      final dest = _isProtected(loc) ? '/welcome' : null;
      debugPrint('[Router] unauthenticated → $loc : redirect=$dest');
      return dest;
    }

    // ── Authenticated ────────────────────────────────────────────────────────
    // The destination is identical for every provider (email, Google, Apple):
    // it depends only on onboarding state and the first-race guide flag, never
    // on which route the sign-in happened to originate from.
    final user = authState.user!;
    debugPrint('[Router] authenticated uid=${user.id} → $loc');
    final replayingDemo = _ref.read(demoReplayProvider);

    // Demo replay deliberately keeps the user in the pre-auth race builder.
    if (replayingDemo && (loc == '/welcome/intro' || loc == '/welcome')) {
      return null;
    }

    if (!user.onboardingComplete) {
      if (_isAuthPreOnboarding(loc) || loc == '/welcome/intro') {
        return '/onboarding/profile';
      }
      return null;
    }

    // Onboarded: hand auth / onboarding / intro routes back to the app.
    if (_isAuthOrOnboarding(loc) || loc == '/welcome/intro') {
      if (authState.guideFirstRace) {
        _ref.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.competeStart;
        return '/compete';
      }
      return '/arena';
    }

    return null;
  }

  // Routes that require authentication
  bool _isProtected(String loc) =>
      loc.startsWith('/arena') ||
      loc.startsWith('/pass') ||
      loc.startsWith('/compete') ||
      loc.startsWith('/move') ||
      loc.startsWith('/profile') ||
      loc.startsWith('/race/') ||
      loc.startsWith('/races/') ||
      loc.startsWith('/proof/') ||
      loc.startsWith('/scan') ||
      loc.startsWith('/u/') ||
      loc.startsWith('/notifications') ||
      loc.startsWith('/settings/') ||
      loc.startsWith('/onboarding/');

  // /welcome and /auth/* — before onboarding begins
  bool _isAuthPreOnboarding(String loc) =>
      loc == '/welcome' || loc.startsWith('/auth/');

  // All pre-app routes
  bool _isAuthOrOnboarding(String loc) =>
      loc == '/welcome' ||
      loc.startsWith('/auth/') ||
      loc.startsWith('/onboarding/');
}

final routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});
