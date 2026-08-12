import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/theme/app_theme.dart';
import 'features/arena/data/arena_api.dart';
import 'features/arena/presentation/arena_screen.dart';
import 'features/compete/presentation/compete_screen.dart';
import 'features/move/presentation/move_screen.dart';
import 'features/pass/presentation/pass_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/shell/presentation/main_shell.dart';
import 'features/arena/data/arena_models.dart';
import 'features/arena/data/arena_repository.dart';
import 'features/arena/presentation/arena_controller.dart';
import 'features/auth/data/auth_api.dart';
import 'features/auth/data/auth_models.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/secure_token_store.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/races/data/race_api.dart';
import 'features/races/data/race_models.dart';
import 'features/races/data/race_repository.dart';
import 'features/races/presentation/race_controller.dart';

// ── Preview data ─────────────────────────────────────────────────────────────

const _previewUser = AuthUser(
  id: 'u1',
  email: 'shresh@nuvo.app',
  fullName: 'Shresh Panda',
  username: 'shresh',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

const _previewPass = PassInfo(
  memberId: 'N-0001',
  passSlug: 'shresh',
  shareUrl: 'https://getnuvo.net/p/shresh',
);

const _previewCrew = [
  PublicUser(
    id: 'u2',
    displayName: 'Alex R.',
    username: 'alex',
    initials: 'AR',
    addedAt: '2024-01-02T00:00:00Z',
  ),
  PublicUser(
    id: 'u3',
    displayName: 'Maya L.',
    username: 'maya',
    initials: 'ML',
    addedAt: '2024-01-03T00:00:00Z',
  ),
];

const _previewRace = Race(
  id: 'preview-race',
  creatorId: 'u1',
  title: 'First to 100 Pushups',
  category: 'fitness',
  goalType: 'manual',
  targetValue: 100,
  unit: 'reps',
  aiActivityType: 'pushups',
  activityId: 'pushups',
  targetUnit: 'reps',
  proofMode: 'manual',
  metric: 'reps',
  status: 'active',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-05T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p-u1',
      userId: 'u1',
      displayName: 'You',
      progressValue: 65,
      progressPercent: 65,
      rank: 1,
      joinedAt: '2024-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p-u2',
      userId: 'u2',
      displayName: 'Alex R.',
      progressValue: 48,
      progressPercent: 48,
      rank: 2,
      joinedAt: '2024-01-02T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p-u3',
      userId: 'u3',
      displayName: 'Maya L.',
      progressValue: 31,
      progressPercent: 31,
      rank: 3,
      joinedAt: '2024-01-03T00:00:00Z',
    ),
  ],
);

const _readyRace = Race(
  id: 'r1',
  creatorId: 'u1',
  title: 'First to 60 Squats',
  category: 'fitness',
  goalType: 'manual',
  targetValue: 60,
  unit: 'reps',
  aiActivityType: 'squats',
  activityId: 'squats',
  targetUnit: 'reps',
  proofMode: 'manual',
  metric: 'reps',
  status: 'active',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-05T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p1-u1',
      userId: 'u1',
      displayName: 'You',
      progressValue: 28,
      progressPercent: 47,
      rank: 2,
      joinedAt: '2024-01-01T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p1-u4',
      userId: 'u4',
      displayName: 'Jordan K.',
      progressValue: 42,
      progressPercent: 70,
      rank: 1,
      joinedAt: '2024-01-04T00:00:00Z',
    ),
  ],
  recentProofs: [
    RaceProof(
      id: 'pf-1',
      userId: 'u1',
      displayName: 'You',
      proofType: 'manual',
      value: 10,
      note: 'Crushed it',
      verificationStatus: 'verified',
      createdAt: '2024-01-05T10:00:00Z',
    ),
  ],
);

const _waitingRace = Race(
  id: 'r2',
  creatorId: 'u1',
  title: 'First to 50 Jumping Jacks',
  category: 'fitness',
  goalType: 'manual',
  targetValue: 50,
  unit: 'reps',
  aiActivityType: 'jumping_jacks',
  activityId: 'jumping_jacks',
  targetUnit: 'reps',
  proofMode: 'manual',
  metric: 'reps',
  status: 'active',
  createdAt: '2024-01-02T00:00:00Z',
  updatedAt: '2024-01-05T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p2-u1',
      userId: 'u1',
      displayName: 'You',
      progressValue: 0,
      progressPercent: 0,
      rank: 1,
      joinedAt: '2024-01-02T00:00:00Z',
    ),
  ],
);

const _finishedRace = Race(
  id: 'r3',
  creatorId: 'u2',
  title: 'First to 40 Lunges',
  category: 'fitness',
  goalType: 'manual',
  targetValue: 40,
  unit: 'reps',
  aiActivityType: 'lunges',
  activityId: 'lunges',
  targetUnit: 'reps',
  proofMode: 'manual',
  metric: 'reps',
  status: 'completed',
  createdAt: '2024-01-02T00:00:00Z',
  updatedAt: '2024-01-04T00:00:00Z',
  participants: [
    RaceParticipant(
      id: 'p3-u1',
      userId: 'u1',
      displayName: 'You',
      progressValue: 40,
      progressPercent: 100,
      rank: 1,
      joinedAt: '2024-01-02T00:00:00Z',
    ),
    RaceParticipant(
      id: 'p3-u3',
      userId: 'u3',
      displayName: 'Maya L.',
      progressValue: 20,
      progressPercent: 50,
      rank: 2,
      joinedAt: '2024-01-03T00:00:00Z',
    ),
  ],
  finalStandings: [
    RaceFinalStanding(
      userId: 'u1',
      displayName: 'You',
      rank: 1,
      scoreValue: 40,
    ),
    RaceFinalStanding(
      userId: 'u3',
      displayName: 'Maya L.',
      rank: 2,
      scoreValue: 20,
    ),
  ],
);

const _previewRaces = <Race>[
  _previewRace,
  _readyRace,
  _waitingRace,
  _finishedRace,
];

// ── Fake repositories ────────────────────────────────────────────────────────

class _PreviewAuthRepository extends AuthRepository {
  _PreviewAuthRepository() : super(AuthApi(), SecureTokenStore());

  @override
  Future<AuthUser?> restoreSession() async => _previewUser;

  @override
  Future<PassInfo> getMemberPass() async => _previewPass;
}

class _PreviewRaceRepository extends RaceRepository {
  _PreviewRaceRepository() : super(RaceApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<Race>> getRaces() async => _previewRaces;

  @override
  Future<List<PublicUser>> getCrew() async => _previewCrew;

  @override
  Future<List<PublicUser>> searchUsers(String query) async => [];
}

class _PreviewArenaRepository extends ArenaRepository {
  _PreviewArenaRepository() : super(ArenaApi(), SecureTokenStore(), AuthApi());

  @override
  Future<ArenaSnapshot> getArenaSnapshot() async => const ArenaSnapshot(
    mode: 'real',
    headerPulse: '',
    focusBoard: ArenaBoard(
      id: 'preview-race',
      source: 'real',
      title: 'Pushups',
      progressLabel: '65 / 100',
      boardContext: 'First to 100 Pushups',
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof',
      progressPercent: 65,
      racerCount: 3,
      isResult: false,
      myRank: 1,
      miniLeaderboard: [
        ArenaMiniLeaderboardRow(
          label: 'You',
          value: '65 / 100',
          isCurrentUser: true,
        ),
        ArenaMiniLeaderboardRow(
          label: 'Alex R.',
          value: '48 / 100',
          isCurrentUser: false,
        ),
        ArenaMiniLeaderboardRow(
          label: 'Maya L.',
          value: '31 / 100',
          isCurrentUser: false,
        ),
      ],
    ),
    liveBoards: [
      ArenaBoard(
        id: 'preview-race',
        source: 'real',
        title: 'Pushups',
        progressLabel: '65 / 100',
        boardContext: 'First to 100 Pushups',
        primaryActionLabel: 'Submit proof',
        primaryActionType: 'submit_proof',
        progressPercent: 65,
        racerCount: 3,
        isResult: false,
        myRank: 1,
        miniLeaderboard: [
          ArenaMiniLeaderboardRow(
            label: 'You',
            value: '65 / 100',
            isCurrentUser: true,
          ),
          ArenaMiniLeaderboardRow(
            label: 'Alex R.',
            value: '48 / 100',
            isCurrentUser: false,
          ),
          ArenaMiniLeaderboardRow(
            label: 'Maya L.',
            value: '31 / 100',
            isCurrentUser: false,
          ),
        ],
      ),
    ],
    results: [],
  );
}

// ── Fake controllers ─────────────────────────────────────────────────────────

class _PreviewAuthController extends AuthController {
  _PreviewAuthController() : super(_PreviewAuthRepository());

  @override
  Future<void> sessionExpired() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

class _PreviewRaceController extends RaceController {
  _PreviewRaceController() : super(_PreviewRaceRepository());
}

class _PreviewArenaController extends ArenaController {
  _PreviewArenaController() : super(_PreviewArenaRepository());
}

// ── Preview router ─────────────────────────────────────────────────────────────

final _previewRouter = GoRouter(
  initialLocation: '/arena',
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/arena',
          builder: (context, state) => const ArenaScreen(),
        ),
        GoRoute(
          path: '/compete',
          builder: (context, state) => const CompeteScreen(),
        ),
        GoRoute(
          path: '/move',
          builder: (context, state) => const MoveScreen(),
        ),
        GoRoute(
          path: '/pass',
          builder: (context, state) => const PassScreen(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    ),
  ],
);

// ── Entry point ──────────────────────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay);

  runApp(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _PreviewAuthController()),
        raceControllerProvider.overrideWith((ref) => _PreviewRaceController()),
        arenaControllerProvider.overrideWith((ref) => _PreviewArenaController()),
        routerProvider.overrideWith((ref) => _previewRouter),
      ],
      child: const NuvoApp(),
    ),
  );
}
