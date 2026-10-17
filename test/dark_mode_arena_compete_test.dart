import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/arena/presentation/arena_screen_fixed.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'user-1',
        email: 'test@getnuvo.net',
        fullName: 'Test User',
        username: 'testuser',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _race(
  String id, {
  required int mine,
  List<int> others = const [10],
  String status = 'active',
}) {
  RaceParticipant p(String uid, int v) => RaceParticipant(
        id: 'p-$uid',
        userId: uid,
        displayName: uid == 'user-1' ? 'Test User' : 'Racer $uid',
        progressValue: v,
        progressPercent: v,
        joinedAt: '2026-01-01T00:00:00Z',
      );
  return Race(
    id: id,
    creatorId: 'user-1',
    title: 'Race $id',
    goalType: 'first_to_goal',
    targetValue: 100,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: [
      p('user-1', mine),
      for (var i = 0; i < others.length; i++) p('o$i', others[i]),
    ],
  );
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Nearest opaque background behind [e], blending translucent fills.
Color _backgroundFor(Element e, Color fallback) {
  final layers = <Color>[];
  var result = fallback;
  var found = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? col;
    if (w is DecoratedBox) {
      final d = w.decoration;
      col = d is BoxDecoration ? d.color : null;
    } else if (w is ColoredBox) {
      col = w.color;
    } else if (w is Material) {
      col = w.color;
    }
    if (col != null && col.a > 0) {
      layers.add(col);
      if (col.a >= 0.999) {
        result = col;
        found = true;
        return false;
      }
    }
    return true;
  });
  if (!found) result = fallback;
  for (final l in layers.reversed) {
    if (l.a < 0.999) result = _over(l, result);
  }
  return result;
}

/// Every visible text run with its effective colour vs. its backdrop.
List<({String text, double ratio})> textContrasts(
  WidgetTester tester,
  Color pageColor, {
  double minSize = 0,
}) {
  final out = <({String text, double ratio})>[];
  for (final el in find.byType(RichText).evaluate()) {
    final rt = el.widget as RichText;
    final span = rt.text;
    final plain = span.toPlainText();
    if (plain.trim().isEmpty) continue;
    // Avatar initials sit on fixed saturated avatar fills (same in both
    // themes) and icon glyphs are private-use code points, not copy.
    if (plain.trim().length <= 2) continue;
    final style = span is TextSpan ? span.style : null;
    final color = style?.color;
    if (color == null) continue;
    final bg = _backgroundFor(el, pageColor);
    out.add((text: plain, ratio: contrast(_over(color, bg), bg)));
  }
  return out;
}

void _expectReadable(
  WidgetTester tester,
  Color page,
  String where, {
  double min = 4.5,
}) {
  final bad = textContrasts(tester, page).where((t) => t.ratio < min).toList();
  expect(
    bad,
    isEmpty,
    reason:
        '$where low contrast: ${bad.map((b) => '"${b.text}" ${b.ratio.toStringAsFixed(2)}').join(', ')}',
  );
}

void main() {
  const sizes = <String, Size>{
    '390x844': Size(390, 844),
    '320x568': Size(320, 568),
  };

  Future<void> pumpArena(WidgetTester tester, Size size, ThemeData theme) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: 47, bottom: size.width < 340 ? 0 : 34);
    tester.view.viewPadding = tester.view.padding;
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
              builder: (c, s) => const ArenaScreen(preview: true),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode:
              theme.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCompete(WidgetTester tester, Size size, ThemeData theme) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final races = [
      _race('lead', mine: 50),
      _race('chase', mine: 5),
      _race('idle', mine: 0, others: [0]),
      _race('done', mine: 100, status: 'completed'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          raceRepositoryProvider.overrideWithValue(_StubRaceRepo(races)),
          authControllerProvider
              .overrideWith((ref) => AuthController(_FakeAuthRepo())),
        ],
        child: MaterialApp(theme: theme, home: const CompeteScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final e in sizes.entries) {
    testWidgets('Arena dark ${e.key}: no exceptions, text readable',
        (tester) async {
      await pumpArena(tester, e.value, AppTheme.dark());
      expect(tester.takeException(), isNull);
      _expectReadable(tester, NuvoThemeColors.dark.page, 'Arena dark ${e.key}');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectReadable(
          tester, NuvoThemeColors.dark.page, 'Arena dark scrolled ${e.key}');
    });

    testWidgets('Compete dark ${e.key}: no exceptions, text readable',
        (tester) async {
      await pumpCompete(tester, e.value, AppTheme.dark());
      expect(tester.takeException(), isNull);
      expect(find.byType(RaceStatusPill), findsWidgets);
      _expectReadable(
          tester, NuvoThemeColors.dark.page, 'Compete dark ${e.key}');
    });

    testWidgets('Compete light ${e.key}: no exceptions', (tester) async {
      await pumpCompete(tester, e.value, AppTheme.light());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RaceStatusPill tones are >= 4.5:1 in dark and light',
      (tester) async {
    for (final theme in [AppTheme.dark(), AppTheme.light()]) {
      await tester.pumpWidget(const SizedBox());
      final page = theme.extension<NuvoThemeColors>()!.page;
      final surface = theme.extension<NuvoThemeColors>()!.surface;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Container(
              color: surface,
              child: Column(
                children: [
                  for (final t in RaceRowTone.values)
                    RaceStatusPill(label: 'Pill ${t.name}', tone: t),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final t in RaceRowTone.values) {
        final f = find.text('Pill ${t.name}');
        final rich = tester.widget<RichText>(
          find.descendant(of: f, matching: find.byType(RichText)).first,
        );
        final fg = (rich.text as TextSpan).style!.color!;
        final bg = _backgroundFor(tester.element(f), page);
        expect(
          contrast(_over(fg, bg), bg),
          greaterThanOrEqualTo(4.5),
          reason: '${t.name} on ${theme.brightness}',
        );
      }
    }
  });

  test('Arena hero surface is a visible step lighter than the page in dark', () {
    final dark = NuvoThemeColors.dark;
    final hero = arenaHeroSurface(Brightness.dark, dark.surface);
    expect(_lum(hero), greaterThan(_lum(dark.page)));
    expect(contrast(hero, dark.page), greaterThan(1.25));
    expect(_lum(hero), greaterThan(_lum(dark.surface)));
    // Light mode unchanged.
    expect(
      arenaHeroSurface(Brightness.light, NuvoThemeColors.light.surface),
      NuvoThemeColors.light.surface,
    );
  });
}
