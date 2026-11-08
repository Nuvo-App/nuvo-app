import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../helpers/screenshot.dart';
import 'package:nuvo/core/utils/photo_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/notifications/data/notification_prefs.dart';
import 'package:nuvo/features/notifications/presentation/notification_prefs_screen.dart';
import 'package:nuvo/features/profile/application/activity_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/profile_v13_api.dart';
import 'package:nuvo/features/profile/presentation/v13/badges_v13_screen.dart';
import 'package:nuvo/features/profile/presentation/v13/edit_profile_v13_screen.dart';
import 'package:nuvo/features/profile/presentation/v13/my_nuvo_code_v13_screen.dart';
import 'package:nuvo/features/profile/presentation/v13/profile_v13_screen.dart';
import 'package:nuvo/features/profile/presentation/v13/public_profile_v13_screen.dart';
import 'package:nuvo/features/profile/presentation/v13/settings_v13_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/social_providers.dart';

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(
    AuthUser(
      id: 'user-1',
      email: 'test@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );

  @override
  Future<void> logout() async {}
}

class _FakeCrewRepo extends CrewRepository {
  _FakeCrewRepo({this.card, this.cardAfterAdd})
    : super(CrewApi(), SecureTokenStore(), AuthApi());

  PublicProfileCard? card;
  PublicProfileCard? cardAfterAdd;
  List<PublicUser> blocked = const [];
  bool muted = false;

  @override
  Future<List<PublicUser>> getCrew() async => const [];

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<PublicProfileCard> getUser(String userId) async =>
      card ?? (throw const ApiException(404, 'User not found'));

  @override
  Future<ConnectOutcome> add(String userId) async {
    if (cardAfterAdd != null) card = cardAfterAdd;
    return ConnectOutcome.pending;
  }

  @override
  Future<void> acceptRequest(String userId) async {}

  @override
  Future<void> remove(String userId) async {}

  @override
  Future<PublicUserActivity> getUserActivity(String userId) async =>
      const PublicUserActivity(shared: true, days: {'2026-02-01': 2});

  @override
  Future<List<PublicUser>> getBlocked() async => blocked;

  @override
  Future<void> unblockUser(String userId) async {
    blocked = [
      for (final u in blocked)
        if (u.id != userId) u,
    ];
  }

  @override
  Future<void> muteUser(String userId) async => muted = true;

  @override
  Future<void> unmuteUser(String userId) async => muted = false;

  @override
  Future<void> reportUser(String userId, {String? reason}) async {}

  @override
  Future<void> blockUser(String userId) async {}
}

PublicProfileCard _friendCard() => const PublicProfileCard(
  id: 'user-2',
  displayName: 'Maya Miles',
  initials: 'MM',
  connectionStatus: CrewConnectionStatus.connected,
  username: 'mayam',
  bio: 'Runs on hill sprints.',
  favoriteMovementKey: 'squats',
  friendsCount: 12,
  level: 7,
  racesFinished: 9,
  racesWon: 4,
  versus: PublicVersus(
    you: PublicVersusSide(
      level: 8,
      wins: 6,
      winRatePercent: 60,
      bestStreakDays: 5,
      proofsThisWeek: 3,
    ),
    them: PublicVersusSide(
      level: 7,
      wins: 4,
      winRatePercent: 44,
      bestStreakDays: 9,
      proofsThisWeek: 1,
    ),
  ),
  mutual: PublicMutual(
    count: 2,
    preview: [
      PublicUser(id: 'user-3', displayName: 'Theo North', initials: 'TN'),
    ],
  ),
  friendship: PublicFriendship(
    connectedSince: '2026-01-01T00:00:00Z',
    badges: [
      PublicFriendshipBadge(
        key: 'first_race',
        name: 'First race',
        description: 'Finish your first race together',
        earned: true,
        progress: 1,
        threshold: 1,
      ),
      PublicFriendshipBadge(
        key: 'rivals',
        name: 'Rivals',
        description: 'Race together 10 times',
        earned: false,
        progress: 3,
        threshold: 10,
      ),
    ],
  ),
  racesWithYou: PublicRacesWithYou(
    total: 3,
    viewerWins: 2,
    targetWins: 1,
    recent: [
      PublicSharedRace(
        raceId: 'race-9',
        title: 'Squat Sprint',
        winnerUserId: 'user-1',
      ),
    ],
  ),
);

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo({List<Race>? races})
    : races = races ?? const [],
      super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() async => races;
}

class _FakeInviteRepo extends InviteRepository {
  _FakeInviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintMyCrewInvite() async =>
      const MintedInvite(token: 't1', url: 'https://getnuvo.net/j/t1');
}

class _FakeNotifPrefsApi extends NotificationPrefsApi {
  _FakeNotifPrefsApi() : super();

  @override
  Future<List<NotificationPref>> list() async => const [
    NotificationPref(
      category: 'passed_on_leaderboard',
      inApp: true,
      push: true,
    ),
    NotificationPref(category: 'race_invite', inApp: true, push: true),
    NotificationPref(category: 'reaction', inApp: true, push: false),
  ];

  @override
  Future<void> update(String category, {bool? inApp, bool? push}) async {}
}

class _FakeProfileV13Api extends ProfileV13Api {
  _FakeProfileV13Api() : super(SecureTokenStore(), AuthApi());

  static const prefs = NuvoProfilePrefs(
    hasBio: true,
    hasFavoriteMovement: true,
    hasActivityMapShared: true,
    hasRaceInvitesFrom: true,
    bio: 'Chasing Level 9.',
    favoriteMovementKey: 'pushups',
    activityMapShared: true,
    raceInvitesFrom: 'everyone',
  );

  @override
  Future<NuvoProfilePrefs> getPrefs() async => prefs;

  @override
  Future<void> updatePrefs({
    String? bio,
    bool clearBio = false,
    String? favoriteMovementKey,
    bool clearFavoriteMovement = false,
    bool? activityMapShared,
    String? raceInvitesFrom,
  }) async {}
}

List<Override> _overrides({_FakeCrewRepo? crewRepo, _StubRaceRepo? raceRepo}) {
  return [
    raceRepositoryProvider.overrideWithValue(raceRepo ?? _StubRaceRepo()),
    crewRepositoryProvider.overrideWithValue(crewRepo ?? _FakeCrewRepo()),
    crewControllerProvider.overrideWith(
      (ref) => CrewController(crewRepo ?? _FakeCrewRepo()),
    ),
    authControllerProvider.overrideWith(
      (ref) => AuthController(_FakeAuthRepo()),
    ),
    // Demo-mode controller reads bundled fixtures — no network in tests.
    progressionControllerProvider.overrideWith((ref) {
      final controller = ProgressionController(
        ProgressionApi(),
        SecureTokenStore(),
        isPresentationDemo: () => true,
        accountId: () => 'user-1',
      );
      unawaited(controller.load());
      return controller;
    }),
    profilePrefsProvider.overrideWith((ref) async => _FakeProfileV13Api.prefs),
    profileV13ApiProvider.overrideWithValue(_FakeProfileV13Api()),
    profileActivityProvider.overrideWith(
      (ref) async => {'2026-02-01': 3, '2026-02-02': 1},
    ),
    inviteRepositoryProvider.overrideWithValue(_FakeInviteRepo()),
    notificationPrefsApiProvider.overrideWithValue(_FakeNotifPrefsApi()),
    photoPickerProvider.overrideWithValue(
      (_) async => const PhotoPickResult.cancelled(),
    ),
  ];
}

Widget _app(Widget child, {List<Override>? overrides}) => ProviderScope(
  overrides: overrides ?? _overrides(),
  child: MaterialApp(home: child),
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadShotFonts);
  editProfileTests();
  testWidgets('Profile: header, counts, actions, sections', (tester) async {
    _size(tester);
    await tester.pumpWidget(_app(const ProfileV13Screen()));
    await tester.pumpAndSettle();
    expect(find.text('@testuser'), findsOneWidget);
    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Share profile'), findsOneWidget);
    expect(find.text('Races'), findsOneWidget);
    expect(find.text('Wins'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('ACTIVITY'), findsOneWidget);
    expect(find.text('RACE HISTORY'), findsOneWidget);
    expect(find.text('Pushups'), findsOneWidget);
    await shot(tester, 'v13_profile_own');
  });

  testWidgets('Profile: Edit profile navigates to /profile/edit', (
    tester,
  ) async {
    _size(tester);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfileV13Screen()),
        GoRoute(
          path: '/profile/edit',
          builder: (_, _) => const Scaffold(body: Text('EDIT_PAGE')),
        ),
        GoRoute(
          path: '/my-nuvo',
          builder: (_, _) => const Scaffold(body: Text('MYNUVO_PAGE')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('SETTINGS_PAGE')),
        ),
        GoRoute(
          path: '/profile/badges',
          builder: (_, _) => const Scaffold(body: Text('BADGES_PAGE')),
        ),
        GoRoute(
          path: '/compete',
          builder: (_, _) => const Scaffold(body: Text('COMPETE_PAGE')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('EDIT_PAGE'), findsOneWidget);
  });

  testWidgets('Public profile: friend view shows Race, stats, friendship', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(
      _app(
        const PublicProfileV13Screen(userId: 'user-2'),
        overrides: _overrides(crewRepo: _FakeCrewRepo(card: _friendCard())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('@mayam'), findsOneWidget);
    expect(find.text('Maya Miles'), findsOneWidget);
    expect(find.text('Runs on hill sprints.'), findsOneWidget);
    expect(find.text('Race Maya'), findsOneWidget);
    expect(find.text('Friends'), findsWidgets);
    await tester.dragUntilVisible(
      find.textContaining('STATS WON'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('STATS WON'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('FRIENDSHIP'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rivals'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('RACED TOGETHER · 3'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Squat Sprint'), findsOneWidget);
    expect(find.text('You won'), findsOneWidget);
    await shot(tester, 'v13_public_friend');
  });

  testWidgets('Public profile: Friends sheet exposes mute and remove', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(
      _app(
        const PublicProfileV13Screen(userId: 'user-2'),
        overrides: _overrides(crewRepo: _FakeCrewRepo(card: _friendCard())),
      ),
    );
    await tester.pumpAndSettle();
    // 'Friends' text also appears in the counts strip — tap the button.
    await tester.tap(find.text('Friends').last);
    await tester.pumpAndSettle();
    expect(find.text('Mute Maya'), findsOneWidget);
    expect(find.text('Remove friend'), findsOneWidget);
  });

  testWidgets('Public profile: non-friend shows Add friend → Requested', (
    tester,
  ) async {
    _size(tester);
    const stranger = PublicProfileCard(
      id: 'user-9',
      displayName: 'Sam Solo',
      initials: 'SS',
      connectionStatus: CrewConnectionStatus.none,
      username: 'samsolo',
      friendsCount: 1,
    );
    const requested = PublicProfileCard(
      id: 'user-9',
      displayName: 'Sam Solo',
      initials: 'SS',
      connectionStatus: CrewConnectionStatus.pendingOutgoing,
      username: 'samsolo',
      friendsCount: 1,
    );
    await tester.pumpWidget(
      _app(
        const PublicProfileV13Screen(userId: 'user-9'),
        overrides: _overrides(
          crewRepo: _FakeCrewRepo(card: stranger, cardAfterAdd: requested),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add friend'), findsOneWidget);
    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    expect(find.text('Request sent.'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    await shot(tester, 'v13_public_nonfriend');
  });

  testWidgets('Public profile: error state retries', (tester) async {
    _size(tester);
    final repo = _FakeCrewRepo(card: null);
    await tester.pumpWidget(
      _app(
        const PublicProfileV13Screen(userId: 'user-9'),
        overrides: _overrides(crewRepo: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this profile"), findsOneWidget);
    repo.card = _friendCard();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Maya Miles'), findsOneWidget);
  });

  testWidgets('Badges: ring, up next, featured slots, filter chips', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_app(const BadgesV13Screen()));
    await tester.pumpAndSettle();
    expect(find.text('Badges'), findsOneWidget);
    expect(find.text('earned'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Find a race'), findsOneWidget);
    expect(find.textContaining('ON YOUR PROFILE'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);
    await shot(tester, 'v13_badges');
  });

  testWidgets('Settings: account card, sections, gated rows hide/show', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_app(const SettingsV13Screen()));
    await tester.pumpAndSettle();
    expect(find.text('Test User'), findsOneWidget);
    expect(find.text('@testuser'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Passes'), findsOneWidget);
    expect(find.text('Invites'), findsOneWidget);
    expect(find.text('Cheers'), findsOneWidget);
    // Reminders has no server category → hidden.
    expect(find.text('Reminders'), findsNothing);
    expect(find.text('Show my activity map'), findsOneWidget);
    expect(find.text('Who can race me'), findsOneWidget);
    expect(find.text('Blocked accounts'), findsOneWidget);
    expect(find.text('Haptics'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Sign out'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Community Guidelines'), findsOneWidget);
    await shot(tester, 'v13_settings');
  });

  testWidgets(
    'Edit profile: fields, bio counter, movement chips, dirty cancel',
    (tester) async {
      _size(tester);
      final router = GoRouter(
        initialLocation: '/profile/edit',
        routes: [
          GoRoute(
            path: '/profile/edit',
            builder: (_, _) => const EditProfileV13Screen(),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('NAME'), findsOneWidget);
      expect(find.text('USERNAME'), findsOneWidget);
      expect(find.text('BIO'), findsOneWidget);
      expect(find.text('FAVORITE MOVEMENT'), findsOneWidget);
      expect(find.text('Pushups'), findsWidgets);
      await tester.enterText(find.byType(TextField).first, 'Different Name');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    },
  );

  testWidgets('My Nuvo: my code segment shows QR + share/copy', (tester) async {
    _size(tester);
    await tester.pumpWidget(_app(const MyNuvoCodeV13Screen()));
    await tester.pumpAndSettle();
    expect(find.text('My code'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('@testuser'), findsOneWidget);
    expect(find.text('Share your code'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    await shot(tester, 'v13_my_code');
  });

  testWidgets('My Nuvo: initialTab=1 opens Scan with paste bar', (
    tester,
  ) async {
    _size(tester);
    await tester.pumpWidget(_app(const MyNuvoCodeV13Screen(initialTab: 1)));
    // Camera init never resolves under the test plugin — the paste bar is
    // present regardless, so settle with fixed pumps instead.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Paste a Nuvo link'), findsOneWidget);
  });
}

void editProfileTests() {
  testWidgets('Edit profile: fields, bio counter, Cancel asks before '
      'discarding edits', (tester) async {
    _size(tester);
    await tester.pumpWidget(_app(const EditProfileV13Screen()));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('USERNAME'), findsOneWidget);
    await shot(tester, 'v13_edit_profile');

    final bioLabel = find.text('BIO');
    if (bioLabel.evaluate().isNotEmpty) {
      final bioField = find.byType(TextField).last;
      await tester.enterText(bioField, 'Pushups before breakfast');
      await tester.pump();
      expect(find.text('24/80'), findsOneWidget);
    } else {
      await tester.enterText(find.byType(TextField).first, 'New Name');
      await tester.pump();
    }

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
  });
}
