// Repo-wide responsive sweep for surfaces outside the dedicated viewport
// suites (auth/onboarding/compete/arena/verify/submit-proof/main-shell are
// covered by layout_* / responsive_viewport / first_viewport_contract).
// The invariant: no RenderFlex overflow, no clipped primary controls, no
// layout exceptions — at compact/standard/large widths, short and tall
// heights, 1.0–1.4 text scale, and with the software keyboard up.
//
// Run captures with:
//   flutter test test/responsive_sweep_test.dart \
//     --dart-define=NUVO_SWEEP_CAPTURE=true
// to write tmp/sweep-<surface>-<w>x<h>.png for review.
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
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/crew/presentation/public_badges_screen.dart';
import 'package:nuvo/features/crew/presentation/public_profile_screen.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/core/widgets/nuvo_confirm_dialog.dart';
import 'package:nuvo/features/notifications/presentation/notifications_screen.dart';
import 'package:nuvo/features/profile/presentation/edit_profile_screen.dart';
import 'package:nuvo/features/profile/presentation/widgets/level_up_dialog.dart';
import 'package:nuvo/features/races/presentation/custom_pose/teach_movement_screen.dart';
import 'package:nuvo/features/races/presentation/race_composer_screen.dart';
import 'package:nuvo/features/social/presentation/my_qr_sheet.dart';
import 'package:nuvo/features/social/presentation/race_share_sheet.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/badges_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/race_detail/presentation/race_detail_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/board_moved_screen.dart';
import 'package:nuvo/features/races/presentation/invite_crew_screen.dart';
import 'package:nuvo/features/races/presentation/join_race_screen.dart';
import 'package:nuvo/features/races/presentation/proof_review_screen.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/race_settings_screen.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/add_crew_screen.dart';
import 'package:nuvo/features/social/presentation/invite_screen.dart';
import 'package:nuvo/features/social/presentation/my_nuvo_screen.dart';
import 'package:nuvo/features/social/social_providers.dart';

const _captureKey = Key('sweep-capture');

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

// Dynamic-data torture: worst-case identity strings the sweep reuses.
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

final _races = [
  _race(),
  _race(
    id: 'race-long',
    title: 'First to Complete 1000 Jumping Jacks Before Friday Night',
    movement: 'Alternating Reverse Walking Lunges',
    targetValue: 999999,
    unit: 'reps',
  ),
];

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

const _progressionTorture = NuvoProgression(
  level: 999,
  totalXp: 999999,
  currentLevelXp: 9999,
  nextLevelXp: 99999,
  progress: 0.5,
  xpToNext: 90000,
  lastSeenLevel: 999,
  featuredSlots: 3,
  achievementsEarned: 44,
  achievementsTotal: 44,
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

const _rival = PublicProfileCard(
  id: 'u-rival',
  displayName: 'Alexandria Montgomery-Santiago',
  username: 'averylongusername123',
  initials: 'AM',
  connectionStatus: CrewConnectionStatus.connected,
  level: 999,
  levelProgress: 0.62,
  achievementsEarned: 12,
  achievementsTotal: 44,
  featured: [
    PublicFeaturedBadge(unlockId: 'b1', key: 'first_move', name: 'First Move'),
    PublicFeaturedBadge(unlockId: 'b2', key: 'hat_trick', name: 'Hat Trick'),
  ],
  racesFinished: 20,
  racesWon: 6,
  racesWithYou: PublicRacesWithYou(total: 4, viewerWins: 1, targetWins: 3),
);

class _StubCrewRepo extends CrewRepository {
  _StubCrewRepo({this.card}) : super(CrewApi(), SecureTokenStore(), AuthApi());
  final PublicProfileCard? card;
  @override
  Future<List<PublicUser>> getCrew() async => const [];
  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();
  @override
  Future<List<CrewSearchResult>> search(String query) async => const [];
  @override
  Future<PublicProfileCard> getUser(String userId) async => card ?? _rival;
}

final _inboxItems = [
  NuvoNotification(
    id: 'n1',
    category: 'race_result',
    title: 'Proof accepted',
    body: '+10 XP — the board moved.',
    createdAt: DateTime(2026, 1, 2, 9),
    read: false,
    actorName: 'Shresh Khadka',
  ),
  NuvoNotification(
    id: 'n2',
    category: 'crew_request',
    title: 'Crew request',
    body: 'wants to pull you into their crew',
    createdAt: DateTime(2026, 1, 2, 8),
    read: false,
    actorName: 'Alexandria Montgomery-Santiago',
  ),
  NuvoNotification(
    id: 'n3',
    category: 'race_invite',
    title: 'Race invite',
    body:
        'First to Complete 1000 Jumping Jacks Before Friday Night — '
        'a very long notification body that keeps going to exercise the '
        'row layout under realistic worst-case copy length.',
    createdAt: DateTime(2026, 1, 1, 22),
    read: true,
    actorName: 'Noah Reyes',
  ),
];

class _FakeNotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: [], unreadCount: 0);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

class _Inbox extends NotificationController {
  _Inbox(List<NuvoNotification> items) : super(_FakeNotifRepo()) {
    state = NotificationState(
      items: items,
      unreadCount: items.where((n) => !n.read).length,
    );
  }
  @override
  Future<void> load({bool force = true}) async {}
}

class _StubInviteRepo extends InviteRepository {
  _StubInviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintMyCrewInvite() async => const MintedInvite(
    token: 'tok',
    url: 'https://nuvo.app/i/tok',
    code: 'ABC-123',
  );
  @override
  Future<MintedInvite> mintRaceInvite(String raceId) async =>
      const MintedInvite(
        token: 'tok-race',
        url: 'https://nuvo.app/i/tok-race',
        code: 'RACE-42',
        kind: 'race_join',
      );
  @override
  Future<InvitePreview> preview(String token) async => const InvitePreview(
    status: InviteStatus.active,
    kind: 'crew_connect',
    requiresAuth: false,
    person: PersonInviteCard(
      userId: 'u-rival',
      displayName: 'Alexandria Montgomery-Santiago',
      username: 'averylongusername123',
    ),
  );
}

class _Harness {
  _Harness({
    this.dark = false,
    this.textScale = 1.0,
    this.user = _me,
    this.races = const [],
    this.progression = _progression,
    this.inbox = const [],
  }) : rival = _rival,
       badges = _badges;
  final bool dark;
  final double textScale;
  final AuthUser user;
  final List<Race> races;
  final PublicProfileCard rival;
  final NuvoProgression progression;
  final List<NuvoBadge> badges;
  final List<NuvoNotification> inbox;

  Widget wrap(Widget child) {
    final crewRepo = _StubCrewRepo(card: rival);
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(_FakeAuthRepo(user)),
        ),
        raceRepositoryProvider.overrideWithValue(_StubRaceRepo(races)),
        raceControllerProvider.overrideWith((ref) => _SeededRaces(races)),
        progressionControllerProvider.overrideWith(
          (ref) => _SeededProgression(progression, badges),
        ),
        crewRepositoryProvider.overrideWithValue(crewRepo),
        crewControllerProvider.overrideWith((ref) => CrewController(crewRepo)),
        inviteRepositoryProvider.overrideWithValue(_StubInviteRepo()),
        notificationControllerProvider.overrideWith((ref) => _Inbox(inbox)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        // The OS-scale simulation mirrors production: the raw scaler is the
        // device setting and NuvoTextScaleScope applies the app clamp, exactly
        // like app.dart's builder chain.
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
}

final _surfaces = <String, Widget Function(_Harness)>{
  'profile': (_) => const ProfileScreen(),
  'badges': (_) => const BadgesScreen(),
  'public-profile': (_) => const PublicProfileScreen(userId: 'u-rival'),
  'public-badges': (h) =>
      PublicBadgesScreen(userId: 'u-rival', card: h.rival),
  'race-detail': (_) => const RaceDetailScreen(id: 'race-1'),
  'race-detail-long': (_) => const RaceDetailScreen(id: 'race-long'),
  'my-nuvo': (_) => const MyNuvoScreen(),
  'add-crew': (_) => const AddCrewScreen(),
  'join-race': (_) => const JoinRaceScreen(),
  'invite-crew': (_) => const InviteCrewScreen(raceId: 'race-1'),
  'race-settings': (_) => const RaceSettingsScreen(raceId: 'race-1'),
  'board-moved': (_) => const BoardMovedScreen(
    raceId: 'race-1',
    args: BoardMovedArgs(
      raceId: 'race-1',
      raceName: 'First to Complete 1000 Jumping Jacks Before Friday Night',
      value: 999999,
      unit: 'reps',
      rankBefore: 4,
      rankAfter: 2,
      peoplePassed: 2,
    ),
  ),
  'invite': (_) => const InviteScreen(token: 'tok'),
  'notifications': (_) => const NotificationsScreen(),
  'proof-review': (_) =>
      const ProofReviewScreen(raceId: 'race-1', proofId: 'p1'),
  'teach': (_) => const TeachMovementScreen(seedReadyFixture: true),
  // Detect-only: these files are another agent's active WIP — failures are
  // reported, not fixed in this pass.
  'composer': (_) => const RaceComposerScreen(),
  'edit-profile': (_) => const EditProfileScreen(),
};

/// Mounts [child] with a button that opens the dialog/sheet under test.
Widget _dialogHost(String label, Future<void> Function(BuildContext) open) {
  return Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: Text(label),
        ),
      ),
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
  bool safeArea = true,
  double keyboard = 0,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = safeArea
      ? const FakeViewPadding(top: 44, bottom: 34)
      : const FakeViewPadding();
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewInsets();
  });
}

/// Bounded settle — several surfaces animate continuously, so pumpAndSettle
/// would time out. Futures from stub repos flush on the first pumps.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps [widget] while recording every reported FlutterError with its full
/// details (offending widget, render-object chain). The errors still reach
/// the test binding, so takeException/expect still observe them.
Future<void> _pumpRecording(
  WidgetTester tester,
  Widget widget,
  List<FlutterErrorDetails> errors,
) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
    prev?.call(details);
  };
  try {
    await tester.pumpWidget(widget);
    await _settle(tester);
  } finally {
    FlutterError.onError = prev;
  }
}

String _dump(FlutterErrorDetails d) =>
    d.toDiagnosticsNode().toStringDeep(minLevel: DiagnosticLevel.info);

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('NUVO_SWEEP_CAPTURE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'tmp/sweep-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}


/// Fails with the full overflow diagnostics (which Row/Column, how much)
/// instead of the truncated takeException summary.
void _expectClean(WidgetTester tester, [String? context]) {
  final e = tester.takeException();
  if (e != null) {
    // ignore: avoid_print
    print(e is FlutterError ? e.toStringDeep() : e);
  }
  expect(e, isNull, reason: context);
}

void main() {
  ByteData? fontBytes;
  ByteData? captureManifest;
  setUpAll(() async {
    // Real Manrope metrics for every run, not only captures — the Ahem
    // fallback measures ~1em per glyph and reports overflows real hardware
    // would never hit, while missing ones it would.
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

  for (final (sizeName, w, h) in _sizes) {
    group('sweep $sizeName', () {
      for (final entry in _surfaces.entries) {
        testWidgets(entry.key, (tester) async {
          _useViewport(tester, w, h);
          final harness = _Harness(races: _races, inbox: _inboxItems);
          final errors = <FlutterErrorDetails>[];
          await _pumpRecording(
            tester,
            harness.wrap(entry.value(harness)),
            errors,
          );
          if (errors.isNotEmpty) {
            // ignore: avoid_print
            print('\n### ${entry.key} $sizeName ###\n${errors.map(_dump).join('\n')}');
          }
          _expectClean(tester, '${entry.key} $sizeName');
          await _capture(tester, '${entry.key}-$sizeName');
        });
      }
    });
  }

  group('text scale', () {
    for (final scale in [1.2, 1.4]) {
      for (final name in [
        'profile',
        'badges',
        'public-profile',
        'race-detail',
        'notifications',
        'my-nuvo',
      ]) {
        testWidgets('$name @1.${scale.toStringAsFixed(1).substring(2)} '
            '320x568 + 390x844', (tester) async {
          for (final (sizeName, w, h) in [
            _sizes.first,
            _sizes[2],
          ]) {
            _useViewport(tester, w, h);
            final harness = _Harness(
              races: _races,
              inbox: _inboxItems,
              user: _meLong,
              progression: _progressionTorture,
              textScale: scale,
            );
            final errors = <FlutterErrorDetails>[];
            await _pumpRecording(
              tester,
              harness.wrap(_surfaces[name]!(harness)),
              errors,
            );
            if (errors.isNotEmpty) {
              // ignore: avoid_print
              print(
                '\n### $name @$scale $sizeName ###\n'
                '${errors.map(_dump).join('\n')}',
              );
            }
            _expectClean(tester, '$name @$scale $sizeName');
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          }
        });
      }
    }
  });

  group('dialogs and sheets', () {
    final dialogHosts = <String, Widget Function()>{
      'confirm-dialog': () => _dialogHost(
        'open',
        (ctx) => showNuvoConfirmDialog(
          ctx,
          title: 'Delete account?',
          message:
              'Your races, proof, and crew connections are removed '
              'permanently. This cannot be undone.',
          confirmLabel: 'Delete account',
        ),
      ),
      'level-up': () => _dialogHost(
        'open',
        (ctx) => showLevelUpMoment(ctx, level: 999, badge: _badges.first),
      ),
      'race-share-sheet': () => _dialogHost(
        'open',
        (ctx) => showRaceShareSheet(
          ctx,
          raceId: 'race-long',
          raceTitle: 'First to Complete 1000 Jumping Jacks Before Friday Night',
        ),
      ),
      'my-qr-sheet': () => _dialogHost(
        'open',
        (ctx) => showMyQrSheet(
          ctx,
          displayName: 'Alexandria Montgomery-Santiago',
          memberId: 'averylongusername123',
        ),
      ),
    };
    for (final (sizeName, w, h) in _sizes) {
      for (final entry in dialogHosts.entries) {
        testWidgets('${entry.key} $sizeName', (tester) async {
          _useViewport(tester, w, h);
          final harness = _Harness(races: _races, user: _meLong);
          final errors = <FlutterErrorDetails>[];
          await _pumpRecording(tester, harness.wrap(entry.value()), errors);
          await tester.tap(find.text('open'));
          await _settle(tester);
          if (errors.isNotEmpty) {
            // ignore: avoid_print
            print(
              '\n### ${entry.key} $sizeName ###\n'
              '${errors.map(_dump).join('\n')}',
            );
          }
          _expectClean(tester, '${entry.key} $sizeName');
          await _capture(tester, '${entry.key}-$sizeName');
        });
      }
    }
  });

  group('keyboard', () {
    for (final name in ['add-crew', 'join-race']) {
      testWidgets('$name with keyboard up at 320x568', (tester) async {
        _useViewport(tester, 320, 568, keyboard: 290);
        final harness = _Harness(races: _races);
        await tester.pumpWidget(harness.wrap(_surfaces[name]!(harness)));
        await _settle(tester);
        _expectClean(tester, '$name keyboard 320x568');
        await _capture(tester, '$name-keyboard-320x568');
      });
    }
  });

  group('dark mode', () {
    for (final name in [
      'profile',
      'race-detail',
      'my-nuvo',
      'notifications',
      'add-crew',
    ]) {
      testWidgets('$name dark at 390x844', (tester) async {
        _useViewport(tester, 390, 844);
        final harness = _Harness(
          dark: true,
          races: _races,
          inbox: _inboxItems,
        );
        await tester.pumpWidget(harness.wrap(_surfaces[name]!(harness)));
        await _settle(tester);
        _expectClean(tester, '$name dark 390x844');
        await _capture(tester, '$name-dark-390x844');
      });
    }
  });
}
