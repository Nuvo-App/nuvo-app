// Release hardening for the Achievements surfaces:
//
//  1. The self + public collections must let the LAST grid tile scroll fully
//     above the bottom safe area — badge, name, and status line all visible,
//     no nav/home-indicator overlap, at every shipped width, dark mode, and
//     max text scale.
//  2. The achievement detail sheet must show exactly ONE drag/grab handle —
//     the one the modal sheet shell renders (theme showDragHandle). Sheet
//     content never draws its own.
//  3. Sheet CTAs sit above the home indicator and content scrolls when text
//     scale demands it.
//
// Run captures with:
//   flutter test test/achievements_hardening_test.dart \
//     --dart-define=NUVO_BADGES_CAPTURE=true
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/theme/nuvo_responsive.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/presentation/public_badges_screen.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/badges_screen.dart';
import 'package:nuvo/features/profile/presentation/widgets/nuvo_badges.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/core/widgets/pressable_scale.dart';

const _captureKey = Key('badges-capture');

const _progression = NuvoProgression(
  level: 8,
  totalXp: 1410,
  currentLevelXp: 30,
  nextLevelXp: 120,
  progress: 0.25,
  xpToNext: 90,
  lastSeenLevel: 8,
  featuredSlots: 3,
  achievementsEarned: 30,
  achievementsTotal: 43,
);

NuvoBadge _badge(
  int i, {
  bool unlocked = true,
  bool featured = false,
  String category = 'racing',
}) {
  return NuvoBadge(
    unlockId: 'u-$i',
    type: 'achievement',
    key: 'k$i',
    name: 'Achievement Number $i',
    description: 'Finish ${i + 1} races to earn this.',
    requiredLevel: 1,
    unlocked: unlocked,
    unlockedAt: unlocked ? '2026-01-0${(i % 9) + 1}T00:00:00Z' : null,
    featured: featured,
    category: category,
    iconKey: 'trophy',
    statKey: 'wins',
    threshold: i + 1,
    progressValue: unlocked ? i + 1 : i,
  );
}

/// The shipped collection — 43 achievements, mixed earned/locked across the
/// real tab categories so the tab row + sorting path are exercised too.
final _all43 = [
  for (var i = 0; i < 43; i++)
    _badge(
      i,
      unlocked: i < 30,
      featured: i < 3,
      category: switch (i % 5) {
        0 => 'racing',
        1 => 'winning',
        2 => 'creating',
        3 => 'consistency',
        _ => 'proof',
      },
    ),
];

final _few = [
  _badge(0, featured: true),
  _badge(1, featured: true),
  _badge(2, unlocked: false, category: 'winning'),
];

class _SeededProgression extends ProgressionController {
  _SeededProgression(this._b, {NuvoProgression progression = _progression})
    : super(
        ProgressionApi(),
        SecureTokenStore(),
        isPresentationDemo: () => false,
      ) {
    state = AsyncValue.data(progression);
  }
  final List<NuvoBadge> _b;
  @override
  Future<List<NuvoBadge>> getBadges() async => _b;
  @override
  Future<List<NuvoBadge>> setFeatured(List<String> unlockIds) async => [
        for (final b in _b)
          NuvoBadge(
            unlockId: b.unlockId,
            type: b.type,
            key: b.key,
            name: b.name,
            description: b.description,
            requiredLevel: b.requiredLevel,
            metadata: b.metadata,
            unlocked: b.unlocked,
            unlockedAt: b.unlockedAt,
            featured: unlockIds.contains(b.unlockId),
            position: b.position,
            category: b.category,
            iconKey: b.iconKey,
            statKey: b.statKey,
            threshold: b.threshold,
            progressValue: b.progressValue,
          ),
      ];
}

Widget _wrap(
  Widget child, {
  required List<NuvoBadge> badges,
  bool dark = false,
  double textScale = 1.0,
  NuvoProgression progression = _progression,
}) {
  return ProviderScope(
    overrides: [
      progressionControllerProvider.overrideWith(
        (ref) => _SeededProgression(badges, progression: progression),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: NuvoTextScaleScope(
          child: RepaintBoundary(key: _captureKey, child: child!),
        ),
      ),
      home: child,
    ),
  );
}

const _sizes = [
  ('320x568', 320.0, 568.0),
  ('375x667', 375.0, 667.0),
  ('390x844', 390.0, 844.0),
  ('430x932', 430.0, 932.0),
];

void _useViewport(
  WidgetTester tester,
  double width,
  double height, {
  double bottomInset = 34,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 44, bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(top: 44, bottom: bottomInset);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await _settle(tester);
}

/// The outermost element of the LAST grid tile — badge + name + status.
Finder _lastTile() => find
    .ancestor(of: find.byType(NuvoAchievementBadge).last, matching: find.byType(PressableScale))
    .last;

/// Pill-shaped containers that read as a drag/grab handle — tight height in
/// the 3–8px range, width 24–56. Matches both the shell's handle and any
/// hand-drawn duplicate inside sheet content.
bool _looksLikeHandle(Widget w) {
  if (w is! Container) return false;
  final c = w.constraints;
  if (c == null) return false;
  final tightH = c.minHeight == c.maxHeight && c.minHeight >= 3 && c.minHeight <= 8;
  final tightW = c.minWidth == c.maxWidth && c.minWidth >= 24 && c.minWidth <= 56;
  if (!(tightH && tightW)) return false;
  final d = w.decoration;
  return d is BoxDecoration && d.color != null;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('NUVO_BADGES_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/badges-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    // Real Manrope metrics — Ahem fallback reports phantom overflows.
    final bytes = ByteData.sublistView(
      await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
    );
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
      manifest['test/fonts/Manrope-$variant.ttf'] = [
        {'asset': 'test/fonts/Manrope-$variant.ttf'},
      ];
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage(manifest);
          }
          if (key.startsWith('test/fonts/Manrope')) return bytes;
          return null;
        });
    for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
      final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });

  group('last row scrolls fully above the safe area', () {
    for (final (sizeName, w, h) in _sizes) {
      testWidgets('self collection — 43 badges $sizeName', (tester) async {
        _useViewport(tester, w, h);
        await tester.pumpWidget(
          _wrap(const BadgesScreen(), badges: _all43),
        );
        await _settle(tester);
        await _scrollToEnd(tester);
        final tile = tester.getRect(_lastTile());
        // Fully above the safe area...
        expect(
          tile.bottom,
          lessThanOrEqualTo(h - 34 + 0.5),
          reason: 'last tile bottom ${tile.bottom} must sit above the '
              '${34}px bottom inset on $sizeName',
        );
        // ...with real clearance — 28px read as "clipped against the
        // edge" on inset-less devices. Pushed pages reserve 56.
        expect(
          tile.bottom,
          lessThanOrEqualTo(h - 34 - 40 + 0.5),
          reason: 'last tile needs ≥40px of breathing room below it',
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, 'end-$sizeName');
      });
    }

    testWidgets('self collection — few badges 375x667, no inset',
        (tester) async {
      // Home-button-class device: viewPadding.bottom is 0, so the only
      // thing standing between the last tile and the screen edge is the
      // list's own bottom padding.
      _useViewport(tester, 375, 667, bottomInset: 0);
      await tester.pumpWidget(_wrap(const BadgesScreen(), badges: _all43));
      await _settle(tester);
      await _scrollToEnd(tester);
      final tile = tester.getRect(_lastTile());
      expect(
        tile.bottom,
        lessThanOrEqualTo(667 - 40 + 0.5),
        reason: 'last tile needs ≥40px of clearance above the screen edge',
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, 'end-375-noinset');
    });

    for (final scale in [1.2, 1.4]) {
      testWidgets('self collection — ts $scale 320x568', (tester) async {
        _useViewport(tester, 320, 568);
        await tester.pumpWidget(
          _wrap(const BadgesScreen(), badges: _all43, textScale: scale),
        );
        await _settle(tester);
        await _scrollToEnd(tester);
        final tile = tester.getRect(_lastTile());
        expect(
          tile.bottom,
          lessThanOrEqualTo(568 - 34 - 40 + 0.5),
          reason: 'last tile clipped/crowded at bottom at ts$scale',
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, 'ts$scale-320');
      });
    }

    testWidgets('self collection — dark 390x844', (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(const BadgesScreen(), badges: _all43, dark: true),
      );
      await _settle(tester);
      await _scrollToEnd(tester);
      final tile = tester.getRect(_lastTile());
      expect(tile.bottom, lessThanOrEqualTo(844 - 34 - 40 + 0.5));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'dark-390');
    });

    testWidgets('public collection — 390x844', (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(
          PublicBadgesScreen(
            userId: 'u-rival',
            card: PublicProfileCard(
              id: 'u-rival',
              displayName: 'Rival One',
              username: 'rival',
              initials: 'RO',
              connectionStatus: CrewConnectionStatus.none,
              level: 6,
              levelProgress: 0.4,
              achievementsEarned: 43,
              achievementsTotal: 43,
              earned: _all43.where((b) => b.unlocked).toList(),
            ),
          ),
          badges: _all43,
        ),
      );
      await _settle(tester);
      await _scrollToEnd(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'public-390');
    });
  });

  group('achievement detail sheet — one handle, safe area', () {
    Future<void> openSheet(
      WidgetTester tester, {
      bool unlocked = true,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => NuvoAchievementDetailSheet(
                    badge: unlocked
                        ? _badge(0, featured: false)
                        : _badge(9, unlocked: false),
                    onFeature: unlocked ? () {} : null,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          badges: _few,
          textScale: textScale,
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('open'));
      await _settle(tester);
    }

    testWidgets('exactly one grab handle', (tester) async {
      _useViewport(tester, 390, 844);
      await openSheet(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      // The shell's handle carries the dismiss semantics.
      expect(
        find.descendant(
          of: sheet,
          matching: find.bySemanticsLabel('Dismiss'),
        ),
        findsOneWidget,
      );
      // And there is no second hand-drawn pill anywhere in the sheet.
      final pills = tester
          .widgetList(find.descendant(of: sheet, matching: find.byWidgetPredicate(_looksLikeHandle)))
          .length;
      expect(pills, 1, reason: 'sheet must render exactly one grab handle');
    });

    testWidgets('CTA clears the home indicator', (tester) async {
      _useViewport(tester, 390, 844);
      await openSheet(tester);
      final cta = tester.getRect(find.text('Feature on Profile'));
      expect(
        cta.bottom,
        lessThanOrEqualTo(844 - 34 + 0.5),
        reason: 'sheet CTA must sit above the 34px bottom inset',
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sheet-390');
    });

    testWidgets('scrolls at 320 + ts1.4 without overflow', (tester) async {
      _useViewport(tester, 320, 568);
      await openSheet(tester, textScale: 1.4);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
        reason: 'sheet content must stay scrollable at max text scale',
      );
      await _capture(tester, 'sheet-320-ts14');
    });

    testWidgets('locked achievement shows progress', (tester) async {
      _useViewport(tester, 390, 844);
      await openSheet(tester, unlocked: false);
      expect(find.text('9 / 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('feature / unfeature round trip through the sheet',
        (tester) async {
      _useViewport(tester, 390, 844);
      final badges = [
        _badge(0, featured: true),
        _badge(1),
        _badge(2, unlocked: false),
      ];
      await tester.pumpWidget(
        _wrap(const BadgesScreen(), badges: badges),
      );
      await _settle(tester);

      // Open the unlocked, unfeatured tile and feature it.
      await tester.tap(find.text('Achievement Number 1'));
      await _settle(tester);
      expect(find.text('Feature on Profile'), findsOneWidget);
      await tester.tap(find.text('Feature on Profile'));
      await _settle(tester);

      // Re-open — the action flips to Unfeature and the tile carries
      // the featured check.
      await tester.tap(find.text('Achievement Number 1'));
      await _settle(tester);
      expect(find.text('Unfeature'), findsOneWidget);
      await tester.tap(find.text('Unfeature'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('what is next leads the Achievements page', () {
    final withNext = NuvoProgression(
      level: 8,
      totalXp: 1410,
      currentLevelXp: 30,
      nextLevelXp: 120,
      progress: 0.25,
      xpToNext: 90,
      lastSeenLevel: 8,
      featuredSlots: 3,
      achievementsEarned: 30,
      achievementsTotal: 43,
      nextAchievement: _badge(50, unlocked: false, category: 'winning'),
      nextUnlock: const NuvoUnlockRef(
        unlockId: 'lvl-9',
        level: 9,
        type: 'badge',
        key: 'clap',
        name: 'Clap reaction',
        description: 'A new reaction for your crew.',
      ),
    );

    testWidgets('next goal and next unlock sit above the full list',
        (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(const BadgesScreen(), badges: _all43, progression: withNext),
      );
      await _settle(tester);

      expect(find.text('NEXT UP'), findsOneWidget);
      expect(find.text('Achievement Number 50'), findsOneWidget);
      expect(find.text('NEXT LEVEL REWARD'), findsOneWidget);
      expect(find.text('Clap reaction'), findsOneWidget);
      expect(find.text('Earned at Level 9'), findsOneWidget);
      expect(find.text('All achievements'), findsOneWidget);

      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.text('NEXT UP')), lessThan(y(find.text('NEXT LEVEL REWARD'))));
      expect(
        y(find.text('NEXT LEVEL REWARD')),
        lessThan(y(find.text('All achievements'))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no next goal or unlock — the page just opens on the list',
        (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(_wrap(const BadgesScreen(), badges: _all43));
      await _settle(tester);

      expect(find.text('NEXT UP'), findsNothing);
      expect(find.text('NEXT LEVEL REWARD'), findsNothing);
      expect(find.text('All achievements'), findsOneWidget);
    });

    testWidgets('survives 320px at text scale 1.4', (tester) async {
      _useViewport(tester, 320, 568);
      await tester.pumpWidget(
        _wrap(
          const BadgesScreen(),
          badges: _all43,
          progression: withNext,
          textScale: 1.4,
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('grid rhythm + filter chips', () {
    // Row-to-row gap (bottom of a tile's status line -> top of the next
    // row's badge) measured on the ORIGINAL grid (fixed childAspectRatio
    // 0.72 + 26px mainAxisSpacing) at 390 wide, text scale 1.0.
    const oldRowGap = 75.63;

    Future<double> measureGap(WidgetTester tester, double w) async {
      _useViewport(tester, w, 844);
      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: NuvoBadgeGrid(badges: _all43),
            ),
          ),
          badges: _all43,
        ),
      );
      await _settle(tester);
      final tile0 = find
          .ancestor(
            of: find.byType(NuvoAchievementBadge).at(0),
            matching: find.byType(PressableScale),
          )
          .first;
      var textBottom = 0.0;
      for (final e in find
          .descendant(of: tile0, matching: find.byType(Text))
          .evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        if (r.bottom > textBottom) textBottom = r.bottom;
      }
      final nextBadgeTop =
          tester.getRect(find.byType(NuvoAchievementBadge).at(3)).top;
      // Row alignment: tiles in a row share the same top.
      expect(
        tester.getRect(find.byType(NuvoAchievementBadge).at(1)).top,
        tester.getRect(find.byType(NuvoAchievementBadge).at(0)).top,
      );
      expect(tester.takeException(), isNull);
      return nextBadgeTop - textBottom;
    }

    testWidgets('row gap is at most 55% of the old gap', (tester) async {
      final gap = await measureGap(tester, 390);
      // ignore: avoid_print
      print('row gap now: $gap (old: $oldRowGap)');
      expect(gap, lessThanOrEqualTo(oldRowGap * 0.55));
      expect(gap, greaterThan(4), reason: 'rows must not touch');
    });

    for (final (sizeName, w, h) in _sizes) {
      for (final scale in [1.0, 1.4]) {
        for (final dark in [false, true]) {
          testWidgets('"All" chip fully visible $sizeName ts$scale dark=$dark',
              (tester) async {
            _useViewport(tester, w, h);
            await tester.pumpWidget(
              _wrap(
                const BadgesScreen(),
                badges: _all43,
                textScale: scale,
                dark: dark,
              ),
            );
            await _settle(tester);
            final chip = tester.getRect(find
                .ancestor(
                  of: find.text('All'),
                  matching: find.byType(PressableScale),
                )
                .first);
            final label = tester.getRect(find.text('All'));
            expect(chip.left, greaterThanOrEqualTo(0));
            expect(chip.right, lessThanOrEqualTo(w));
            expect(label.left, greaterThanOrEqualTo(chip.left));
            expect(label.right, lessThanOrEqualTo(chip.right));
            // Chip is not clipped vertically by the row.
            final row = tester.getRect(find
                .ancestor(
                  of: find.text('All'),
                  matching: find.byType(ListView),
                )
                .first);
            expect(chip.top, greaterThanOrEqualTo(row.top - 0.5));
            expect(chip.bottom, lessThanOrEqualTo(row.bottom + 0.5));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('selected off-screen chip scrolls into view', (tester) async {
      _useViewport(tester, 320, 568);
      await tester.pumpWidget(_wrap(const BadgesScreen(), badges: _all43));
      await _settle(tester);
      final special = find.text('Special');
      await tester.ensureVisible(special);
      await tester.tap(special);
      await _settle(tester);
      final r = tester.getRect(special);
      expect(r.right, lessThanOrEqualTo(320));
      expect(r.left, greaterThanOrEqualTo(0));
      // And back to All (scroll the row back first, as a user would).
      await tester.ensureVisible(find.text('All'));
      await _settle(tester);
      await tester.tap(find.text('All'));
      await _settle(tester);
      expect(tester.getRect(find.text('All')).left, greaterThanOrEqualTo(0));
    });
  });
}
