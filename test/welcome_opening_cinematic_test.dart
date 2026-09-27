import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:nuvo/app/router.dart';
import 'package:nuvo/core/widgets/nuvo_flip_text.dart';
import 'package:nuvo/features/auth/presentation/welcome_auth_screen.dart';
import 'package:nuvo/features/auth/presentation/email_start_screen.dart';
import 'package:nuvo/features/auth/presentation/welcome_onboarding_state.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/auth/presentation/welcome_opening_cinematic.dart';
import 'package:nuvo/features/auth/presentation/welcome_race_builder_screen.dart';
import 'package:nuvo/features/races/presentation/widgets/rive_movement_preview.dart';
import 'package:nuvo/features/splash/presentation/splash_screen.dart';

void _usePhone(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
}

Widget _cinematicApp({
  required VoidCallback onComplete,
  bool disableAnimations = false,
  Key? boundaryKey,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        textScaler: const TextScaler.linear(1.3),
      ),
      child: child!,
    ),
    home: RepaintBoundary(
      key: boundaryKey,
      child: Scaffold(
        backgroundColor: NuvoColors.page,
        body: SafeArea(child: WelcomeOpeningCinematic(onComplete: onComplete)),
      ),
    ),
  );
}

double _progress(WidgetTester tester) =>
    tester.widget<WelcomeOpeningPath>(find.byType(WelcomeOpeningPath)).progress;

Future<void> _expectBlankCanvas(WidgetTester tester, Key boundaryKey) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final pixels = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });
  expect(pixels, isNotNull);
  var nonBackgroundPixels = 0;
  for (var i = 0; i < pixels!.length; i += 4) {
    if (pixels[i] != 251 ||
        pixels[i + 1] != 252 ||
        pixels[i + 2] != 255 ||
        pixels[i + 3] != 255) {
      nonBackgroundPixels++;
    }
  }
  expect(nonBackgroundPixels, 0, reason: 'Opening starts on a blank page.');
}

class _PendingRestoreRepository extends AuthRepository {
  _PendingRestoreRepository(this.restored)
    : super(AuthApi(), SecureTokenStore());

  final Completer<RestoreResult> restored;
  int completionCalls = 0;

  @override
  Future<RestoreResult> restoreSession() => restored.future;

  @override
  Future<void> completeOnboarding() async {
    completionCalls++;
  }
}

Future<void> _captureOnboarding(WidgetTester tester, String name) async {
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


/// 'Welcome to Nuvo.' and friends render through NuvoFlipText (per-character
/// cells) — find.text can't see them. Match the NuvoFlipText widget itself;
/// it stays in the tree in reduced-motion mode too (its build() just swaps
/// the cells for a plain Text child).
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
  int maxTicks = 60,
}) async {
  for (var i = 0; i < maxTicks && finder.evaluate().isEmpty; i++) {
    await tester.pump(step);
  }
  expect(finder, findsOneWidget);
}

/// The CTA exists inside a growing AnimatedSize the moment it's found —
/// let the reveal finish so the tap lands on a settled button.
Future<void> tapWhenFound(WidgetTester tester, Finder finder) async {
  await pumpUntilFound(tester, finder);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(finder);
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

  group('Welcome opening cinematic', () {
    testWidgets('starts blank and exposes no onboarding chrome', (
      tester,
    ) async {
      _usePhone(tester);
      const boundaryKey = ValueKey('opening-canvas');
      await tester.pumpWidget(
        _cinematicApp(onComplete: () {}, boundaryKey: boundaryKey),
      );

      expect(_progress(tester), 0);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(NuvoPrimaryButton), findsNothing);
      expect(find.byType(PageView), findsNothing);
      await _expectBlankCanvas(tester, boundaryKey);

      // The 400ms pre-draw hold is deliberate — verify it survives most of
      // that window, not just an early frame.
      await tester.pump(const Duration(milliseconds: 390));
      await _expectBlankCanvas(tester, boundaryKey);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'draws through distinct phases and holds before completing at ~4.8s',
      (tester) async {
        _usePhone(tester);
        var completions = 0;
        await tester.pumpWidget(_cinematicApp(onComplete: () => completions++));

        // Before drawing: still inside the 0–400ms blank hold.
        await tester.pump(const Duration(milliseconds: 390));
        expect(_progress(tester), closeTo(390 / 4800, .0001));
        expect(completions, 0);

        // During drawing: partway through the 400–3400ms travel window.
        await tester.pump(const Duration(milliseconds: 10)); // -> 400ms
        await tester.pump(const Duration(milliseconds: 1500)); // -> 1900ms
        expect(_progress(tester), closeTo(1900 / 4800, .0001));
        expect(completions, 0);

        // Finish beginning: the path has just reached the destination and
        // the posts have started drawing (3400–3650ms).
        await tester.pump(const Duration(milliseconds: 1500)); // -> 3400ms
        expect(_progress(tester), closeTo(3400 / 4800, .0001));
        expect(completions, 0);

        // Finish complete: posts (done by 3650ms) and the overlapping blue
        // element (done by 3850ms) have both finished.
        await tester.pump(const Duration(milliseconds: 450)); // -> 3850ms
        expect(_progress(tester), closeTo(3850 / 4800, .0001));
        expect(completions, 0);

        // Hold: the finished composition stays visible, untouched, well
        // before the controller's own duration elapses.
        await tester.pump(const Duration(milliseconds: 949)); // -> 4799ms
        expect(
          completions,
          0,
          reason: 'The completed drawing needs its full hold.',
        );

        await tester.pump(const Duration(milliseconds: 1)); // -> 4800ms
        // AnimationController only reports `completed` once elapsed time is
        // strictly greater than duration, so nudge past the exact boundary.
        await tester.pump(const Duration(microseconds: 1));
        expect(_progress(tester), 1);
        expect(completions, 1);

        // onComplete exactly once: further time never fires it again.
        await tester.pump(const Duration(seconds: 1));
        expect(completions, 1);
      },
    );

    testWidgets('rebuilds and resume never replay or repeat completion', (
      tester,
    ) async {
      _usePhone(tester);
      var completions = 0;
      void complete() => completions++;
      await tester.pumpWidget(_cinematicApp(onComplete: complete));
      await tester.pump(const Duration(milliseconds: 1800));
      final beforeRebuild = _progress(tester);

      await tester.pumpWidget(_cinematicApp(onComplete: complete));
      expect(_progress(tester), greaterThanOrEqualTo(beforeRebuild));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_progress(tester), greaterThanOrEqualTo(beforeRebuild));

      await tester.pump(const Duration(milliseconds: 3000)); // -> 4800ms
      await tester.pump(const Duration(microseconds: 1));
      expect(completions, 1);
      await tester.pumpWidget(_cinematicApp(onComplete: complete));
      await tester.pump(const Duration(seconds: 4));
      expect(_progress(tester), 1);
      expect(completions, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion keeps a static finish for a real 400ms hold', (
      tester,
    ) async {
      _usePhone(tester);
      var completions = 0;
      await tester.pumpWidget(
        _cinematicApp(onComplete: () => completions++, disableAnimations: true),
      );
      expect(_progress(tester), 1);
      expect(completions, 0);

      await tester.pump(const Duration(milliseconds: 399));
      expect(_progress(tester), 1);
      expect(completions, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      expect(completions, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(completions, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposing during the drawing cancels completion and ticker', (
      tester,
    ) async {
      _usePhone(tester);
      var completions = 0;
      await tester.pumpWidget(_cinematicApp(onComplete: () => completions++));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      expect(completions, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(320, 568),
      Size(375, 667),
      Size(390, 844),
      Size(430, 932),
    ]) {
      testWidgets('canvas fits the safe area at ${size.width}×${size.height}', (
        tester,
      ) async {
        _usePhone(tester, size);
        await tester.pumpWidget(_cinematicApp(onComplete: () {}));
        for (final elapsed in [250, 900, 700, 250, 400]) {
          await tester.pump(Duration(milliseconds: elapsed));
          final canvasFinder = find.descendant(
            of: find.byType(WelcomeOpeningPath),
            matching: find.byType(CustomPaint),
          );
          expect(canvasFinder, findsOneWidget);
          final canvas = tester.getRect(canvasFinder);
          expect(canvas.width, greaterThan(0));
          expect(canvas.height, greaterThan(0));
          expect(canvas.left, greaterThanOrEqualTo(0));
          expect(canvas.right, lessThanOrEqualTo(size.width));
          expect(canvas.top, greaterThanOrEqualTo(44));
          expect(canvas.bottom, lessThanOrEqualTo(size.height - 34));
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  /// For NuvoFlipText the per-character Opacity cells are inside the widget —
  /// descend to the first rendered Text so its ancestor Opacity is the cell's.
  double opacityOf(WidgetTester tester, Finder textFinder) {
    final inner = find.descendant(of: textFinder, matching: find.byType(Text));
    final target = inner.evaluate().isNotEmpty ? inner.first : textFinder;
    return tester
        .widget<Opacity>(
          find.ancestor(of: target, matching: find.byType(Opacity)).first,
        )
        .opacity;
  }

  bool wordmarkVisible(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .any(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('nuvotext'),
      );

  GoRouter buildOnboardingRouter() => GoRouter(
    initialLocation: '/welcome/intro',
    routes: [
      GoRoute(
        path: '/welcome/intro',
        builder: (_, _) => const WelcomeRaceBuilderScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const Scaffold(body: Text('auth-destination')),
      ),
    ],
  );

  testWidgets(
    'cinematic completion keeps page 0 mounted and never auto-advances',
    (tester) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      // Screen 0 and Screen 1 are one composition from frame one: the
      // PageView (and page 0's text) already exist, just not yet visible —
      // there is no separate "cinematic slide" to crossfade away from.
      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('See how it works'), findsNothing);
      expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
      expect(opacityOf(tester, findNuvoText('Welcome to Nuvo.')), 0);
      expect(wordmarkVisible(tester), isFalse);

      // Run the cinematic out to completion (4800ms; AnimationController
      // only reports `completed` once elapsed is strictly greater than its
      // duration).
      await tester.pump(const Duration(milliseconds: 4800));
      await tester.pump(const Duration(microseconds: 1));

      // (1) Never navigates away when the cinematic finishes.
      expect(router.routeInformationProvider.value.uri.path, '/welcome/intro');
      // (2) The same composition holds — the cinematic widget is never
      // removed, and the first-screen text is on that same page.
      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
      // Its own short text entrance has only just started, not already
      // resolved — the root cause of the old "skip" bug.
      expect(find.text('See how it works'), findsNothing);
      expect(opacityOf(tester, findNuvoText('Welcome to Nuvo.')), lessThan(1));

      // Text settles (~1.1s) but the CTA must NOT appear yet — every page
      // holds its finished state for a deliberate beat first.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(microseconds: 1));
      expect(opacityOf(tester, findNuvoText('Welcome to Nuvo.')), 1);
      expect(
        find.text('See how it works'),
        findsNothing,
        reason:
            'The CTA must wait out the post-settle hold, not appear the '
            'instant the text finishes.',
      );

      // Only after the post-settle hold does the CTA slide up — the support
      // line reports settling first, so this is longer than the headline's
      // own entrance. Pump until it exists rather than betting on a budget.
      await pumpUntilFound(tester, find.text('See how it works'));
      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);

      // (4) Waiting well past 10s never changes the page on its own.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('See how it works'), findsOneWidget);
      expect(find.text('Keep going'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/welcome/intro');

      // (5) Only an explicit tap advances the page.
      await tapWhenFound(tester, find.text('See how it works'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(wordmarkVisible(tester), isFalse);
      // The cinematic is still the same mounted (kept-alive) instance —
      // PageView keeps page 0's state rather than disposing/rebuilding it.
      // It's offstage while page 1 is showing, so the finder must not skip
      // offstage elements here.
      expect(
        find.byType(WelcomeOpeningCinematic, skipOffstage: false),
        findsOneWidget,
      );

      // (6) Going back to page 0 never replays its entrance: the footer is
      // available immediately, with no re-fade from 0 opacity.
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
      expect(find.text('See how it works'), findsOneWidget);
      expect(opacityOf(tester, findNuvoText('Welcome to Nuvo.')), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reduced motion reaches the same ready state quickly without advancing',
    (tester) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);

      // Reduced motion shortens the cinematic hold to 400ms, the text
      // entrance snaps, and the pre-CTA hold shortens to 300ms — still
      // short, never zero, never skipped.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpUntilFound(tester, find.text('See how it works'));

      expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
      expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/welcome/intro');

      // Still page 0 after waiting — the cinematic completing never counts
      // as a page advance, reduced motion or not.
      await tester.pump(const Duration(seconds: 5));
      expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
      expect(find.text('Keep going'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('Leaderboard overtake', () {
    Future<void> pumpToLeaderboard(WidgetTester tester, GoRouter router) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump(const Duration(milliseconds: 4800));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1550));
      // A second, separate pump so the footer's AnimatedSize — started by
      // whatever setState happened inside the jump above — gets a real
      // subsequent tick to finish growing, rather than being sampled at
      // its own animation's t=0.
      await tapWhenFound(tester, find.text('See how it works'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('begins with You in third and ends with You first', (
      tester,
    ) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToLeaderboard(tester, router);

      // Initial order: Maya 1st, Priya 2nd, You 3rd (top to bottom) —
      // registering "you're third" is the point of the opening hold.
      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.text('Priya Nair'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('2 / 10'), findsOneWidget);
      final mayaY0 = tester.getTopLeft(find.text('Maya Chen')).dy;
      final priyaY0 = tester.getTopLeft(find.text('Priya Nair')).dy;
      final youY0 = tester.getTopLeft(find.text('You')).dy;
      expect(mayaY0, lessThan(priyaY0));
      expect(priyaY0, lessThan(youY0));

      // CTA must not exist yet — the whole story (settle, score change,
      // grab, carry, drop, hold) hasn't played.
      expect(find.text('Keep going'), findsNothing);

      // Run the ~2.23s overtake to completion.
      await tester.pump(const Duration(milliseconds: 3150));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 50));

      // Final order: You leads with an updated score; the others' own
      // scores never changed.
      expect(find.text('8 / 10'), findsOneWidget);
      expect(find.text('6 / 10'), findsOneWidget);
      expect(find.text('4 / 10'), findsOneWidget);
      double youY() => tester.getTopLeft(find.text('You')).dy;
      double mayaY() => tester.getTopLeft(find.text('Maya Chen')).dy;
      double priyaY() => tester.getTopLeft(find.text('Priya Nair')).dy;
      expect(youY(), lessThan(mayaY()));
      expect(mayaY(), lessThan(priyaY()));

      // CTA still must not appear immediately — the completed board holds
      // for ~1.5s first.
      expect(
        find.text('Keep going'),
        findsNothing,
        reason: 'The finished board must hold before the CTA appears.',
      );

      final settledYouY = youY();
      await tester.pump(const Duration(milliseconds: 1550));
      await pumpUntilFound(tester, find.text('Keep going'));
      // Stable: the hold never reshuffles the board.
      expect(youY(), settledYouY);
      expect(youY(), lessThan(mayaY()));
      expect(mayaY(), lessThan(priyaY()));

      // Further waiting never navigates on its own.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Keep going'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/welcome/intro');
      expect(find.text('Choose my direction'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'renders the carried card above the other rows without clipping',
      (tester) async {
        _usePhone(tester);
        final router = buildOnboardingRouter();
        addTearDown(router.dispose);
        await pumpToLeaderboard(tester, router);

        // Late in the carry (carry runs 1350–2500ms, drop starts at 2500ms):
        // "You" should already be well above both other rows' current
        // positions — a real overlap, not a same-slot swap.
        await tester.pump(const Duration(milliseconds: 2300));
        final youY = tester.getTopLeft(find.text('You')).dy;
        final mayaY = tester.getTopLeft(find.text('Maya Chen')).dy;
        final priyaY = tester.getTopLeft(find.text('Priya Nair')).dy;
        expect(
          youY,
          lessThan(mayaY),
          reason:
              'While carried, "You" must sit above row 1, not merely '
              'swap places at the same height as the other rows.',
        );
        expect(youY, lessThan(priyaY));

        // The Stack it's carried within must allow rendering outside its
        // own bounds, or the overlap above would be clipped away.
        final stacks = tester
            .widgetList<Stack>(
              find.ancestor(of: find.text('You'), matching: find.byType(Stack)),
            )
            .toList();
        expect(
          stacks.any((stack) => stack.clipBehavior == Clip.none),
          isTrue,
          reason:
              'The carried card must be able to render outside the '
              "stack's own bounds while it passes over the other rows.",
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  group('Movement/verification page', () {
    Future<void> pumpToMovementPage(
      WidgetTester tester,
      GoRouter router,
    ) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump(const Duration(milliseconds: 4800));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1550));
      await tapWhenFound(tester, find.text('See how it works'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Leaderboard: run the overtake + hold, then advance.
      await tester.pump(const Duration(milliseconds: 3150));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1550));
      await tapWhenFound(tester, find.text('Keep going'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets(
      'uses the real jumping-jack Rive preview and reaches Verified after 3 reps',
      (tester) async {
        _usePhone(tester);
        final router = buildOnboardingRouter();
        addTearDown(router.dispose);
        await pumpToMovementPage(tester, router);

        expect(findNuvoText('Just do the activity.'), findsOneWidget);
        expect(find.byType(RiveJumpingJackPreview), findsOneWidget);
        expect(find.text('AI MOTION PROOF'), findsNothing);
        expect(find.text('EXAMPLE PROOF'), findsNothing);
        expect(find.text('0 / 3'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1400));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('1 / 3'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1200));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('2 / 3'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 1200));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('3 / 3'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Verified'), findsOneWidget);

        // CTA must not appear the instant it's verified — it holds first.
        expect(find.text('Choose my direction'), findsNothing);
        await tester.pump(const Duration(milliseconds: 1400));
        await pumpUntilFound(tester, find.text('Choose my direction'));

        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Choose my direction'), findsOneWidget);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/welcome/intro',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });

  Future<void> pumpThroughWelcomeLeaderboardMovement(
    WidgetTester tester,
    GoRouter router,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          raceRepositoryProvider.overrideWith(
            (ref) => throw StateError('No race API in onboarding'),
          ),
        ],
        child: RepaintBoundary(
          key: const ValueKey('onboarding-capture'),
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
    // Welcome (0) settles, then -> Leaderboard (1).
    await tester.pump(const Duration(milliseconds: 4800));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(milliseconds: 1550));
    await tapWhenFound(tester, find.text('See how it works'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Leaderboard (1) settles, then -> Movement (2).
    await tester.pump(const Duration(milliseconds: 3150));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(milliseconds: 1550));
    await tapWhenFound(tester, find.text('Keep going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpToActivityPage(
    WidgetTester tester,
    GoRouter router, {
    bool waitForReady = true,
  }) async {
    await pumpThroughWelcomeLeaderboardMovement(tester, router);
    // Movement (2) settles, then -> Activity (3).
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump(const Duration(milliseconds: 1400));
    await pumpUntilFound(tester, find.text('Choose my direction'));
    expect(tester.takeException(), isNull, reason: 'Earlier pages fit.');
    await tapWhenFound(tester, find.text('Choose my direction'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull, reason: 'Activity entrance fits.');
    // Activity's own short settle before its CTA is allowed to exist.
    if (!waitForReady) return;
    await tester.pump(const Duration(milliseconds: 900));
    await pumpUntilFound(tester, find.text('Continue'));
  }

  Future<void> pumpToAuthPage(WidgetTester tester, GoRouter router) async {
    await pumpToActivityPage(tester, router);
    await tapWhenFound(tester, find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  const legacyPracticeCopy = [
    'This is an example using Jumping Jacks. Your real proof happens inside a race.',
    'See how your\nmove becomes\nproof.',
    'PRACTICE MODE',
    'See how your\nmove becomes proof.',
    'EXAMPLE PROOF',
    'PRACTICE',
    'Tap practice to watch three example reps.',
    'Practice the move',
  ];

  testWidgets(
    'active sequence is Welcome → Leaderboard → Movement → Activity → Auth, '
    'and legacy proof/practice copy never appears',
    (tester) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpThroughWelcomeLeaderboardMovement(tester, router);
      for (final copy in legacyPracticeCopy) {
        expect(find.text(copy), findsNothing);
      }
      expect(find.text('AI MOTION PROOF'), findsNothing);
      expect(find.text('Move real.\nCount real.'), findsNothing);
      expect(find.text('Proof turns\neffort into\nprogress.'), findsNothing);

      // Movement (2) -> Activity (3).
      await tester.pump(const Duration(milliseconds: 4100));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump(const Duration(milliseconds: 1400));
      await pumpUntilFound(tester, find.text('Choose my direction'));
      expect(find.text('Proof turns\neffort into\nprogress.'), findsNothing);
      await tapWhenFound(tester, find.text('Choose my direction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(findNuvoText('What do you want\nto race on?'), findsOneWidget);
      for (final copy in legacyPracticeCopy) {
        expect(find.text(copy), findsNothing);
      }

      // Activity (3) -> Auth (4): the legacy Practice page is unreachable —
      // there is no sixth page, and no page ever shows its copy.
      await tester.pump(const Duration(milliseconds: 900));
      await tapWhenFound(tester, find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final copy in legacyPracticeCopy) {
        expect(find.text(copy), findsNothing);
      }
      expect(findNuvoText('Ready to start\nyour first race?'), findsOneWidget);
      expect(
        find.text(
          'Create an account to save your races, invite your crew, and keep your progress.',
        ),
        findsOneWidget,
      );

      // There is no page 5: swiping/advancing further does nothing since
      // this is the PageView's last child and Auth owns no "next" CTA.
      expect(find.byType(NuvoPrimaryButton), findsOneWidget);
      expect(
        tester.widget<NuvoPrimaryButton>(find.byType(NuvoPrimaryButton)).label,
        'Create account',
      );

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  group('Activity page', () {
    testWidgets('Continue holds then slides up without advancing', (
      tester,
    ) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToActivityPage(tester, router, waitForReady: false);
      expect(find.text('Continue'), findsNothing);
      // Catch the CTA as it appears, then sample mid-reveal and settled —
      // the first frame exists at opacity 0 while the reveal ramps up.
      await pumpUntilFound(
        tester,
        find.text('Continue'),
        step: const Duration(milliseconds: 20),
      );
      expect(opacityOf(tester, find.text('Continue')), 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        opacityOf(tester, find.text('Continue')),
        greaterThan(0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacityOf(tester, find.text('Continue')), 1);
      expect(findNuvoText('Ready to start\nyour first race?'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'shows real supported activities with Jumping Jacks selected by '
      'default, and no NUVO wordmark',
      (tester) async {
        _usePhone(tester);
        final router = buildOnboardingRouter();
        addTearDown(router.dispose);
        await pumpToActivityPage(tester, router);

        expect(findNuvoText('50 Jumping Jacks'), findsOneWidget);
        for (var i = 0; i < 5; i++) {
          expect(
            tester
                .widget<Semantics>(
                  find.byKey(ValueKey('onboarding-activity-$i')),
                )
                .properties
                .selected,
            i == 1,
          );
        }
        for (final chip in [
          motionActivityForType(MotionActivityType.pushUps)!.title,
          motionActivityForType(MotionActivityType.jumpingJacks)!.title,
          motionActivityForType(MotionActivityType.plankHold)!.title,
          motionActivityForType(MotionActivityType.runningInPlace)!.title,
          'Teach Nuvo',
        ]) {
          expect(find.text(chip), findsOneWidget);
        }
        expect(wordmarkVisible(tester), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('selecting another activity updates the local example without '
        'navigating or touching the network', (tester) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToActivityPage(tester, router);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WelcomeRaceBuilderScreen)),
      );
      final builderState = container.read(welcomeOnboardingStateProvider);
      var networkCalls = 0;
      await HttpOverrides.runZoned(
        () async {
          expect(findNuvoText('50 Jumping Jacks'), findsOneWidget);

          await tester.tap(find.text('Pushups'));
          await tester.pump();
          expect(findNuvoText('50 Pushups'), findsOneWidget);
          expect(findNuvoText('50 Jumping Jacks'), findsNothing);
          // Purely local selection — no route change, no async gap.
          expect(
            router.routeInformationProvider.value.uri.path,
            '/welcome/intro',
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Plank'));
          await tester.pump();
          expect(findNuvoText('Plank: 20 seconds'), findsOneWidget);

          await tester.tap(find.text('Running in Place'));
          await tester.pump();
          expect(findNuvoText('Running in Place: 50 steps'), findsOneWidget);

          await tester.ensureVisible(find.text('Teach Nuvo'));
          await tester.tap(find.text('Teach Nuvo'));
          await tester.pump();
          expect(findNuvoText('Your Own Movement'), findsOneWidget);
          // Selecting it must never enter the real Teach Nuvo camera flow.
          expect(
            router.routeInformationProvider.value.uri.path,
            '/welcome/intro',
          );
        },
        createHttpClient: (_) {
          networkCalls++;
          throw StateError('Onboarding cannot use the network');
        },
      );
      expect(networkCalls, 0);
      expect(
        container.read(welcomeOnboardingStateProvider),
        same(builderState),
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey('onboarding-activity-4')),
            )
            .properties
            .selected,
        isTrue,
      );

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('CTA advances Activity → Auth and never auto-advances', (
      tester,
    ) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToActivityPage(tester, router);
      expect(find.text('Continue'), findsOneWidget);

      // Waiting does not advance on its own.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Continue'), findsOneWidget);
      expect(findNuvoText('Ready to start\nyour first race?'), findsNothing);

      await tapWhenFound(tester, find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(findNuvoText('Ready to start\nyour first race?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  GoRouter buildProductionOnboardingRouter() {
    final restored = Completer<RestoreResult>()
      ..complete(const RestoreNoSession());
    final repository = _PendingRestoreRepository(restored);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => expect(repository.completionCalls, 0));
    return container.read(routerProvider)..go('/welcome/intro');
  }

  group('Auth page', () {
    testWidgets(
      'renders Sign up and Log in with no Skip and no repeated wordmark',
      (tester) async {
        _usePhone(tester);
        final router = buildOnboardingRouter();
        addTearDown(router.dispose);
        await pumpToAuthPage(tester, router);

        expect(find.text('Create account'), findsOneWidget);
        expect(find.text('Already have an account? Log in'), findsOneWidget);
        expect(find.text("That's Nuvo."), findsNothing);
        expect(find.text('Skip'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_OnboardingFooter',
          ),
          findsNothing,
        );
        expect(
          tester
              .widget<PageView>(find.byType(PageView))
              .childrenDelegate
              .estimatedChildCount,
          5,
        );
        expect(wordmarkVisible(tester), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('Create account opens the existing email flow directly', (
      tester,
    ) async {
      _usePhone(tester);
      final router = buildProductionOnboardingRouter();
      await pumpToAuthPage(tester, router);

      await tester.tap(find.text('Create account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        '/auth/email',
      );
      expect(find.byType(EmailStartScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'Log in opens the shared email-code form without another page',
      (tester) async {
        _usePhone(tester);
        final router = buildProductionOnboardingRouter();
        await pumpToAuthPage(tester, router);

        await tester.ensureVisible(
          find.byKey(const ValueKey('auth-mode-toggle')),
        );
        await tester.tap(find.byKey(const ValueKey('auth-mode-toggle')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/welcome/intro',
        );
        expect(findNuvoText('Welcome back.'), findsOneWidget);
        expect(find.byType(EmailStartScreen), findsOneWidget);
        expect(find.text("Don't have an account? Sign up"), findsOneWidget);
        expect(find.byType(WelcomeAuthScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('back returns to the Activity page, not a replay', (
      tester,
    ) async {
      _usePhone(tester);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToActivityPage(tester, router);
      await tester.tap(find.text('Pushups'));
      await tester.pump();
      await tapWhenFound(tester, find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(findNuvoText('What do you want\nto race on?'), findsOneWidget);
      // Already-ready pages don't replay their entrance/hold on return.
      expect(find.text('Continue'), findsOneWidget);
      expect(findNuvoText('50 Pushups'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  for (final size in const [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(430, 932),
  ]) {
    testWidgets('no overflow walking cinematic → leaderboard → movement → '
        'activity → auth at ${size.width}×${size.height}', (tester) async {
      _usePhone(tester, size);
      final router = buildOnboardingRouter();
      addTearDown(router.dispose);
      await pumpToActivityPage(tester, router);
      expect(tester.takeException(), isNull);
      final ctaBottom = tester.getBottomLeft(find.text('Continue')).dy;
      expect(ctaBottom, lessThanOrEqualTo(size.height - 34));
      final visual = tester.getRect(
        find.byKey(const ValueKey('onboarding-activity-visual')),
      );
      expect(visual.center.dx, closeTo(size.width / 2, .5));
      await _captureOnboarding(tester, 'activity-${size.width.toInt()}');
      for (var i = 0; i < 5; i++) {
        final chip = find.byKey(ValueKey('onboarding-activity-$i'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
      }

      await tapWhenFound(tester, find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await _captureOnboarding(tester, 'auth-${size.width.toInt()}');
      await tester.ensureVisible(find.text('Create account'));
      final signUpBottom = tester.getBottomLeft(find.text('Create account')).dy;
      expect(signUpBottom, lessThanOrEqualTo(size.height - 34));
      final modeToggle = find.byKey(const ValueKey('auth-mode-toggle'));
      await tester.ensureVisible(modeToggle);
      expect(modeToggle.hitTestable(), findsOneWidget);
      await tester.tap(modeToggle);
      await tester.pump();
      await _captureOnboarding(tester, 'login-${size.width.toInt()}');
      expect(findNuvoText('Welcome back.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.ensureVisible(find.text('Log in'));
      expect(find.text('Log in').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('signed-out launch stays clean and bypasses branded splash', (
    tester,
  ) async {
    _usePhone(tester);
    final restored = Completer<RestoreResult>();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(_PendingRestoreRepository(restored)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(
          path: '/welcome/intro',
          builder: (_, _) => const WelcomeRaceBuilderScreen(),
        ),
        GoRoute(
          path: '/arena',
          builder: (_, _) => const Scaffold(body: Text('arena-destination')),
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
    // SplashScreen awaits FirstUseStore.ensureLoaded() (a real disk read via
    // path_provider) before it can resolve the signed-out destination — that
    // needs the real event loop, not just fake-clock pump() ticks, to finish.
    // See splash_screen_offline_test.dart's _pumpSplash for the same pattern.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump(const Duration(milliseconds: 500));
    expect(router.routeInformationProvider.value.uri.path, '/splash');
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(WelcomeOpeningCinematic), findsNothing);

    restored.complete(const RestoreNoSession());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(router.routeInformationProvider.value.uri.path, '/welcome/intro');
    expect(find.byType(WelcomeOpeningCinematic), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    // Page 0's text already exists structurally (it's the same continuous
    // composition as the cinematic), just not visible yet.
    expect(findNuvoText('Welcome to Nuvo.'), findsOneWidget);
    expect(opacityOf(tester, findNuvoText('Welcome to Nuvo.')), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
