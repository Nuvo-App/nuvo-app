// First-view acceptance for the movement picker.
//
// The primary decision surface must fit the first viewport on every
// supported iPhone size — the user reads the whole choice (recent/suggested
// tiles, catalog path, Teach Nuvo, custom goal, CTA) without scrolling.
//
// Hard geometry assertions per size × recents-count:
//   bottom('See all movements') < top(CTA)          — all sizes
//   bottom('Teach Nuvo')        < top(CTA)          — 375+
//   bottom(custom goal)         < top(CTA)          — 375+
//   scroll offset == 0 in the primary state         — all sizes
//
// Captures:
//   flutter test test/picker_first_view_test.dart \
//     --dart-define=NUVO_RESTYLE_CAPTURE=true
// writes tmp/picker-<case>.png for visual review.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_motion.dart';
import 'package:nuvo/core/widgets/pressable_scale.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/presentation/custom_pose/recent_movements_provider.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';

const _captureKey = Key('picker-capture');

class _PickerStore extends RecentMovementsStore {
  _PickerStore(this.ids);
  final List<String> ids;
  @override
  Future<List<String>> readIds() async => ids;
  @override
  Future<List<String>> recordSelection(String movementId) async => ids;
}

const _sizes = [
  ('320x568', Size(320, 568)),
  ('375x667', Size(375, 667)),
  ('390x844', Size(390, 844)),
  ('430x932', Size(430, 932)),
];

const _recentsCases = <String, List<String>>{
  'r0': [],
  'r1': ['plank_hold'],
  'r2': ['plank_hold', 'squats'],
  'r3': ['plank_hold', 'squats', 'jumping_jacks'],
  'r4': ['plank_hold', 'squats', 'jumping_jacks', 'push_ups'],
};

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  setUpAll(() async {
    // Real Manrope metrics — the Ahem fallback over-measures text. Same
    // asset-channel stub as the sweep/composer harnesses.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const fontAssets = {
      'test/fonts/Manrope-Regular.ttf':
          'tmp/social-qa/fonts/Manrope_regular.ttf',
      'test/fonts/Manrope-Medium.ttf':
          'tmp/social-qa/fonts/Manrope_medium.ttf',
      'test/fonts/Manrope-SemiBold.ttf':
          'tmp/social-qa/fonts/Manrope_semiBold.ttf',
      'test/fonts/Manrope-Bold.ttf': 'tmp/social-qa/fonts/Manrope_bold.ttf',
      'test/fonts/Manrope-ExtraBold.ttf':
          'tmp/social-qa/fonts/Manrope_extraBold.ttf',
    };
    const families = {
      'Manrope_regular': 'tmp/social-qa/fonts/Manrope_regular.ttf',
      'Manrope_500': 'tmp/social-qa/fonts/Manrope_medium.ttf',
      'Manrope_600': 'tmp/social-qa/fonts/Manrope_semiBold.ttf',
      'Manrope_700': 'tmp/social-qa/fonts/Manrope_bold.ttf',
      'Manrope_800': 'tmp/social-qa/fonts/Manrope_extraBold.ttf',
    };
    final manifest = const StandardMessageCodec().decodeMessage(
            await rootBundle.load('AssetManifest.bin'))
        as Map<Object?, Object?>;
    for (final key in fontAssets.keys) {
      manifest[key] = [
        {'asset': key}
      ];
    }
    final manifestBytes =
        const StandardMessageCodec().encodeMessage(manifest);
    final fontBytes = {
      for (final e in fontAssets.entries)
        e.key: ByteData.sublistView(await File(e.value).readAsBytes())
    };
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') return manifestBytes;
      return fontBytes[key] ??
          await messenger.delegate.send('flutter/assets', message);
    });
    for (final e in families.entries) {
      await (FontLoader(e.key)
            ..addFont(Future.value(
                ByteData.sublistView(
                    await File(e.value).readAsBytes()))))
          .load();
    }
  });

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  /// Pumps the composer straight onto the movement step (name prefill
  /// resolves the first stage). Fails the test on any layout exception.
  Future<void> pumpPicker(
    WidgetTester tester, {
    required List<String> recents,
    required Size size,
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    setSize(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentMovementsStoreProvider
              .overrideWithValue(_PickerStore(recents)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: _captureKey, child: child!),
          ),
          home: const RaceComposerScreen(
            prefill: RaceCreatePrefill(idea: 'Weekend book club'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose activity'));
    await tester.pumpAndSettle();
    var sawError = false;
    Object? pumpError;
    while ((pumpError = tester.takeException()) != null) {
      sawError = true;
      debugPrint('picker pump exception: $pumpError');
    }
    if (sawError) fail('picker threw during pump');
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('NUVO_RESTYLE_CAPTURE')) return;
    final boundary = tester
        .renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tmp/picker-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  /// The scroll viewport's bottom is the pinned CTA's top edge — anything
  /// above the fold ends strictly above it.
  double ctaTop(WidgetTester tester) =>
      tester.getTopLeft(find.byType(NuvoPrimaryButton)).dy;

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  Finder seeAll() => find.ancestor(
        of: find.text('See all movements'),
        matching: find.byType(NuvoPressable),
      );
  Finder teachCard() => find.ancestor(
        of: find.text('Teach Nuvo'),
        matching: find.byType(PressableScale),
      );
  Finder customPath() => find.ancestor(
        of: find.text('Not a movement? Create a custom goal'),
        matching: find.byType(NuvoPressable),
      );

  group('first-view budget', () {
    for (final (sizeName, size) in _sizes) {
      for (final MapEntry(key: rcName, value: recents)
          in _recentsCases.entries) {
        testWidgets('$rcName at $sizeName — whole decision above the fold',
            (tester) async {
          await pumpPicker(tester, recents: recents, size: size);
          await capture(tester, '$rcName-$sizeName');

          final cta = ctaTop(tester);
          // Hard rule: the catalog path is always visible.
          expect(seeAll(), findsOneWidget);
          expect(tester.getBottomLeft(seeAll()).dy, lessThan(cta),
              reason: '$rcName $sizeName: See all sits below the CTA');

          // 375+ shows all three secondary paths in the first viewport;
          // 320 must still show See all + all four tiles + CTA.
          if (size.width >= 375) {
            expect(tester.getBottomLeft(teachCard()).dy, lessThan(cta),
                reason: '$rcName $sizeName: Teach Nuvo below the fold');
            expect(tester.getBottomLeft(customPath()).dy, lessThan(cta),
                reason: '$rcName $sizeName: custom goal below the fold');
          }

          // All four primary choices end above the CTA too.
          final tiles = find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_MovementTile');
          expect(tiles, findsNWidgets(4));
          for (final t in tester.widgetList(tiles)) {
            expect(tester.getBottomLeft(find.byWidget(t)).dy, lessThan(cta));
          }

          // The one-look requirement: nothing scrolled to get here.
          expect(scrollOffset(tester), 0,
              reason: '$rcName $sizeName: primary state requires scrolling');
        });
      }
    }

    testWidgets('selected tile keeps identical geometry', (tester) async {
      await pumpPicker(tester,
          recents: const [], size: const Size(390, 844));
      Finder tile(String t) =>
          find.widgetWithText(PressableScale, t).first;
      final before = tester.getRect(tile('Pushups'));
      await tester.tap(find.text('Pushups'));
      await tester.pumpAndSettle();
      expect(tester.getRect(tile('Pushups')), before);
      expect(find.text('Continue with Pushups'), findsOneWidget);
    });

    testWidgets('text scale 1.4 at 320 — scrollable but nothing clipped',
        (tester) async {
      await pumpPicker(
        tester,
        recents: const ['plank_hold', 'squats', 'jumping_jacks'],
        size: const Size(320, 568),
        textScale: 1.4,
      );
      await capture(tester, 'ts14-320');
      // Everything exists; scrolling may be required at accessibility scale.
      expect(seeAll(), findsOneWidget);
      expect(teachCard(), findsOneWidget);
      expect(customPath(), findsOneWidget);
      expect(find.byType(NuvoPrimaryButton), findsOneWidget);
      // Scroll to the bottom — every path reachable, nothing half-clipped.
      final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.fling(scrollable, const Offset(0, -400), 1200);
      await tester.pumpAndSettle();
      expect(scrollOffset(tester), greaterThan(0));
      while (tester.takeException() != null) {
        fail('overflow at text scale 1.4');
      }
    });

    testWidgets('dark mode 390 — same first-view contract', (tester) async {
      await pumpPicker(
        tester,
        recents: const ['plank_hold', 'squats', 'jumping_jacks'],
        size: const Size(390, 844),
        theme: AppTheme.dark(),
      );
      await capture(tester, 'r3-dark-390');
      final cta = ctaTop(tester);
      expect(tester.getBottomLeft(seeAll()).dy, lessThan(cta));
      expect(tester.getBottomLeft(teachCard()).dy, lessThan(cta));
      expect(scrollOffset(tester), 0);
    });
  });
}
