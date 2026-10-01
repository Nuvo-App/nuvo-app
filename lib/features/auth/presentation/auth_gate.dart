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
import '../data/auth_models.dart';
import '../../onboarding/data/first_use_store.dart';
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
    // Exception: /profile stays reachable — it renders entirely from local
    // state and hosts Sign out, the only way off a session that can never
    // re-authenticate on this network (e.g. a stale store-review login that
    // needs to be replaced by the offline demo sign-in).
    if (authState.status == AuthStatus.offline) {
      if (loc == '/splash' || loc == '/arena' || loc == '/profile') {
        return null;
      }
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

    // Demo replay owns the whole authenticated session: every destination —
    // auth screens it just signed in from, deep links, tabs — resolves to the
    // story at page 0, which is the only route the replay renders. This is
    // what makes the store-review account's fresh-demo experience
    // deterministic: nothing can side-step the replay once it is armed.
    // (Unauthenticated sessions never reach here — /welcome stays usable so
    // the reviewer credential can be entered.)
    if (replayingDemo) {
      return loc == '/onboarding/nuvo' ? null : '/onboarding/nuvo';
    }

    // Mandatory post-auth setup (legal, identity, consent, then the Nuvo
    // story) applies to every account — a real person's crew shouldn't see
    // "Nuvo member" because profile setup was never required of them.
    if (!user.onboardingComplete) {
      if (_isAuthPreOnboarding(loc) ||
          // Accounts that owe setup cannot wander the app — protected
          // non-onboarding routes bounce back to the earliest step they
          // still owe (see _firstRunTarget). Onboarding routes themselves
          // stay reachable so setup can finish.
          (_isProtected(loc) && !loc.startsWith('/onboarding/'))) {
        return _firstRunTarget(user);
      }
      return null;
    }

    // First-run notification education sits between the Nuvo story and the
    // first-race guide. The story's completion marks the step owed; if the
    // app was killed there, relaunch resumes at the permission moment
    // instead of silently skipping it. Resolved (enable / maybe-later /
    // auto-skip) clears the flag, so this never replays — and demo replay
    // never reaches this point (it is already handled above).
    if (!replayingDemo &&
        _ref.read(firstUseStoreProvider).isNotificationPromptOwed) {
      return loc == '/onboarding/notifications'
          ? null
          : '/onboarding/notifications';
    }

    // Onboarded: hand auth / onboarding routes back to the app.
    if (_isAuthOrOnboarding(loc)) {
      if (_shouldArmGuide(authState, user)) return '/compete';
      return '/arena';
    }

    // A guide-eligible account landing on the canonical home (cold launch
    // hands authenticated users to /arena) gets the coach exactly once —
    // while a guide step is already armed the user may roam freely, and a
    // finished guide leaves /arena alone.
    if (loc == '/arena' &&
        _ref.read(firstRaceGuideProvider) == FirstRaceGuideStep.idle &&
        authState.guideFirstRace &&
        firstRaceGuideAllowed(_ref, user)) {
      _armGuide();
      return '/compete';
    }

    return null;
  }

  // Redirect can run inside the router's build/restoration phase — provider
  // state must never be written synchronously from here, so the arm is
  // deferred to the next microtask. Navigation to /compete commits first;
  // the coach mounts the moment the step flips.
  void _armGuide() {
    Future<void>.microtask(() {
      _ref.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.competeStart;
    });
  }

  // The earliest first-run step the account still owes. The Nuvo story is
  // the LAST step of onboarding, not an entry point: an account that bailed
  // mid-setup resumes at the step it left, never mid-cinematic.
  //
  //  profile+legal incomplete → /onboarding/profile
  //  consent unanswered       → /onboarding/motion-consent
  //  everything answered      → /onboarding/nuvo
  //
  // Motion consent is a yes/no screen, so "declined" is indistinguishable
  // from "not yet seen" — both correctly resume at the consent screen once.
  String _firstRunTarget(AuthUser user) {
    final profileDone =
        user.termsAccepted &&
        user.ageAttested &&
        (user.fullName?.trim().isNotEmpty ?? false) &&
        (user.username?.trim().isNotEmpty ?? false);
    if (!profileDone) return '/onboarding/profile';
    if (!user.motionTrainingConsent) return '/onboarding/motion-consent';
    return '/onboarding/nuvo';
  }

  bool _shouldArmGuide(AuthState authState, AuthUser user) {
    if (!authState.guideFirstRace) return false;
    final step = _ref.read(firstRaceGuideProvider);
    if (step == FirstRaceGuideStep.idle) {
      if (!firstRaceGuideAllowed(_ref, user)) return false;
      _armGuide();
      return true;
    }
    // Mid-guide: keep them on the guide's screen; a finished guide frees
    // every destination.
    return step != FirstRaceGuideStep.complete;
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
      loc.startsWith('/crew/') ||
      loc.startsWith('/my-nuvo') ||
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
