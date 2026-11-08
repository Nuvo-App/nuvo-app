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
import 'package:nuvo/features/races/data/motion_catalog.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
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
}
