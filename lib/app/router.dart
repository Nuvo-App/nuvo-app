// Route registration. BEFORE adding/moving/removing a route or changing a
// navigation verb, read docs/NAVIGATION_MAP.md (route table, graph, verb rules,
// the 10 rules) and update it in the same change.
//
// Invariants: one route per screen (aliases are `redirect:`, never a 2nd
// pageBuilder — see /race/:id/edit); every "open a race" tap lands on /race/:id;
// pushed routes use one of the existing _authPage/_detailPage/_cameraPage/
// _tabPage builders; routes that need `extra:` have a null-safe fallback.
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/bottom_nav.dart';
import '../core/widgets/nuvo_motion.dart';

import '../features/arena/presentation/arena_screen.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/auth/presentation/email_start_screen.dart';
import '../features/auth/presentation/email_verify_screen.dart';
import '../features/auth/presentation/welcome_auth_screen.dart';
import '../features/auth/presentation/welcome_race_builder_screen.dart';
import '../features/compete/presentation/compete_screen_fixed.dart';
import '../features/onboarding/presentation/member_pass_screen.dart';
import '../features/onboarding/presentation/motion_contribution_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/pass/presentation/pass_screen.dart';
import '../features/profile/presentation/badges_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/move/presentation/move_screen.dart';
import '../features/race_detail/presentation/race_detail_screen.dart';
import '../features/races/data/race_models.dart' show RaceCreatePrefill;
import '../features/races/presentation/race_composer_screen.dart';
import '../features/races/presentation/ai_motion_proof_screen.dart';
import '../features/races/presentation/invite_crew_screen.dart';
import '../features/races/presentation/join_race_screen.dart';
import '../features/races/presentation/proof_review_screen.dart';
import '../features/races/presentation/race_settings_screen.dart';
import '../features/races/presentation/board_moved_screen.dart';
import '../features/races/presentation/custom_pose/teach_movement_screen.dart';
import '../features/races/presentation/movement_preview/rive_calibration_screen.dart';
import '../features/races/presentation/submit_proof_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/crew/presentation/public_profile_screen.dart';
import '../features/notifications/presentation/notification_prefs_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/social/presentation/add_crew_screen.dart';
import '../features/social/presentation/invite_screen.dart';
import '../features/social/presentation/my_nuvo_screen.dart';
import '../features/social/presentation/qr_scan_screen.dart';
import '../features/splash/presentation/splash_screen.dart';

// Native interactive page transition used on all pushed routes. CupertinoPage
// gives iOS the system edge-back gesture and correct cancellation behavior.
Page<void> _authPage(GoRouterState state, Widget child) =>
    CupertinoPage<void>(key: state.pageKey, child: child);

// Slide-up transition for camera/verification — feels like the action is expanding.
Page<void> _cameraPage(GoRouterState state, Widget child) =>
    CupertinoPage<void>(key: state.pageKey, child: child);

// Race detail: horizontal slide with slight scale for depth.
Page<void> _detailPage(GoRouterState state, Widget child) =>
    CupertinoPage<void>(key: state.pageKey, child: child);

/// Bottom-nav tab pages: no route-level transition. The directional
/// slide+fade between destinations is owned by NuvoTabStack (the shell's
/// branch container), which keeps every branch mounted — the page itself
/// just swaps instantly and the shell animates around it.
Page<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

/// The screen behind each shell destination — keyed by the canonical
/// destination path so route → screen is declared exactly once.
Widget _tabScreenFor(String path) {
  final screen = switch (path) {
    '/compete' => const CompeteScreen(),
    '/move' => const MoveScreen(),
    '/pass' => const PassScreen(),
    '/profile' => const ProfileScreen(),
    _ => const ArenaScreen(),
  };
  // Debug-only trace: pairs with the [NuvoNav] tap print in MainShell so a
  // wrong-page report shows index → path → screen in the console.
  assert(() {
    debugPrint('[NuvoNav] route $path → ${screen.runtimeType}');
    return true;
  }());
  return screen;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(routerNotifierProvider);
  const debugInitialLocation = String.fromEnvironment('NUVO_INITIAL_LOCATION');
  final router = GoRouter(
    initialLocation: kDebugMode && debugInitialLocation.isNotEmpty
        ? debugInitialLocation
        : '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // ── Launch ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/splash',
        pageBuilder: (_, state) =>
            NoTransitionPage(key: state.pageKey, child: const SplashScreen()),
      ),
      GoRoute(
        path: '/welcome/intro',
        pageBuilder: (_, state) =>
            _authPage(state, const WelcomeRaceBuilderScreen()),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, state) => _authPage(
          state,
          WelcomeAuthScreen(
            initialLogin: state.uri.queryParameters['mode'] == 'login',
          ),
        ),
      ),

      // ── Invite / universal-link landing ───────────────────────────────────
      // Every QR scan, universal link, shared URL and web fallback resolves
      // here (see lib/features/social). Renders logged-out (previews first).
      GoRoute(
        path: '/invite/:token',
        pageBuilder: (_, state) => _detailPage(
          state,
          InviteScreen(token: state.pathParameters['token']!),
        ),
      ),
      GoRoute(
        path: '/scan',
        pageBuilder: (_, state) => _cameraPage(state, const QrScanScreen()),
      ),
      GoRoute(
        path: '/u/:id',
        pageBuilder: (_, state) => _detailPage(
          state,
          PublicProfileScreen(userId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/crew/add',
        pageBuilder: (_, state) => _authPage(state, const AddCrewScreen()),
      ),
      GoRoute(
        path: '/my-nuvo',
        pageBuilder: (_, state) => _authPage(state, const MyNuvoScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, state) =>
            _detailPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/settings/notifications',
        pageBuilder: (_, state) =>
            _authPage(state, const NotificationPrefsScreen()),
      ),

      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/email',
        pageBuilder: (_, state) => _authPage(state, const EmailStartScreen()),
      ),
      GoRoute(
        path: '/auth/verify',
        pageBuilder: (_, state) => _authPage(
          state,
          EmailVerifyScreen(email: state.extra as String? ?? ''),
        ),
      ),

      // ── Onboarding ────────────────────────────────────────────────────────
      GoRoute(
        path: '/onboarding/profile',
        pageBuilder: (_, state) => _authPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/onboarding/motion-consent',
        pageBuilder: (_, state) =>
            _authPage(state, const MotionContributionScreen()),
      ),
      GoRoute(
        path: '/onboarding/member-pass',
        pageBuilder: (_, state) =>
            _authPage(state, const OnboardingMemberPassScreen()),
      ),

      // ── Main shell (bottom nav) ────────────────────────────────────────────
      // StatefulShellRoute gives each of the five destinations its own
      // branch Navigator, so tab switches preserve each screen's mounted
      // state (scroll position, selections, ephemeral UI) instead of
      // rebuilding it. NuvoTabStack is the branch container — it keeps all
      // branches in the tree and animates the directional slide/fade.
      //
      // Branch order IS nav order: the branches are generated from
      // nuvoDestinations (the canonical table in bottom_nav.dart), so
      // nav index == branch index == route — never reorder one without
      // the other.
      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) =>
            NuvoTabStack(
          index: navigationShell.currentIndex,
          children: children,
        ),
        builder: (context, _, navigationShell) =>
            MainShell(child: navigationShell),
        branches: [
          for (final d in nuvoDestinations)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: d.path,
                  pageBuilder: (_, state) =>
                      _tabPage(state, _tabScreenFor(d.path)),
                ),
              ],
            ),
        ],
      ),

      // ── Detail / standalone ───────────────────────────────────────────────
      GoRoute(
        path: '/races/new',
        pageBuilder: (_, state) => _authPage(
          state,
          RaceComposerScreen(
            prefill: state.extra is RaceCreatePrefill
                ? state.extra! as RaceCreatePrefill
                : null,
          ),
        ),
      ),
      GoRoute(
        path: '/races/join',
        pageBuilder: (_, state) => _authPage(state, const JoinRaceScreen()),
      ),
      // Teach Nuvo — the custom-movement capture flow. Public entry is
      // /races/teach (reached from the race composer's activity step).
      GoRoute(
        path: '/races/teach',
        pageBuilder: (_, state) => _cameraPage(
          state,
          TeachMovementScreen(
            seedReadyFixture:
                kDebugMode && state.uri.queryParameters['fixture'] == 'ready',
            args: state.extra is TeachMovementArgs
                ? state.extra! as TeachMovementArgs
                : null,
          ),
        ),
      ),
      // Legacy alias — keep old links / bookmarks working.
      GoRoute(
        path: '/internal/teach-movement',
        redirect: (_, state) =>
            '/races/teach${state.uri.hasQuery ? '?${state.uri.query}' : ''}',
      ),
      GoRoute(
        path: '/race/:id',
        pageBuilder: (_, state) => _detailPage(
          state,
          RaceDetailScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/race/:id/settings',
        pageBuilder: (_, state) => _authPage(
          state,
          RaceSettingsScreen(raceId: state.pathParameters['id']!),
        ),
      ),
      // Legacy alias — "Edit race" and "Race settings" were once separate
      // screens; they are now one. Keep the path working for old links.
      GoRoute(
        path: '/race/:id/edit',
        redirect: (_, state) => '/race/${state.pathParameters['id']}/settings',
      ),
      GoRoute(
        path: '/race/:id/invite',
        pageBuilder: (_, state) => _authPage(
          state,
          InviteCrewScreen(raceId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/race/:id/proof',
        pageBuilder: (_, state) => _cameraPage(
          state,
          SubmitProofScreen(raceId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/race/:id/proof/ai-motion',
        pageBuilder: (_, state) => _cameraPage(
          state,
          AiMotionProofScreen(raceId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/race/:id/board-moved',
        pageBuilder: (_, state) => _authPage(
          state,
          BoardMovedScreen(
            raceId: state.pathParameters['id']!,
            args: state.extra is BoardMovedArgs
                ? state.extra! as BoardMovedArgs
                : BoardMovedArgs(
                    raceId: state.pathParameters['id']!,
                    raceName: '',
                    value: 0,
                  ),
          ),
        ),
      ),
      GoRoute(
        path: '/race/:id/proofs/:proofId',
        pageBuilder: (_, state) => _authPage(
          state,
          ProofReviewScreen(
            raceId: state.pathParameters['id']!,
            proofId: state.pathParameters['proofId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/proof/:id',
        redirect: (_, state) => '/race/${state.pathParameters['id']}/proof',
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (_, state) => _authPage(state, const EditProfileScreen()),
      ),
      GoRoute(
        path: '/profile/badges',
        pageBuilder: (_, state) => _authPage(state, const BadgesScreen()),
      ),
      if (kDebugMode)
        GoRoute(
          path: '/dev/rive-calibration',
          pageBuilder: (_, state) =>
              _authPage(state, const RiveCalibrationScreen()),
        ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
