// Coverage for the shell's tab-stack contract:
//  - switching tabs preserves each destination's mounted state (scroll
//    offsets, counters, any ephemeral widget state)
//  - the switch animates directionally (incoming tab slides from the
//    direction of travel, outgoing slides off opposite)
//  - hidden tabs stay mounted but are offstage, non-ticking, and unfocusable
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/theme/app_colors.dart';
import 'package:nuvo/features/arena/data/arena_api.dart';
import 'package:nuvo/features/arena/data/arena_models.dart';
import 'package:nuvo/features/arena/data/arena_repository.dart';
import 'package:nuvo/features/arena/presentation/arena_controller.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/motion_catalog_cache.dart';
import 'package:nuvo/features/races/data/motion_catalog_repository.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/motion_catalog_provider.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/core/widgets/nuvo_motion.dart';
import 'package:nuvo/features/social/data/crew_activity.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _AuthRepo extends AuthRepository {
  _AuthRepo() : super(AuthApi(), SecureTokenStore());

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

class _RaceRepo extends RaceRepository {
  _RaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<Race>> getRaces() async => const [];
}

class _ArenaRepo extends ArenaRepository {
  _ArenaRepo() : super(ArenaApi(), SecureTokenStore(), AuthApi());

  @override
  Future<ArenaSnapshot> getArenaSnapshot() async =>
      const ArenaSnapshot(mode: 'real', headerPulse: '');
}

class _CrewRepo implements CrewRepository {
  @override
  Future<List<PublicUser>> getCrew() async => const [];

  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();

  @override
  Future<List<CrewSearchResult>> search(String query) async => const [];

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

class _FeedRepo extends CrewActivityRepository {
  _FeedRepo() : super(CrewActivityApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<CrewActivityItem>> getFeed({int limit = 40, String? cursor}) =>
      Future.value(const []);
}

class _NotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: [], unreadCount: 0);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

class _CatalogRepo extends MotionCatalogRepository {
  _CatalogRepo() : super(RaceApi(), MotionCatalogCache());

  @override
  Future<MotionCatalogSnapshot> load({bool force = false}) async =>
      MotionCatalogSnapshot.bundled();
}

// ── Stub tab screen ───────────────────────────────────────────────────────────

/// A scrollable tab with ephemeral widget state — scroll offset plus a
/// counter. If the tab were re-created on every switch, both would reset.
class _StubTab extends StatefulWidget {
  const _StubTab(this.tag);

  final String tag;

  @override
  State<_StubTab> createState() => _StubTabState();
}

class _StubTabState extends State<_StubTab> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Kept above the lazy list so the counter stays mounted even after
        // the list scrolls its first rows out of the viewport.
        GestureDetector(
          key: ValueKey('bump-${widget.tag}'),
          onTap: () => setState(() => _taps++),
          child: Text('${widget.tag}-tab', textDirection: TextDirection.ltr),
        ),
        Text('taps-${widget.tag}:$_taps'),
        Expanded(
          child: ListView(
            key: ValueKey('scroll-${widget.tag}'),
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 100, child: Text('${widget.tag}-row-$i')),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Harness ───────────────────────────────────────────────────────────────────

Future<void> _pumpShell(
  WidgetTester tester, {
  String initialLocation = '/arena',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  const tabs = ['arena', 'compete', 'move', 'pass', 'profile'];
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      // Mirror the production wiring: StatefulShellRoute with NuvoTabStack
      // as the branch container.
      StatefulShellRoute(
        navigatorContainerBuilder: (context, shell, children) =>
            NuvoTabStack(index: shell.currentIndex, children: children),
        builder: (context, state, shell) => MainShell(child: shell),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/$tab',
                  builder: (context, state) => _StubTab(tab),
                ),
              ],
            ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) => AuthController(_AuthRepo()),
        ),
        raceRepositoryProvider.overrideWithValue(_RaceRepo()),
        arenaRepositoryProvider.overrideWithValue(_ArenaRepo()),
        crewRepositoryProvider.overrideWithValue(_CrewRepo()),
        crewActivityRepositoryProvider.overrideWithValue(_FeedRepo()),
        notificationRepositoryProvider.overrideWithValue(_NotifRepo()),
        motionCatalogRepositoryProvider.overrideWithValue(_CatalogRepo()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

double _scrollOffset(WidgetTester tester, String tag) {
  final state = tester.state<ScrollableState>(
    find.descendant(
      of: find.byKey(ValueKey('scroll-$tag')),
      matching: find.byType(Scrollable),
    ),
  );
  return state.position.pixels;
}

/// nav label → page marker → nav icon, in canonical order.
const _tabMap = <String, (String marker, IconData icon)>{
  'Arena': ('arena-tab', Icons.stadium_outlined),
  'Compete': ('compete-tab', Icons.emoji_events_outlined),
  'Verify': ('move-tab', Icons.gpp_good_outlined),
  'Crew': ('pass-tab', Icons.group_outlined),
  'Profile': ('profile-tab', Icons.person_outline),
};

void _expectSelected(WidgetTester tester, String label) {
  final (marker, _) = _tabMap[label]!;
  expect(
    find.text(marker),
    findsOneWidget,
    reason: '$label must show its own page',
  );
  // Selection reads through Nuvo blue on the nav label for every
  // destination — including Verify, whose icon stays white on its circle.
  expect(
    tester.widget<Text>(find.text(label)).style?.color,
    NuvoColors.blue,
    reason: '$label must be the highlighted nav destination',
  );
}

void main() {
  testWidgets('every nav destination shows its own page and highlights', (
    tester,
  ) async {
    await _pumpShell(tester);
    for (final label in _tabMap.keys) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      _expectSelected(tester, label);
    }
  });

  testWidgets('body and nav agree across a full tab tour', (tester) async {
    await _pumpShell(tester);
    for (final label in ['Crew', 'Compete', 'Profile', 'Verify', 'Arena']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      _expectSelected(tester, label);
    }
  });

  testWidgets('deep links select the correct destination', (tester) async {
    await _pumpShell(tester, initialLocation: '/move');
    _expectSelected(tester, 'Verify');

    await _pumpShell(tester, initialLocation: '/pass');
    _expectSelected(tester, 'Crew');
  });

  testWidgets('tab switch preserves scroll offset and widget state', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Mutate state first — the bump control scrolls offscreen after the
    // drag, so it must be tapped while still visible.
    await tester.tap(find.byKey(const ValueKey('bump-arena')));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('scroll-arena')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester, 'arena');
    expect(offset, greaterThan(200));
    expect(find.text('taps-arena:1'), findsOneWidget);

    // Arena → Crew → Arena.
    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arena'));
    await tester.pumpAndSettle();

    expect(
      _scrollOffset(tester, 'arena'),
      offset,
      reason: 'the arena tab must keep its scroll position across switches',
    );
    expect(
      find.text('taps-arena:1'),
      findsOneWidget,
      reason: 'ephemeral tab state must survive switching away and back',
    );
  });

  testWidgets('hidden tabs stay mounted but offstage and non-ticking', (
    tester,
  ) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    // The Crew tab is live; Arena is still mounted but offstage.
    expect(find.text('pass-tab'), findsOneWidget);
    expect(find.text('arena-tab'), findsNothing);
    expect(
      find.text('arena-tab', skipOffstage: false),
      findsOneWidget,
      reason: 'visited tabs stay mounted for state preservation',
    );

    final offstages = tester.widgetList<Offstage>(
      find.ancestor(
        of: find.text('arena-tab', skipOffstage: false),
        matching: find.byType(Offstage, skipOffstage: false),
      ),
    );
    expect(
      offstages.any((o) => o.offstage),
      isTrue,
      reason: 'the shell must offstage hidden tabs (no layout/paint cost)',
    );

    // Route internals may insert their own (enabled) TickerMode inside the
    // branch; the shell's slot wrapper must be among the ancestors and off.
    // (matching needs skipOffstage: false — the wrapper lives inside the
    // offstage region it creates.)
    final tickerModes = tester.widgetList<TickerMode>(
      find.ancestor(
        of: find.text('arena-tab', skipOffstage: false),
        matching: find.byType(TickerMode, skipOffstage: false),
      ),
    );
    expect(
      tickerModes.any((m) => !m.enabled),
      isTrue,
      reason: 'hidden tabs must not keep animations/streams ticking',
    );
  });

  testWidgets('tab switch animates the incoming tab directionally', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Arena (index 0) → Crew (index 3): Crew arrives from the right.
    await tester.tap(find.text('Crew'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Ancestor finders hit the branch Navigator's own wrappers too, so
    // assert on the existence of the NuvoTabStack transition values rather
    // than the nearest ancestor.
    final opacities = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('pass-tab'),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity);
    expect(
      opacities.any((o) => o > 0.2 && o < 1.0),
      isTrue,
      reason: 'the incoming tab fades in mid-flight',
    );

    double dxOf(String tag) {
      final transforms = tester.widgetList<Transform>(
        find.ancestor(
          of: find.text('$tag-tab', skipOffstage: false),
          matching: find.byType(Transform),
        ),
      );
      return transforms
              .map((t) => t.transform.storage[12]) // Matrix4 x-translation
              .where((dx) => dx != 0)
              .firstOrNull ??
          0;
    }

    expect(
      dxOf('pass'),
      greaterThan(0),
      reason: 'moving to a rightward tab slides the new screen in '
          'from the right (positive dx, easing to zero)',
    );

    // The outgoing tab is still mounted mid-transition, sliding left.
    expect(
      dxOf('arena'),
      lessThan(0),
      reason: 'the outgoing tab slides off the opposite edge',
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('pass-tab'), findsOneWidget);
  });

  testWidgets('rapid tab switching settles on the last destination', (
    tester,
  ) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Crew'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Compete'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('profile-tab'), findsOneWidget);
    expect(find.text('compete-tab'), findsNothing);
  });

  testWidgets('selected destination reads through blue on icon + label', (
    tester,
  ) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    final icon = tester.widget<Icon>(find.byIcon(Icons.group_outlined));
    expect(
      icon.color,
      NuvoColors.blue,
      reason: 'the active destination settles on Nuvo blue',
    );
  });
}
