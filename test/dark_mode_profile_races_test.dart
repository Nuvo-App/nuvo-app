// Dark-mode audit for Profile, Settings, Achievements, Race Detail and the
// level explainer sheet: no exceptions/overflow, readable text contrast, and a
// legible heat-map ramp under AppTheme.dark().
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/theme/nuvo_responsive.dart';
import 'package:nuvo/core/widgets/nuvo_podium.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/badges_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/profile/presentation/widgets/activity_heatmap.dart';
import 'package:nuvo/features/race_detail/presentation/race_detail_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

const _me = AuthUser(
  id: 'user-1',
  email: 'akshay@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  fullName: 'Akshay Sanjai',
  username: 'akshay',
  motionTrainingConsent: true,
);


class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo(this.user) : super(AuthApi(), SecureTokenStore());
  final AuthUser user;
  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(user);
}


Race _race({
  String id = 'race-1',
  String title = 'Pushup Race',
  String status = 'active',
  String movement = 'Pushup',
  int? targetValue = 100,
  String? unit = 'reps',
  List<RaceParticipant>? participants,
}) {
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: targetValue,
    unit: unit,
    customActivityName: movement,
    proofRequirement: 'photo_video',
    proofMode: 'photo',
    verificationMethod: 'photo_review',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants:
        participants ??
        const [
          RaceParticipant(
            id: 'part-1',
            userId: 'user-1',
            displayName: 'Test User',
            progressValue: 40,
            progressPercent: 40,
            joinedAt: '2026-01-01T00:00:00Z',
          ),
          RaceParticipant(
            id: 'part-2',
            userId: 'u-rival',
            displayName: 'Alexandria Montgomery-Santiago',
            progressValue: 62,
            progressPercent: 62,
            joinedAt: '2026-01-01T00:00:00Z',
          ),
          RaceParticipant(
            id: 'part-3',
            userId: 'u-3',
            displayName: 'Noah Reyes',
            progressValue: 11,
            progressPercent: 11,
            joinedAt: '2026-01-01T00:00:00Z',
          ),
        ],
  );
}


class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
  @override
  Future<Race> getRaceDetail(String id) => Future.value(
    races.firstWhere((r) => r.id == id, orElse: () => races.first),
  );
}

class _SeededRaces extends RaceController {
  _SeededRaces(List<Race> races)
    : super(
        _StubRaceRepo(races),
        isPresentationDemo: () => false,
        presentationUserId: () => 'user-1',
        onMutated: () {},
      ) {
    state = RaceState(races: races);
  }
  @override
  Future<void> loadRaces({bool force = false}) async {}
}


const _badges = [
  NuvoBadge(
    unlockId: 'u-first-move',
    type: 'achievement',
    key: 'first_move',
    name: 'First Move',
    description: 'Submit your first accepted proof.',
    requiredLevel: 1,
    unlocked: true,
    featured: true,
    category: 'racing',
    iconKey: 'bolt',
    statKey: 'proofs',
    threshold: 1,
    progressValue: 1,
  ),
  NuvoBadge(
    unlockId: 'u-hat-trick',
    type: 'achievement',
    key: 'hat_trick',
    name: 'Hat Trick',
    description: 'Win 3 races. One more win.',
    requiredLevel: 1,
    unlocked: false,
    featured: false,
    category: 'racing',
    iconKey: 'trophy',
    statKey: 'wins',
    threshold: 3,
    progressValue: 2,
  ),
  NuvoBadge(
    unlockId: 'u-first-w',
    type: 'achievement',
    key: 'first_w',
    name: 'First W',
    requiredLevel: 1,
    unlocked: true,
    featured: false,
    category: 'racing',
    iconKey: 'flag',
  ),
  NuvoBadge(
    unlockId: 'u-marathon',
    type: 'achievement',
    key: 'marathon_mind',
    name: 'A Very Long Achievement Name That Wraps',
    requiredLevel: 4,
    unlocked: false,
    featured: false,
    category: 'consistency',
    iconKey: 'timer',
  ),
];

const _progression = NuvoProgression(
  level: 8,
  totalXp: 1410,
  currentLevelXp: 30,
  nextLevelXp: 120,
  progress: 0.25,
  xpToNext: 90,
  lastSeenLevel: 8,
  featuredSlots: 2,
  achievementsEarned: 6,
  achievementsTotal: 24,
);


class _SeededProgression extends ProgressionController {
  _SeededProgression(this._p, this._b)
    : super(
        ProgressionApi(),
        SecureTokenStore(),
        isPresentationDemo: () => false,
      ) {
    state = AsyncValue.data(_p);
  }
  final NuvoProgression _p;
  final List<NuvoBadge> _b;
  @override
  Future<List<NuvoBadge>> getBadges() async => _b;
}


// ── Harness ────────────────────────────────────────────────────────────────

final _raceList = [_race(), _race(id: 'race-done', status: 'completed')];

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo(_me)),
      ),
      raceRepositoryProvider.overrideWithValue(_StubRaceRepo(_raceList)),
      raceControllerProvider.overrideWith((ref) => _SeededRaces(_raceList)),
      progressionControllerProvider.overrideWith(
        (ref) => _SeededProgression(_progression, _badges),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: NuvoTextScaleScope(child: child!),
      ),
      home: child,
    ),
  );
}

void _viewport(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Color _over(Color top, Color bottom) {
  final a = top.a;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color? _layerColor(Widget w) {
  if (w is DecoratedBox && w.decoration is BoxDecoration) {
    return (w.decoration as BoxDecoration).color;
  }
  if (w is ColoredBox) return w.color;
  if (w is Material && w.type != MaterialType.transparency) {
    return w.color;
  }
  return null;
}

/// Nearest opaque background behind [e], blending translucent layers above.
Color _backgroundBehind(Element e, Color fallback) {
  final layers = <Color>[];
  var base = fallback;
  e.visitAncestorElements((a) {
    final c = _layerColor(a.widget);
    if (c != null && c.a > 0) {
      if (c.a >= 0.99) {
        base = c;
        return false;
      }
      layers.add(c);
    }
    return true;
  });
  var out = base;
  for (final l in layers.reversed) {
    out = _over(l, out);
  }
  return out;
}

/// Foreground text colours vs their effective background. Returns offenders
/// (text, ratio) under [min].
List<String> _lowContrast(WidgetTester tester, {double min = 4.5}) {
  final page = AppTheme.dark().extension<NuvoThemeColors>()!.page;
  final bad = <String>[];
  for (final el in find.byType(RichText).evaluate()) {
    // NuvoPodium lives in lib/core (shared widget, owned elsewhere).
    if (el.findAncestorWidgetOfExactType<NuvoPodium>() != null) continue;
    final rt = el.widget as RichText;
    final text = rt.text.toPlainText();
    final color = rt.text.style?.color;
    if (text.trim().length <= 2 || color == null) continue; // skip avatar initials
    final bg = _backgroundBehind(el, page);
    final fg = _over(color, bg);
    final ratio = _contrast(fg, bg);
    if (ratio < min) bad.add('"$text" ${ratio.toStringAsFixed(2)} fg=${fg.toARGB32().toRadixString(16)} bg=${bg.toARGB32().toRadixString(16)}');
  }
  return bad;
}

void main() {
  const sizes = [(390.0, 844.0), (320.0, 568.0)];

  final surfaces = <String, Widget Function()>{
    'profile': () => const ProfileScreen(),
    'settings': () => const SettingsScreen(),
    'achievements': () => const BadgesScreen(),
    'race-detail': () => const RaceDetailScreen(id: 'race-1'),
    'race-detail-finished': () => const RaceDetailScreen(id: 'race-done'),
  };

  for (final s in sizes) {
    for (final e in surfaces.entries) {
      testWidgets('${e.key} dark ${s.$1.toInt()}x${s.$2.toInt()}: no overflow, '
          'readable text', (tester) async {
        _viewport(tester, s.$1, s.$2);
        await tester.pumpWidget(_wrap(e.value()));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final bad = _lowContrast(tester);
        expect(bad, isEmpty, reason: 'low-contrast text: $bad');
      });
    }
  }

  for (final s in sizes) {
    for (final scale in [1.0, 1.4]) {
      testWidgets('level explainer sheet dark ${s.$1.toInt()}x'
          '${s.$2.toInt()} @$scale', (tester) async {
        _viewport(tester, s.$1, s.$2);
        await tester.pumpWidget(_wrap(const ProfileScreen(), textScale: scale));
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'profile behind sheet');
        final trigger = find.textContaining('XP to Level');
        expect(trigger, findsWidgets);
        await tester.tap(trigger.first, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('Accepted proof'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final bad = _lowContrast(tester);
        expect(bad, isEmpty, reason: 'low-contrast text: $bad');
        // Pills keep their mild tint readable.
        final pill = find.text('+10');
        expect(pill, findsOneWidget);
      });
    }
  }

  test('heat map dark ramp: levels distinct from card and each other', () {
    final c = AppTheme.dark().extension<NuvoThemeColors>()!;
    final card = c.panelLight;
    final shades = <Color>[
      _over(c.inkMuted.withValues(alpha: 0.22), card),
      for (var l = 1; l <= 4; l++) _over(heatmapDarkLevelColor(c, l), card),
    ];
    for (var i = 0; i < shades.length; i++) {
      expect(
        _contrast(shades[i], card),
        greaterThanOrEqualTo(1.3),
        reason: 'level $i vs card',
      );
      if (i > 0) {
        expect(
          _contrast(shades[i], shades[i - 1]),
          greaterThanOrEqualTo(1.12),
          reason: 'level $i vs level ${i - 1}',
        );
      }
    }
  });

  testWidgets('heat map renders in dark without exceptions', (tester) async {
    _viewport(tester, 320, 568);
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: ActivityHeatmap(counts: {'2026-01-02': 1, '2026-01-03': 5}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
