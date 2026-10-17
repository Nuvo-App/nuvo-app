// ignore_for_file: unused_element, unused_element_parameter
import 'dart:io';

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
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/notifications/presentation/notifications_screen.dart';
import 'package:nuvo/features/profile/presentation/edit_profile_screen.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/badges_screen.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/social_providers.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/core/widgets/nuvo_fade_scroll.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';
import 'package:nuvo/features/notifications/data/notification_prefs.dart';
import 'package:nuvo/features/notifications/presentation/notification_prefs_screen.dart';

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
  Future<NotificationPage> list({String? cursor, String? etag}) async =>
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

// ── Crew-group (squad) + prefs fakes ─────────────────────────────────────────
Map<String, dynamic> _g(String id, String name) => {
  'id': id,
  'name': name,
  'joinCode': 'CODE$id',
  'isOwner': true,
  'memberCount': 4,
  'raceCount': 2,
};

Map<String, dynamic> _s(
  String id,
  String name,
  int rank,
  int pts, {
  bool you = false,
}) => {
  'userId': id,
  'displayName': name,
  'rank': rank,
  'points': pts,
  'wins': rank == 1 ? 2 : 0,
  'races': 2,
  'isYou': you,
};

class _SquadRepo implements SquadRepository {
  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) async {
    final raw = {
      'squads': [for (var i = 0; i < 6; i++) _g('g$i', 'Sunrise Crew $i')],
    };
    return Conditional(data: parseCrewGroupList(raw), etag: 'e', raw: raw);
  }

  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) async {
    final raw = {
      'squad': _g(id, 'Sunrise Crew'),
      'races': [
        {'id': 'r1', 'title': 'Morning push-ups', 'status': 'active'},
        {'id': 'r2', 'title': 'Weekend jumping jacks', 'status': 'active'},
      ],
      'standings': [
        _s('1', 'Ava Long', 1, 9),
        _s('2', 'Ben', 2, 6, you: true),
        _s('3', 'Cy Stone', 3, 3),
        _s('4', 'Dee', 4, 1),
        _s('5', 'Eli', 5, 1),
        _s('6', 'Fay', 6, 0),
      ],
    };
    return Conditional(
      data: CrewGroupDetail.fromJson(raw),
      etag: 'd',
      raw: raw,
    );
  }

  @override
  Future<CrewGroup> create(String name) async =>
      CrewGroup.fromJson(_g('n', name));
  @override
  Future<void> join(String code) async {}
  @override
  Future<int> addRace(String id, String raceId) async => 1;
  @override
  Future<void> leave(String id) async {}

  @override
  Future<void> setRole(String id, String userId, String role) async {}

  @override
  Future<void> removeMember(String id, String userId) async {}

  @override
  Future<void> removeRace(String id, String raceId) async {}
}

class _PrefsApi implements NotificationPrefsApi {
  @override
  Future<List<NotificationPref>> list() async => const [
    NotificationPref(category: 'race_starting', inApp: true, push: true),
    NotificationPref(category: 'race_completed', inApp: true, push: true),
    NotificationPref(
      category: 'passed_on_leaderboard',
      inApp: true,
      push: false,
    ),
    NotificationPref(category: 'proof_accepted', inApp: true, push: true),
    NotificationPref(category: 'proof_rejected', inApp: true, push: false),
    NotificationPref(category: 'crew_request', inApp: true, push: true),
    NotificationPref(
      category: 'crew_request_accepted',
      inApp: true,
      push: false,
    ),
  ];
  @override
  Future<void> update(String category, {bool? inApp, bool? push}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _scoped(_Harness h, Widget child) => ProviderScope(
  overrides: [
    squadControllerProvider.overrideWith(
      (ref) => SquadController(
        _SquadRepo(),
        CacheStore.memory(),
        accountId: () => 'u1',
      ),
    ),
    notificationPrefsApiProvider.overrideWithValue(_PrefsApi()),
  ],
  child: h.wrap(child),
);

class _Page {
  const _Page(this.build, [this.prep]);
  final Widget Function() build;
  final Future<void> Function(WidgetTester)? prep;
}

final _pages = <String, _Page>{
  'crews-list': _Page(() => const CrewGroupsScreen()),
  'crew-detail': _Page(() => const CrewGroupDetailScreen(groupId: 'g1')),
  'crew-create-sheet': _Page(() => const CrewGroupsScreen(), (t) async {
    await t.tap(find.text('Start a crew'));
    await _settle(t);
  }),
  'crew-join-sheet': _Page(() => const CrewGroupsScreen(), (t) async {
    await t.tap(find.text('Join with a code'));
    await _settle(t);
  }),
  'achievements': _Page(() => const BadgesScreen()),
  'settings': _Page(() => const SettingsScreen()),
  'edit-profile': _Page(() => const EditProfileScreen()),
  'notifications': _Page(() => const NotificationsScreen()),
  'notification-prefs': _Page(() => const NotificationPrefsScreen()),
};

const _matrixSizes = [
  (320.0, 568.0),
  (375.0, 667.0),
  (390.0, 844.0),
  (393.0, 852.0),
  (430.0, 932.0),
];

bool _hasFade(WidgetTester tester) =>
    find.byType(NuvoFadeScroll).evaluate().isNotEmpty ||
    find.byKey(const ValueKey('nuvo-bottom-fade')).evaluate().isNotEmpty;

Iterable<RenderParagraph> _paragraphs(WidgetTester tester) sync* {
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    if (ro.text.toPlainText().trim().isEmpty) continue;
    yield ro;
  }
}

Rect _rect(RenderParagraph p) => p.localToGlobal(Offset.zero) & p.size;

void main() {
  setUpAll(() async {
    final bytes = ByteData.sublistView(
      await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
    );
    for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
      final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final entry in _pages.entries) {
    for (final (w, h) in _matrixSizes) {
      for (final inset in [0.0, 34.0]) {
        for (final dark in [false, true]) {
          for (final scale in [1.0, 1.3]) {
            final name =
                '${entry.key} ${w.toInt()}x${h.toInt()} '
                'inset$inset ${dark ? 'dark' : 'light'} x$scale';
            testWidgets(name, (tester) async {
              tester.view.physicalSize = Size(w, h);
              tester.view.devicePixelRatio = 1;
              tester.view.padding = FakeViewPadding(top: 44, bottom: inset);
              tester.view.viewPadding = FakeViewPadding(top: 44, bottom: inset);
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
                tester.view.resetPadding();
                tester.view.resetViewPadding();
              });
              final harness = _Harness(
                dark: dark,
                textScale: scale,
                races: _races,
                inbox: _inboxItems,
              );
              await tester.pumpWidget(_scoped(harness, entry.value.build()));
              await _settle(tester);
              if (entry.value.prep != null) await entry.value.prep!(tester);
              expect(tester.takeException(), isNull, reason: name);

              final fade = _hasFade(tester);
              final edge = h - inset;
              final bad = <String>[];
              for (final p in _paragraphs(tester)) {
                final r = _rect(p);
                if (r.bottom <= 0 || r.top >= h) continue;
                final txt = p.text.toPlainText();
                if (!fade &&
                    r.top < edge - 0.5 &&
                    r.bottom > edge + 0.5 &&
                    r.top >= 0) {
                  // A line under a bottom-pinned inset that is also bisected.
                  if (r.top < h && r.bottom > edge + 0.5) {
                    bad.add('crosses safe edge: "$txt" $r');
                  }
                }
                if (scale == 1.0 && txt.length <= 35 && p.didExceedMaxLines) {
                  bad.add('ellipsized at 1.0: "$txt"');
                }
              }
              expect(bad, isEmpty, reason: '$name\n${bad.join('\n')}');

              // Scroll to the end: last row must clear the bottom inset.
              final scrollables = find.byType(Scrollable);
              if (scrollables.evaluate().isNotEmpty && inset > 0) {
                final s = tester.state<ScrollableState>(scrollables.first);
                if (s.position.maxScrollExtent > 0 &&
                    s.axisDirection == AxisDirection.down) {
                  s.position.jumpTo(s.position.maxScrollExtent);
                  await tester.pump(const Duration(milliseconds: 100));
                  var maxBottom = 0.0;
                  String last = '';
                  for (final p in _paragraphs(tester)) {
                    final r = _rect(p);
                    if (r.top >= 0 && r.top < h && r.bottom > maxBottom) {
                      maxBottom = r.bottom;
                      last = p.text.toPlainText();
                    }
                  }
                  expect(
                    maxBottom,
                    lessThanOrEqualTo(edge + 0.5),
                    reason: '$name last row "$last" under inset',
                  );
                }
              }
              expect(tester.takeException(), isNull, reason: name);
            });
          }
        }
      }
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
