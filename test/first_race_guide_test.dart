// Interactive first-race coach guide coverage:
//
//  - the spotlight coach renders against REAL controls: the highlighted
//    widget stays visible, bright, and tappable, and the production tap is
//    what advances the guide (no fake Next button, no timers)
//  - "Skip" is a small plain-text action, never a competing CTA
//  - guide state survives navigation and back-out without corrupting
//  - completion persists per account (install file), while the dedicated
//    testing account re-arms endlessly for QA
//  - the product intro (/welcome/intro) is install-scoped first-use: seen once
//    → signed-out launches go straight to auth
//  - eligibility never depends on the auth provider
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/auth_gate.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/onboarding/presentation/first_use_guide.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/presentation/motion_catalog_provider.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

const _publicUser = AuthUser(
  id: 'u-public',
  email: 'member@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

const _internalUser = AuthUser(
  id: 'u-internal',
  email: 'akshay@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

const _testingUser = AuthUser(
  id: 'u-testing',
  email: 'testing@getnuvo.net',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
);

const _demoFlagUser = AuthUser(
  id: 'u-demo',
  email: 'demo@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  isDemo: true,
);

class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo({required this.user})
    : super(AuthApi(), SecureTokenStore());

  final AuthUser user;
  RestoreResult? restoreResult;

  @override
  Future<RestoreResult> restoreSession() async =>
      restoreResult ?? const RestoreNoSession();

  @override
  Future<AuthUser> verifyEmailCode(String email, String code) async => user;

  @override
  Future<AuthUser> signInWithGoogle(String idToken) async => user;

  @override
  Future<AuthUser> signInWithApple(
    String idToken, {
    String? fullName,
  }) async =>
      user;

  @override
  Future<AuthUser> signInReviewer(String email, String password) async => user;

  @override
  Future<void> logout() async {}

  @override
  Future<void> clearSession() async {}
}

// ── Coach overlay harness ─────────────────────────────────────────────────────

/// Minimal real-control harness: a keyed button inside a scrollable scaffold,
/// with the coach overlaid — the same shape Compete uses.
class _CoachHarness extends ConsumerWidget {
  const _CoachHarness({
    required this.targetKey,
    required this.step,
    required this.onTargetTap,
    this.nextStep,
    this.targetAtTop = true,
    this.completesGuide = false,
    this.obstacleKey,
  });

  final GlobalKey targetKey;
  final FirstRaceGuideStep step;
  final VoidCallback onTargetTap;
  final FirstRaceGuideStep? nextStep;
  final bool targetAtTop;

  /// Mirrors production wiring like SubmitProofScreen's Begin — the real
  /// tap is what completes the guide.
  final bool completesGuide;
  final GlobalKey? obstacleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(firstRaceGuideProvider);
    final target = Padding(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton(
        key: targetKey,
        onPressed: () {
          onTargetTap();
          if (completesGuide) completeFirstRaceGuide(ref);
          final next = nextStep;
          if (next != null) {
            ref.read(firstRaceGuideProvider.notifier).state = next;
          }
        },
        child: const Text('Start'),
      ),
    );
    // Column (not ListView): production guide targets live in eagerly-built
    // scrollables, so an off-screen target still has a RenderObject the coach
    // can measure before it calls ensureVisible.
    final obstacle = obstacleKey == null
        ? const SizedBox(height: 900)
        : Container(
            key: obstacleKey,
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: Colors.grey.shade300,
          );
    final screen = Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (targetAtTop) target else const SizedBox(height: 900),
            if (targetAtTop) obstacle else target,
            const SizedBox(height: 600),
          ],
        ),
      ),
    );
    if (current != step) return screen;
    return Stack(
      children: [
        screen,
        FirstRaceGuideCoach(
          step: step,
          targetKey: targetKey,
          avoidKeys: [?obstacleKey],
          eyebrow: 'FIRST MOVE',
          title: 'Start your first race.',
          body: 'Tap Start.',
        ),
      ],
    );
  }
}

Future<ProviderContainer> _pumpCoach(
  WidgetTester tester, {
  required GlobalKey targetKey,
  required FirstRaceGuideStep step,
  required VoidCallback onTargetTap,
  FirstRaceGuideStep? nextStep,
  bool targetAtTop = true,
  bool completesGuide = false,
  GlobalKey? obstacleKey,
  Size? viewport,
}) async {
  final container = ProviderContainer(
    overrides: [
      firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_ScriptedAuthRepo(user: _testingUser)),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(firstRaceGuideProvider.notifier).state = step;
  if (viewport != null) {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: _CoachHarness(
          targetKey: targetKey,
          step: step,
          onTargetTap: onTargetTap,
          nextStep: nextStep,
          targetAtTop: targetAtTop,
          completesGuide: completesGuide,
          obstacleKey: obstacleKey,
        ),
      ),
    ),
  );
  // The spotlight pulse is a repeating animation — pumpAndSettle would never
  // return. Bounded pumps cover post-frame measure + the ensureVisible sweep.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  return container;
}

// ── Router harness (mirrors the convergence test's approach) ─────────────────

class _Screen extends StatelessWidget {
  const _Screen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

({GoRouter router, ProviderContainer container}) _buildRouter({
  required AuthRepository repo,
  required String initialLocation,
  FirstUseStore? store,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
      firstUseStoreProvider.overrideWithValue(store ?? FirstUseStore.memory()),
    ],
  );
  final notifier = container.read(routerNotifierProvider);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const _Screen('splash')),
      GoRoute(
        path: '/welcome/intro',
        builder: (_, _) => const _Screen('intro'),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const _Screen('welcome')),
      GoRoute(path: '/arena', builder: (_, _) => const _Screen('arena')),
      GoRoute(path: '/compete', builder: (_, _) => const _Screen('compete')),
      GoRoute(path: '/profile', builder: (_, _) => const _Screen('profile')),
    ],
  );
  return (router: router, container: container);
}

Future<({GoRouter router, ProviderContainer container})> _pumpAt(
  WidgetTester tester, {
  required AuthRepository repo,
  required String location,
  FirstUseStore? store,
}) async {
  final built = _buildRouter(
    repo: repo,
    initialLocation: location,
    store: store,
  );
  addTearDown(built.container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(routerConfig: built.router),
    ),
  );
  await tester.pumpAndSettle();
  return built;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('coach presentation', () {
    testWidgets(
      'spotlight targets a real visible control that stays tappable and its '
      'production tap advances the guide',
      (tester) async {
        var taps = 0;
        final key = GlobalKey();
        final container = await _pumpCoach(
          tester,
          targetKey: key,
          step: FirstRaceGuideStep.competeStart,
          onTargetTap: () => taps++,
          nextStep: FirstRaceGuideStep.composerName,
        );

        // The real control is present and inside the coach's spotlight.
        final targetRect = tester.getRect(find.byKey(key));
        expect(targetRect.size, greaterThan(Size.zero));
        expect(find.text('Tap Start.'), findsOneWidget);

        // Tapping the REAL button performs the production action AND
        // advances the guide — the overlay never swallows the tap.
        await tester.tap(find.byKey(key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(taps, 1);
        expect(
          container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.composerName,
        );
      },
    );

    testWidgets('Skip is plain muted text — no filled Skip guide button', (
      tester,
    ) async {
      await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.competeStart,
        onTargetTap: () {},
      );
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Skip guide'), findsNothing);
      // The Skip affordance is a bare Text, not a button-styled control.
      final skip = tester.widget<Text>(find.text('Skip'));
      expect(skip.style?.color, isNot(equals(Colors.white)));
    });

    testWidgets('Skip dismisses the guide and stays put', (tester) async {
      var taps = 0;
      final container = await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.competeStart,
        onTargetTap: () => taps++,
      );
      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.complete,
      );
      expect(find.text('FIRST MOVE'), findsNothing);
      expect(taps, 0); // skipping never performs the highlighted action
    });

    testWidgets('the bubble never covers its target', (tester) async {
      for (final atTop in [true, false]) {
        final key = GlobalKey();
        await _pumpCoach(
          tester,
          targetKey: key,
          step: FirstRaceGuideStep.competeStart,
          onTargetTap: () {},
          targetAtTop: atTop,
        );
        final target = tester.getRect(find.byKey(key));
        final bubble = tester.getRect(find.text('Tap Start.'));
        expect(
          bubble.overlaps(target.inflate(8)),
          isFalse,
          reason: 'atTop=$atTop',
        );
      }
    });

    testWidgets('waiting never advances the guide — no timers', (
      tester,
    ) async {
      final container = await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.competeStart,
        onTargetTap: () {},
      );
      // Sit on the step far longer than any animation could explain.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.competeStart,
      );
    });

    testWidgets('guide state survives a screen swap and retargets', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
          authControllerProvider.overrideWith(
            (ref) => AuthController(_ScriptedAuthRepo(user: _testingUser)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.competeStart;

      final keyA = GlobalKey();
      final keyB = GlobalKey();
      var onSecondScreen = false;
      late void Function(void Function()) rebuild;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return _CoachHarness(
                  targetKey: onSecondScreen ? keyB : keyA,
                  step: onSecondScreen
                      ? FirstRaceGuideStep.composerGoal
                      : FirstRaceGuideStep.competeStart,
                  onTargetTap: () {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(keyA), findsOneWidget);

      // "Navigate": the guide step moves on and the coach mounts against the
      // next screen's real control — state is not reset by the swap.
      container.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.composerGoal;
      rebuild(() => onSecondScreen = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(keyB), findsOneWidget);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerGoal,
      );
    });

    testWidgets('no overflow on any supported viewport', (tester) async {
      for (final size in [
        const Size(320, 568),
        const Size(375, 667),
        const Size(390, 844),
        const Size(430, 932),
      ]) {
        for (final atTop in [true, false]) {
          await _pumpCoach(
            tester,
            targetKey: GlobalKey(),
            step: FirstRaceGuideStep.competeStart,
            onTargetTap: () {},
            targetAtTop: atTop,
            viewport: size,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$size atTop=$atTop',
          );
        }
      }
    });
  });

  group('eligibility', () {
    test('guide eligibility is a demo-account property, provider-agnostic', () {
      // guideFirstRace is computed from the resolved account — identical for
      // every sign-in channel and for restore.
      expect(
        const AuthState(
          status: AuthStatus.authenticated,
          user: _testingUser,
        ).guideFirstRace,
        isTrue,
      );
      expect(
        const AuthState(
          status: AuthStatus.authenticated,
          user: _demoFlagUser,
        ).guideFirstRace,
        isTrue,
      );
      // Internal ≠ testing: a plain @getnuvo.net account is not the endless
      // QA identity.
      expect(
        const AuthState(
          status: AuthStatus.authenticated,
          user: _internalUser,
        ).guideFirstRace,
        isFalse,
      );
      expect(
        const AuthState(
          status: AuthStatus.authenticated,
          user: _publicUser,
        ).guideFirstRace,
        isFalse,
      );
      expect(
        const AuthState(status: AuthStatus.unauthenticated).guideFirstRace,
        isFalse,
      );
    });

    test('testing identity is exact — lookalikes do not qualify', () {
      expect(isNuvoStoreDemoEmail('testing@getnuvo.net'), isTrue);
      expect(isNuvoStoreDemoEmail(' TESTING@GETNUVO.NET '), isTrue);
      for (final email in [
        'akshay@getnuvo.net',
        'testing@getnuvo.net.evil.com',
        'testing@fakegetnuvo.net',
        'getnuvo.net@testing.com',
        'member@example.com',
      ]) {
        expect(isNuvoStoreDemoEmail(email), isFalse, reason: email);
      }
    });
  });

  group('first-use persistence', () {
    test('introSeen and guideDone persist across store instances', () async {
      final dir = await Directory.systemTemp.createTemp('nuvo_first_use');
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );

      final first = FirstUseStore();
      await first.ensureLoaded();
      expect(first.introSeen, isFalse);
      expect(first.isGuideDone('a@getnuvo.net'), isFalse);

      await first.markIntroSeen();
      await first.markGuideDone('A@GetNuvo.net'); // normalization check

      // "App restart": a brand-new store over the same directory.
      final second = FirstUseStore();
      await second.ensureLoaded();
      expect(second.introSeen, isTrue);
      expect(second.isGuideDone('a@getnuvo.net'), isTrue);
      // Account-scoped: another account on the same install is unaffected.
      expect(second.isGuideDone('b@getnuvo.net'), isFalse);
    });

    test('guideDone does not leak between accounts', () async {
      final store = FirstUseStore.memory();
      await store.markGuideDone('testing@getnuvo.net');
      expect(store.isGuideDone('testing@getnuvo.net'), isTrue);
      expect(store.isGuideDone('public@gmail.com'), isFalse);
      expect(store.isGuideDone('akshay@getnuvo.net'), isFalse);
    });

    test('corrupt persistence falls back to safe defaults', () async {
      final dir = await Directory.systemTemp.createTemp('nuvo_corrupt');
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );
      await File('${dir.path}/nuvo_first_use.json').writeAsString('not json{');

      final store = FirstUseStore();
      await store.ensureLoaded();
      expect(store.introSeen, isFalse);
      expect(store.isGuideDone('x@getnuvo.net'), isFalse);
    });
  });

  group('routing', () {
    testWidgets('demo account sign-in lands on Compete with guide armed', (
      tester,
    ) async {
      final store = FirstUseStore.memory();
      final repo = _ScriptedAuthRepo(user: _demoFlagUser);
      final built = await _pumpAt(
        tester,
        repo: repo,
        location: '/welcome',
        store: store,
      );
      await built.container
          .read(authControllerProvider.notifier)
          .signInWithGoogle('token');
      await tester.pumpAndSettle();
      expect(_path(built.router), '/compete');
      expect(
        built.container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.competeStart,
      );
    });

    testWidgets('demo account with persisted completion lands on /arena', (
      tester,
    ) async {
      final store = FirstUseStore.memory();
      await store.markGuideDone(_demoFlagUser.email);
      final repo = _ScriptedAuthRepo(user: _demoFlagUser);
      final built = await _pumpAt(
        tester,
        repo: repo,
        location: '/welcome',
        store: store,
      );
      await built.container
          .read(authControllerProvider.notifier)
          .signInWithApple('token');
      await tester.pumpAndSettle();
      expect(_path(built.router), '/arena');
      expect(
        built.container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.idle,
      );
    });

    testWidgets('testing account always re-arms for QA', (tester) async {
      final store = FirstUseStore.memory();
      await store.markGuideDone(_testingUser.email); // done is ignored for it
      final repo = _ScriptedAuthRepo(user: _testingUser);
      final built = await _pumpAt(
        tester,
        repo: repo,
        location: '/welcome',
        store: store,
      );
      await built.container
          .read(authControllerProvider.notifier)
          .verifyEmailCode(_testingUser.email, '123456');
      await tester.pumpAndSettle();
      expect(_path(built.router), '/compete');
      expect(
        built.container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.competeStart,
      );
    });

    testWidgets('public and internal non-demo accounts never get the guide', (
      tester,
    ) async {
      for (final user in [_publicUser, _internalUser]) {
        final repo = _ScriptedAuthRepo(user: user);
        final built = await _pumpAt(tester, repo: repo, location: '/welcome');
        await built.container
            .read(authControllerProvider.notifier)
            .signInWithGoogle('token');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/arena', reason: user.email);
        expect(
          built.container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.idle,
          reason: user.email,
        );
      }
    });

    testWidgets(
      'account switch: demo guide state cannot leak into the next account',
      (tester) async {
        final store = FirstUseStore.memory();
        final repo = _ScriptedAuthRepo(user: _demoFlagUser);
        final built = await _pumpAt(
          tester,
          repo: repo,
          location: '/welcome',
          store: store,
        );
        await built.container
            .read(authControllerProvider.notifier)
            .signInWithGoogle('token');
        await tester.pumpAndSettle();
        expect(
          built.container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.competeStart,
        );

        // Sign out — app.dart clears the in-session guide flags in
        // production; simulate the same reset here (the router harness does
        // not mount NuvoApp's listener).
        await built.container.read(authControllerProvider.notifier).logout();
        built.container.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.idle;
        await tester.pumpAndSettle();

        // A public account on the same install must not be bounced to
        // /compete by the previous account's guide.
        final repo2 = _ScriptedAuthRepo(user: _publicUser);
        final built2 = await _pumpAt(
          tester,
          repo: repo2,
          location: '/welcome',
          store: store,
        );
        await built2.container
            .read(authControllerProvider.notifier)
            .verifyEmailCode('member@example.com', '123456');
        await tester.pumpAndSettle();
        expect(_path(built2.router), '/arena');
        expect(
          built2.container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.idle,
        );
      },
    );

    testWidgets(
      'a guide-eligible account landing on /arena gets redirected to the '
      'coach once; a finished guide leaves /arena alone',
      (tester) async {
        final store = FirstUseStore.memory();
        final repo = _ScriptedAuthRepo(user: _demoFlagUser)
          ..restoreResult = const RestoreOk(_demoFlagUser);
        final built = await _pumpAt(
          tester,
          repo: repo,
          location: '/arena',
          store: store,
        );
        await tester.pumpAndSettle();
        // Restore arms eligibility → the /arena landing redirects to Compete.
        expect(_path(built.router), '/compete');
        expect(
          built.container.read(firstRaceGuideProvider),
          FirstRaceGuideStep.competeStart,
        );

        // Finishing the guide frees /arena.
        built.container.read(firstRaceGuideProvider.notifier).state =
            FirstRaceGuideStep.complete;
        built.router.go('/arena');
        await tester.pumpAndSettle();
        expect(_path(built.router), '/arena');
      },
    );
  });

  group('composerCoachSpec — input → continue substeps', () {
    test('name: field until a name exists, then the real CTA', () {
      var spec = composerCoachSpec(ComposerGuidePage.name, inputReady: false)!;
      expect(spec.targetKey, FirstRaceGuideKeys.composerName);
      expect(spec.eyebrow, 'NAME IT');

      spec = composerCoachSpec(ComposerGuidePage.name, inputReady: true)!;
      expect(spec.targetKey, FirstRaceGuideKeys.composerNameCta);
      expect(spec.body, 'Tap Choose activity.');
    });

    test('activity: selection until picked, then continue CTA', () {
      var spec = composerCoachSpec(
        ComposerGuidePage.activity,
        inputReady: false,
      )!;
      expect(spec.targetKey, FirstRaceGuideKeys.composerActivity);
      expect(spec.eyebrow, 'PICK THE MOVE');

      spec = composerCoachSpec(ComposerGuidePage.activity, inputReady: true)!;
      expect(spec.targetKey, FirstRaceGuideKeys.composerActivityCta);
      expect(spec.body, 'Tap Set the finish line.');

      // Custom (Teach Nuvo) movement — the CTA says Continue to training.
      spec = composerCoachSpec(
        ComposerGuidePage.activity,
        inputReady: true,
        teachMode: true,
      )!;
      expect(spec.body, 'Tap Continue to training.');
    });

    test('goal, racers, review follow the same input → CTA pattern', () {
      expect(
        composerCoachSpec(ComposerGuidePage.goal, inputReady: true)!.targetKey,
        FirstRaceGuideKeys.composerGoalCta,
      );
      expect(
        composerCoachSpec(ComposerGuidePage.goal, inputReady: true)!.body,
        'Tap Invite racers.',
      );
      expect(
        composerCoachSpec(ComposerGuidePage.racers, inputReady: true)!.body,
        'Tap Review race.',
      );
      final review = composerCoachSpec(
        ComposerGuidePage.review,
        inputReady: false,
      )!;
      expect(review.targetKey, FirstRaceGuideKeys.composerReview);
      expect(review.body, 'Tap Start race.');
    });

    test('train is self-guided — no coach', () {
      expect(
        composerCoachSpec(ComposerGuidePage.train, inputReady: true),
        isNull,
      );
    });
  });

  group('coach positioning', () {
    testWidgets('bubble clears a declared obstacle below the target', (
      tester,
    ) async {
      final obstacle = GlobalKey();
      await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.competeStart,
        onTargetTap: () {},
        obstacleKey: obstacle,
      );
      final obstacleRect = tester.getRect(find.byKey(obstacle));
      // The bubble's copy sits fully below the obstacle — it never parks on
      // the featured card's title.
      final bubbleTop = tester.getTopLeft(find.text('Start your first race.'));
      expect(bubbleTop.dy, greaterThan(obstacleRect.bottom));
    });

    testWidgets('bubble never slides under the keyboard', (tester) async {
      await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.composerName,
        onTargetTap: () {},
        targetAtTop: false,
      );
      // Open a ~45%-height keyboard and re-layout.
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final bubble = tester.getRect(find.text('Start your first race.'));
      expect(bubble.bottom, lessThanOrEqualTo(800 - 360 - 4));
      addTearDown(() => tester.view.resetViewInsets());
    });

    testWidgets('caret edge faces the target', (tester) async {
      // Target at top → bubble below → caret on the bubble's top edge.
      await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.competeStart,
        onTargetTap: () {},
      );
      final caret = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size(14, 10),
        ),
      );
      expect(caret.size, const Size(14, 10));
      final caretRect = tester.getRect(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.size == const Size(14, 10),
      ));
      final bubble = tester.getRect(find.text('Start your first race.'));
      expect(caretRect.bottom, lessThanOrEqualTo(bubble.top + 20));
    });
  });

  group('verify setup step', () {
    testWidgets('Begin is the final coached action and completes the guide', (
      tester,
    ) async {
      var taps = 0;
      final container = await _pumpCoach(
        tester,
        targetKey: GlobalKey(),
        step: FirstRaceGuideStep.verifySetup,
        onTargetTap: () => taps++,
        completesGuide: true,
        targetAtTop: false,
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(taps, 1);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.complete,
      );
    });
  });

  group('real composer walkthrough', () {
    Future<ProviderContainer> pumpComposer(WidgetTester tester) async {
      // Phone-sized viewport — the default 800×600 window lets bottom bars
      // cover scrollable rows and misroutes taps.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final container = ProviderContainer(
        overrides: [
          firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
          authControllerProvider.overrideWith(
            (ref) => AuthController(_ScriptedAuthRepo(user: _testingUser)),
          ),
          motionCatalogProvider.overrideWith(
            (ref) async => MotionCatalogSnapshot.bundled(),
          ),
          raceControllerProvider.overrideWith(
            (ref) => RaceController(
              ref.watch(raceRepositoryProvider),
              isPresentationDemo: () => true,
              presentationUserId: () => 'u-testing',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(firstRaceGuideProvider.notifier).state =
          FirstRaceGuideStep.composerName;
      final router = GoRouter(
        initialLocation: '/races/new',
        routes: [
          GoRoute(
            path: '/races/new',
            builder: (_, _) => const RaceComposerScreen(),
          ),
          GoRoute(path: '/compete', builder: (_, _) => const _Screen('c')),
          GoRoute(path: '/races/teach', builder: (_, _) => const _Screen('t')),
          GoRoute(
            path: '/race/:id',
            builder: (_, _) => const _Screen('detail'),
          ),
          GoRoute(
            path: '/race/:id/invite',
            builder: (_, _) => const _Screen('invite'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Bounded pumps — the coach pulse never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      return container;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
    }

    testWidgets('input → continue-CTA substeps across every page', (
      tester,
    ) async {
      final container = await pumpComposer(tester);

      // NAME — input substep on the real field.
      expect(find.text('NAME IT'), findsOneWidget);
      expect(find.text('Give your race a name.'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      // Typing satisfies the input, but the coach stays on the field while
      // the keyboard is up — it only retargets once the user is done typing.
      await tester.enterText(find.byType(TextField).first, 'Morning Mile');
      await settle(tester);
      expect(find.text('NAME IT'), findsOneWidget);
      expect(find.text('Pick the activity.'), findsNothing);

      // Dismiss the keyboard → coach retargets the real CTA. Route does NOT
      // move on input alone.
      WidgetsBinding.instance.focusManager.primaryFocus?.unfocus();
      await settle(tester);
      expect(find.text('Pick the activity.'), findsOneWidget);
      expect(find.text('Tap Choose activity.'), findsOneWidget);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerName,
      );

      // The real CTA drives the page change.
      await tester.tap(find.text('Choose activity'));
      await settle(tester);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerActivity,
      );
      expect(find.text('PICK THE MOVE'), findsOneWidget);

      // Pick a real movement — coach moves to the continue CTA.
      await tester.ensureVisible(find.text('Pushups').first);
      await tester.pump();
      await tester.tap(find.text('Pushups').first);
      await settle(tester);
      expect(find.text('Set the finish line.'), findsOneWidget);
      expect(find.text('Tap Set the finish line.'), findsOneWidget);

      await tester.tap(find.text('Set the finish line'));
      await settle(tester);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerGoal,
      );
      expect(find.text('SET THE FINISH'), findsOneWidget);

      // Change the goal — coach retargets Invite racers.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await settle(tester);
      expect(find.text('Bring in your crew.'), findsOneWidget);
      expect(find.text('Tap Invite racers.'), findsOneWidget);

      await tester.tap(find.text('Invite racers'));
      await settle(tester);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerRacers,
      );
      expect(find.text('BRING YOUR CREW'), findsOneWidget);

      // Choose solo — coach retargets Review race.
      await tester.tap(find.text('Start solo'));
      await settle(tester);
      expect(find.text('Review your race.'), findsOneWidget);
      expect(find.text('Tap Review race.'), findsOneWidget);

      await tester.tap(find.text('Review race'));
      await settle(tester);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.composerReview,
      );
      expect(find.text('START THE RACE'), findsOneWidget);

      // The real Start race button creates the race and arms raceDetail.
      await tester.tap(find.text('Start race'));
      await settle(tester);
      expect(
        container.read(firstRaceGuideProvider),
        FirstRaceGuideStep.raceDetail,
      );
      // Unmount the tree and advance the fake clock past the demo-race
      // expiry timer (10 min in RaceController._addPresentationRace).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 11));
      await tester.pump();
    });

    testWidgets('back navigation re-derives the correct substep', (
      tester,
    ) async {
      await pumpComposer(tester);

      await tester.enterText(find.byType(TextField).first, 'Morning Mile');
      await settle(tester);
      await tester.tap(find.text('Choose activity'));
      await settle(tester);
      await tester.ensureVisible(find.text('Pushups').first);
      await tester.pump();
      await tester.tap(find.text('Pushups').first);
      await settle(tester);
      await tester.tap(find.text('Set the finish line'));
      await settle(tester);
      expect(find.text('SET THE FINISH'), findsOneWidget);

      // Back → Activity. The movement is still picked, so the coach points
      // at the continue CTA — not the input — without re-asking.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await settle(tester);
      expect(find.text('Set the finish line.'), findsOneWidget);
      expect(find.text('PICK THE MOVE'), findsNothing);

      // Back → Name. The name is still valid → coach targets the CTA again.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
      await settle(tester);
      expect(find.text('Pick the activity.'), findsOneWidget);
      expect(find.text('NAME IT'), findsNothing);
      // Entered values survive — the field still holds the typed name.
      expect(find.text('Morning Mile'), findsOneWidget);
      // Unmount the tree and advance the fake clock — fires/cancels
      // flutter_animate's deferred mount timers.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
