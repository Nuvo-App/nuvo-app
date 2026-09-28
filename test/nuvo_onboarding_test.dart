// Canonical first-use Nuvo onboarding coverage (docs/ONBOARDING_REDESIGN_MODEL
// — First-Run V2). Drives the REAL NuvoOnboardingScreen inside a minimal
// GoRouter with a scripted AuthRepository, so page readiness, personalization,
// the real Level 1 / 0 XP payoff, and the completeOnboarding → /arena handoff
// exercise production code end to end — the same technique as
// test/auth_post_auth_convergence_test.dart.
//
// Page capture for visual QA: run with
//   flutter test test/nuvo_onboarding_test.dart \
//     --dart-define=NUVO_ONBOARDING_CAPTURE=true
// to write tmp/onboarding-p<N>-<width>.png for every page at every size.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/nuvo_flip_text.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/welcome_opening_cinematic.dart';
import 'package:nuvo/features/onboarding/presentation/nuvo_onboarding_screen.dart';
import 'package:nuvo/features/races/presentation/widgets/rive_movement_preview.dart';

void _usePhone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
}

/// A freshly-set-up account: legal + identity + consent done, Nuvo story owed.
/// Exactly the state auth_gate's smart-resume sends to /onboarding/nuvo.
const _namedUser = AuthUser(
  id: 'u-named',
  email: 'akshay@example.com',
  onboardingComplete: false,
  hasMemberPass: true,
  termsAccepted: true,
  ageAttested: true,
  fullName: 'Akshay Sanjai',
  username: 'akshay',
  motionTrainingConsent: true,
);

/// Same state minus a usable name — Apple private-relay accounts can land
/// here; every personalized string must have a fallback.
const _namelessUser = AuthUser(
  id: 'u-nameless',
  email: 'relay@privaterelay.appleid.com',
  onboardingComplete: false,
  hasMemberPass: true,
  termsAccepted: true,
  ageAttested: true,
  username: 'racer',
  motionTrainingConsent: true,
);

class _ScriptedAuthRepo extends AuthRepository {
  _ScriptedAuthRepo(this.user) : super(AuthApi(), SecureTokenStore());

  final AuthUser user;
  int completionCalls = 0;

  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(user);

  @override
  Future<void> completeOnboarding() async => completionCalls++;

  // AuthController re-reads the account after graduating it — return the
  // post-write state instead of letting the call reach the real API.
  @override
  Future<AuthUser> getMe() async => user.copyWith(onboardingComplete: true);
}

/// Headlines render through NuvoFlipText (per-character cells) — find.text
/// can't see them. Match the widget itself; it stays in the tree in
/// reduced-motion mode too (its build() swaps cells for a plain Text child).
Finder findNuvoText(String t) =>
    find.byWidgetPredicate((w) => w is NuvoFlipText && w.text == t);

/// Each page's footer waits for that page's own settle-then-hold before the
/// CTA exists; fixed pump budgets rot whenever entrance timing changes.
/// Pump in small ticks until the finder matches (bounded, so a genuinely
/// missing CTA still fails fast).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 100),
  int maxTicks = 80,
}) async {
  for (var i = 0; i < maxTicks && finder.evaluate().isEmpty; i++) {
    await tester.pump(step);
  }
  expect(finder, findsOneWidget);
}

/// The CTA exists inside a growing AnimatedSize the moment it's found —
/// let the reveal finish so the tap lands on a settled button. A label can
/// briefly belong to the OUTGOING page mid-transition (the page index flips
/// partway through animateToPage); if it vanishes before the tap, re-wait
/// for the new page's own CTA instead of tapping a ghost.
Future<void> tapWhenFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    await pumpUntilFound(tester, finder);
    await tester.pump(const Duration(milliseconds: 500));
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder);
      return;
    }
  }
  await tester.tap(finder);
}

({GoRouter router, ProviderContainer container}) _buildApp(
  AuthRepository repo,
) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
    ],
  );
  final router = GoRouter(
    initialLocation: '/onboarding/nuvo',
    routes: [
      GoRoute(
        path: '/onboarding/nuvo',
        builder: (_, _) => const NuvoOnboardingScreen(),
      ),
      GoRoute(
        path: '/arena',
        builder: (_, _) => const Scaffold(body: Text('arena-destination')),
      ),
      GoRoute(
        path: '/compete',
        builder: (_, _) => const Scaffold(body: Text('compete-destination')),
      ),
    ],
  );
  return (router: router, container: container);
}

Future<({GoRouter router, ProviderContainer container})> _pumpOnboarding(
  WidgetTester tester, {
  required AuthRepository repo,
  bool disableAnimations = false,
}) async {
  final built = _buildApp(repo);
  addTearDown(built.container.dispose);
  addTearDown(built.router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(
        routerConfig: built.router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  return built;
}

String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

/// Snapshots the screen's RepaintBoundary('onboarding-capture') to
/// tmp/onboarding-<name>.png. No-ops unless NUVO_ONBOARDING_CAPTURE is set —
/// capture passes need real font rasterization, which the font-loading
/// setUp below provides only in capture mode.
Future<void> captureOnboarding(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('NUVO_ONBOARDING_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('onboarding-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/onboarding-$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  ByteData? fontBytes;
  ByteData? captureManifest;
  setUp(() {
    if (captureManifest == null) return;
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') return captureManifest;
      if (key.startsWith('test/fonts/Manrope-')) return fontBytes;
      return messenger.delegate.send('flutter/assets', message);
    });
  });
  setUpAll(() async {
    if (!const bool.fromEnvironment('NUVO_ONBOARDING_CAPTURE')) return;
    final bytes = ByteData.sublistView(
      await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
    );
    fontBytes = bytes;
    final manifest =
        const StandardMessageCodec().decodeMessage(
              await rootBundle.load('AssetManifest.bin'),
            )
            as Map<Object?, Object?>;
    for (final variant in [
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      final key = 'test/fonts/Manrope-$variant.ttf';
      manifest[key] = [
        {'asset': key},
      ];
    }
    captureManifest = const StandardMessageCodec().encodeMessage(manifest);
    for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
      final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'page 0 opens on the real cinematic, personalizes, and never '
    'auto-advances',
    (tester) async {
      _usePhone(tester);
      await _pumpOnboarding(tester, repo: _ScriptedAuthRepo(_namedUser));

      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
      expect(find.text('Show me'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      await pumpUntilFound(tester, findNuvoText('Ready, Akshay?'));
      expect(findNuvoText('Make real life a race.'), findsOneWidget);
      await pumpUntilFound(tester, find.text('Show me'));

      // Waiting well past the full composition never turns the page —
      // only an explicit CTA advances.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Show me'), findsOneWidget);
      expect(findNuvoText('Race anything.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nameless accounts get fallbacks — onboarding never stalls on identity',
    (tester) async {
      _usePhone(tester);
      await _pumpOnboarding(tester, repo: _ScriptedAuthRepo(_namelessUser));

      await pumpUntilFound(tester, findNuvoText('Ready?'));
      await pumpUntilFound(tester, find.text('Show me'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('walks all eight pages, then graduates into Arena', (
    tester,
  ) async {
    _usePhone(tester);
    final repo = _ScriptedAuthRepo(_namedUser);
    final built = await _pumpOnboarding(tester, repo: repo);

    // Page 1 — Race anything (FlexiRace): real example titles cycle as text.
    await tapWhenFound(tester, find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Race anything.'));
    expect(find.text('FLEXIRACE'), findsOneWidget);
    expect(find.text('First to 100 pushups'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);

    // Page 2 — Make your move: the real jumping-jack Rive preview plus the
    // proof-acceptance counter.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Make your move.'));
    expect(find.byType(RiveJumpingJackPreview), findsOneWidget);

    // Page 3 — Climb the board: the overtake story with real names.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Climb the board.'));
    expect(find.text('Noah'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);

    // Page 4 — Level up: XP counting and the level badge build.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Every race builds\nyour Nuvo.'));

    // Page 5 — Identity: real achievement names from the badge system.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(
      tester,
      findNuvoText('Make your name\nmean something.'),
    );
    expect(find.text('First W'), findsOneWidget);
    expect(find.text('Personal Best'), findsOneWidget);

    // Page 6 — Crew: social levels against real names.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Better with\ncompetition.'));
    expect(find.text('Shresh'), findsOneWidget);

    // Page 7 — payoff: real account state (fresh user → Level 1, 0 XP),
    // personalized, and the only server write in the whole flow.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Akshay, you\'re ready.'));
    expect(find.text('LEVEL'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('0 XP'), findsOneWidget);

    expect(repo.completionCalls, 0);
    await tapWhenFound(tester, find.text('Start your first race'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.completionCalls, 1);
    expect(_path(built.router), '/arena');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion reaches the CTA quickly on every page kind', (
    tester,
  ) async {
    _usePhone(tester);
    await _pumpOnboarding(
      tester,
      repo: _ScriptedAuthRepo(_namedUser),
      disableAnimations: true,
    );

    // The cinematic snaps to its finished state and the pre-CTA hold
    // shortens — still a beat, never zero, never blocked.
    await pumpUntilFound(tester, find.text('Show me'), maxTicks: 40);
    expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
    expect(findNuvoText('Ready, Akshay?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back returns to the previous page without replaying it', (
    tester,
  ) async {
    _usePhone(tester);
    await _pumpOnboarding(tester, repo: _ScriptedAuthRepo(_namedUser));

    await tapWhenFound(tester, find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Race anything.'));
    await pumpUntilFound(tester, find.text('Keep going'));

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Page 0 stays mounted (keep-alive) and its CTA is still ready — no
    // re-entrance, no replay.
    expect(findNuvoText('Ready, Akshay?'), findsOneWidget);
    expect(find.text('Show me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
  ]) {
    testWidgets('no overflow across the flow at ${size.width}×${size.height}', (
      tester,
    ) async {
      _usePhone(tester, size);
      final repo = _ScriptedAuthRepo(_namedUser);
      await _pumpOnboarding(tester, repo: repo);

      await pumpUntilFound(tester, find.text('Show me'));
      await tester.pump(const Duration(milliseconds: 600));
      await captureOnboarding(tester, 'p0-${size.width.toInt()}');
      expect(tester.takeException(), isNull);

      // Walk every mid page — each pumps until its own CTA exists so the
      // assertions are entrance-timing independent.
      for (var page = 1; page <= 6; page++) {
        await tapWhenFound(
          tester,
          find.text(page == 1 ? 'Show me' : 'Keep going'),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await pumpUntilFound(tester, find.text('Keep going'));
        await tester.pump(const Duration(milliseconds: 400));
        await captureOnboarding(tester, 'p$page-${size.width.toInt()}');
        expect(
          tester.takeException(),
          isNull,
          reason: 'page $page overflowed at ${size.width}×${size.height}',
        );
      }

      // Payoff page: CTA must sit inside the safe area even at 320×568.
      // Measure AFTER the AnimatedSize grow + CtaReveal settle — sampling
      // mid-reveal reads the child's translated position below its slot.
      await tapWhenFound(tester, find.text('Keep going'));
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntilFound(tester, find.text('Start your first race'));
      await tester.pump(const Duration(milliseconds: 700));
      await captureOnboarding(tester, 'p7-${size.width.toInt()}');
      expect(
        tester.getBottomLeft(find.text('Start your first race')).dy,
        lessThanOrEqualTo(size.height - 34),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
