import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/core/widgets/nuvo_back_header.dart';
import 'package:nuvo/core/widgets/nuvo_icons.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';

Map<String, dynamic> _g(String id, String name) => {
      'id': id,
      'name': name,
      'joinCode': 'CODE$id',
      'isOwner': true,
      'memberCount': 4,
      'raceCount': 1,
    };

Map<String, dynamic> _s(String id, String name, int rank, int pts,
        {bool you = false}) =>
    {
      'userId': id,
      'displayName': name,
      'rank': rank,
      'points': pts,
      'wins': rank == 1 ? 2 : 0,
      'races': 2,
      'isYou': you,
    };

class _Repo implements SquadRepository {
  _Repo(this.groups);
  final List<Map<String, dynamic>> groups;

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) async {
    final raw = {'squads': groups};
    return Conditional(data: parseCrewGroupList(raw), etag: 'e', raw: raw);
  }

  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) async {
    final raw = {
      'squad': _g(id, 'Sunrise Crew With A Rather Long Name'),
      'races': [
        {'id': 'r1', 'title': 'Morning push-ups', 'status': 'active'},
      ],
      'members': [
        {'userId': '2', 'displayName': 'Ben', 'role': 'owner'},
        {'userId': '1', 'displayName': 'Ava Long', 'role': 'admin'},
        {'userId': '3', 'displayName': 'Cy Extremely Long Name', 'role': 'member'},
        {'userId': '4', 'displayName': 'Dee', 'role': 'member'},
      ],
      'standings': [
        _s('1', 'Ava Long', 1, 9),
        _s('2', 'Ben', 2, 6, you: true),
        _s('3', 'Cy Extremely Long Name', 3, 3),
        _s('4', 'Dee', 4, 1),
      ],
    };
    return Conditional(
        data: CrewGroupDetail.fromJson(raw), etag: 'd', raw: raw);
  }

  @override
  Future<CrewGroup> create(String name) async => CrewGroup.fromJson(_g('n', name));
  @override
  Future<void> join(String code) async {}
  @override
  Future<int> addRace(String id, String raceId) async => 1;
  @override
  Future<void> leave(String id) async {}

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> setRole(String id, String userId, String role) async {}

  @override
  Future<void> removeMember(String id, String userId) async {}

  @override
  Future<void> removeRace(String id, String raceId) async {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  List<Map<String, dynamic>> groups, {
  Size size = const Size(390, 844),
  double scale = 1.0,
  double top = 59,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: top);
  tester.view.viewPadding = FakeViewPadding(top: top);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final c = SquadController(_Repo(groups), CacheStore.memory(),
      accountId: () => 'u1');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [squadControllerProvider.overrideWith((ref) => c)],
      child: MaterialApp(
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        home: screen,
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final list = [_g('a', 'Sunrise Crew'), _g('b', 'Night Owls')];

  testWidgets('list header clears the Dynamic Island', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), list);
    expect(tester.getTopLeft(find.byType(NuvoBackHeader)).dy,
        greaterThanOrEqualTo(59));
    expect(find.text('Crews'), findsOneWidget);
    expect(find.text('Sunrise Crew'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('CODEa'), findsOneWidget);
    expect(find.text('Start a crew'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header clears nothing-inset devices too', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), list, top: 0);
    expect(tester.getTopLeft(find.byType(NuvoBackHeader)).dy,
        greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state is centered in the viewport', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), const []);
    expect(find.text('Race with a crew'), findsOneWidget);
    final y = tester.getCenter(find.text('Race with a crew')).dy;
    expect(y, greaterThan(250));
    expect(y, lessThan(550));
    expect(tester.takeException(), isNull);
  });

  testWidgets('list: no overflow at 320x568 and 1.4 scale', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), list,
        size: const Size(320, 568), scale: 1.4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty: no overflow at 320x568 and 1.4 scale', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), const [],
        size: const Size(320, 568), scale: 1.4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail: races first (each its own card), members second, QR sheet',
      (tester) async {
    await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), const []);
    expect(tester.getTopLeft(find.byType(NuvoBackHeader)).dy,
        greaterThanOrEqualTo(59));
    // No crew-wide leaderboard any more: races lead, members follow.
    expect(find.text('Leaderboard'), findsNothing);
    expect(find.byKey(const ValueKey('crew-summary')), findsOneWidget);
    expect(find.text('Add people'), findsOneWidget);
    expect(find.text('Add race'), findsOneWidget); // I own this crew
    // The Races tab is the default and lists each race as its own card.
    expect(find.text('Races (1)'), findsOneWidget);
    expect(find.text('Morning push-ups'), findsOneWidget);
    expect(find.text('Tap a race to see its leaderboard.'), findsOneWidget);
    await tester.tap(find.text('Members (4)'));
    await tester.pumpAndSettle();
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Ava Long'), findsOneWidget);
    // Add people opens the QR + code sheet.
    await tester.tap(find.text('Add people').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crew-qr')), findsOneWidget);
    expect(find.text('Crew code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail: no overflow at 320x568 and 1.4 scale', (tester) async {
    await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), const [],
        size: const Size(320, 568), scale: 1.4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders list and detail', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), list, dark: true);
    expect(tester.takeException(), isNull);
    await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), const [],
        dark: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Races (1)'), findsOneWidget);
  });

  group('crew icon', () {
    const sizes = [
      Size(320, 568),
      Size(375, 667),
      Size(390, 844),
      Size(393, 852),
      Size(430, 932),
    ];
    for (final size in sizes) {
      testWidgets('list cards use it at $size', (tester) async {
        await _pump(tester, const CrewGroupsScreen(), list, size: size);
        expect(find.byType(NuvoCrewIcon), findsNWidgets(2));
        expect(find.byIcon(Icons.groups_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
      testWidgets('empty state uses it at $size', (tester) async {
        await _pump(tester, const CrewGroupsScreen(), const [], size: size);
        expect(find.byType(NuvoCrewIcon), findsOneWidget);
        expect(find.byIcon(Icons.groups_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
