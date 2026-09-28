// Unit coverage for WelcomeOpeningCinematic — the drawing sequence shared by
// the post-auth Nuvo onboarding opener (page 0 of /onboarding/nuvo). The
// full-screen flow coverage lives in nuvo_onboarding_test.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/auth/presentation/welcome_opening_cinematic.dart';

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
}
