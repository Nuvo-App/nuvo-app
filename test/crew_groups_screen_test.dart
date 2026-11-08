import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
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

class _Repo extends SquadRepository {
  _Repo(this.groups) : super(SquadApi(), SecureTokenStore(), AuthApi());
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
      'races': const <Map<String, dynamic>>[],
      'members': const <Map<String, dynamic>>[],
      'standings': const <Map<String, dynamic>>[],
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
  Future<void> leave(String id) async {}

  @override
  Future<void> deleteCrew(String id) async {}

  @override
  Future<void> rename(String id, String name) async {}
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  List<Map<String, dynamic>> groups, {
  Size size = const Size(390, 844),
  double scale = 1.0,
  double top = 59,
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
  final c = SquadController(
    _Repo(groups),
    CacheStore.memory(),
    accountId: () => 'u1',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [squadControllerProvider.overrideWith((ref) => c)],
      child: MaterialApp(home: screen),
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
    expect(
      tester.getTopLeft(find.byType(V13BackBar)).dy,
      greaterThanOrEqualTo(59),
    );
    expect(find.text('Crews'), findsOneWidget);
    expect(find.text('Sunrise Crew'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('Start a crew'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Scan a crew QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header clears nothing-inset devices too', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), list, top: 0);
    expect(
      tester.getTopLeft(find.byType(V13BackBar)).dy,
      greaterThanOrEqualTo(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state is centered in the viewport', (tester) async {
    await _pump(tester, const CrewGroupsScreen(), const []);
    expect(find.text('Race with a crew'), findsOneWidget);
    expect(find.text('Start a crew'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    final y = tester.getCenter(find.text('Race with a crew')).dy;
    expect(y, greaterThan(250));
    expect(y, lessThan(550));
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state shows the message and a Retry', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = SquadController(
      _FailingRepo(),
      CacheStore.memory(),
      accountId: () => 'u1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squadControllerProvider.overrideWith((ref) => c)],
        child: const MaterialApp(home: CrewGroupsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your crews"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list: no overflow at 320x568 and 1.4 scale', (tester) async {
    await _pump(
      tester,
      const CrewGroupsScreen(),
      list,
      size: const Size(320, 568),
      scale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty: no overflow at 320x568 and 1.4 scale', (tester) async {
    await _pump(
      tester,
      const CrewGroupsScreen(),
      const [],
      size: const Size(320, 568),
      scale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('join confirm shows the code and one primary action', (
    tester,
  ) async {
    await _pump(tester, const CrewJoinScreen(code: 'K7PQ2M'), list);
    expect(find.text('Join this crew?'), findsOneWidget);
    expect(find.text('K7PQ2M'), findsOneWidget);
    expect(
      find.text('You will join its leaderboard and its running races.'),
      findsOneWidget,
    );
    expect(find.text('Join crew'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('join confirm: no overflow at 320x568 and 1.4 scale', (
    tester,
  ) async {
    await _pump(
      tester,
      const CrewJoinScreen(code: 'K7PQ2M'),
      list,
      size: const Size(320, 568),
      scale: 1.4,
    );
    expect(tester.takeException(), isNull);
  });

  group('crew icon tile', () {
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
        // One tile per crew card + the join/scan row tiles.
        expect(find.byType(V13IconTile), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      });
      testWidgets('empty state icon at $size', (tester) async {
        await _pump(tester, const CrewGroupsScreen(), const [], size: size);
        expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FailingRepo extends SquadRepository {
  _FailingRepo() : super(SquadApi(), SecureTokenStore(), AuthApi());

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) =>
      Future.error(const ApiException(500, 'Server error'));
}
