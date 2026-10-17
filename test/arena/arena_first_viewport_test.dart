import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/presentation/arena_podium.dart';
import 'package:nuvo/features/arena/presentation/arena_rest_board.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

/// The Arena first composition:
///   header -> Your next move -> [card through its N / M reps progress row]
///   -> actions -> (fold). The standings (Leaderboard) begin BELOW the visible
/// area and only appear on scroll; Recent activity no longer exists here.
void main() {
  Future<void> pumpArena(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
    double textScale = 1.0,
    ArenaSnapshot? snapshot,
    bool dark = false,
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 47, bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(top: 47, bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/arena',
              builder: (c, s) =>
                  ArenaScreen(preview: true, debugSnapshot: snapshot),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? ThemeData.dark() : null,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  ArenaSnapshot snap(List<(String, String, bool)> rows) => ArenaSnapshot(
    mode: 'real',
    headerPulse: '',
    focusBoard: ArenaBoard(
      id: 'r1',
      source: 'real',
      title: 'First to 100 Pushups',
      progressLabel: '22 / 100 reps',
      boardContext: '',
      primaryActionLabel: 'Submit proof',
      primaryActionType: 'submit_proof',
      progressPercent: 22,
      racerCount: rows.length,
      isResult: false,
      myRank: rows.indexWhere((r) => r.$3) + 1,
      chaseCopy: 'You trail Alex by 17 reps.',
      miniLeaderboard: [
        for (final r in rows)
          ArenaMiniLeaderboardRow(
            label: r.$1,
            value: '${r.$2} / 100',
            isCurrentUser: r.$3,
          ),
      ],
    ),
    activity: const [],
  );

  final full = snap([
    ('Alex R.', '39', false),
    ('Maya L.', '31', false),
    ('You', '22', true),
  ]);
  final outside = snap([
    ('Alex R.', '39', false),
    ('Maya L.', '31', false),
    ('Sam K.', '28', false),
    ('Jo P.', '25', false),
    ('You', '22', true),
  ]);
  final duo = snap([('Alex R.', '39', false), ('You', '22', true)]);

  double h(WidgetTester t, int rank) =>
      t.getSize(find.byKey(ValueKey('arena-podium-block-$rank'))).height;
  double cx(WidgetTester t, int rank) =>
      t.getCenter(find.byKey(ValueKey('arena-podium-block-$rank'))).dx;

  const sizes = <String, Size>{
    'compact (320x568)': Size(320, 568),
    'small iPhone (SE)': Size(375, 667),
    'standard (390x844)': Size(390, 844),
    'iPhone 393x852': Size(393, 852),
    'Pro Max (430x932)': Size(430, 932),
  };

  for (final entry in sizes.entries) {
    testWidgets(
      '${entry.key}: top-3 podium fits above the nav; no full board',
      (tester) async {
        final size = entry.value;
        final compact = size.width < 340;
        await pumpArena(
          tester,
          size,
          bottomInset: compact ? 0 : 34,
          snapshot: full,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Recent activity'), findsNothing);
        expect(find.text('Leaderboard'), findsNothing);
        expect(find.textContaining('See full'), findsNothing);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

        // Heights 1st > 2nd > 3rd; the winner is the centre block.
        expect(h(tester, 1), greaterThan(h(tester, 2)));
        expect(h(tester, 2), greaterThan(h(tester, 3)));
        expect(cx(tester, 2), lessThan(cx(tester, 1)));
        expect(cx(tester, 1), lessThan(cx(tester, 3)));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('arena-podium-block-1')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('39'), findsOneWidget);
        // The viewer's block is labelled 'You'.
        expect(find.text('You'), findsOneWidget);

        if (!compact) {
          final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
          final blockBottom = tester
              .getBottomLeft(find.byKey(const ValueKey('arena-podium-block-1')))
              .dy;
          expect(
            blockBottom,
            lessThanOrEqualTo(foldY),
            reason: '${entry.key}: podium above the nav',
          );
          final progress = find.textContaining('reps');
          expect(
            tester.getBottomLeft(progress.first).dy,
            lessThanOrEqualTo(foldY),
          );
          // No scrolling needed: the page cannot scroll.
          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          expect(scrollable.position.maxScrollExtent, lessThanOrEqualTo(0.5));
        }
        final submitBtn = tester.widget<NuvoPrimaryButton>(
          find.byType(NuvoPrimaryButton),
        );
        expect(submitBtn.height, greaterThanOrEqualTo(48));
      },
    );
  }

  testWidgets('4th and below sit below the fold and fade in one by one', (
    tester,
  ) async {
    await pumpArena(tester, const Size(390, 844), snapshot: outside);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('arena-podium-viewer-chip')),
      findsNothing,
    );
    expect(find.text('You \u00b7 5th \u00b7 22'), findsNothing);
    final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
    // Not visible when the page opens: below the nav and fully transparent.
    final jo = find.text('Jo');
    expect(jo, findsOneWidget);
    expect(tester.getTopLeft(jo).dy, greaterThanOrEqualTo(navTop - 8));
    double opacityOf(Finder f) => tester
        .renderObject<RenderArenaScrollReveal>(
          find.ancestor(of: f, matching: find.byType(ArenaScrollReveal)).first,
        )
        .progress;
    expect(opacityOf(jo), lessThan(0.02));

    // A small nudge does not play the whole thing.
    final scrollable = find.byType(CustomScrollView);
    await tester.drag(scrollable, const Offset(0, -20));
    await tester.pump();
    expect(opacityOf(jo), lessThan(0.5));

    // Scrolled all the way: the rows are in and each is fully shown.
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(opacityOf(jo), 1);
    expect(find.text('You'), findsOneWidget);
    expect(opacityOf(find.text('You')), 1);
  });

  testWidgets(
    'fewer than 3 racers: empty places stay empty',
    (tester) async {
      await pumpArena(tester, const Size(390, 844), snapshot: duo);
      expect(tester.takeException(), isNull);
      // An empty place stays empty: no dashed placeholder, no "Open" label.
      expect(find.byKey(const ValueKey('arena-podium-open-3')), findsNothing);
      expect(find.text('Open'), findsNothing);
      expect(
        find.byKey(const ValueKey('arena-podium-block-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('arena-podium-block-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('blocks rise: mid-animation shorter than final; completes', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(390, 844),
      snapshot: full,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 150));
    final mid = h(tester, 1);
    await tester.pumpAndSettle();
    expect(h(tester, 1), greaterThan(mid));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion: podium is static at its final height', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(390, 844),
      snapshot: full,
      reduceMotion: true,
      settle: false,
    );
    final first = h(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h(tester, 1), first);
    expect(first, greaterThan(60));
  });

  testWidgets('320x568 at 1.4 text scale renders without overflow', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(320, 568),
      bottomInset: 0,
      textScale: 1.4,
      snapshot: outside,
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Leaderboard'), findsNothing);
  });

  testWidgets('dark mode renders the podium without exceptions', (
    tester,
  ) async {
    await pumpArena(
      tester,
      const Size(390, 844),
      snapshot: outside,
      dark: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('arena-podium-block-1')), findsOneWidget);
  });

  test('podium text keeps >= 4.5:1 on every block fill', () {
    double contrast(Color a, Color b) {
      final l1 = a.computeLuminance(), l2 = b.computeLuminance();
      final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final rank in [1, 2, 3]) {
      expect(
        contrast(arenaPodiumInk, arenaPodiumFill(rank)),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('card height is content-driven: same density tier gives the same '
      'height regardless of raw width', (tester) async {
    await pumpArena(tester, const Size(390, 844));
    final hStandard = tester.getSize(find.byType(PageView).first).height;
    await pumpArena(tester, const Size(430, 850));
    final hProMax = tester.getSize(find.byType(PageView).first).height;
    expect(hProMax, closeTo(hStandard, 1.0));
  });

  group('dark-mode hero surface', () {
    double lum(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    test('dark hero is lighter than the old surface; light unchanged', () {
      final dark = arenaHeroSurface(Brightness.dark, NuvoColors.darkSurface);
      expect(dark, isNot(NuvoColors.darkSurface));
      expect(lum(dark), greaterThan(lum(NuvoColors.darkSurface)));
      expect(
        arenaHeroSurface(Brightness.light, NuvoColors.surface),
        NuvoColors.surface,
      );
    });

    test('text on the dark hero keeps >= 4.5:1', () {
      final dark = arenaHeroSurface(Brightness.dark, NuvoColors.darkSurface);
      expect(contrast(NuvoColors.darkInk, dark), greaterThanOrEqualTo(4.5));
      expect(
        contrast(NuvoColors.darkInkMuted, dark),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
