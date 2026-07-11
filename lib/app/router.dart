import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/arena/presentation/arena_screen_fixed.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/auth/presentation/email_start_screen.dart';
import '../features/auth/presentation/email_verify_screen.dart';
import '../features/auth/presentation/welcome_auth_screen.dart';
import '../features/compete/presentation/compete_screen.dart';
import '../features/onboarding/presentation/add_crew_screen.dart';
import '../features/onboarding/presentation/create_identity_screen.dart';
import '../features/onboarding/presentation/first_race_screen.dart';
import '../features/onboarding/presentation/member_pass_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/secure_account_screen.dart';
import '../features/pass/presentation/pass_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/proof/presentation/proof_screen.dart';
import '../features/move/presentation/move_screen.dart';
import '../features/race_detail/presentation/race_detail_screen.dart';
import '../features/races/presentation/create_race_screen.dart';
import '../features/races/presentation/ai_motion_proof_screen.dart';
import '../features/races/presentation/invite_crew_screen.dart';
import '../features/races/presentation/join_race_screen.dart';
import '../features/races/presentation/proof_review_screen.dart';
import '../features/races/presentation/race_settings_screen.dart';
import '../features/races/presentation/board_moved_screen.dart';
import '../features/races/presentation/submit_proof_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/splash/presentation/splash_screen.dart';

// Soft horizontal-slide + fade transition used on all auth/onboarding routes.
Page<void> _authPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeOut).animate(animation),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
            child: child,
          ),
        );
      },
    );

// Slide-up transition for camera/verification — feels like the action is expanding.
Page<void> _cameraPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeOut).animate(animation),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
            child: child,
          ),
        );
      },
    );

// Race detail: horizontal slide with slight scale for depth.
Page<void> _detailPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(curvedAnimation),
              child: child,
            ),
          ),
        );
      },
    );

/// Bottom-nav tab switch: instant, no transition. Each tab is a full
/// screen rebuild (this ShellRoute doesn't preserve branch state across
/// switches — pre-existing architecture, not introduced by this redesign),
/// so animating the switch just exposes that rebuild cost as visible jank.
/// Native iOS tab bars don't crossfade content either; matching that instead
/// of fighting it is the actually-seamless choice here.
Page<void> _tabPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.read(routerNotifierProvider);
  final router = GoRouter(
    initialLocation: '/splash',
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
        path: '/welcome',
        pageBuilder: (_, state) => _authPage(state, const WelcomeAuthScreen()),
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
        path: '/onboarding/create-identity',
        pageBuilder: (_, state) =>
            _authPage(state, const CreateIdentityScreen()),
      ),
      GoRoute(
        path: '/onboarding/secure-account',
        pageBuilder: (_, state) =>
            _authPage(state, const SecureAccountScreen()),
      ),
      GoRoute(
        path: '/onboarding/profile',
        pageBuilder: (_, state) => _authPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/onboarding/member-pass',
        pageBuilder: (_, state) =>
            _authPage(state, const OnboardingMemberPassScreen()),
      ),
      GoRoute(
        path: '/onboarding/add-crew',
        pageBuilder: (_, state) => _authPage(state, const AddCrewScreen()),
      ),
      GoRoute(
        path: '/onboarding/first-race',
        pageBuilder: (_, state) => _authPage(state, const FirstRaceScreen()),
      ),

      // ── Main shell (bottom nav) ────────────────────────────────────────────
      ShellRoute(
        builder: (context, _, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/arena',
            pageBuilder: (_, state) => _tabPage(state, const ArenaScreen()),
          ),
          GoRoute(
            path: '/pass',
            pageBuilder: (_, state) => _tabPage(state, const PassScreen()),
          ),
          GoRoute(
            path: '/compete',
            pageBuilder: (_, state) => _tabPage(state, const CompeteScreen()),
          ),
          GoRoute(
            path: '/move',
            pageBuilder: (_, state) => _tabPage(state, const MoveScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => _tabPage(state, const ProfileScreen()),
          ),
        ],
      ),

      // ── Detail / standalone ───────────────────────────────────────────────
      GoRoute(
        path: '/races/new',
        pageBuilder: (_, state) => _authPage(
          state,
          CreateRaceScreen(
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
      GoRoute(
        path: '/race/:id/edit',
        pageBuilder: (_, state) => _authPage(
          state,
          RaceSettingsScreen(raceId: state.pathParameters['id']!),
        ),
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
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: ProofScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (_, state) => _authPage(state, const EditProfileScreen()),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
