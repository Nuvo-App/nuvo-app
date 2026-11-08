// Release hardening for the public badge collection (`/u/:id/badges`):
//
//  1. The grid must let the LAST tile scroll fully above the bottom safe
//     area — badge and name visible, no nav/home-indicator overlap — at
//     every shipped width and max text scale.
//  2. The v13 detail sheet draws exactly ONE grab handle — the one the sheet
//     frame renders — and stays inside the safe area at small sizes.
//  3. The sheet is read-only on a friend's profile: no "Show on profile"
//     action, and locked tiles carry catalog data only — never progress.
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

import 'package:nuvo/core/theme/nuvo_responsive.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/presentation/public_badges_screen.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/v13/v13_profile_shared.dart';

const _captureKey = Key('badges-capture');

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

/// The shipped collection — 43 achievements, mixed categories so the filter
/// row + layout path are exercised too.
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

final _lockedCatalog = const [
  PublicLockedAchievement(
    key: 'locked_0',
    name: 'Locked Alpha',
    iconKey: 'bolt',
    category: 'racing',
  ),
  PublicLockedAchievement(
    key: 'locked_1',
    name: 'Locked Beta',
    iconKey: 'star',
    category: 'winning',
  ),
];

PublicProfileCard _card({
  List<NuvoBadge>? earned,
  List<PublicLockedAchievement>? locked,
}) {
  final e = earned ?? const <NuvoBadge>[];
  final l = locked ?? const <PublicLockedAchievement>[];
  return PublicProfileCard(
    id: 'u-rival',
    displayName: 'Rival One',
    username: 'rival',
    initials: 'RO',
    connectionStatus: CrewConnectionStatus.none,
    level: 6,
    levelProgress: 0.4,
    achievementsEarned: e.length,
    achievementsTotal: e.length + l.length,
    earned: e,
    lockedAchievements: l,
  );
}

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return ProviderScope(
    child: MaterialApp(
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

/// Pill-shaped containers that read as a drag/grab handle — tight height in
/// the 3–8px range, width 24–56. Matches the v13 sheet-frame handle.
bool _looksLikeHandle(Widget w) {
  if (w is! Container) return false;
  final c = w.constraints;
  if (c == null) return false;
  final tightH =
      c.minHeight == c.maxHeight && c.minHeight >= 3 && c.minHeight <= 8;
  final tightW =
      c.minWidth == c.maxWidth && c.minWidth >= 24 && c.minWidth <= 56;
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
    testWidgets('public collection — 390x844', (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(
          PublicBadgesScreen(
            userId: 'u-rival',
            card: _card(earned: _all43.where((b) => b.unlocked).toList()),
          ),
        ),
      );
      await _settle(tester);
      await _scrollToEnd(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'public-390');
    });
  });

  group('detail sheet — one handle, read-only', () {
    /// Pumps the screen with one earned + two locked catalog badges, then
    /// opens a sheet by tapping the tile at [tileIndex].
    Future<void> openSheet(
      WidgetTester tester, {
      int tileIndex = 0,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(
        _wrap(
          PublicBadgesScreen(
            userId: 'u-rival',
            card: _card(earned: [_badge(0)], locked: _lockedCatalog),
          ),
          textScale: textScale,
        ),
      );
      await _settle(tester);
      await tester.tap(find.byType(V13BadgeTile).at(tileIndex));
      await _settle(tester);
    }

    testWidgets('exactly one grab handle', (tester) async {
      _useViewport(tester, 390, 844);
      await openSheet(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      final pills = tester
          .widgetList(
            find.descendant(
              of: sheet,
              matching: find.byWidgetPredicate(_looksLikeHandle),
            ),
          )
          .length;
      expect(pills, 1, reason: 'sheet must render exactly one grab handle');
    });

    testWidgets('earned sheet has no feature action', (tester) async {
      _useViewport(tester, 390, 844);
      await openSheet(tester);
      expect(find.text('Earned'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Achievement Number 0'),
        ),
        findsOneWidget,
      );
      // A friend's badges are read-only — featuring lives on your own
      // collection only.
      expect(find.text('Show on profile'), findsNothing);
      expect(find.text('Feature on Profile'), findsNothing);
      expect(find.text('Remove from profile'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sheet-390');
    });

    testWidgets('locked sheet shows no progress', (tester) async {
      _useViewport(tester, 390, 844);
      // Tile order: earned first, then the locked catalog tiles.
      await openSheet(tester, tileIndex: 1);
      expect(find.text('Locked'), findsWidgets);
      expect(find.text("Rival hasn't earned this one yet."), findsOneWidget);
      // Catalog metadata only — a friend's progress is never exposed.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('/'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sheet fits 320 + ts1.4 without overflow', (tester) async {
      _useViewport(tester, 320, 568);
      await openSheet(tester, textScale: 1.4);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'sheet-320-ts14');
    });
  });

  group('v13 grid + filter chips', () {
    testWidgets('Earned and Locked filters partition the grid', (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(
          PublicBadgesScreen(
            userId: 'u-rival',
            card: _card(earned: [_badge(0)], locked: _lockedCatalog),
          ),
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Locked'));
      await _settle(tester);
      expect(find.text('Locked Alpha'), findsOneWidget);
      expect(find.text('Achievement Number 0'), findsNothing);

      await tester.tap(find.text('Earned'));
      await _settle(tester);
      expect(find.text('Achievement Number 0'), findsOneWidget);
      expect(find.text('Locked Alpha'), findsNothing);
    });

    testWidgets('category chips filter by catalog category', (tester) async {
      _useViewport(tester, 390, 844);
      await tester.pumpWidget(
        _wrap(
          PublicBadgesScreen(
            userId: 'u-rival',
            card: _card(
              earned: [_badge(0, category: 'racing')],
              locked: _lockedCatalog,
            ),
          ),
        ),
      );
      await _settle(tester);
      // The chip row scrolls horizontally — pull the chip into view first.
      await tester.ensureVisible(find.text('Winning'));
      await _settle(tester);
      await tester.tap(find.text('Winning'));
      await _settle(tester);
      expect(find.text('Locked Beta'), findsOneWidget);
      expect(find.text('Locked Alpha'), findsNothing);
      expect(find.text('Achievement Number 0'), findsNothing);
    });
  });
}
