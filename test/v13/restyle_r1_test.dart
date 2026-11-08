// Widget tests for the S10-r1 v13 restyle — the secondary social/crew
// screens (Add friend hub, invite landing, crews list, join confirm, crew
// settings). Populated + error state per screen, with shots.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/add_crew_screen.dart';
import 'package:nuvo/features/social/presentation/invite_screen.dart';
import 'package:nuvo/features/social/social_providers.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';

import '../helpers/screenshot.dart';

// ── Fakes ────────────────────────────────────────────────────────────────

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

class _StubCrewRepo extends CrewRepository {
  _StubCrewRepo({
    this.requests = const [],
    this.outgoing = const [],
    this.searchResults = const [],
    this.searchFails = false,
  }) : super(CrewApi(), SecureTokenStore(), AuthApi());

  final List<PublicUser> requests;
  final List<PublicUser> outgoing;
  final List<CrewSearchResult> searchResults;
  final bool searchFails;

  @override
  Future<List<PublicUser>> getCrew() => Future.value(const []);
  @override
  Future<CrewRequestPage> getRequestPage() =>
      Future.value(CrewRequestPage(incoming: requests, outgoing: outgoing));
  @override
  Future<List<CrewSearchResult>> search(String query) => searchFails
      ? Future.error(const ApiException(500, 'Server error'))
      : Future.value(searchResults);
}

class _StubSquadRepo extends SquadRepository {
  _StubSquadRepo({
    this.groups = const [],
    this.detailData,
    this.listError,
    this.detailError,
    this.joinError,
  }) : super(SquadApi(), SecureTokenStore(), AuthApi());

  final List<CrewGroup> groups;
  final CrewGroupDetail? detailData;
  final ApiException? listError;
  final ApiException? detailError;
  final ApiException? joinError;

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) => listError != null
      ? Future.error(listError!)
      : Future.value(Conditional(data: groups, etag: 'e'));
  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) =>
      detailError != null
      ? Future.error(detailError!)
      : Future.value(Conditional(data: detailData, etag: 'd'));
  @override
  Future<void> join(String code) =>
      joinError != null ? Future.error(joinError!) : Future.value();
}

class _StubInviteRepo extends InviteRepository {
  _StubInviteRepo({this.previewJson, this.previewError})
    : super(InviteApi(), SecureTokenStore(), AuthApi());

  final Map<String, dynamic>? previewJson;
  final Object? previewError;

  @override
  Future<InvitePreview> preview(String token) => previewError != null
      ? Future.error(previewError!)
      : Future.value(InvitePreview.fromJson(previewJson!));
}

// ── Fixtures ─────────────────────────────────────────────────────────────

PublicUser _friend(String id, String name, {String? username}) => PublicUser(
  id: id,
  displayName: name,
  username: username,
  initials: name.substring(0, 1),
);

CrewGroup _group({String id = 'c1', String name = 'Sunrise Crew'}) => CrewGroup(
  id: id,
  name: name,
  joinCode: 'SUN123',
  isOwner: true,
  memberCount: 4,
  raceCount: 3,
  myRole: 'owner',
  colorKey: 'sun',
  myRankWeek: 2,
  memberPreviews: const [
    CrewMemberPreview(userId: 'user-2', displayName: 'Ben Carter'),
    CrewMemberPreview(userId: 'user-3', displayName: 'Maya Miles'),
  ],
);

CrewGroupDetail _detail() => CrewGroupDetail(
  group: _group(),
  races: const [],
  standings: const [],
  members: const [
    CrewMember(userId: 'user-1', displayName: 'Test User', role: 'owner'),
    CrewMember(userId: 'user-2', displayName: 'Ben Carter', role: 'member'),
  ],
);

List<Override> _overrides({
  _StubCrewRepo? crew,
  _StubSquadRepo? squads,
  _StubInviteRepo? invites,
}) {
  return [
    crewControllerProvider.overrideWith(
      (ref) => CrewController(
        crew ?? _StubCrewRepo(),
        isPresentationDemo: () => false,
        cache: CacheStore.memory(),
        accountId: () => 'user-1',
      ),
    ),
    squadControllerProvider.overrideWith(
      (ref) => SquadController(
        squads ?? _StubSquadRepo(),
        CacheStore.memory(),
        accountId: () => 'user-1',
      ),
    ),
    if (invites != null) inviteRepositoryProvider.overrideWithValue(invites),
    authControllerProvider.overrideWith(
      (ref) => AuthController(_FakeAuthRepo()),
    ),
  ];
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget screen, List<Override> o) async {
  _size(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: o,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadShotFonts);

  group('AddCrewScreen (/crew/add)', () {
    testWidgets('populated: requests + sent + search results', (tester) async {
      final crew = _StubCrewRepo(
        requests: [_friend('u-kai', 'Kai Storm', username: 'kai')],
        outgoing: [_friend('u-sam', 'Sam Vale', username: 'sam')],
        searchResults: [
          CrewSearchResult(
            user: _friend('u-may', 'Maya Miles', username: 'maya'),
            connectionStatus: CrewConnectionStatus.none,
            mutualCount: 2,
          ),
          CrewSearchResult(
            user: _friend('u-ben', 'Ben Carter', username: 'ben'),
            connectionStatus: CrewConnectionStatus.connected,
          ),
        ],
      );
      await _pump(tester, const AddCrewScreen(), _overrides(crew: crew));

      expect(find.text('Add friend'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('My Nuvo'), findsOneWidget);
      expect(find.text('WANTS TO BE FRIENDS'), findsOneWidget);
      expect(find.text('Kai wants to race'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('REQUESTS SENT'), findsOneWidget);
      expect(find.text('Waiting on Sam'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Search swaps the queue for open result rows.
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Maya Miles'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Friends'), findsOneWidget);
      expect(find.text('WANTS TO BE FRIENDS'), findsNothing);
      await shot(tester, 'v13_add_crew');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error: search failure shows an inline retry', (tester) async {
      final crew = _StubCrewRepo(searchFails: true);
      await _pump(tester, const AddCrewScreen(), _overrides(crew: crew));

      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search failed. Try again.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await shot(tester, 'v13_add_crew_error');
      expect(tester.takeException(), isNull);
    });
  });

  group('InviteScreen (/invite/:token)', () {
    testWidgets('populated: race invite preview', (tester) async {
      final invites = _StubInviteRepo(
        previewJson: const {
          'status': 'active',
          'kind': 'race_join',
          'requiresAuth': true,
          'preview': {
            'race': {
              'id': 'r1',
              'title': 'Sunday pushups',
              'activityId': 'push_ups',
              'targetValue': 100,
              'targetUnit': 'reps',
              'participantCount': 3,
              'creator': {'displayName': 'Ben Carter'},
            },
          },
        },
      );
      await _pump(
        tester,
        const InviteScreen(token: 'tok'),
        _overrides(invites: invites),
      );

      expect(find.text("You're invited to a race"), findsOneWidget);
      expect(find.text('Sunday pushups'), findsOneWidget);
      expect(find.text('Goal 100 reps'), findsOneWidget);
      expect(find.text('push ups'), findsOneWidget);
      expect(find.text('3 racing'), findsOneWidget);
      expect(find.text('Created by Ben Carter'), findsOneWidget);
      expect(find.text('Join race'), findsOneWidget);
      await shot(tester, 'v13_invite_race');
      expect(tester.takeException(), isNull);
    });

    testWidgets('populated: friend invite preview', (tester) async {
      final invites = _StubInviteRepo(
        previewJson: const {
          'status': 'active',
          'kind': 'crew_connect',
          'requiresAuth': true,
          'preview': {
            'person': {
              'userId': 'u9',
              'displayName': 'Maya Miles',
              'username': 'maya',
            },
          },
        },
      );
      await _pump(
        tester,
        const InviteScreen(token: 'tok'),
        _overrides(invites: invites),
      );

      expect(find.text('Maya Miles'), findsOneWidget);
      expect(find.text('@maya'), findsOneWidget);
      expect(
        find.text('Add them as a friend to race together.'),
        findsOneWidget,
      );
      expect(find.text('Add friend'), findsOneWidget);
      await shot(tester, 'v13_invite_person');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error: failed preview shows error + Retry', (tester) async {
      final invites = _StubInviteRepo(
        previewError: const ApiException(500, 'Server error'),
      );
      await _pump(
        tester,
        const InviteScreen(token: 'tok'),
        _overrides(invites: invites),
      );

      expect(find.text("Couldn't load this invite."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await shot(tester, 'v13_invite_error');
      expect(tester.takeException(), isNull);
    });
  });

  group('CrewGroupsScreen (/crews)', () {
    testWidgets('populated: crew cards + ways to add', (tester) async {
      final squads = _StubSquadRepo(
        groups: [
          _group(),
          _group(id: 'c2', name: 'Night Owls'),
        ],
      );
      await _pump(tester, const CrewGroupsScreen(), _overrides(squads: squads));

      expect(find.text('Crews'), findsOneWidget);
      expect(find.text('Sunrise Crew'), findsOneWidget);
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('#2 this week'), findsNWidgets(2));
      expect(find.text('Start a crew'), findsOneWidget);
      expect(find.text('Join with a code'), findsOneWidget);
      expect(find.text('Scan a crew QR'), findsOneWidget);
      await shot(tester, 'v13_crews_list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty: real next actions', (tester) async {
      await _pump(tester, const CrewGroupsScreen(), _overrides());

      expect(find.text('Race with a crew'), findsOneWidget);
      expect(find.text('Start a crew'), findsOneWidget);
      expect(find.text('Join with a code'), findsOneWidget);
      await shot(tester, 'v13_crews_empty');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error: failed list shows error + Retry', (tester) async {
      final squads = _StubSquadRepo(
        listError: const ApiException(500, 'Server error'),
      );
      await _pump(tester, const CrewGroupsScreen(), _overrides(squads: squads));

      expect(find.text("Couldn't load your crews"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await shot(tester, 'v13_crews_error');
      expect(tester.takeException(), isNull);
    });
  });

  group('CrewJoinScreen (/crews/join/:code)', () {
    testWidgets('populated: code + join confirm', (tester) async {
      await _pump(tester, const CrewJoinScreen(code: 'K7PQ2M'), _overrides());

      expect(find.text('Join a crew'), findsOneWidget);
      expect(find.text('Join this crew?'), findsOneWidget);
      expect(find.text('K7PQ2M'), findsOneWidget);
      expect(find.text('Join crew'), findsOneWidget);
      await shot(tester, 'v13_crew_join');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error: failed join shows the server message', (tester) async {
      final squads = _StubSquadRepo(
        joinError: const ApiException(404, 'That code did not work.'),
      );
      await _pump(
        tester,
        const CrewJoinScreen(code: 'BAD123'),
        _overrides(squads: squads),
      );

      await tester.tap(find.text('Join crew'));
      await tester.pumpAndSettle();
      expect(find.text('That code did not work.'), findsOneWidget);
      expect(find.text('Join crew'), findsOneWidget);
      await shot(tester, 'v13_crew_join_error');
      expect(tester.takeException(), isNull);
    });
  });

  group('CrewSettingsScreen (/crews/:id/settings)', () {
    testWidgets('populated: name, code, about, leave, delete', (tester) async {
      final squads = _StubSquadRepo(groups: [_group()], detailData: _detail());
      await _pump(
        tester,
        const CrewSettingsScreen(groupId: 'c1'),
        _overrides(squads: squads),
      );

      expect(find.text('Crew settings'), findsOneWidget);
      expect(find.text('NAME'), findsOneWidget);
      expect(find.text('Save name'), findsOneWidget);
      expect(find.text('CREW CODE'), findsOneWidget);
      expect(find.text('SUN123'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('Your role'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Leave crew'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Delete crew'), findsOneWidget);
      await shot(tester, 'v13_crew_settings');
      expect(tester.takeException(), isNull);
    });

    testWidgets('error: failed detail shows error + Retry', (tester) async {
      final squads = _StubSquadRepo(
        detailError: const ApiException(500, 'Server error'),
      );
      await _pump(
        tester,
        const CrewSettingsScreen(groupId: 'c1'),
        _overrides(squads: squads),
      );

      expect(find.text("Couldn't load crew settings"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await shot(tester, 'v13_crew_settings_error');
      expect(tester.takeException(), isNull);
    });
  });
}
