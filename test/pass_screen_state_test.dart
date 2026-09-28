import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/core/widgets/pressable_scale.dart';
import 'package:nuvo/core/demo/presentation_demo.dart';
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
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

const _passInfo = PassInfo(
  memberId: 'NUVO-001',
  passSlug: 'testuser',
  shareUrl: 'https://getnuvo.net/p/testuser',
);

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

  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

/// The presentation/testing identity — every controller reads
/// `isPresentationDemoUser(user)` and serves the demo fixtures, so this
/// one repo populates the whole Crew screen for layout tests.
class _DemoAuthRepo extends AuthRepository {
  _DemoAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(AuthUser(
        id: 'demo-viewer-1',
        email: 'team@getnuvo.net',
        isDemo: true,
        fullName: 'Maya Chen',
        username: 'maya',
        onboardingComplete: true,
        hasMemberPass: true,
        termsAccepted: true,
      ));

  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

class _PassRaceRepo extends RaceRepository {
  _PassRaceRepo({this.races = const [], this.throws = false})
      : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  final bool throws;
  int getRacesCalls = 0;

  @override
  Future<List<Race>> getRaces() async {
    getRacesCalls++;
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return races;
  }
}

/// Feed source for non-demo tests — returns the supplied canonical
/// items so partial states (races but no events, events but no races)
/// can be exercised independently.
class _FeedRepo extends CrewActivityRepository {
  _FeedRepo(this.items, {this.throws = false})
      : super(CrewActivityApi(), SecureTokenStore(), AuthApi());

  final List<CrewActivityItem> items;
  final bool throws;
  int reactCalls = 0;
  int unreactCalls = 0;
  int feedCalls = 0;

  @override
  Future<List<CrewActivityItem>> getFeed(
      {int limit = 40, String? cursor}) async {
    feedCalls++;
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return items;
  }

  @override
  Future<ReactionSummary> react(CrewActivityItem item, String emoji) async {
    reactCalls++;
    final counts = {...item.reactions};
    counts[emoji] = (counts[emoji] ?? 0) + 1;
    return ReactionSummary(counts: counts, myReaction: emoji);
  }

  @override
  Future<ReactionSummary> unreact(CrewActivityItem item) async {
    unreactCalls++;
    final counts = {...item.reactions};
    final mine = item.myReaction;
    if (mine != null) {
      final n = (counts[mine] ?? 0) - 1;
      n <= 0 ? counts.remove(mine) : counts[mine] = n;
    }
    return ReactionSummary(counts: counts);
  }
}

class _FakeCrewRepo implements CrewRepository {
  _FakeCrewRepo({
    this.throws = false,
    this.searchResults = const [],
    this.searchThrows = false,
    this.members = const [],
  });

  final bool throws;
  final List<CrewSearchResult> searchResults;
  final bool searchThrows;
  final List<PublicUser> members;

  @override
  Future<List<PublicUser>> getCrew() async {
    if (throws) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return members;
  }

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<List<CrewSearchResult>> search(String query) async {
    if (searchThrows) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return searchResults;
  }

  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();
  @override
  Future<ConnectOutcome> add(String userId) async => ConnectOutcome.active;
  @override
  Future<void> acceptRequest(String userId) async {}
  @override
  Future<void> declineRequest(String userId) async {}
  @override
  Future<void> remove(String userId) async {}

  @override
  Future<void> reportUser(String userId, {String? reason}) async {}
  @override
  Future<void> reportRace(String raceId, {String? reason}) async {}
  @override
  Future<void> reportContent(String contentId, {String? reason}) async {}
  @override
  Future<void> blockUser(String userId) async {}
  @override
  Future<void> unblockUser(String userId) async {}
}

class _FakeNotifRepo implements NotificationRepository {
  _FakeNotifRepo({this.throws = false});

  final bool throws;

  @override
  Future<NotificationPage> list({String? cursor}) async {
    if (throws) throw const ApiException(503, 'Service Unavailable');
    return const NotificationPage(items: [], unreadCount: 0);
  }
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildApp({
  bool crewThrows = false,
  List<CrewSearchResult> searchResults = const [],
  bool searchThrows = false,
  bool demo = false,
  List<PublicUser> members = const [],
  List<Race> races = const [],
  List<CrewActivityItem> feed = const [],
  CrewActivityRepository? feedRepo,
  RaceRepository? racesRepo,
  bool notifThrows = false,
}) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider
          .overrideWithValue(racesRepo ?? _PassRaceRepo(races: races)),
      crewRepositoryProvider.overrideWithValue(_FakeCrewRepo(
        throws: crewThrows,
        searchResults: searchResults,
        searchThrows: searchThrows,
        members: members,
      )),
      crewActivityRepositoryProvider
          .overrideWithValue(feedRepo ?? _FeedRepo(feed)),
      notificationRepositoryProvider
          .overrideWithValue(_FakeNotifRepo(throws: notifThrows)),
      authControllerProvider.overrideWith(
        (ref) => AuthController(demo ? _DemoAuthRepo() : _FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: PassScreen()),
  );
}

/// Let the restore → controller loads → fixture writes settle.
Future<void> _settleDemo(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400)); // debounce
  await tester.pump(); // microtask drain
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

/// Search lives behind the header icon now — tap it to expand the field.
Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search_rounded));
  await tester.pump();
}

void main() {
  group('PassScreen tab stability', () {
    /// The selector is a fixed region: switching lenses may only change
    /// what's below it. Any tab-conditional widget above the tabs (a live
    /// card, a spacer, different padding) shows up here as a moved Y.
    testWidgets('tab selector stays pixel-stable across all three tabs',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(demo: true));
      await _settleDemo(tester);
      // Populated demo — the live card is inside the For-you body.
      expect(find.text('Pushup Battle'), findsWidgets);

      double tabY(String label) =>
          tester.getTopLeft(find.text(label)).dy;
      final baseY = tabY('Activity');
      final forYouY = tabY('For you');
      final racesY = tabY('Races');

      await tester.tap(find.text('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tabY('Activity'), baseY);
      expect(tabY('For you'), forYouY);
      expect(tabY('Races'), racesY);

      await tester.tap(find.text('Races'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tabY('Activity'), baseY);
      expect(tabY('For you'), forYouY);
      expect(tabY('Races'), racesY);

      await tester.tap(find.text('For you'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tabY('Activity'), baseY);
    });
  });

  group('PassScreen populated demo', () {
    testWidgets('every lens renders real content, no dead canvas',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(demo: true));
      await _settleDemo(tester);

      // For you — live first, then direct moments.
      expect(find.text('Pushup Battle'), findsWidgets);
      expect(find.text('just passed you in Pushup Battle'), findsOneWidget);

      // Activity — a real stream, not an empty note.
      await tester.tap(find.text('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Jules Carter joined your crew'),
        findsOneWidget,
      );

      // Races — the full lifecycle shows.
      await tester.tap(find.text('Races'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Happening now'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('60 Second Squat Battle'), findsOneWidget);
    });
  });

  /// The key regression: For you is composed of independent modules —
  /// relationship and race data are content even when the event stream
  /// has nothing new to say.
  group('PassScreen For-you composition', () {
    testWidgets('shared races populate For You with zero feed events',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: PresentationDemoData.races('user-1'),
      ));
      await _settleDemo(tester);

      expect(find.text('Racing with your crew'), findsOneWidget);
      expect(find.text('Pushup Battle'), findsWidgets);
      expect(find.text('60 Second Squat Battle'), findsOneWidget);
      expect(find.text('Start a race'), findsOneWidget);
    });

    testWidgets(
        'quiet crew with race history gets action + recent + run it back',
        (tester) async {
      _tallViewport(tester);
      final finished = PresentationDemoData.races('user-1')
          .where((r) => r.status == 'completed')
          .toList();
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: finished,
      ));
      await _settleDemo(tester);

      expect(find.text('Start a race'), findsOneWidget);
      expect(find.text('Recently with your crew'), findsOneWidget);
      expect(find.textContaining('First To 30 Lunges'), findsWidgets);
      expect(find.text('Run it back'), findsOneWidget);
      expect(find.text('Rematch'), findsOneWidget);
    });

    testWidgets('feed events render without any active races',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        feed: PresentationDemoData.crewActivity('user-1'),
      ));
      await _settleDemo(tester);

      // Live item heads the surface even with no races loaded.
      expect(find.text('Pushup Battle'), findsWidgets);
      expect(find.text('From your crew'), findsOneWidget);
      expect(find.text('Start a race'), findsOneWidget);
    });

    testWidgets('social hero centers on the closest shared race',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: PresentationDemoData.races('user-1'),
      ));
      await _settleDemo(tester);

      // Pushup Battle (me 39, leader 50) is the tightest chase —
      // it heads the surface as the matchup card, once.
      expect(find.text('39 — 50'), findsOneWidget);
      expect(find.text('11 reps behind'), findsOneWidget);
      expect(find.text('You'), findsWidgets);
      expect(find.text('Sam'), findsWidgets);
      expect(find.text('See race'), findsOneWidget);
      // The hero's race doesn't repeat in "Racing with your crew".
      expect(find.text('Pushup Battle'), findsOneWidget);
    });

    testWidgets('finished races stay at result weight — no forced hero',
        (tester) async {
      _tallViewport(tester);
      final finished = PresentationDemoData.races('user-1')
          .where((r) => r.status == 'completed')
          .toList();
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: finished,
      ));
      await _settleDemo(tester);

      // A completed race is history, not a hero — no centerpiece chrome.
      expect(find.text('FINISHED'), findsNothing);
      expect(find.text('You took it'), findsNothing);
      expect(find.text('See result'), findsNothing);

      // The newest result is the rematch candidate — its own module, and
      // it does not repeat as the first row of recent history.
      expect(find.text('Run it back'), findsOneWidget);
      expect(find.text('Rematch'), findsOneWidget);
      expect(find.text('Recently with your crew'), findsOneWidget);
      expect(
        find.textContaining('First To 50 Running In Place'),
        findsOneWidget,
      );
      expect(find.textContaining('First To 30 Lunges'), findsWidgets);
    });

    testWidgets('recent rows and rematch survive a 320px viewport',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final finished = PresentationDemoData.races('user-1')
          .where((r) => r.status == 'completed')
          .toList();
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: finished,
      ));
      await _settleDemo(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Run it back'), findsOneWidget);
      expect(find.text('Rematch'), findsOneWidget);
      expect(find.text('Recently with your crew'), findsOneWidget);
    });

    testWidgets('hero matchup row survives a 320px viewport',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: PresentationDemoData.races('user-1'),
      ));
      await _settleDemo(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('39 — 50'), findsOneWidget);
    });

    testWidgets('live item still heads the surface over the hero',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: PresentationDemoData.races('user-1'),
        feed: PresentationDemoData.crewActivity('user-1'),
      ));
      await _settleDemo(tester);

      // Live beats hero — the navy live card renders, not the matchup.
      expect(find.text('LIVE'), findsWidgets);
      expect(find.text('See race'), findsNothing);
    });

    testWidgets('reaction chips render on reactionable social items',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        feed: PresentationDemoData.crewActivity('user-1'),
      ));
      await _settleDemo(tester);
      expect(find.text('From your crew'), findsOneWidget);
      for (final g in ['🔥', '👏', '💪']) {
        expect(find.text(g), findsWidgets);
      }
    });

    testWidgets('tapping a reaction chip adds then removes the reaction',
        (tester) async {
      _tallViewport(tester);
      final feed = PresentationDemoData.crewActivity('user-1');
      final repo = _FeedRepo(feed);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        feed: feed,
        feedRepo: repo,
      ));
      await _settleDemo(tester);

      // Tap the first visible 🔥 chip — the optimistic toggle lands before
      // the repo summary; a second tap removes it. Match the pressable
      // ancestor so the glyph inside body copy isn't hit instead.
      final fireChip = find.ancestor(
        of: find.text('🔥'),
        matching: find.byType(PressableScale),
      );
      await tester.tap(fireChip.first);
      await tester.pumpAndSettle();
      expect(repo.reactCalls, 1);
      expect(repo.unreactCalls, 0);

      await tester.tap(fireChip.first);
      await tester.pumpAndSettle();
      expect(repo.unreactCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('demo session renders fixtures when every request fails',
        (tester) async {
      _tallViewport(tester);
      final feedRepo = _FeedRepo(const [], throws: true);
      final racesRepo = _PassRaceRepo(throws: true);
      await tester.pumpWidget(_buildApp(
        demo: true,
        crewThrows: true,
        notifThrows: true,
        feedRepo: feedRepo,
        racesRepo: racesRepo,
      ));
      await _settleDemo(tester);

      // Presentation mode must be network-independent — the feed repo is
      // never called and fixtures render with visible reaction controls.
      expect(feedRepo.feedCalls, 0);
      expect(find.text('From your crew'), findsOneWidget);
      for (final g in ['🔥', '👏', '💪']) {
        expect(find.text(g), findsWidgets);
      }
      expect(find.byType(NuvoErrorState), findsNothing);
    });

    testWidgets('non-demo session surfaces the feed error and retries',
        (tester) async {
      _tallViewport(tester);
      final feedRepo = _FeedRepo(const [], throws: true);
      await tester.pumpWidget(_buildApp(
        crewThrows: true,
        feedRepo: feedRepo,
      ));
      await _settleDemo(tester);
      // A real account keeps production semantics — failed loads surface an
      // error state with a retry path.
      expect(feedRepo.feedCalls, greaterThan(0));
      expect(find.byType(NuvoErrorState), findsWidgets);
    });

    testWidgets('person sheet flips between identity and competition',
        (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(
        members: PresentationDemoData.crewMembers(),
        races: PresentationDemoData.races('user-1'),
        feed: PresentationDemoData.crewActivity('user-1'),
      ));
      await _settleDemo(tester);

      // Open the person sheet from a feed actor.
      await tester.tap(find.text('Noah Williams').first);
      await tester.pumpAndSettle();

      // Front = identity/relationship layer, stable actions below.
      expect(find.text('Your matchup ↻'), findsOneWidget);
      expect(find.text('Race Noah'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Flip to the competitive layer — the rivalry reveal.
      await tester.tap(find.text('Your matchup ↻'));
      await tester.pumpAndSettle();
      expect(find.text('VS'), findsOneWidget);
      expect(find.text('NOAH'), findsOneWidget);
      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('About Noah ↻'), findsOneWidget);
      expect(find.text('RECENT MATCHUPS'), findsOneWidget);
      expect(find.textContaining('TOGETHER'), findsOneWidget);

      // Flip back — chrome (affordance, actions) never moved.
      await tester.tap(find.text('About Noah ↻'));
      await tester.pumpAndSettle();
      expect(find.text('Your matchup ↻'), findsOneWidget);
      expect(find.text('VS'), findsNothing);
    });

    testWidgets('brand-new user gets the true empty note', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp());
      await _settleDemo(tester);

      expect(
        find.text('Race friends, classmates, teammates — whoever '
            'makes you want to win. Find someone above.'),
        findsOneWidget,
      );
    });
  });

  group('PassScreen crew section', () {
    testWidgets('crew error surfaces in the crew section', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(crewThrows: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('PassScreen search behavior', () {
    testWidgets('search failure shows error, not "no results"', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(searchThrows: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(NuvoErrorState), findsNothing);

      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);

      expect(find.text('Search failed. Try again.'), findsOneWidget);
      expect(find.text('No matching Nuvo members found.'), findsNothing);
    });

    testWidgets('successful search shows results', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(
        _buildApp(searchResults: const [
          CrewSearchResult(
            user: PublicUser(
              id: 'u2',
              displayName: 'John Doe',
              username: 'john',
              initials: 'JD',
            ),
            connectionStatus: CrewConnectionStatus.none,
          ),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);

      expect(find.text('Search failed. Try again.'), findsNothing);
      expect(find.text('No matching Nuvo members found.'), findsNothing);
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('retry after error re-runs the search', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(searchThrows: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      await tester.tap(find.text('Search failed. Try again.'));
      await _settleSearch(tester);
      // Still shows the error (still failing) — the tap re-ran, didn't crash.
      expect(find.text('Search failed. Try again.'), findsOneWidget);
    });

    testWidgets('clearing the query clears the error', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(searchThrows: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await _openSearch(tester);
      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.text('Search failed. Try again.'), findsNothing);
    });
  });
}
