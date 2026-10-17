// Visual loop for the Crews screens across phone sizes. With SHOTS_DIR set,
// each state is saved as <prefix>_<w>x<h>.png (see test/helpers/screenshot.dart);
// without it the shots are no-ops and this is a plain no-exceptions check.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/core/network/conditional.dart';
import 'package:nuvo/core/theme/app_theme.dart';
import 'package:nuvo/core/widgets/nuvo_button.dart';
import 'package:nuvo/features/squads/application/squad_controller.dart';
import 'package:nuvo/features/squads/data/squad_api.dart';
import 'package:nuvo/features/squads/presentation/crew_groups_screen.dart';

import 'helpers/screenshot.dart';

Map<String, dynamic> _g(
  String id,
  String name, {
  bool owner = true,
  String role = 'owner',
  int members = 4,
  int races = 3,
}) => {
  'id': id,
  'name': name,
  'joinCode': 'K7PQ2M$id',
  'isOwner': owner,
  'myRole': role,
  'memberCount': members,
  'raceCount': races,
};

class _Repo implements SquadRepository {
  _Repo(this.groups, this.detailJson, {this.deleted});
  final List<String>? deleted;
  final List<Map<String, dynamic>> groups;
  final Map<String, dynamic> Function(String id) detailJson;

  @override
  Future<Conditional<List<CrewGroup>>> list({String? etag}) async {
    final raw = {'squads': groups};
    return Conditional(data: parseCrewGroupList(raw), etag: 'e', raw: raw);
  }

  @override
  Future<Conditional<CrewGroupDetail>> detail(String id, {String? etag}) async {
    final raw = detailJson(id);
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
  Future<void> deleteCrew(String id) async => deleted?.add(id);
  @override
  Future<void> rename(String id, String name) async {}
  @override
  Future<void> setRole(String id, String userId, String role) async {}
  @override
  Future<void> removeMember(String id, String userId) async {}
  @override
  Future<void> removeRace(String id, String raceId) async {}
}

Map<String, dynamic> _detail({
  bool owner = true,
  String role = 'owner',
  bool alone = false,
  String name = 'Sunrise Crew With A Rather Long Name',
}) {
  final members = alone
      ? [
          {'userId': '2', 'displayName': 'Ben', 'role': 'owner'},
        ]
      : [
          {'userId': '2', 'displayName': 'Ben Carter', 'role': 'owner'},
          {'userId': '1', 'displayName': 'Ava Long', 'role': 'admin'},
          {'userId': '3', 'displayName': 'Cy Extremely Long Name', 'role': 'member'},
          {'userId': '4', 'displayName': 'Dee', 'role': 'member'},
        ];
  final races = alone
      ? <Map<String, dynamic>>[]
      : [
          {
            'id': 'r1',
            'title': 'Morning push-ups',
            'status': 'active',
            'targetValue': 50,
            'targetUnit': 'reps',
          },
          {
            'id': 'r2',
            'title': 'Plank hold showdown for the whole crew',
            'status': 'active',
            'targetValue': 120,
            'targetUnit': 'sec',
          },
          {'id': 'r3', 'title': 'Squat sprint', 'status': 'completed'},
        ];
  return {
    'squad': _g(
      'a',
      name,
      owner: owner,
      role: role,
      members: members.length,
      races: races.length,
    ),
    'races': races,
    'members': members,
    'standings': <Map<String, dynamic>>[],
  };
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  Size size, {
  List<Map<String, dynamic>> groups = const [],
  Map<String, dynamic> Function(String id)? detail,
  List<String>? deleted,
  bool router = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  const pad = FakeViewPadding(top: 47, bottom: 34);
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final c = SquadController(
    _Repo(groups, detail ?? (id) => _detail(), deleted: deleted),
    CacheStore.memory(),
    accountId: () => 'u1',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [squadControllerProvider.overrideWith((ref) => c)],
      child: router
          ? MaterialApp.router(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              routerConfig: GoRouter(
                initialLocation: '/settings',
                routes: [
                  GoRoute(path: '/settings', builder: (_, _) => screen),
                  GoRoute(
                    path: '/crews',
                    builder: (_, _) => const Scaffold(body: Text('crews-home')),
                  ),
                ],
              ),
            )
          : MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: screen,
            ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

String _n(Size s, String prefix) => '${prefix}_${s.width.toInt()}x${s.height.toInt()}';

void main() {
  setUpAll(loadShotFonts);
  const sizes = [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(393, 852),
    Size(430, 932),
  ];
  final list = [
    _g('a', 'Sunrise Crew'),
    _g('b', 'Night Owls And Early Birds Racing Club', members: 12, races: 1),
    _g('c', 'Lunch Break', owner: false, role: 'member', members: 2, races: 0),
  ];

  for (final size in sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('crews list $tag', (tester) async {
      await _pump(tester, const CrewGroupsScreen(), size, groups: list);
      await shot(tester, _n(size, 'crews_list'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('crews empty $tag', (tester) async {
      await _pump(tester, const CrewGroupsScreen(), size);
      await shot(tester, _n(size, 'crews_empty'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('start a crew sheet $tag', (tester) async {
      await _pump(tester, const CrewGroupsScreen(), size, groups: list);
      await tester.tap(find.text('Start a crew'));
      await tester.pumpAndSettle();
      await shot(tester, _n(size, 'crews_start'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('join sheet $tag', (tester) async {
      await _pump(tester, const CrewGroupsScreen(), size, groups: list);
      await tester.tap(find.text('Join with a code'));
      await tester.pumpAndSettle();
      await shot(tester, _n(size, 'crews_join'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail owner races $tag', (tester) async {
      await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), size);
      await shot(tester, _n(size, 'crew_owner_races'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail owner members $tag', (tester) async {
      await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), size);
      await tester.tap(find.textContaining('Members ('));
      await tester.pumpAndSettle();
      await shot(tester, _n(size, 'crew_owner_members'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail member races $tag', (tester) async {
      await _pump(
        tester,
        const CrewGroupDetailScreen(groupId: 'a'),
        size,
        detail: (id) => _detail(owner: false, role: 'member', name: 'Night Owls'),
      );
      await shot(tester, _n(size, 'crew_member_races'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail member members $tag', (tester) async {
      await _pump(
        tester,
        const CrewGroupDetailScreen(groupId: 'a'),
        size,
        detail: (id) => _detail(owner: false, role: 'member', name: 'Night Owls'),
      );
      await tester.tap(find.textContaining('Members ('));
      await tester.pumpAndSettle();
      await shot(tester, _n(size, 'crew_member_members'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail alone $tag', (tester) async {
      await _pump(
        tester,
        const CrewGroupDetailScreen(groupId: 'a'),
        size,
        detail: (id) => _detail(alone: true, name: 'Just Me'),
      );
      await shot(tester, _n(size, 'crew_alone'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('add people sheet $tag', (tester) async {
      await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), size);
      await tester.tap(find.text('Add people').first);
      await tester.pumpAndSettle();
      await shot(tester, _n(size, 'crew_qr'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings owner $tag', (tester) async {
      await _pump(tester, const CrewSettingsScreen(groupId: 'a'), size);
      await shot(tester, _n(size, 'crew_settings'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('join confirm $tag', (tester) async {
      await _pump(tester, const CrewJoinScreen(code: 'K7PQ2M'), size);
      await shot(tester, _n(size, 'crew_joinconfirm'));
      expect(tester.takeException(), isNull);
    });
  }

  group('delete crew', () {
    const size = Size(390, 844);
    Map<String, dynamic> Function(String) as(String role) =>
        (id) => _detail(owner: role == 'owner', role: role);

    testWidgets('owner sees Delete crew and gets a confirm dialog', (
      tester,
    ) async {
      final deleted = <String>[];
      await _pump(
        tester,
        const CrewSettingsScreen(groupId: 'a'),
        size,
        detail: as('owner'),
        deleted: deleted,
        router: true,
      );
      final btn = find.byKey(const ValueKey('crew-delete'));
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete Sunrise Crew'), findsOneWidget);
      expect(
        find.textContaining('This removes the crew for everyone'),
        findsOneWidget,
      );
      // Cancel leaves everything alone.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      // Confirm deletes and lands back on the Crews list.
      await tester.tap(btn);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NuvoDangerButton), matching: find.text('Delete crew')).last);
      await tester.pumpAndSettle();
      expect(deleted, ['a']);
      expect(find.text('crews-home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final role in ['admin', 'member']) {
      testWidgets('$role does not see Delete crew', (tester) async {
        await _pump(
          tester,
          const CrewSettingsScreen(groupId: 'a'),
          size,
          detail: as(role),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('crew-delete')), findsNothing);
        expect(find.text('Delete crew'), findsNothing);
        expect(find.text('Leave crew'), findsOneWidget);
      });
    }
  });

  group('share', () {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    const size = Size(390, 844);

    Future<void> openAndShare(WidgetTester tester) async {
      await _pump(tester, const CrewGroupDetailScreen(groupId: 'a'), size);
      await tester.tap(find.text('Add people').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
    }

    testWidgets('Share opens the share sheet with the invite text', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await openAndShare(tester);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      final args = calls.single.arguments as Map;
      expect(
        args['text'],
        'Join my crew "Sunrise Crew With A Rather Long Name" on Nuvo. '
        'Crew code: K7PQ2Ma\nhttps://getnuvo.net/c/K7PQ2Ma',
      );
      expect(args['originWidth'], greaterThan(0));
      expect(find.textContaining('Invite copied'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing share channel falls back to copying the invite', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'nope'),
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      await openAndShare(tester);
      expect(find.text('Invite copied — paste it into a message'), findsOneWidget);
      expect(copied, contains('https://getnuvo.net/c/K7PQ2Ma'));
      expect(tester.takeException(), isNull);
    });
  });
}
