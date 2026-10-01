// Release-hardening coverage for the AI Motion Proof routing contract:
//
//  - every camera-verifiable entry (Verify hero, Ready Next row, Race
//    Detail, the proof chooser's Begin, board-moved retry) lands directly on
//    /race/:id/proof/ai-motion — the boxed legacy scaffold is deleted, so no
//    state can render the old white-shell verifier
//  - non-camera races still route to the /race/:id/proof chooser
//  - background/resume recovers onto the same surface, never a dead preview
//  - the first-race guide stays armed through the verifier, advances to
//    profileReward on a real submission, and Profile's 'Got it' is the only
//    thing that completes it
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/ai_motion_proof_screen.dart';
import 'package:nuvo/features/races/presentation/board_moved_screen.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/submit_proof_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

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

class _FakeRaceRepo extends RaceRepository {
  _FakeRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;

  @override
  Future<List<Race>> getRaces() => Future.value(races);

  @override
  Future<Race> getRaceDetail(String id) async =>
      races.firstWhere((r) => r.id == id, orElse: () => races.first);
}

/// A camera-verifiable movement race (pushups, first-to-N).
Race _movementRace({String id = 'race-move', String title = 'Pushup Race'}) =>
    Race(
      id: id,
      creatorId: 'user-1',
      title: title,
      goalType: 'first_to_goal',
      targetValue: 15,
      unit: 'reps',
      targetUnit: 'reps',
      activityId: 'push_ups',
      metric: 'reps',
      format: 'first_to_goal',
      proofRequirement: 'ai_check',
      proofMode: 'ai_check',
      verificationMethod: 'camera_pose',
      status: 'active',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      participants: const [_participant],
    );

const _participant = RaceParticipant(
  id: 'p-1',
  userId: 'user-1',
  displayName: 'Test User',
  progressValue: 0,
  progressPercent: 0,
  joinedAt: '2026-01-01T00:00:00Z',
);

/// A manual-goal race — never camera-verifiable.
Race _manualRace({String id = 'race-manual'}) => Race(
  id: id,
  creatorId: 'user-1',
  title: 'Reading Race',
  goalType: 'first_to_goal',
  targetValue: 5,
  unit: 'books',
  targetUnit: 'books',
  metric: 'books',
  format: 'first_to_goal',
  proofRequirement: 'manual',
  proofMode: 'manual',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  participants: const [_participant],
);

// ── Route markers — the proof chooser and the verifier are DISTINCT widgets ──

class _ChooserMarker extends StatelessWidget {
  const _ChooserMarker();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('PROOF-CHOOSER'));
}

class _VerifierMarker extends StatelessWidget {
  const _VerifierMarker();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('CANONICAL-VERIFIER'));
}

class _RaceDetailMarker extends StatelessWidget {
  const _RaceDetailMarker();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('RACE-DETAIL'));
}

class _ProfileMarker extends StatelessWidget {
  const _ProfileMarker();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('PROFILE'));
}

({GoRouter router, ProviderContainer container}) _app({
  required List<Race> races,
  Widget? home,
  FirstUseStore? store,
  FirstRaceGuideStep guideStep = FirstRaceGuideStep.idle,
  bool realVerifier = false,
}) {
  final container = ProviderContainer(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_FakeRaceRepo(races)),
      firstUseStoreProvider.overrideWithValue(
        store ?? (FirstUseStore.memory()..markCameraPrimerSeen()),
      ),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
  );
  container.read(firstRaceGuideProvider.notifier).state = guideStep;
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => home ?? const MoveScreen()),
      GoRoute(
        path: '/race/:id/proof',
        builder: (_, _) => const _ChooserMarker(),
      ),
      GoRoute(
        path: '/race/:id/proof/ai-motion',
        builder: (_, state) => realVerifier
            ? AiMotionProofScreen(raceId: state.pathParameters['id']!)
            : const _VerifierMarker(),
      ),
      GoRoute(path: '/race/:id', builder: (_, _) => const _RaceDetailMarker()),
      GoRoute(path: '/profile', builder: (_, _) => const _ProfileMarker()),
    ],
  );
  return (router: router, container: container);
}

/// The topmost match — what the user actually sees. `uri.path` reads the
/// base location and ignores pushed routes.
String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canonical verifier entry', () {
    testWidgets(
      'A: Verify hero CTA opens the fullscreen verifier directly — the '
      'proof chooser never renders',
      (tester) async {
        final built = _app(races: [_movementRace()]);
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('verify-hero-cta')), findsOneWidget);
        expect(find.text('PROOF-CHOOSER'), findsNothing);

        await tester.tap(find.byKey(const Key('verify-hero-cta')));
        await tester.pumpAndSettle();

        expect(_path(built.router), '/race/race-move/proof/ai-motion');
        expect(find.text('CANONICAL-VERIFIER'), findsOneWidget);
        expect(find.text('PROOF-CHOOSER'), findsNothing);
      },
    );

    testWidgets('B: Ready Next row opens the verifier directly', (
      tester,
    ) async {
      final built = _app(
        races: [_movementRace(), _movementRace(id: 'race-two', title: 'Squats')],
      );
      addTearDown(built.container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: built.container,
          child: MaterialApp.router(routerConfig: built.router),
        ),
      );
      await tester.pumpAndSettle();

      // The second Ready race is a 'Ready next' row.
      final row = find.text('Squats');
      expect(row, findsWidgets);
      await tester.tap(row.first);
      await tester.pumpAndSettle();

      expect(_path(built.router), '/race/race-two/proof/ai-motion');
      expect(find.text('CANONICAL-VERIFIER'), findsOneWidget);
      expect(find.text('PROOF-CHOOSER'), findsNothing);
    });

    testWidgets(
      'non-camera race still goes to the proof chooser, not the verifier',
      (tester) async {
        final built = _app(races: [_manualRace()]);
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('verify-hero-cta')));
        await tester.pumpAndSettle();

        expect(_path(built.router), '/race/race-manual/proof');
        expect(find.text('PROOF-CHOOSER'), findsOneWidget);
        expect(find.text('CANONICAL-VERIFIER'), findsNothing);
      },
    );

    testWidgets(
      'G: cancel returns to origin; restarting re-enters the verifier directly',
      (tester) async {
        final built = _app(
          races: [_movementRace()],
          home: const SubmitProofScreen(raceId: 'race-move'),
        );
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pumpAndSettle();

        // The proof chooser renders for direct /proof entry (deep link or
        // fallback); Begin is the real control that opens the verifier.
        await tester.tap(find.text('Begin'));
        await tester.pumpAndSettle();
        expect(_path(built.router), '/race/race-move/proof/ai-motion');

        // Cancel → back to the chooser — the origin route in this harness.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(_path(built.router), '/home');
        expect(find.text('Begin'), findsOneWidget);

        // Restart → the canonical verifier again, not another screen.
        await tester.tap(find.text('Begin'));
        await tester.pumpAndSettle();
        expect(_path(built.router), '/race/race-move/proof/ai-motion');
      },
    );
  });

  group('first-race guide', () {
    testWidgets(
      'D: the guide survives entry into the verifier — no early completion',
      (tester) async {
        final built = _app(
          races: [_movementRace()],
          home: const SubmitProofScreen(raceId: 'race-move'),
          guideStep: FirstRaceGuideStep.verifySetup,
        );
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        // The coach keeps a looping pulse alive — timed pumps, not settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        // Coach is up on the real Begin control.
        expect(find.text('Get in position.'), findsOneWidget);

        await tester.tap(find.text('Begin'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        expect(_path(built.router), '/race/race-move/proof/ai-motion');
        // The guide must NOT complete at entry — it completes at the
        // Profile reward moment after a real proof.
        expect(
          built.container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.verifySetup,
        );
      },
    );

    testWidgets(
      'H: armed guide turns board-moved continue into the Profile reward step',
      (tester) async {
        final built = _app(
          races: [_movementRace()],
          guideStep: FirstRaceGuideStep.profileReward,
          home: const BoardMovedScreen(
            raceId: 'race-move',
            args: BoardMovedArgs(
              raceId: 'race-move',
              raceName: 'Pushup Race',
              value: 15,
              unit: 'reps',
              status: 'verified',
              rankBefore: 2,
              rankAfter: 1,
              aiMotionProof: true,
            ),
          ),
        );
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        expect(find.text('See your progress'), findsOneWidget);
        await tester.tap(find.text('See your progress'));
        await tester.pumpAndSettle();

        expect(_path(built.router), '/profile');
      },
    );

    testWidgets(
      'I: normal post-proof route is unchanged outside the guide',
      (tester) async {
        final built = _app(
          races: [_movementRace()],
          home: const BoardMovedScreen(
            raceId: 'race-move',
            args: BoardMovedArgs(
              raceId: 'race-move',
              raceName: 'Pushup Race',
              value: 15,
              unit: 'reps',
              status: 'verified',
              rankBefore: 2,
              rankAfter: 1,
              aiMotionProof: true,
            ),
          ),
        );
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        // No guided CTA — the normal race return stays.
        expect(find.text('View race'), findsOneWidget);
        expect(find.text('See your progress'), findsNothing);
        await tester.tap(find.text('View race'));
        await tester.pumpAndSettle();
        expect(_path(built.router), '/race/race-move');
      },
    );

    testWidgets(
      'board-moved retry re-enters the verifier directly for camera proofs',
      (tester) async {
        final built = _app(
          races: [_movementRace()],
          home: const BoardMovedScreen(
            raceId: 'race-move',
            args: BoardMovedArgs(
              raceId: 'race-move',
              raceName: 'Pushup Race',
              value: 15,
              unit: 'reps',
              status: 'verified',
              rankBefore: 2,
              rankAfter: 1,
              aiMotionProof: true,
            ),
          ),
        );
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));

        await tester.tap(find.text('Record again'));
        await tester.pumpAndSettle();
        expect(_path(built.router), '/race/race-move/proof/ai-motion');
        expect(find.text('PROOF-CHOOSER'), findsNothing);
      },
    );

    testWidgets(
      'the profileReward coach is the only step that ends with a definite '
      'action label',
      (tester) async {
        // Coach-level check: the final step reads 'Got it' and dismissing it
        // completes the guide — the same affordance Skip always had.
        final key = GlobalKey();
        final container = ProviderContainer(
          overrides: [
            firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
            authControllerProvider.overrideWith(
              (ref) => AuthController(_FakeAuthRepo()),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.profileReward;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    Center(child: SizedBox(key: key, width: 80, height: 40)),
                    FirstRaceGuideCoach(
                      step: FirstRaceGuideStep.profileReward,
                      targetKey: key,
                      eyebrow: 'PROOF LANDED',
                      title: 'You’re on the board.',
                      body: 'Every verified effort moves your profile forward.',
                      actionLabel: 'Got it',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Got it'), findsOneWidget);
        await tester.tap(find.text('Got it'));
        await tester.pump();
        expect(
          container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.complete,
        );
      },
    );
  });

  group('lifecycle / restore', () {
    testWidgets(
      'E/F: the verifier surface is always the dark fullscreen shell — '
      'processing and error states never render the boxed white scaffold',
      (tester) async {
        final built = _app(races: [_movementRace()], realVerifier: true);
        addTearDown(built.container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: built.container,
            child: MaterialApp.router(routerConfig: built.router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('verify-hero-cta')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Whatever state the real verifier settles into (camera plugins are
        // unavailable in tests → an error/unsupported state), it must render
        // the dark immersive shell — the legacy white page used a
        // bottomNavigationBar action column; the status scaffold does not.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(scaffold.bottomNavigationBar, isNull);
        expect(scaffold.backgroundColor, isNot(equals(Colors.white)));

        // Background then resume — no crash, still not the old surface.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 300));

        final resumed = tester.widget<Scaffold>(
          find.byType(Scaffold).last,
        );
        expect(resumed.bottomNavigationBar, isNull);
        expect(_path(built.router), '/race/race-move/proof/ai-motion');
      },
    );
  });
}
