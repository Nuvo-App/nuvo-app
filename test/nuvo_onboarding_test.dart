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
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nuvo/features/notifications/application/push_service.dart';
import 'package:nuvo/features/onboarding/data/first_use_store.dart';
import 'package:nuvo/features/onboarding/presentation/notification_permission_screen.dart';
import 'package:nuvo/features/onboarding/presentation/nuvo_onboarding_screen.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';
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

/// A controller pre-seeded with a server payload, so the payoff page's
/// loaded path ('0 / 60 XP', live nextAchievement) is exercised without an
/// API. Only `state` is touched — presentation reads it like production.
/// Firebase-free push double — the permission screen asks it for the OS
/// status and fires its request only behind the CTA.
class _StubPushService extends PushService {
  _StubPushService(super.ref);

  int requestCount = 0;

  @override
  Future<AuthorizationStatus?> notificationAuthorizationStatus() async =>
      AuthorizationStatus.notDetermined;

  @override
  Future<bool> requestPermissionInContext() async {
    requestCount++;
    return true;
  }
}

class _SeededProgression extends ProgressionController {
  _SeededProgression(NuvoProgression progression)
    : super(
        ProgressionApi(),
        SecureTokenStore(),
        isPresentationDemo: () => false,
      ) {
    state = AsyncValue.data(progression);
  }
}

/// The canonical Level-2 capability and the fresh account's first goal —
/// mirrors the shipped definitions the payoff renders.
const _firstMoveBadge = NuvoBadge(
  unlockId: 'ach-first-move',
  type: 'achievement',
  key: 'first_move',
  name: 'First Move',
  description: 'Submit your first accepted progress.',
  requiredLevel: 0,
  unlocked: false,
  featured: false,
  category: 'racing',
  iconKey: 'arrow_forward',
  statKey: 'progresses_accepted',
  threshold: 1,
  progressValue: 0,
);

const _freshProgression = NuvoProgression(
  level: 1,
  totalXp: 0,
  currentLevelXp: 0,
  nextLevelXp: 60,
  progress: 0,
  xpToNext: 60,
  lastSeenLevel: 1,
  featuredSlots: 1,
  achievementsEarned: 0,
  achievementsTotal: 44,
  nextUnlock: NuvoUnlockRef(
    unlockId: 'cap-badge-slot-2',
    level: 2,
    type: 'capability',
    key: 'featured_slot',
    name: 'Second badge slot',
    description: 'Feature a second achievement on your profile.',
  ),
  nextAchievement: _firstMoveBadge,
);

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
  int maxTicks = 180,
}) async {
  for (var i = 0; i < maxTicks && finder.evaluate().isEmpty; i++) {
    await tester.pump(step);
  }
  expect(finder, findsOneWidget);
}

/// Waits until the current page's 'Keep going' is present AND persists —
/// during a page transition the outgoing page's footer label can still be in
/// the tree, so a bare find can latch a ghost.
Future<void> _waitForOwnCta(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await pumpUntilFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 900));
    if (find.text('Keep going').evaluate().isNotEmpty) return;
  }
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
  AuthRepository repo, {
  NuvoProgression? progression,
}) {
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => AuthController(repo)),
      // The story's finish now hands off to the notification permission
      // moment — a real route, a memory-backed store, and a push service
      // that reports notDetermined so the education page renders.
      firstUseStoreProvider.overrideWithValue(FirstUseStore.memory()),
      pushServiceProvider.overrideWith((ref) => _StubPushService(ref)),
      if (progression != null)
        progressionControllerProvider.overrideWith(
          (ref) => _SeededProgression(progression),
        ),
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
        path: '/onboarding/notifications',
        builder: (_, _) => const NotificationPermissionScreen(),
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
  bool dark = false,
  double textScale = 1.0,
  NuvoProgression? progression,
}) async {
  final built = _buildApp(repo, progression: progression);
  addTearDown(built.container.dispose);
  addTearDown(built.router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: built.container,
      child: MaterialApp.router(
        routerConfig: built.router,
        // Real theme pair so themeColors resolve like production — the
        // onboarding chrome is intentionally light-pinned, and this is how
        // we verify the badge surfaces stay consistent with it in dark mode.
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
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
/// `tmp/onboarding-NAME.png`. No-ops unless NUVO_ONBOARDING_CAPTURE is set —
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
    final built = await _pumpOnboarding(
      tester,
      repo: repo,
      progression: _freshProgression,
    );

    // Page 1 — Race anything (FlexiRace): real example titles cycle as text.
    await tapWhenFound(tester, find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Race anything.'));
    expect(find.text('FLEXIRACE'), findsOneWidget);
    // Examples cycle — wait a cycle for this one rather than sampling blind.
    await pumpUntilFound(tester, find.text('First to 100 pushups'));
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

    // Page 4 — Level up: the canonical XP economy (+10 proof, then the
    // finish/win/PB line) rolls 50/60 into Level 2 and reveals the real
    // level-2 capability (Second badge slot — cap-badge-slot-2).
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Every race builds\nyour Nuvo.'));
    // Wait the storyboard out — the level roll + unlock card are the settle
    // state, not the entrance.
    await pumpUntilFound(tester, find.text('Second badge slot'));
    expect(find.text('Level up'), findsOneWidget);
    expect(find.text('AT LEVEL 2'), findsOneWidget);

    // Page 5 — Identity: real achievement definitions (featured set, the
    // First Move earn beat, Hat Trick as a 0/3 goal — a fresh user builds
    // wins, the explanation never implies they have any).
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(
      tester,
      findNuvoText('Make your name\nmean something.'),
    );
    await pumpUntilFound(tester, find.text('EARNED'));
    expect(find.text('First W'), findsOneWidget);
    expect(find.text('Five Deep'), findsOneWidget);
    expect(find.text('Personal Best'), findsOneWidget);
    expect(find.text('FIRST MOVE'), findsOneWidget);
    expect(find.text('Submit your first accepted progress.'), findsOneWidget);
    expect(find.text('EARNED'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('HAT TRICK'), findsOneWidget);
    expect(find.text('Win 3 races.'), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget);

    // Page 6 — Crew: social levels + one featured badge glyph each.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Better with\ncompetition.'));
    expect(find.text('Shresh'), findsOneWidget);
    expect(find.text('Lv. 14'), findsOneWidget);
    expect(find.text('Lv. 1'), findsOneWidget);
    // 3 crew glyphs + the keep-alive identity page's badge set.
    expect(find.byType(NuvoAchievementBadge), findsWidgets);

    // Page 7 — payoff: real account state (fresh user → Level 1, 0 XP),
    // the canonical first goal, personalized, and the only server write in
    // the whole flow.
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Akshay, you\'re ready.'));
    expect(find.text('LEVEL'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    // Loaded payload path — canonical threshold renders, no hardcoded 60.
    expect(find.text('0 / 60 XP'), findsOneWidget);
    // The canonical first goal is live on the payoff page — First Move is
    // also mounted (keep-alive) on the identity page, so ≥1, not exactly 1.
    expect(find.text('FIRST MOVE'), findsWidgets);
    expect(find.text('0 / 1'), findsWidgets);
    // Let the CTA reveal settle so the capture carries the real first step.
    await pumpUntilFound(tester, find.text('Start your first race'));
    await tester.pump(const Duration(milliseconds: 700));
    await captureOnboarding(tester, 'payoff-real-390');

    expect(repo.completionCalls, 0);
    await tapWhenFound(tester, find.text('Start your first race'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.completionCalls, 1);
    // The story hands off to the notification permission moment — the
    // education page is the next step in first-run, not /arena directly.
    expect(_path(built.router), '/onboarding/notifications');
    await tester.pump(const Duration(milliseconds: 600));
    // Maybe later resolves the step and lands in the app — and the OS
    // prompt is never fired for this path.
    await tapWhenFound(tester, find.text('Maybe later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('system back unwinds the story before leaving the route', (
    tester,
  ) async {
    _usePhone(tester);
    final built = await _pumpOnboarding(
      tester,
      repo: _ScriptedAuthRepo(_namedUser),
    );

    await tapWhenFound(tester, find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, findNuvoText('Race anything.'));
    await pumpUntilFound(tester, find.text('Keep going'));

    // iOS edge-swipe / Android system back → previous story page, and the
    // onboarding route stays on the stack.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_path(built.router), '/onboarding/nuvo');
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

      // Walk every mid page — each settles on ITS OWN CTA (the footer label
      // can ghost from the outgoing page, so require persistence) and on its
      // headline so captures land after the page's storyboard, not mid-it.
      const headlines = [
        'Race anything.',
        'Make your move.',
        'Climb the board.',
        'Every race builds\nyour Nuvo.',
        'Make your name\nmean something.',
        'Better with\ncompetition.',
      ];
      for (var page = 1; page <= 6; page++) {
        await tapWhenFound(
          tester,
          find.text(page == 1 ? 'Show me' : 'Keep going'),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await pumpUntilFound(tester, findNuvoText(headlines[page - 1]));
        if (page == 4) {
          // XP page — first beat: transition done (~480ms), storyboard still
          // in its settle window (<670ms) → LEVEL 1 · 0/60 XP.
          await tester.pump(const Duration(milliseconds: 550));
          await captureOnboarding(
            tester,
            'xp-initial-${size.width.toInt()}',
          );
        }
        await _waitForOwnCta(tester);
        await tester.pump(const Duration(milliseconds: 1200));
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

  // Worst-case composition: narrowest width with 1.4 accessibility text.
  // Pages may scroll instead of clipping — overflow is the failure.
  testWidgets('no overflow across the flow at 320×568, text scale 1.4', (
    tester,
  ) async {
    _usePhone(tester, const Size(320, 568));
    await _pumpOnboarding(
      tester,
      repo: _ScriptedAuthRepo(_namedUser),
      textScale: 1.4,
    );

    await pumpUntilFound(tester, find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 600));
    await captureOnboarding(tester, 'p0-320-ts140');
    expect(tester.takeException(), isNull);

    const headlines = [
      'Race anything.',
      'Make your move.',
      'Climb the board.',
      'Every race builds\nyour Nuvo.',
      'Make your name\nmean something.',
      'Better with\ncompetition.',
    ];
    for (var page = 1; page <= 6; page++) {
      await tapWhenFound(
        tester,
        find.text(page == 1 ? 'Show me' : 'Keep going'),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntilFound(tester, findNuvoText(headlines[page - 1]));
      await _waitForOwnCta(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      await captureOnboarding(tester, 'p$page-320-ts140');
      expect(
        tester.takeException(),
        isNull,
        reason: 'page $page overflowed at 320×568 text 1.4',
      );
    }

    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 600));
    await pumpUntilFound(tester, find.text('Start your first race'));
    await tester.pump(const Duration(milliseconds: 700));
    await captureOnboarding(tester, 'p7-320-ts140');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The XP/achievement lesson, captured mid-beat — the frames reviewers need
  // to see (award → economy line → level roll → unlock → earn → goals).
  // Under NUVO_ONBOARDING_CAPTURE this writes PNGs; without it the walk still
  // asserts the canonical strings exist at each beat.
  for (final size in const [Size(320, 568), Size(390, 844)]) {
    testWidgets(
      'progression beats at ${size.width.toInt()} — xp, level-up, unlock, earn',
      (tester) async {
        _usePhone(tester, size);
        await _pumpOnboarding(tester, repo: _ScriptedAuthRepo(_namedUser));
        final w = size.width.toInt();

        // Walk to page 4 (the level page).
        await tapWhenFound(tester, find.text('Show me'));
        for (var i = 0; i < 3; i++) {
          await tapWhenFound(tester, find.text('Keep going'));
          await tester.pump(const Duration(milliseconds: 600));
        }
        await pumpUntilFound(
          tester,
          findNuvoText('Every race builds\nyour Nuvo.'),
          step: const Duration(milliseconds: 100),
        );

        // Wait for the level roll + unlock card — the settled beats.
        await pumpUntilFound(tester, find.text('Second badge slot'));
        await tester.pump(
          const Duration(milliseconds: 700),
        ); // let the card fade fully in
        await captureOnboarding(tester, 'xp-unlock-$w');
        expect(find.text('Level up'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Page 5 — after full settle: earned First Move + Hat Trick goal.
        await tapWhenFound(tester, find.text('Keep going'));
        await tester.pump(const Duration(milliseconds: 600));
        await pumpUntilFound(
          tester,
          findNuvoText('Make your name\nmean something.'),
        );
        // Rows sit at Opacity 0 in the tree, so text-finds can't gate on
        // visibility — pump past the full 4.2s storyboard instead.
        await tester.pump(const Duration(milliseconds: 5000));
        expect(find.text('HAT TRICK'), findsOneWidget);
        expect(find.text('EARNED'), findsOneWidget);
        await captureOnboarding(tester, 'achievements-earned-$w');
        expect(find.text('HAT TRICK'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'dark mode — light-chrome onboarding stays coherent, no overflow',
    (tester) async {
      _usePhone(tester, const Size(390, 844));
      await _pumpOnboarding(
        tester,
        repo: _ScriptedAuthRepo(_namedUser),
        dark: true,
      );
      await tapWhenFound(tester, find.text('Show me'));
      await pumpUntilFound(tester, findNuvoText('Race anything.'));
      // Walk page-by-page, gating on each headline so ghost CTAs can't
      // short-circuit the count.
      for (final headline in [
        'Make your move.',
        'Climb the board.',
        'Every race builds\nyour Nuvo.',
        'Make your name\nmean something.',
      ]) {
        await tapWhenFound(tester, find.text('Keep going'));
        await tester.pump(const Duration(milliseconds: 600));
        await pumpUntilFound(tester, findNuvoText(headline));
      }
      // Identity page settled under dark theme — badge surfaces pinned to
      // the page's light chrome via the Theme override, no dark-on-light
      // panels, no overflow.
      await tester.pump(const Duration(milliseconds: 5000));
      expect(find.text('HAT TRICK'), findsOneWidget);
      expect(find.byType(NuvoAchievementBadge), findsWidgets);
      await captureOnboarding(tester, 'achievements-dark-390');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
