import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../helpers/screenshot.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';
import 'package:nuvo/features/races/presentation/v13/composer/race_composer_v13_screen.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/compete/presentation/v13/compete_v13_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/v13/race_detail_v13_screen.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_sheet.dart';

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'user-1',
      email: 'test@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo({this.races = const [], this.openRaces, this.leaderboard})
    : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  final List<Race>? openRaces;
  final List<LeaderboardEntry>? leaderboard;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
  @override
  Future<List<Race>> getOpenRaces() => Future.value(openRaces ?? const []);
  @override
  Future<List<LeaderboardEntry>> getLeaderboard({String scope = 'friends'}) =>
      Future.value(leaderboard ?? const []);
  @override
  Future<Race> getRaceDetail(String id) =>
      Future.value(races.firstWhere((r) => r.id == id));
}

Race _race({
  String id = 'race-1',
  String title = 'Pushup Race',
  String status = 'active',
  int meProgress = 20,
  bool includeMe = true,
  String creatorId = 'user-1',
  String format = 'first_to_goal',
  String scoringRule = 'cumulative_sum',
  String scoreDirection = 'higher',
  int? targetValue = 100,
  int? attemptDurationSeconds,
  int? attemptLimit,
  int attemptsUsed = 0,
  List<RaceProof> recentProofs = const [],
}) {
  final participants = <RaceParticipant>[
    if (includeMe)
      RaceParticipant(
        id: 'p1',
        userId: 'user-1',
        displayName: 'Test User',
        progressValue: meProgress,
        progressPercent: meProgress,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
    const RaceParticipant(
      id: 'p2',
      userId: 'user-2',
      displayName: 'Maya Miles',
      progressValue: 40,
      progressPercent: 40,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    const RaceParticipant(
      id: 'p3',
      userId: 'user-3',
      displayName: 'Theo North',
      progressValue: 10,
      progressPercent: 10,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ];
  return Race(
    id: id,
    creatorId: creatorId,
    title: title,
    goalType: 'first_to_goal',
    targetValue: targetValue,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    activityId: 'pushups',
    format: format,
    scoringRule: scoringRule,
    scoreDirection: scoreDirection,
    attemptDurationSeconds: attemptDurationSeconds,
    attemptLimit: attemptLimit,
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: participants,
    recentProofs: recentProofs,
    viewerContext: RaceViewerContext(
      raceId: id,
      status: status,
      rank: 2,
      viewerScore: meProgress,
      leaderScore: 40,
      timeRemainingSeconds: 86400,
      isMember: includeMe,
      attemptsUsed: attemptsUsed,
    ),
  );
}

List<Override> _overrides(_StubRaceRepo repo) => [
  raceRepositoryProvider.overrideWithValue(repo),
  authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
];

Widget _app(_StubRaceRepo repo, {required Widget home}) => ProviderScope(
  overrides: _overrides(repo),
  child: MaterialApp(home: home),
);

void main() {
  setUpAll(loadShotFonts);
  composerTests();
  testWidgets('Compete: header, live races, hidden open section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(_StubRaceRepo(races: [_race()]), home: const CompeteV13Screen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compete'), findsOneWidget);
    expect(find.text('New race'), findsOneWidget);
    expect(find.text('Join with code'), findsOneWidget);
    expect(find.text('Live races'), findsOneWidget);
    expect(find.text('Pushup Race'), findsWidgets);
    // No open races → the whole section hides.
    expect(find.text('Join a race'), findsNothing);
    expect(find.text('Leaderboard'), findsNothing);
  });

  testWidgets('test_gap15_goalless_race_card_hides_percent', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(
          races: [
            _race(),
            _race(
              id: 'race-2',
              title: 'Golf Round',
              format: 'best_attempt',
              scoringRule: 'maximum_attempt',
              targetValue: null,
            ),
          ],
        ),
        home: const CompeteV13Screen(),
      ),
    );
    await tester.pumpAndSettle();
    // Only the first-to-goal card carries a bar and a percent — a
    // best-single card has no finish line to be a share of, so it shows
    // the score next to the mode name instead.
    expect(find.byType(V13ProgressBar), findsOneWidget);
    expect(find.text('20 / 100 reps · 20%'), findsOneWidget);
    expect(find.text('20 reps · Best single'), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('Compete retires a pending pre-v13 guide step', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: _overrides(_StubRaceRepo(races: const [])),
    );
    addTearDown(container.dispose);
    container.read(firstRaceGuideProvider.notifier).state =
        FirstRaceGuideStep.competeStart;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CompeteV13Screen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(firstRaceGuideProvider), FirstRaceGuideStep.complete);
  });

  testWidgets('Compete: open races + leaderboard render when served', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(
          races: const [],
          openRaces: [
            _race(id: 'open-1', title: 'Squat Sprint', includeMe: false),
          ],
          leaderboard: const [
            LeaderboardEntry(
              userId: 'user-2',
              displayName: 'Maya Miles',
              points: 120,
              rank: 1,
              isMe: false,
            ),
            LeaderboardEntry(
              userId: 'user-1',
              displayName: 'Test User',
              points: 80,
              rank: 2,
              isMe: true,
            ),
          ],
        ),
        home: const CompeteV13Screen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Join a race'), findsOneWidget);
    expect(
      find.textContaining('is racing Squat Sprint', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Join'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Maya Miles'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('80 pts'), findsOneWidget);
    await shot(tester, 'v13_compete_populated');
  });

  testWidgets('Race detail: podium, rows, join CTA for non-participant', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/race/race-1',
      routes: [
        GoRoute(
          path: '/race/:id',
          builder: (_, s) =>
              RaceDetailV13Screen(raceId: s.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          _StubRaceRepo(races: [_race(includeMe: false, creatorId: 'user-2')]),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pushup Race'), findsOneWidget);
    expect(find.text('First to 100 reps'), findsOneWidget);
    // Two racers with progress → ranked list rows (full names), no podium.
    expect(find.text('Maya Miles'), findsOneWidget);
    expect(find.text('Join race'), findsOneWidget);
    await shot(tester, 'v13_race_detail_visitor');
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Report this race'), findsOneWidget);
  });

  testWidgets('Race detail: participant sees Submit proof', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(races: [_race()]),
        home: const RaceDetailV13Screen(raceId: 'race-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Submit proof'), findsOneWidget);
    expect(find.text('Join race'), findsNothing);
    await shot(tester, 'v13_race_detail_racer');
  });

  testWidgets('attempt-race proof rows show the bare score, not "+N"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(
          races: [
            _race(
              format: 'best_attempt',
              scoringRule: 'maximum_attempt',
              targetValue: null,
              recentProofs: const [
                RaceProof(
                  id: 'proof-1',
                  userId: 'user-2',
                  displayName: 'Maya Miles',
                  proofType: 'manual',
                  value: 30,
                  verificationStatus: 'verified',
                  createdAt: '2026-01-02T08:00:00Z',
                ),
              ],
            ),
          ],
        ),
        home: const RaceDetailV13Screen(raceId: 'race-1'),
      ),
    );
    await tester.pumpAndSettle();
    // A best-single proof stands alone — the activity row shows the score
    // itself, never a "+N" onto a total that does not exist.
    expect(
      find.textContaining('Maya 30 reps', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('+30 reps', findRichText: true), findsNothing);
  });

  testWidgets('test_gapOC6_attempt_limit_visible_in_ui', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(
          races: [
            _race(
              format: 'timed_attempt',
              scoringRule: 'maximum_attempt',
              targetValue: null,
              attemptDurationSeconds: 30,
              attemptLimit: 5,
              attemptsUsed: 2,
            ),
          ],
        ),
        home: const RaceDetailV13Screen(raceId: 'race-1'),
      ),
    );
    await tester.pumpAndSettle();
    // The attempt budget was invisible — the racer now sees it next to
    // their score.
    expect(find.text('2 of 5 attempts used'), findsOneWidget);
    expect(find.text('Most in 30s wins'), findsOneWidget);
  });

  testWidgets('/race/:id/proof lands on Race detail with the sheet open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(races: [_race()]),
        home: const RaceDetailV13Screen(
          raceId: 'race-1',
          openProofOnLoad: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SubmitProofV13Sheet), findsOneWidget);
  });

  testWidgets('openProofOnLoad does nothing for a visitor', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(races: [_race(includeMe: false)]),
        home: const RaceDetailV13Screen(
          raceId: 'race-1',
          openProofOnLoad: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SubmitProofV13Sheet), findsNothing);
  });

  testWidgets('Submit proof sheet: manual requires a photo', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        _StubRaceRepo(races: [_race()]),
        home: Scaffold(body: SubmitProofV13Sheet(race: _race())),
      ),
    );
    await tester.pumpAndSettle();
    // Camera-verifiable pushup → segmented chooser shows both.
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    await shot(tester, 'v13_submit_sheet');
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log proof'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a photo — proof is required for this race.'),
      findsOneWidget,
    );
    expect(find.text('Keeps you at 2nd.'), findsOneWidget);
  });
}

void composerTests() {
  testWidgets('New race: typing a name autofills "auto" chips; tapping one '
      'opens the setup step', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(_StubRaceRepo(races: const []), home: const RaceComposerV13Screen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('What are you racing?'), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), 'First to 100 pushups');
    await tester.pump(const Duration(milliseconds: 400)); // autofill debounce
    await tester.pumpAndSettle();
    await shot(tester, 'v13_composer_name');
    final chip = find.text('100');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Set it up.'), findsOneWidget);
    expect(find.text('2 of 4'), findsOneWidget);
    await shot(tester, 'v13_composer_setup');
  });
}
