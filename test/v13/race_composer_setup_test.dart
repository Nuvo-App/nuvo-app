// Widget coverage for the v13 composer correctness gaps — drives the real
// four-step composer and asserts the POST /races body it produces.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/core/config/nuvo_flags.dart';
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';
import 'package:nuvo/features/races/domain/race_draft.dart';
import 'package:nuvo/features/races/presentation/motion_catalog_provider.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/v13/composer/race_composer_v13_screen.dart';

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

class _Store extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'test-token';
}

/// A real repository wired to a MockClient so the exact create body the app
/// sends can be asserted end-to-end; only the friends lookup is stubbed.
class _WireRaceRepo extends RaceRepository {
  _WireRaceRepo({required this.onBody})
    : super(
        RaceApi(
          client: MockClient((req) async {
            if (req.method == 'POST' && req.url.path.endsWith('/races')) {
              onBody(jsonDecode(req.body) as Map<String, dynamic>);
              return http.Response(
                jsonEncode({
                  'race': {
                    'id': 'race-test',
                    'creatorId': 'user-1',
                    'title': 'Race',
                    'goalType': 'timed_attempt',
                    'status': 'active',
                    'createdAt': '2026-01-01T00:00:00Z',
                    'updatedAt': '2026-01-01T00:00:00Z',
                  },
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'races': []}), 200);
          }),
        ),
        _Store(),
        AuthApi(),
      );

  final void Function(Map<String, dynamic>) onBody;

  @override
  Future<List<PublicUser>> getCrew() => Future.value(const []);
}

Widget _app(RaceRepository repo, {required Widget home}) => ProviderScope(
  overrides: [
    raceRepositoryProvider.overrideWithValue(repo),
    authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
    // The bundled catalog snapshot — deterministic, all bundled movements.
    motionCatalogProvider.overrideWith(
      (_) async => MotionCatalogSnapshot.bundled(),
    ),
  ],
  child: MaterialApp(home: home),
);

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The step bodies are lazy ListViews — scroll a label into view, then tap.
Future<void> _tapVisible(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _toSetup(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'First to 100 pushups');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Set it up'));
  await tester.pumpAndSettle();
  expect(find.text('Set it up.'), findsOneWidget);
}

Future<void> _toReview(WidgetTester tester) async {
  await _tapVisible(tester, 'Invite friends');
  await _tapVisible(tester, 'Review race');
  expect(find.text('Start the race?'), findsOneWidget);
}

void main() {
  testWidgets('test_gap1_create_race_sends_finish_line_and_attempt_fields', (
    tester,
  ) async {
    _size(tester);
    final bodies = <Map<String, dynamic>>[];
    final repo = _WireRaceRepo(onBody: bodies.add);
    await tester.pumpWidget(_app(repo, home: const RaceComposerV13Screen()));
    await tester.pumpAndSettle();

    // UI path: Best single + a finish line — _createRace must forward
    // finishLineAt through controller → repository → POST /races.
    await _toSetup(tester);
    await _tapVisible(tester, 'Best single');
    await _tapVisible(tester, 'In 1 week');
    await _toReview(tester);
    await tester.tap(find.text('Start race'));
    await tester.pumpAndSettle();

    expect(bodies, hasLength(1));
    expect(bodies.single['format'], 'best_attempt');
    expect(bodies.single['finishLineAt'], isNotNull);

    // The attempt fields ride the same additive params — drive the same
    // controller the screen used and assert they reach the wire body.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RaceComposerV13Screen)),
    );
    await container.read(raceControllerProvider.notifier).createRace(
      title: 'Timed battle',
      goalType: 'timed_attempt',
      unit: 'reps',
      targetUnit: 'reps',
      metric: 'reps',
      format: 'timed_attempt',
      proofRequirement: 'ai_check',
      proofReviewMode: 'auto_accept',
      proofMode: 'ai_check',
      finishLineAt: '2026-01-08T00:00:00Z',
      attemptDurationSeconds: 30,
      attemptLimit: 3,
    );
    expect(bodies, hasLength(2));
    expect(bodies[1]['finishLineAt'], '2026-01-08T00:00:00Z');
    expect(bodies[1]['attemptDurationSeconds'], 30);
    expect(bodies[1]['attemptLimit'], 3);
  });

  testWidgets('test_gap5_timed_battle_duration_picker_sets_draft', (
    tester,
  ) async {
    _size(tester);
    final bodies = <Map<String, dynamic>>[];
    final repo = _WireRaceRepo(onBody: bodies.add);
    await tester.pumpWidget(_app(repo, home: const RaceComposerV13Screen()));
    await tester.pumpAndSettle();

    await _toSetup(tester);
    await _tapVisible(tester, 'Timed battle');
    await _tapVisible(tester, '30 s');
    await _tapVisible(tester, '3');
    await _tapVisible(tester, 'In 1 week');
    await _toReview(tester);

    // Review shows the attempt timing before the race goes live.
    expect(find.text('Attempt length'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.text('Attempts'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Start race'));
    await tester.pumpAndSettle();
    expect(bodies, hasLength(1));
    expect(bodies.single['format'], 'timed_attempt');
    expect(bodies.single['attemptDurationSeconds'], 30);
    expect(bodies.single['attemptLimit'], 3);
    expect(bodies.single['finishLineAt'], isNotNull);
  });

  testWidgets('test_gap9_all_available_movements_rendered', (tester) async {
    _size(tester);
    NuvoFlags.customMotion.value = true;
    addTearDown(() => NuvoFlags.customMotion.value = false);
    final repo = _WireRaceRepo(onBody: (_) {});
    await tester.pumpWidget(_app(repo, home: const RaceComposerV13Screen()));
    await tester.pumpAndSettle();
    await _toSetup(tester);

    // The grid is lazy inside the step ListView — scroll down, collecting
    // every movement label until the trailing Custom tiles are in view.
    final titles = motionActivityDefinitions.map((d) => d.title).toSet();
    final found = <String>{};
    var guard = 0;
    while (find.text('Custom goal').evaluate().isEmpty && guard++ < 40) {
      for (final t in titles) {
        if (find.text(t).evaluate().isNotEmpty) found.add(t);
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
    }
    for (final t in titles) {
      if (find.text(t).evaluate().isNotEmpty) found.add(t);
    }
    expect(found, containsAll(titles));
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Custom goal'), findsOneWidget);
  });

  testWidgets('test_gap11_lower_wins_toggle_best_attempt', (tester) async {
    _size(tester);
    final bodies = <Map<String, dynamic>>[];
    final repo = _WireRaceRepo(onBody: bodies.add);
    await tester.pumpWidget(_app(repo, home: const RaceComposerV13Screen()));
    await tester.pumpAndSettle();
    await _toSetup(tester);

    // First to (the default) never shows a win-direction control.
    for (var i = 0; i < 6; i++) {
      expect(find.text('WIN DIRECTION'), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump();
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
    await tester.pumpAndSettle();

    await _tapVisible(tester, 'Best single');
    expect(find.text('WIN DIRECTION'), findsOneWidget);
    expect(find.text('Most wins'), findsOneWidget);
    await _tapVisible(tester, 'Lowest wins');
    await _tapVisible(tester, 'In 1 week');
    await _toReview(tester);
    await tester.tap(find.text('Start race'));
    await tester.pumpAndSettle();

    expect(bodies, hasLength(1));
    expect(bodies.single['format'], 'best_attempt');
    expect(bodies.single['scoreDirection'], 'lower');
  });

  testWidgets('test_gapN10_custom_movement_offers_all_modes', (tester) async {
    _size(tester);
    final repo = _WireRaceRepo(onBody: (_) {});
    // A taught-custom draft: camera-verified movement without a preset
    // catalog entry. Edited fields guard the merge so the name step
    // carries the draft through untouched.
    final custom = RaceDraft(
      title: 'Cartwheels',
      hasCustomName: true,
      activity: motionActivityDefinitions.first,
      metric: RaceMetric.reps,
      format: RaceFormat.firstToGoal,
      targetValue: 10,
      customActivityName: 'Cartwheels',
      userEditedFields: const {
        RaceField.title,
        RaceField.activity,
        RaceField.goalKind,
        RaceField.format,
        RaceField.target,
      },
    );
    await tester.pumpWidget(
      _app(
        repo,
        home: RaceComposerV13Screen(
          prefill: RaceCreatePrefill(draft: custom),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set it up'));
    await tester.pumpAndSettle();

    for (final mode in [
      'First to',
      'Most total',
      'Best single',
      'Timed battle',
    ]) {
      await tester.scrollUntilVisible(
        find.text(mode),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(mode), findsOneWidget, reason: mode);
    }
  });
}
