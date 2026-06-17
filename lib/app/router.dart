import 'package:go_router/go_router.dart';

import '../features/auth/presentation/otp_screen.dart';
import '../features/auth/presentation/phone_auth_screen.dart';
import '../features/challenges/presentation/arena_screen.dart';
import '../features/challenges/presentation/challenge_detail_screen.dart';
import '../features/challenges/presentation/challenge_ideas_screen.dart';
import '../features/challenges/presentation/create_challenge_screen.dart';
import '../features/crew/presentation/crew_screen.dart';
import '../features/devices/presentation/devices_screen.dart';
import '../features/founders/presentation/founders_screen.dart';
import '../features/invite/presentation/invite_screen.dart';
import '../features/investor/presentation/investor_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/verification/presentation/verification_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const SplashScreen(),
      ),
    ),
    GoRoute(
      path: '/auth/phone',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const PhoneAuthScreen(),
      ),
    ),
    GoRoute(
      path: '/auth/otp',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const OtpScreen(),
      ),
    ),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const OnboardingScreen(),
      ),
    ),

    // Bottom-nav shell — Home · Crew · Create · Profile
    // NoTransitionPage on tab routes prevents slide-over collisions during tab switches.
    ShellRoute(
      builder: (context, _, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/arena',
          pageBuilder: (_, state) => NoTransitionPage(
            key: state.pageKey,
            child: const ArenaScreen(),
          ),
        ),
        GoRoute(
          path: '/crew',
          pageBuilder: (_, state) => NoTransitionPage(
            key: state.pageKey,
            child: const CrewScreen(),
          ),
        ),
        GoRoute(
          path: '/create',
          pageBuilder: (_, state) => NoTransitionPage(
            key: state.pageKey,
            child: const CreateChallengeScreen(),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (_, state) => NoTransitionPage(
            key: state.pageKey,
            child: const ProfileScreen(),
          ),
        ),
      ],
    ),

    // Standalone screens — simple fade transition (no slide-over)
    GoRoute(
      path: '/verification',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const VerificationScreen(),
      ),
    ),
    GoRoute(
      path: '/challenge/:id',
      builder: (_, state) =>
          ChallengeDetailScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/challenge-ideas',
      pageBuilder: (_, state) => NoTransitionPage(
        key: state.pageKey,
        child: const ChallengeIdeasScreen(),
      ),
    ),
    GoRoute(
      path: '/invite',
      builder: (_, _) => const InviteScreen(),
    ),
    GoRoute(
      path: '/founders',
      builder: (_, _) => const FoundersScreen(),
    ),
    GoRoute(
      path: '/devices',
      builder: (_, _) => const DevicesScreen(),
    ),
    GoRoute(
      path: '/investor',
      builder: (_, _) => const InvestorScreen(),
    ),
  ],
);
