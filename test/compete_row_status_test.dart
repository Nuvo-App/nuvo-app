import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

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
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _race(
  String id, {
  required int mine,
  List<int> others = const [10],
  String status = 'active',
  RaceViewerContext? vc,
}) {
  RaceParticipant p(String uid, int v) => RaceParticipant(
        id: 'p-$uid',
        userId: uid,
        displayName: uid == 'user-1' ? 'Test User' : 'Racer $uid',
        progressValue: v,
        progressPercent: v,
        joinedAt: '2026-01-01T00:00:00Z',
      );
  return Race(
    id: id,
    creatorId: 'user-1',
    title: 'Race $id',
    goalType: 'first_to_goal',
    targetValue: 100,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    viewerContext: vc,
    participants: [
      p('user-1', mine),
      for (var i = 0; i < others.length; i++) p('o$i', others[i]),
    ],
  );
}

Widget _app(List<Race> races, {Brightness b = Brightness.light}) =>
    ProviderScope(
      overrides: [
        raceRepositoryProvider.overrideWithValue(_StubRaceRepo(races)),
        authControllerProvider
            .overrideWith((ref) => AuthController(_FakeAuthRepo())),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: b),
        home: const CompeteScreen(),
      ),
    );

void main() {
  group('competeRowStatus', () {
    test('leading / chasing / waiting / finished / not started', () {
      final lead = competeRowStatus(_race('a', mine: 50), 'user-1')!;
      expect(lead.label, "You're leading");
      expect(lead.tone, RaceRowTone.leading);

      final chase = competeRowStatus(_race('b', mine: 5), 'user-1')!;
      expect(chase.label, "You're 2nd");
      expect(chase.tone, RaceRowTone.chasing);

      final wait = competeRowStatus(_race('c', mine: 0, others: []), 'user-1')!;
      expect(wait.label, 'Waiting for crew');
      expect(wait.tone, RaceRowTone.waiting);

      final done = competeRowStatus(
        _race('d', mine: 100, status: 'completed'),
        'user-1',
      )!;
      expect(done.tone, RaceRowTone.finished);

      final idle = competeRowStatus(
        _race('e', mine: 0, others: [0]),
        'user-1',
      )!;
      expect(idle.label, 'At the start line');
      expect(idle.tone, RaceRowTone.waiting);

      final soon = competeRowStatus(
        _race('f',
            mine: 0,
            vc: const RaceViewerContext(
                raceId: 'f', status: 'active', startsInSeconds: 17 * 60)),
        'user-1',
      )!;
      expect(soon.label, 'Starts in 17m');
    });
  });

  group('Compete rows carry a status pill', () {
    final races = [
      _race('lead', mine: 50),
      _race('chase', mine: 5),
      _race('idle', mine: 0, others: [0]),
      _race('x4', mine: 30, others: [60, 40]),
    ];

    Future<void> setUp(WidgetTester t, {Brightness b = Brightness.light}) async {
      await t.binding.setSurfaceSize(const Size(320, 568));
      t.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        t.binding.setSurfaceSize(null);
        t.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await t.pumpWidget(_app(races, b: b));
      await t.pumpAndSettle();
    }

    void expectEveryRowLabelled(WidgetTester t) {
      final rows = find.byType(RaceRow).evaluate().length;
      expect(rows, greaterThan(0));
      expect(find.byType(RaceStatusPill).evaluate().length, rows);
      for (final e in find.byType(RaceRow).evaluate()) {
        final row = e.widget as RaceRow;
        expect(row.raised, isFalse, reason: 'no unexplained lift');
        expect(row.statusLabel, isNotNull);
      }
    }

    testWidgets('collapsed list: right labels, no overflow at 320x568 / 1.4',
        (t) async {
      await setUp(t);
      expect(find.text("You're leading"), findsOneWidget);
      expect(find.text("You're 2nd"), findsOneWidget);
      expect(find.text('At the start line'), findsOneWidget);
      expectEveryRowLabelled(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('See all uses the same labels', (t) async {
      await setUp(t);
      await t.ensureVisible(find.text('See all'));
      await t.tap(find.text('See all'));
      await t.pumpAndSettle();
      expect(find.byType(RaceRow), findsNWidgets(4));
      expect(find.text("You're 3rd"), findsOneWidget);
      expectEveryRowLabelled(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('dark mode renders without error', (t) async {
      await setUp(t, b: Brightness.dark);
      expectEveryRowLabelled(t);
      expect(t.takeException(), isNull);
    });
  });
}
