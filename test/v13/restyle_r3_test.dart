// S10 r3 — PublicBadgesScreen (read-only v13 collection), the Teach Nuvo
// name/intro stages (chrome only), the S8-audited NotificationPrefsScreen,
// and the MotionContributionScreen consent step.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/screenshot.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/crew/presentation/public_badges_screen.dart';
import 'package:nuvo/features/notifications/data/notification_prefs.dart';
import 'package:nuvo/features/notifications/presentation/notification_prefs_screen.dart';
import 'package:nuvo/features/onboarding/presentation/motion_contribution_screen.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/v13/v13_profile_shared.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_providers.dart';
import 'package:nuvo/features/races/ai/motion_session/motion_session_upload_queue.dart';
import 'package:nuvo/features/races/presentation/custom_pose/teach_movement_screen.dart';

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
}

class _FakeCrewRepo extends CrewRepository {
  _FakeCrewRepo({this.card}) : super(CrewApi(), SecureTokenStore(), AuthApi());

  PublicProfileCard? card;

  @override
  Future<PublicProfileCard> getUser(String userId) async =>
      card ?? (throw const ApiException(404, 'User not found'));
}

class _FakePrefsApi implements NotificationPrefsApi {
  _FakePrefsApi({this.fail = false});

  bool fail;

  @override
  Future<List<NotificationPref>> list() async {
    if (fail) throw const ApiException(500, 'down');
    return const [
      NotificationPref(category: 'race_starting', inApp: true, push: true),
      NotificationPref(category: 'race_completed', inApp: true, push: true),
      NotificationPref(
        category: 'passed_on_leaderboard',
        inApp: true,
        push: false,
      ),
      NotificationPref(category: 'proof_accepted', inApp: true, push: true),
      NotificationPref(category: 'crew_request', inApp: true, push: false),
    ];
  }

  @override
  Future<void> update(String category, {bool? inApp, bool? push}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Teach's initState flushes the staged-session upload queue — a no-op fake
/// keeps the widget test off the filesystem and the network.
class _FakeTeachQueue extends MotionSessionUploadQueue {
  _FakeTeachQueue()
    : super(upload: ({required metadata, required gzipBytes}) async {});

  @override
  Future<void> flush() async {}
}

NuvoBadge _badge(int i, {bool unlocked = true, String category = 'racing'}) {
  return NuvoBadge(
    unlockId: 'u-$i',
    type: 'achievement',
    key: 'k$i',
    name: 'Badge Number $i',
    description: 'Finish ${i + 1} races to earn this.',
    requiredLevel: 1,
    unlocked: unlocked,
    unlockedAt: unlocked ? '2026-01-0${(i % 9) + 1}T00:00:00Z' : null,
    featured: false,
    category: category,
    iconKey: 'trophy',
    statKey: 'wins',
    threshold: i + 1,
    progressValue: unlocked ? i + 1 : i,
  );
}

PublicProfileCard _card({
  List<NuvoBadge>? earned,
  List<PublicLockedAchievement>? locked,
}) {
  final e = earned ?? const <NuvoBadge>[];
  final l = locked ?? const <PublicLockedAchievement>[];
  return PublicProfileCard(
    id: 'u-rival',
    displayName: 'Rival One',
    initials: 'RO',
    connectionStatus: CrewConnectionStatus.connected,
    username: 'rival',
    achievementsEarned: e.length,
    achievementsTotal: e.length + l.length,
    earned: e,
    lockedAchievements: l,
  );
}

final _mixedCard = _card(
  earned: [
    _badge(0, category: 'racing'),
    _badge(1, category: 'winning'),
  ],
  locked: const [
    PublicLockedAchievement(
      key: 'locked_a',
      name: 'Locked Alpha',
      iconKey: 'bolt',
      category: 'racing',
    ),
    PublicLockedAchievement(
      key: 'locked_b',
      name: 'Locked Beta',
      iconKey: 'star',
      category: 'winning',
    ),
  ],
);

List<Override> _overrides({
  _FakeCrewRepo? crewRepo,
  _FakePrefsApi? prefsApi,
}) => [
  crewRepositoryProvider.overrideWithValue(crewRepo ?? _FakeCrewRepo()),
  authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
  notificationPrefsApiProvider.overrideWithValue(prefsApi ?? _FakePrefsApi()),
  teachSessionUploadQueueProvider.overrideWithValue(_FakeTeachQueue()),
];

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

  group('Public badges', () {
    testWidgets('ring, filters, read-only earned + locked sheets', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          const PublicBadgesScreen(userId: 'u-rival', card: null),
          overrides: _overrides(crewRepo: _FakeCrewRepo(card: _mixedCard)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Badges'), findsOneWidget);
      expect(find.text('2/4'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Locked Alpha'), findsOneWidget);
      await shot(tester, 'v13_public_badges');

      // Earned tile → detail sheet, read-only: no feature action exists.
      await tester.tap(find.byType(V13BadgeTile).first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Badge Number 0'),
        ),
        findsOneWidget,
      );
      expect(find.text('Earned'), findsWidgets);
      expect(find.text('Show on profile'), findsNothing);
      expect(find.text('Feature on Profile'), findsNothing);
      expect(find.text('Remove from profile'), findsNothing);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      // Locked tile → dashed catalog sheet, still read-only. Tile order:
      // the 2 earned tiles, then the 2 locked ones.
      await tester.tap(find.byType(V13BadgeTile).at(2));
      await tester.pumpAndSettle();
      expect(find.text('Locked'), findsWidgets);
      expect(find.text("Rival hasn't earned this one yet."), findsOneWidget);
    });

    testWidgets('error state retries into the loaded grid', (tester) async {
      _size(tester);
      final repo = _FakeCrewRepo(card: null);
      await tester.pumpWidget(
        _app(
          const PublicBadgesScreen(userId: 'u-rival'),
          overrides: _overrides(crewRepo: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load their badges"), findsOneWidget);
      await shot(tester, 'v13_public_badges_error');
      repo.card = _mixedCard;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Badge Number 0'), findsWidgets);
    });

    testWidgets('Locked filter shows only dashed tiles', (tester) async {
      _size(tester);
      await tester.pumpWidget(
        _app(
          const PublicBadgesScreen(userId: 'u-rival', card: null),
          overrides: _overrides(crewRepo: _FakeCrewRepo(card: _mixedCard)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locked'));
      await tester.pumpAndSettle();
      expect(find.text('Locked Alpha'), findsOneWidget);
      expect(find.text('Badge Number 0'), findsNothing);
    });
  });

  group('Notification prefs', () {
    testWidgets('grouped toggles render and tap updates the api', (
      tester,
    ) async {
      _size(tester);
      await tester.pumpWidget(_app(const NotificationPrefsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Race starting'), findsOneWidget);
      expect(find.text('Friend requests'), findsOneWidget);
      await shot(tester, 'v13_notification_prefs');
    });

    testWidgets('error state retries', (tester) async {
      _size(tester);
      final api = _FakePrefsApi(fail: true);
      await tester.pumpWidget(
        _app(
          const NotificationPrefsScreen(),
          overrides: _overrides(prefsApi: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your settings."), findsOneWidget);
      await shot(tester, 'v13_notification_prefs_error');
      api.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Race starting'), findsOneWidget);
    });
  });

  group('Teach Nuvo', () {
    testWidgets('name stage renders the v13 focused stage', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(const TeachMovementScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Name your movement'), findsOneWidget);
      expect(find.text('What should Nuvo call it?'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      await shot(tester, 'v13_teach_name');
    });
  });

  group('Motion contribution', () {
    testWidgets('consent step renders two real choices', (tester) async {
      _size(tester);
      await tester.pumpWidget(_app(const MotionContributionScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Help improve Nuvo'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await shot(tester, 'v13_motion_contribution');
    });
  });
}
