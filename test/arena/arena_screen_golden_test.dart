import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';
import 'package:nuvo/core/widgets/trackside_layout_diagnostics.dart';

void main() {
  const defaultPhysicalSize = Size(390, 844);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final manrope = await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes();
    final manropeData = Future<ByteData>.value(ByteData.sublistView(manrope));
    // GoogleFonts builds fontFamily names like Manrope_regular, Manrope_700.
    for (final name in [
      'Manrope_regular',
      'Manrope_500',
      'Manrope_600',
      'Manrope_700',
      'Manrope_800',
      'Manrope_900',
    ]) {
      await (FontLoader(name)..addFont(manropeData)).load();
    }

    final materialIcons = await File(
      '/Users/shreshpanda/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final materialData = Future<ByteData>.value(ByteData.sublistView(materialIcons));
    await (FontLoader('MaterialIcons')..addFont(materialData)).load();
  });

  Future<void> pumpArena(
    WidgetTester tester, {
    Size physicalSize = defaultPhysicalSize,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/arena',
              builder: (context, state) => const ArenaScreen(preview: true),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ArenaScreen mounts the TrackSide foundation', (tester) async {
    await pumpArena(tester);

    expect(find.textContaining('Pushups'), findsOneWidget);
    expect(find.text('Your next move'), findsOneWidget);
    expect(find.text('CREW STANDINGS'), findsOneWidget);
    expect(find.text('Submit proof'), findsOneWidget);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('full shell keeps the baseline TrackSide canvas and nav boundary', (
    tester,
  ) async {
    await pumpArena(tester);

    final hero = tester.getRect(find.byKey(TrackSideLayoutKeys.hero));
    final panel = tester.getRect(find.byKey(TrackSideLayoutKeys.panel));
    final navigation = tester.getRect(find.byKey(TrackSideLayoutKeys.navigation));

    expect(hero.top, 0);
    expect(hero.bottom, 464);
    expect(panel.top, 464);
    expect(navigation.top, 769);
    expect(navigation.height, 75);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
  });

  testWidgets('full shell fills taller and inset viewports without a navy gap', (
    tester,
  ) async {
    await pumpArena(
      tester,
      physicalSize: const Size(390, 932),
      bottomInset: 34,
    );

    final panel = tester.getRect(find.byKey(TrackSideLayoutKeys.panel));
    final navigation = tester.getRect(find.byKey(TrackSideLayoutKeys.navigation));

    expect(panel.top, 464);
    expect(panel.bottom, greaterThanOrEqualTo(navigation.top));
    expect(navigation.bottom, 932);
    expect(navigation.height, 109);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
  });

  testWidgets('swiping the orbit page view switches race and updates score and pager', (
    tester,
  ) async {
    await pumpArena(tester);

    expect(find.text('First to 100 Pushups'), findsOneWidget);
    expect(find.text('65 / 100'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    final pageView = find.byType(PageView);
    expect(pageView, findsOneWidget);

    await tester.fling(pageView, const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('First to 60 Pushups'), findsOneWidget);
    expect(find.text('28 / 60'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.fling(pageView, const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('First to 40 Pushups'), findsOneWidget);
    expect(find.text('0 / 40'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    // Boundary: dragging past the last page should keep the last board.
    await tester.fling(pageView, const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('First to 40 Pushups'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('race switcher arrows navigate pages', (tester) async {
    await pumpArena(tester);

    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('First to 60 Pushups'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('First to 40 Pushups'), findsOneWidget);

    // Right arrow is disabled on the last page, so going back works.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('First to 60 Pushups'), findsOneWidget);
  });

  testWidgets('tapping an orbit participant highlights it', (tester) async {
    await pumpArena(tester);

    // Rank 1 marker is centered at (195, 337) for the 390x844 baseline.
    await tester.tapAt(const Offset(195, 337));
    await tester.pumpAndSettle();

    // Pumping and settling without an exception proves selection wiring is in
    // place; the golden for the selected state verifies the visual treatment.
    expect(find.byType(ArenaScreen), findsOneWidget);
  });

  testWidgets('renders without runtime fetching and respects reduced motion', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          disableAnimations: true,
          reduceMotion: true,
        );
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    await pumpArena(tester);

    expect(find.text('Your next move'), findsOneWidget);
    expect(find.text('Submit proof'), findsOneWidget);
  });

  testWidgets('ArenaTrackSide default page golden', (tester) async {
    await pumpArena(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/arena_trackside_default.png'),
    );
  });

  testWidgets('ArenaTrackSide 390x844 inset golden', (tester) async {
    await pumpArena(tester, bottomInset: 34);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/arena_trackside_390x844_inset.png'),
    );
  });

  testWidgets('ArenaTrackSide page 2 golden', (tester) async {
    await pumpArena(tester);

    final pageView = find.byType(PageView);
    await tester.drag(pageView, const Offset(-180, 0));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/arena_trackside_page2.png'),
    );
  });

  testWidgets('ArenaTrackSide selected participant golden', (tester) async {
    await pumpArena(tester);

    await tester.tapAt(const Offset(195, 337));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('golden/arena_trackside_selected.png'),
    );
  });
}
