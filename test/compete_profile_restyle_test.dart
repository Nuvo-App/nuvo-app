// Acceptance matrix for the Compete + Profile restyle.
//
// Invariants exercised: no RenderFlex overflow, no layout exceptions, key
// visual elements present — across the required fixture matrix:
//   Compete: 0/1/many races, long title, long activity, 1/many participants
//   Profile: long names, 0/many achievements, level 1 / double-digit level
//   Both:    320/375/390/430 widths, text scale 1.0/1.2/1.4, dark mode
//
// Captures:
//   flutter test test/compete_profile_restyle_test.dart \
//     --dart-define=NUVO_RESTYLE_CAPTURE=true
// writes tmp/restyle-<case>.png for visual review.
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
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

const _captureKey = Key('restyle-capture');

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

const _meLong = AuthUser(
  id: 'user-1',
  email: 'akshay@example.com',
  onboardingComplete: true,
  hasMemberPass: true,
  termsAccepted: true,
  fullName: 'Alexandria Montgomery-Santiago',
  username: 'averylongusername123',
  motionTrainingConsent: true,
);

RaceParticipant _p(String userId, String name, int value, {int? rank}) =>
    RaceParticipant(
      id: 'part-$userId',
      userId: userId,
      displayName: name,
      progressValue: value,
      progressPercent: value,
      rank: rank,
      joinedAt: '2026-01-01T00:00:00Z',
    );

Race _race({
  String id = 'race-1',
  String title = 'Pushup Race',
  String status = 'active',
  String? movement = 'Pushup',
  int? targetValue = 50,
  String? unit = 'reps',
  List<RaceParticipant>? participants,
  RaceViewerContext? viewerContext,
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
    viewerContext: viewerContext,
    participants:
        participants ??
        [
          _p('user-1', 'Akshay Sanjai', 39, rank: 2),
          _p('u-noah', 'Noah Reyes', 42, rank: 1),
          _p('u-3', 'Maya Chen', 11, rank: 3),
        ],
  );
}

/// One featured race in mid-flight — viewer chasing, rival ahead.
final _heroRace = _race(
  viewerContext: const RaceViewerContext(
    raceId: 'race-1',
    status: 'active',
    rank: 2,
    leaderUserId: 'u-noah',
    leaderScore: 42,
    viewerScore: 39,
    gapToLeader: 3,
    isMember: true,
  ),
);

final _manyRaces = [
  _heroRace,
  _race(
    id: 'race-2',
    title: 'First To 30 Squats',
    participants: [
      _p('user-1', 'Akshay Sanjai', 8, rank: 2),
      _p('u-4', 'Riley Park', 15, rank: 1),
    ],
  ),
  _race(
    id: 'race-3',
    title: 'First to Complete 1000 Jumping Jacks Before Friday Night',
    movement: 'Alternating Reverse Walking Lunges',
    targetValue: 999999,
    participants: [
      _p('user-1', 'Akshay Sanjai', 41, rank: 1),
      _p('u-noah', 'Noah Reyes', 32, rank: 2),
      _p('u-5', 'Sam Ortiz', 20, rank: 3),
      _p('u-6', 'Priya Shah', 12, rank: 4),
      _p('u-7', 'Bo Jackson', 4, rank: 5),
    ],
  ),
  _race(
    id: 'race-waiting',
    title: 'Solo Plank Race',
    movement: 'Plank',
    targetValue: 300,
    unit: 'seconds',
    participants: [_p('user-1', 'Akshay Sanjai', 0)],
  ),
  _race(
    id: 'race-fin-1',
    title: 'First To 10 Jumping Jacks',
    status: 'completed',
    targetValue: 10,
    participants: [
      _p('user-1', 'Akshay Sanjai', 10, rank: 1),
      _p('u-noah', 'Noah Reyes', 10, rank: 2),
    ],
  ),
  _race(
    id: 'race-fin-2',
    title: 'Weekend Golf',
    status: 'completed',
    targetValue: 72,
    unit: 'strokes',
    participants: [
      _p('user-1', 'Akshay Sanjai', 78, rank: 2),
      _p('u-noah', 'Noah Reyes', 74, rank: 1),
    ],
  ),
];

final _soloRace = _race(
  participants: [_p('user-1', 'Akshay Sanjai', 39, rank: 1)],
  viewerContext: const RaceViewerContext(
    raceId: 'race-1',
    status: 'active',
    rank: 1,
    viewerScore: 39,
    isLeading: true,
    isMember: true,
  ),
);

// ── Progression fixtures ─────────────────────────────────────────────────────

const _badgeFirstMove = NuvoBadge(
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
);

const _badgeFirstW = NuvoBadge(
  unlockId: 'u-first-w',
  type: 'achievement',
  key: 'first_w',
  name: 'First W',
  requiredLevel: 1,
  unlocked: true,
  featured: true,
  category: 'winning',
  iconKey: 'trophy_1',
  statKey: 'wins',
  threshold: 1,
  progressValue: 1,
);

const _badgePb = NuvoBadge(
  unlockId: 'u-pb',
  type: 'achievement',
  key: 'personal_best',
  name: 'Personal Best',
  requiredLevel: 1,
  unlocked: true,
  featured: true,
  category: 'performance',
  iconKey: 'spark',
  statKey: 'pbs',
  threshold: 1,
  progressValue: 1,
);

const _hatTrick = NuvoBadge(
  unlockId: 'u-hat-trick',
  type: 'achievement',
  key: 'hat_trick',
  name: 'Hat Trick',
  description: 'Win 3 races.',
  requiredLevel: 1,
  unlocked: false,
  featured: false,
  category: 'winning',
  iconKey: 'trophy_3',
  statKey: 'wins',
  threshold: 3,
  progressValue: 2,
);

const _unlock = NuvoUnlockRef(
  unlockId: 'u-clap',
  type: 'capability',
  key: 'reaction_clap',
  name: 'Clap reaction',
  level: 9,
);

const _progression = NuvoProgression(
  level: 8,
  totalXp: 1410,
  currentLevelXp: 40,
  nextLevelXp: 180,
  progress: 0.25,
  xpToNext: 140,
  lastSeenLevel: 8,
  featuredSlots: 3,
  achievementsEarned: 4,
  achievementsTotal: 7,
  nextUnlock: _unlock,
  nextAchievement: _hatTrick,
  featuredBadges: [_badgeFirstW, _badgeFirstMove, _badgePb],
);

const _progressionLevel1 = NuvoProgression(
  level: 1,
  totalXp: 0,
  currentLevelXp: 0,
  nextLevelXp: 60,
  progress: 0,
  xpToNext: 60,
  lastSeenLevel: 1,
  featuredSlots: 1,
  achievementsEarned: 0,
  achievementsTotal: 7,
  nextUnlock: _unlock,
  nextAchievement: _badgeFirstMove,
);

const _progressionBig = NuvoProgression(
  level: 27,
  totalXp: 6120,
  currentLevelXp: 196,
  nextLevelXp: 210,
  progress: 0.93,
  xpToNext: 14,
  lastSeenLevel: 27,
  featuredSlots: 3,
  achievementsEarned: 21,
  achievementsTotal: 44,
  nextAchievement: _hatTrick,
  featuredBadges: [_badgeFirstW, _badgeFirstMove, _badgePb],
);

// ── Harness ──────────────────────────────────────────────────────────────────

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo(this.user) : super(AuthApi(), SecureTokenStore());
  final AuthUser user;
  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(user);
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

class _SeededProgression extends ProgressionController {
  _SeededProgression(this._p)
    : super(
        ProgressionApi(),
        SecureTokenStore(),
        isPresentationDemo: () => false,
      ) {
    state = AsyncValue.data(_p);
  }
  final NuvoProgression _p;
  @override
  Future<List<NuvoBadge>> getBadges() async => const [];
}

Widget _app({
  bool dark = false,
  double textScale = 1.0,
  AuthUser user = _me,
  List<Race> races = const [],
  NuvoProgression progression = _progression,
  required Widget home,
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo(user)),
      ),
      raceRepositoryProvider.overrideWithValue(_StubRaceRepo(races)),
      raceControllerProvider.overrideWith((ref) => _SeededRaces(races)),
      progressionControllerProvider.overrideWith(
        (ref) => _SeededProgression(progression),
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
      home: home,
    ),
  );
}

const _sizes = [
  ('320x568', 320.0, 568.0),
  ('375x667', 375.0, 667.0),
  ('390x844', 390.0, 844.0),
  ('430x932', 430.0, 932.0),
];

void _useViewport(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
  });
}

/// Bounded settle — surfaces animate, so pumpAndSettle would time out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('NUVO_RESTYLE_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/restyle-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget app,
  String name, {
  void Function()? then,
}) async {
  // Record full error details — the binding truncates takeException() and
  // swallows prints, so the overflow diagnosis rides in the expect reason.
  final details = <FlutterErrorDetails>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    details.add(d);
    prev?.call(d);
  };
  try {
    await tester.pumpWidget(app);
    await _settle(tester);
    then?.call();
  } finally {
    FlutterError.onError = prev;
  }
  final e = tester.takeException();
  expect(
    e,
    isNull,
    reason:
        '$name\n'
        '${details.map((d) => d.toDiagnosticsNode().toStringDeep(minLevel: DiagnosticLevel.info)).join('\n')}',
  );
  await _capture(tester, name);
}

void main() {
  ByteData? fontBytes;
  ByteData? captureManifest;
  setUpAll(() async {
    // Real Manrope metrics — the Ahem fallback over-measures text. Same
    // mechanism as responsive_sweep_test: fake asset-manifest entries plus
    // weight-named families so google_fonts resolves locally and capture
    // runs never hit the network.
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
  setUp(() {
    if (fontBytes == null || captureManifest == null) return;
    final bytes = fontBytes!;
    final manifest = captureManifest!;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') return manifest;
          if (key.startsWith('test/fonts/Manrope')) return bytes;
          return null;
        });
  });

  group('Compete restyle', () {
    testWidgets('hero race dominates — anchor, named marks, stakes', (
      tester,
    ) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(races: [_heroRace], home: const CompeteScreen()),
        'compete-hero-390',
      );
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
      // The named lane — viewer mark, rival mark, goal ring label.
      expect(find.text('You 39'), findsOneWidget);
      expect(find.text('Noah 42'), findsOneWidget);
      expect(find.text('Goal 50'), findsOneWidget);
      // Stakes line from canonical viewerContext.
      expect(find.text('3 reps to take 1st'), findsOneWidget);
      // Primary/secondary actions in the header.
      expect(
        find.descendant(
          of: find.byType(Row),
          matching: find.byType(NuvoPrimaryButton),
        ),
        findsWidgets,
      );
      expect(find.byType(NuvoOutlineButton), findsOneWidget);
    });

    testWidgets('leading reads as a lead, not a chase', (tester) async {
      _useViewport(tester, 390, 844);
      final leading = _race(
        viewerContext: const RaceViewerContext(
          raceId: 'race-1',
          status: 'active',
          rank: 1,
          leaderUserId: 'user-1',
          leaderScore: 45,
          viewerScore: 45,
          gapToNextRank: 5,
          isLeading: true,
          isMember: true,
        ),
        participants: [
          _p('user-1', 'Akshay Sanjai', 45, rank: 1),
          _p('u-noah', 'Noah Reyes', 40, rank: 2),
        ],
      );
      await _pump(
        tester,
        _app(races: [leading], home: const CompeteScreen()),
        'compete-leading-390',
      );
      // Both flip faces stay mounted for sizing, so stakes text may
      // appear twice — presence is what matters.
      expect(find.text('You lead by 5 reps'), findsWidgets);
      expect(find.text('1st'), findsWidgets);
    });

    for (final (name, w, h) in _sizes) {
      testWidgets('empty state $name', (tester) async {
        _useViewport(tester, w, h);
        await _pump(
          tester,
          _app(home: const CompeteScreen()),
          'compete-empty-$name',
        );
        expect(find.text('Your races will live here.'), findsOneWidget);
        // Header Start + the empty-state's own Start a race CTA.
        expect(find.byType(NuvoPrimaryButton), findsWidgets);
        expect(find.byType(NuvoOutlineButton), findsWidgets);
      });

      testWidgets('one race $name', (tester) async {
        _useViewport(tester, w, h);
        await _pump(
          tester,
          _app(races: [_heroRace], home: const CompeteScreen()),
          'compete-one-$name',
        );
        expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
        expect(find.textContaining('Your races'), findsNothing);
      });

      testWidgets('many races $name', (tester) async {
        _useViewport(tester, w, h);
        await _pump(
          tester,
          _app(races: _manyRaces, home: const CompeteScreen()),
          'compete-many-$name',
        );
        expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
        expect(find.textContaining('Your races'), findsOneWidget);
        // Sections below the fold exist in the sliver's element tree but
        // stay unlaid-out until scrolled to — assert presence with
        // skipOffstage off, then drag to the bottom to exercise the whole
        // scroll path (throws if content overflows the list).
        for (final label in ['Waiting for crew', 'Finished', 'Quick starts']) {
          expect(
            find.text(label, skipOffstage: false),
            findsOneWidget,
            reason: 'missing section "$label"',
          );
        }
        final pageScroll = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        );
        for (var i = 0; i < 12; i++) {
          await tester.drag(pageScroll, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(find.text('Quick starts'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('flip still works — front/back faces', (tester) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(races: [_heroRace], home: const CompeteScreen()),
        'compete-flip-front-390',
      );
      await tester.tap(find.text('Updates ↻'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('RACE STATUS'), findsWidgets);
      await _capture(tester, 'compete-flip-back-390');
    });

    testWidgets('dark mode 390', (tester) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(dark: true, races: _manyRaces, home: const CompeteScreen()),
        'compete-dark-390',
      );
      expect(find.byType(NuvoFeaturedRaceCard), findsOneWidget);
    });

    for (final scale in [1.2, 1.4]) {
      testWidgets('text scale $scale at 320x568', (tester) async {
        _useViewport(tester, 320, 568);
        await _pump(
          tester,
          _app(
            textScale: scale,
            races: _manyRaces,
            home: const CompeteScreen(),
          ),
          'compete-ts${scale.toStringAsFixed(1).replaceAll('.', '')}-320',
        );
      });
    }

    testWidgets('solo race — no fabricated rival mark', (tester) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(races: [_soloRace], home: const CompeteScreen()),
        'compete-solo-390',
      );
      expect(find.text('You 39'), findsOneWidget);
      expect(find.text('Noah 42'), findsNothing);
      expect(find.text('Goal 50'), findsOneWidget);
    });
  });

  group('Profile restyle', () {
    for (final (name, w, h) in _sizes) {
      testWidgets('identity + progression $name', (tester) async {
        _useViewport(tester, w, h);
        await _pump(
          tester,
          _app(races: _manyRaces, home: const ProfileScreen()),
          'profile-$name',
        );
        expect(find.text('Profile'), findsOneWidget);
        // Level is the hero — big number beside the LEVEL label.
        expect(find.textContaining('LEVEL', findRichText: true), findsWidgets);
        expect(find.textContaining('LEVEL 8', findRichText: true), findsWidgets);
        expect(find.text('140 XP to Level 9'), findsOneWidget);
        expect(find.text('NEXT UNLOCK'), findsOneWidget);
        expect(find.text('Clap reaction'), findsOneWidget);
        // Edit anchored to the identity row.
        expect(
          find.bySemanticsLabel('Edit profile'),
          findsOneWidget,
        );
        expect(find.text('Achievements'), findsOneWidget);
        expect(find.text('NEXT UP'), findsOneWidget);
        expect(find.text('Hat Trick'), findsOneWidget);
        expect(find.text('ONE MORE WIN'), findsOneWidget);
      });
    }

    testWidgets('long names + double-digit level at 320', (tester) async {
      _useViewport(tester, 320, 568);
      await _pump(
        tester,
        _app(
          user: _meLong,
          races: _manyRaces,
          progression: _progressionBig,
          home: const ProfileScreen(),
        ),
        'profile-long-320',
      );
      expect(find.textContaining('LEVEL', findRichText: true), findsWidgets);
      expect(find.textContaining('LEVEL 27', findRichText: true), findsWidgets);
      expect(find.text('14 XP to Level 28'), findsOneWidget);
    });

    testWidgets('level 1 + zero achievements at 390', (tester) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(
          progression: _progressionLevel1,
          home: const ProfileScreen(),
        ),
        'profile-level1-390',
      );
      expect(find.textContaining('LEVEL', findRichText: true), findsWidgets);
      expect(find.text('60 XP to Level 2'), findsOneWidget);
    });

    for (final scale in [1.2, 1.4]) {
      testWidgets('text scale $scale at 320x568', (tester) async {
        _useViewport(tester, 320, 568);
        await _pump(
          tester,
          _app(
            textScale: scale,
            user: _meLong,
            races: _manyRaces,
            progression: _progressionBig,
            home: const ProfileScreen(),
          ),
          'profile-ts${scale.toStringAsFixed(1).replaceAll('.', '')}-320',
        );
      });
    }

    testWidgets('dark mode 390', (tester) async {
      _useViewport(tester, 390, 844);
      await _pump(
        tester,
        _app(dark: true, races: _manyRaces, home: const ProfileScreen()),
        'profile-dark-390',
      );
      expect(find.textContaining('LEVEL', findRichText: true), findsWidgets);
    });
  });
}
