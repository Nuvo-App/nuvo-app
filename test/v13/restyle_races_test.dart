// S10 restyle coverage — the secondary race screens moved onto the v13
// design system. These tests pin the new chrome (back bar, cards, pills,
// sheets, toasts) and the preserved behavior (join-by-code, invite +
// share + add-by-username, owner settings + lifecycle confirms, proof
// review + veto, board-moved reward) with text/semantics finders.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/screenshot.dart';

import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/board_moved_screen.dart';
import 'package:nuvo/features/races/presentation/invite_crew_screen.dart';
import 'package:nuvo/features/races/presentation/join_race_screen.dart';
import 'package:nuvo/features/races/presentation/motion_catalog_provider.dart';
import 'package:nuvo/features/races/presentation/proof_review_screen.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/race_settings_screen.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

const _user = AuthUser(
  id: 'user-1',
  email: 'test@getnuvo.net',
  fullName: 'Test User',
  username: 'testuser',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(_user);
}

/// The real store round-trips through flutter_secure_storage's platform
/// channel, which never resolves under flutter_test — stub the one read the
/// evidence flow makes.
class _FakeTokenStore extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => null;
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo({
    this.races = const [],
    this.crew = const [],
    this.searchResults = const [],
    this.joinedRace,
    this.joinError,
    this.detailError,
  }) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  final List<PublicUser> crew;
  final List<PublicUser> searchResults;
  Race? joinedRace;
  Object? joinError;
  Object? detailError;

  // Recorded mutations — assertions on what the screens actually called.
  String? joinedCode;
  String? addedUserId;
  String? archivedRaceId;
  String? vetoReason;

  @override
  Future<List<Race>> getRaces() => Future.value(races);

  @override
  Future<Race> getRaceDetail(String id) {
    final error = detailError;
    if (error != null) return Future.error(error);
    return Future.value(
      races.firstWhere((r) => r.id == id, orElse: () => races.first),
    );
  }

  @override
  Future<List<PublicUser>> getCrew() => Future.value(crew);

  @override
  Future<List<PublicUser>> searchUsers(String query) =>
      Future.value(searchResults);

  @override
  Future<String> createInviteCode(String id) => Future.value('NUV-NEW777');

  @override
  Future<Race> joinRaceByCode(String code) {
    final error = joinError;
    if (error != null) return Future.error(error);
    joinedCode = code;
    return Future.value(joinedRace ?? races.first);
  }

  @override
  Future<Race> addRaceParticipant(String raceId, String userId) {
    addedUserId = userId;
    return Future.value(races.first);
  }

  @override
  Future<Race> archiveRace(String id) {
    archivedRaceId = id;
    return Future.value(races.first);
  }

  @override
  Future<Race> reviewProof(
    String raceId,
    String proofId, {
    required String status,
    String? summary,
  }) => Future.value(races.first);

  @override
  Future<ProofVetoResult> vetoProof(
    String raceId,
    String proofId, {
    required String reason,
  }) {
    vetoReason = reason;
    return Future.value(
      const ProofVetoResult(
        proofId: 'proof-1',
        state: 'disputed',
        vetoCount: 1,
        eligibleVoters: 3,
        threshold: 2,
        alreadyVoted: false,
      ),
    );
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _me = RaceParticipant(
  id: 'p1',
  userId: 'user-1',
  displayName: 'Test User',
  progressValue: 20,
  progressPercent: 20,
  joinedAt: '2026-01-01T00:00:00Z',
);

const _maya = RaceParticipant(
  id: 'p2',
  userId: 'user-2',
  displayName: 'Maya Miles',
  progressValue: 40,
  progressPercent: 40,
  joinedAt: '2026-01-01T00:00:00Z',
);

const _theo = PublicUser(
  id: 'user-3',
  displayName: 'Theo North',
  username: 'theo',
  initials: 'TN',
);

Race _race({
  String id = 'race-1',
  String creatorId = 'user-1',
  String? inviteCode,
  List<RaceProof> proofs = const [],
  String format = 'first_to_goal',
  String scoringRule = 'cumulative_sum',
  String scoreDirection = 'higher',
  int? targetValue = 100,
}) => Race(
  id: id,
  creatorId: creatorId,
  title: 'Pushup Race',
  goalType: 'first_to_goal',
  targetValue: targetValue,
  unit: 'reps',
  proofRequirement: 'manual',
  format: format,
  scoringRule: scoringRule,
  scoreDirection: scoreDirection,
  status: 'active',
  inviteCode: inviteCode,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: const [_me, _maya],
  recentProofs: proofs,
);

RaceProof _proof({
  String id = 'proof-1',
  String userId = 'user-2',
  String status = 'needs_review',
  String vetoState = 'none',
}) => RaceProof(
  id: id,
  userId: userId,
  displayName: 'Maya Miles',
  proofType: 'manual',
  value: 15,
  note: 'Knocked these out before breakfast.',
  verificationStatus: status,
  vetoState: vetoState,
  createdAt: '2026-01-02T08:00:00Z',
);

// ── Harness ──────────────────────────────────────────────────────────────────

class _Marker extends StatelessWidget {
  const _Marker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

List<Override> _overrides(_StubRaceRepo repo) => [
  raceRepositoryProvider.overrideWithValue(repo),
  authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
  secureTokenStoreProvider.overrideWithValue(_FakeTokenStore()),
  firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
  // Settings resolves camera-verification through the control-plane catalog —
  // serve the bundled snapshot so no repository load runs in tests.
  motionCatalogProvider.overrideWith(
    (ref) => Future.value(MotionCatalogSnapshot.bundled()),
  ),
];

GoRouter _router(Widget home) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/compete', builder: (_, _) => const _Marker('COMPETE')),
    GoRoute(path: '/arena', builder: (_, _) => const _Marker('ARENA')),
    GoRoute(path: '/profile', builder: (_, _) => const _Marker('PROFILE')),
    GoRoute(
      path: '/race/:id',
      builder: (_, s) => _Marker('RACE ${s.pathParameters['id']}'),
    ),
    GoRoute(
      path: '/race/:id/proof',
      builder: (_, s) => _Marker('PROOF ${s.pathParameters['id']}'),
    ),
    GoRoute(
      path: '/race/:id/proof/ai-motion',
      builder: (_, s) => _Marker('AI ${s.pathParameters['id']}'),
    ),
    GoRoute(
      path: '/u/:id',
      builder: (_, s) => _Marker('USER ${s.pathParameters['id']}'),
    ),
  ],
);

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

Future<GoRouter> _pump(
  WidgetTester tester,
  _StubRaceRepo repo,
  Widget home,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router(home);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  return router;
}

void main() {
  setUpAll(loadShotFonts);

  group('JoinRaceScreen', () {
    testWidgets('join by invite code routes to the race', (tester) async {
      final repo = _StubRaceRepo(
        races: [_race()],
        joinedRace: _race(id: 'race-joined'),
      );
      final router = await _pump(tester, repo, const JoinRaceScreen());
      await tester.pumpAndSettle();

      expect(find.text('Join a race'), findsOneWidget);
      expect(find.text('Invite code'), findsOneWidget);
      await shot(tester, 'v13_join_race');

      await tester.enterText(find.byType(TextField), 'nuv-9xyz');
      await tester.tap(find.text('Join race'));
      await tester.pumpAndSettle();

      // Codes normalize to uppercase before the API call.
      expect(repo.joinedCode, 'NUV-9XYZ');
      expect(_path(router), '/race/race-joined');
    });

    testWidgets('join failure shows the server message under the field', (
      tester,
    ) async {
      final repo = _StubRaceRepo(
        races: [_race()],
        joinError: const ApiException(404, 'That invite code did not work.'),
      );
      await _pump(tester, repo, const JoinRaceScreen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'NUV-BAD');
      await tester.tap(find.text('Join race'));
      await tester.pumpAndSettle();

      expect(find.text('That invite code did not work.'), findsOneWidget);
    });
  });

  group('InviteCrewScreen', () {
    testWidgets('friends list, code, and share action render', (tester) async {
      final repo = _StubRaceRepo(
        races: [_race(inviteCode: 'NUV-XYZ123')],
        crew: const [_theo],
      );
      await _pump(tester, repo, const InviteCrewScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      expect(find.text('Invite your friends'), findsOneWidget);
      expect(find.text('Pushup Race'), findsOneWidget);
      expect(find.text('ADD BY USERNAME'), findsOneWidget);
      expect(find.text('YOUR FRIENDS'), findsOneWidget);
      expect(find.text('Theo North'), findsOneWidget);
      expect(find.text('Add to race'), findsOneWidget);
      expect(find.text('SHARE A LINK OR QR'), findsOneWidget);
      expect(find.text('Share link & QR'), findsOneWidget);
      expect(find.text('OR A TYPABLE CODE'), findsOneWidget);
      expect(find.text('NUV-XYZ123'), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);
      await shot(tester, 'v13_invite_crew');
    });

    testWidgets('search results add to race through the controller', (
      tester,
    ) async {
      final repo = _StubRaceRepo(
        races: [_race(inviteCode: 'NUV-XYZ123')],
        crew: const [_theo],
        searchResults: const [
          PublicUser(
            id: 'user-9',
            displayName: 'Rin Osei',
            username: 'rin',
            initials: 'RO',
          ),
        ],
      );
      await _pump(tester, repo, const InviteCrewScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'rin');
      // Search is debounced ~360ms.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Rin Osei'), findsOneWidget);
      await tester.tap(find.text('Add to race').first);
      // Timed pumps — the toast auto-dismisses, so don't settle past it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.addedUserId, 'user-9');
      expect(find.text('Rin Osei added to race.'), findsOneWidget);
    });

    testWidgets('load failure shows error state with Retry', (tester) async {
      final repo = _StubRaceRepo(
        races: [_race()],
        detailError: StateError('offline'),
      );
      await _pump(tester, repo, const InviteCrewScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load invite details'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await shot(tester, 'v13_invite_crew_error');

      repo.detailError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Pushup Race'), findsOneWidget);
    });
  });

  group('RaceSettingsScreen', () {
    testWidgets('owner sees editable fields and lifecycle actions', (
      tester,
    ) async {
      final repo = _StubRaceRepo(races: [_race()]);
      await _pump(tester, repo, const RaceSettingsScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      expect(find.text('Edit race'), findsOneWidget);
      // Title field comes prefilled from the race.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Pushup Race',
      );
      expect(find.text('Save changes'), findsOneWidget);

      // The actions card sits below the fold — scroll it into view (the
      // first Scrollable is the form's ListView; EditableText registers its
      // own inner ones, so name the finder explicitly).
      await tester.scrollUntilVisible(
        find.text('Archive race'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('RACE ACTIONS'), findsOneWidget);
      expect(find.text('Archive race'), findsOneWidget);
      expect(find.text('Cancel race'), findsOneWidget);
      expect(find.text('Delete race'), findsOneWidget);
      await shot(tester, 'v13_race_settings');
    });

    testWidgets('archive runs through a confirm sheet', (tester) async {
      final repo = _StubRaceRepo(races: [_race()]);
      final router = await _pump(
        tester,
        repo,
        const RaceSettingsScreen(raceId: 'race-1'),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Archive race'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Archive race'));
      await tester.pumpAndSettle();

      expect(find.text('Archive race?'), findsOneWidget);
      expect(find.text('Keep race'), findsOneWidget);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(repo.archivedRaceId, 'race-1');
      expect(_path(router), '/race/race-1');
    });

    testWidgets('non-owner gets the locked state', (tester) async {
      final repo = _StubRaceRepo(races: [_race(creatorId: 'user-2')]);
      await _pump(tester, repo, const RaceSettingsScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      expect(
        find.text('Only the race creator can edit race settings.'),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsNothing);
      expect(find.text('Back to race'), findsOneWidget);
    });

    testWidgets('load failure shows error state with Retry', (tester) async {
      final repo = _StubRaceRepo(
        races: [_race()],
        detailError: StateError('offline'),
      );
      await _pump(tester, repo, const RaceSettingsScreen(raceId: 'race-1'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load race settings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('ProofReviewScreen', () {
    testWidgets('owner sees the move summary and decision controls', (
      tester,
    ) async {
      final repo = _StubRaceRepo(
        races: [
          _race(proofs: [_proof()]),
        ],
      );
      await _pump(
        tester,
        repo,
        const ProofReviewScreen(raceId: 'race-1', proofId: 'proof-1'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review move'), findsOneWidget);
      expect(find.text('Maya Miles'), findsOneWidget);
      expect(find.text('Pushup Race'), findsOneWidget);
      expect(find.text('+15 reps'), findsOneWidget);
      expect(find.text('Knocked these out before breakfast.'), findsOneWidget);
      expect(find.text('Proof decision'), findsOneWidget);
      expect(find.text('Accept proof'), findsOneWidget);
      expect(find.text('Ask for another proof'), findsOneWidget);
      expect(find.text('Reject proof'), findsOneWidget);
      await shot(tester, 'v13_proof_review');
    });

    testWidgets('participant sees the verdict and can veto', (tester) async {
      // Viewer is a racer, not the creator — no decision controls.
      final repo = _StubRaceRepo(
        races: [
          _race(
            creatorId: 'user-2',
            proofs: [_proof(status: 'accepted')],
          ),
        ],
      );
      await _pump(
        tester,
        repo,
        const ProofReviewScreen(raceId: 'race-1', proofId: 'proof-1'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Proof'), findsOneWidget);
      expect(
        find.text('Accepted — counts on the leaderboard.'),
        findsOneWidget,
      );
      expect(find.text('Accept proof'), findsNothing);
      expect(find.text('Veto proof'), findsOneWidget);
      expect(find.text('Report this move'), findsOneWidget);
      await shot(tester, 'v13_proof_review_racer');

      await tester.tap(find.text('Veto proof'));
      await tester.pumpAndSettle();
      expect(find.text('Veto this proof?'), findsOneWidget);

      await tester.tap(find.text('Wrong result'));
      await tester.pumpAndSettle();
      expect(repo.vetoReason, 'wrong_result');
    });

    testWidgets('load failure shows error state with Retry', (tester) async {
      final repo = _StubRaceRepo(
        races: [_race()],
        detailError: StateError('offline'),
      );
      await _pump(
        tester,
        repo,
        const ProofReviewScreen(raceId: 'race-1', proofId: 'proof-1'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load move review.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('unknown proof id shows the not-found state', (tester) async {
      final repo = _StubRaceRepo(races: [_race()]);
      await _pump(
        tester,
        repo,
        const ProofReviewScreen(raceId: 'race-1', proofId: 'proof-gone'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Move not found'), findsOneWidget);
      expect(find.text('Back to race'), findsOneWidget);
    });
  });

  group('BoardMovedScreen', () {
    testWidgets('verified move shows +N, the rank pop, and both actions', (
      tester,
    ) async {
      final repo = _StubRaceRepo(races: [_race()]);
      await _pump(
        tester,
        repo,
        const BoardMovedScreen(
          raceId: 'race-1',
          args: BoardMovedArgs(
            raceId: 'race-1',
            raceName: 'Pushup Race',
            value: 15,
            unit: 'reps',
            status: 'verified',
            rankBefore: 3,
            rankAfter: 1,
            aiMotionProof: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('MOVE VERIFIED'), findsOneWidget);
      expect(find.text('+15'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('View race'), findsOneWidget);
      expect(find.text('Go again'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await shot(tester, 'v13_board_moved');

      await tester.tap(find.text('View race'));
      await tester.pumpAndSettle();
    });

    testWidgets('test_gap16_lower_direction_has_no_plus_prefix', (
      tester,
    ) async {
      final repo = _StubRaceRepo(
        races: [
          _race(
            format: 'best_attempt',
            scoringRule: 'minimum_attempt',
            scoreDirection: 'lower',
            targetValue: null,
          ),
        ],
      );
      await _pump(
        tester,
        repo,
        const BoardMovedScreen(
          raceId: 'race-1',
          args: BoardMovedArgs(
            raceId: 'race-1',
            raceName: 'Golf Round',
            value: 30,
            unit: 'reps',
            status: 'verified',
            rankBefore: 2,
            rankAfter: 1,
            aiMotionProof: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(seconds: 3));

      // A lower-wins attempt stands alone — nothing is added to a total,
      // so no "+N" prefix appears anywhere.
      expect(find.text('+30'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining('added to your total'), findsNothing);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('30 reps logged'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
    });

    testWidgets('attempt-mode race: hero and pill drop the +', (
      tester,
    ) async {
      final repo = _StubRaceRepo(
        races: [
          _race(
            format: 'timed_attempt',
            scoringRule: 'maximum_attempt',
            targetValue: null,
          ),
        ],
      );
      await _pump(
        tester,
        repo,
        const BoardMovedScreen(
          raceId: 'race-1',
          args: BoardMovedArgs(
            raceId: 'race-1',
            raceName: 'Pushup Battle',
            value: 15,
            unit: 'reps',
            status: 'verified',
            rankBefore: 3,
            rankAfter: 2,
            aiMotionProof: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('+15'), findsNothing);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('15 reps logged'), findsOneWidget);
      expect(find.textContaining('added to your total'), findsNothing);
    });

    testWidgets('pending move stays calm', (tester) async {
      final repo = _StubRaceRepo(races: [_race()]);
      await _pump(
        tester,
        repo,
        const BoardMovedScreen(
          raceId: 'race-1',
          args: BoardMovedArgs(
            raceId: 'race-1',
            raceName: 'Pushup Race',
            value: 15,
            unit: 'reps',
            status: 'needs_review',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Move logged — under review'), findsOneWidget);
      expect(find.text('View race'), findsOneWidget);
      expect(find.text('Go again'), findsNothing);
      await shot(tester, 'v13_board_moved_pending');
    });

    testWidgets('not-verified move offers a retry, not a celebration', (
      tester,
    ) async {
      final repo = _StubRaceRepo(races: [_race()]);
      await _pump(
        tester,
        repo,
        const BoardMovedScreen(
          raceId: 'race-1',
          args: BoardMovedArgs(
            raceId: 'race-1',
            raceName: 'Pushup Race',
            value: 0,
            unit: 'reps',
            status: 'rejected',
            aiMotionProof: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Proof needs another try'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Back to race'), findsOneWidget);
      await shot(tester, 'v13_board_moved_failed');
    });
  });
}
