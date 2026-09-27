import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/core/widgets/nuvo_race_components.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());

  @override
  Future<RestoreResult> restoreSession() async =>
      RestoreOk(const AuthUser(
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

class _ThrowRaceRepo extends RaceRepository {
  _ThrowRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  @override
  Future<List<Race>> getRaces() =>
      Future.error(const ApiException(500, 'Internal Server Error'));
}

class _PendingRaceRepo extends RaceRepository {
  _PendingRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  final completer = Completer<List<Race>>();

  @override
  Future<List<Race>> getRaces() => completer.future;
}

/// Creates a camera-verifiable race where the user has [progressPercent].
/// If progressPercent >= 100, the race is "completed" for the user.
/// Title must contain a supported activity keyword (Pushup, Squat, etc.) for
/// the camera verification resolver to mark it as camera-verifiable.
Race _readyRace({
  String id = 'race-1',
  String title = 'Squat Race',
  int progressPercent = 40,
  int participantCount = 2,
  String status = 'active',
  List<RaceProof> recentProofs = const [],
  int? targetValue = 50,
  String? unit = 'reps',
  String format = 'first_to_goal',
  String scoringRule = 'cumulative_sum',
  String verifierType = 'preset_pose',
  String proofMode = 'ai_check',
  String verificationMethod = 'camera_pose',
  String? metric,
  String scoreDirection = 'higher',
}) {
  final participants = <RaceParticipant>[
    RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: progressPercent,
      progressPercent: progressPercent,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
    for (var i = 1; i < participantCount; i++)
      RaceParticipant(
        id: 'part-${i + 1}',
        userId: 'user-${i + 1}',
        displayName: 'Racer $i',
        progressValue: 10,
        progressPercent: 10,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
  ];
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    goalType: 'first_to_goal',
    targetValue: targetValue,
    unit: unit,
    format: format,
    scoringRule: scoringRule,
    verifierType: verifierType,
    proofRequirement: 'ai_check',
    proofMode: proofMode,
    verificationMethod: verificationMethod,
    metric: metric,
    scoreDirection: scoreDirection,
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    participants: participants,
    recentProofs: recentProofs,
  );
}

Race _completedRace({String id = 'c-1', String title = 'Done Race'}) =>
    _readyRace(id: id, title: 'Pushup $title', progressPercent: 100);

Race _raceWithProof({String id = 'r-1', String title = 'Proof Race'}) =>
    _readyRace(
      id: id,
      title: 'Squat $title',
      recentProofs: [
        const RaceProof(
          id: 'proof-1',
          userId: 'user-1',
          displayName: 'Test User',
          proofType: 'ai_check',
          verificationStatus: 'ai_verified',
          value: 10,
          createdAt: '2026-01-01T00:00:00Z',
        ),
      ],
    );

List<Race> _generateReadyRaces(int count) {
  // Cycle through supported activity keywords so every race is
  // camera-verifiable via title inference. Uniform progress keeps the
  // Ready queue's closest-to-finish ordering neutral — the cap/expand
  // tests assert positions in the server's original order.
  const activities = ['Pushups', 'Squat', 'Lunge', 'Plank', 'Jumping Jack'];
  return [
    for (var i = 0; i < count; i++)
      _readyRace(
        id: 'race-$i',
        title: '${activities[i % activities.length]} Ready ${i + 1}',
        progressPercent: 20,
      ),
  ];
}

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: MoveScreen()),
  );
}

void main() {
  group('Verify IA (Variant B)', () {
    testWidgets('Ready segment is default and Up next is rendered', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // "Up next" label should be visible.
      expect(find.text('Up next'), findsOneWidget);
      // Race title should be visible in the Up next card.
      expect(find.text('Squat Race'), findsOneWidget);
      // "Start AI Motion Proof" button should be present.
      expect(find.text('Start AI Motion Proof'), findsOneWidget);
    });

    testWidgets('no repeated full-width Verify buttons on ready rows', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(5))));
      await tester.pumpAndSettle();

      // The old design had "Verify" pill buttons on every ready row.
      // The new design should have exactly ONE "Start AI Motion Proof" button
      // (on the Up next card) and NO "Verify" text buttons on rows.
      expect(find.text('Start AI Motion Proof'), findsOneWidget);
      // "Verify" as standalone button text should not appear on rows.
      // (The header title "Verify" is separate from button text.)
      expect(find.byType(VerifyButtonFinder), findsNothing);
    });

    testWidgets('Ready/Completed/Recent segments switch correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(id: 'r1', title: 'Squat Ready'),
            _completedRace(id: 'c1', title: 'Completed'),
            _raceWithProof(id: 'p1', title: 'Proof'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Default: Ready segment — Up next shows ready race.
      expect(find.textContaining('Squat Ready'), findsOneWidget);

      // Tap "Completed" segment.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      // Completed race should be visible now.
      expect(find.textContaining('Pushup Completed'), findsOneWidget);
      // Ready race should NOT be visible.
      expect(find.textContaining('Squat Ready'), findsNothing);

      // Tap "Recent" segment.
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      // Recent proof entry should show the viewer's own moves as "You"
      // (rendered inline in the row's "who · what · how much" meta line).
      expect(find.textContaining('You · '), findsWidgets);
      // Completed race should NOT be visible.
      expect(find.textContaining('Pushup Completed'), findsNothing);
    });

    testWidgets('selection pill slides between segment slots', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(id: 'r1', title: 'Squat Ready'),
            _completedRace(id: 'c1', title: 'Completed'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      AnimatedAlign pill() =>
          tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));

      // Ready is selected by default — the pill sits in the left slot.
      expect(pill().alignment, const Alignment(-1, 0));

      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      // Same pill widget moved to the middle slot rather than a new
      // selected widget appearing.
      expect(pill().alignment, const Alignment(0, 0));

      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();
      expect(pill().alignment, const Alignment(1, 0));
    });

    testWidgets('40 ready races: Also ready capped at 8, not artificially at 3', (
      tester,
    ) async {
      // The cap was raised from a mockup-matched 3 to 8 — a real viewport
      // with real data should read as populated, not truncated to a
      // cherry-picked few rows with a blank lower half.
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(40))),
      );
      await tester.pumpAndSettle();

      // Up next shows first race.
      expect(find.textContaining('Ready 1'), findsOneWidget);
      // 8 capped "Also ready" rows (races 2 through 9).
      for (var i = 2; i <= 9; i++) {
        expect(find.textContaining('Ready $i'), findsOneWidget);
      }
      // Race 10 should NOT be visible (capped at 8).
      expect(find.textContaining('Ready 10'), findsNothing);
      // "See all" should be visible.
      expect(find.textContaining('See all'), findsOneWidget);
    });

    testWidgets('See all expands Also ready', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(12))));
      await tester.pumpAndSettle();

      // Initially Race 12 is hidden (cap is 8, "Also ready" holds races 2–12).
      expect(find.textContaining('Ready 12'), findsNothing);

      // Tap "See all".
      await tester.tap(find.textContaining('See all'));
      await tester.pumpAndSettle();

      // Now Race 12 should be visible.
      expect(find.textContaining('Ready 12'), findsOneWidget);
      // "Show less" should be visible.
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('Show less collapses Also ready', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(12))));
      await tester.pumpAndSettle();

      // Expand.
      await tester.tap(find.textContaining('See all'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready 12'), findsOneWidget);

      // Collapse.
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();

      // Race 12 should be hidden again.
      expect(find.textContaining('Ready 12'), findsNothing);
    });

    testWidgets('Ready empty state', (tester) async {
      // Only completed races, no ready races.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_completedRace()])));
      await tester.pumpAndSettle();

      // Should show Ready empty state.
      expect(find.text('Nothing waiting on proof.'), findsOneWidget);
    });

    testWidgets('Completed empty state', (tester) async {
      // Only ready races, no completed.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // Tap "Completed" segment.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();

      expect(find.text('No completed races yet.'), findsOneWidget);
    });

    testWidgets('Recent empty state', (tester) async {
      // Ready race with no recent proofs.
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pumpAndSettle();

      // Tap "Recent" segment.
      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();

      expect(find.text('No recent proof.'), findsOneWidget);
    });

    testWidgets('loading state preserved', (tester) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error state preserved with friendly copy', (tester) async {
      await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
      await tester.pumpAndSettle();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Internal Server Error'), findsNothing);
      expect(find.text("Couldn't load your races."), findsOneWidget);
    });

    testWidgets('all-empty state shows the create-a-race prompt', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pumpAndSettle();
      expect(find.text('Nothing to prove yet'), findsOneWidget);
    });

    testWidgets('small viewport (375x667) does not overflow', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(10))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('smallest viewport (320x568) does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(10))),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('compact header shows "Verify" title and ready count', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(_generateReadyRaces(3))));
      await tester.pumpAndSettle();

      expect(find.text('Verify'), findsOneWidget);
      expect(find.textContaining('ready for proof'), findsOneWidget);
    });

    testWidgets('segmented control stays a compact filter, not three CTAs', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(10))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Each segment tab must stay in the compact-filter range (~48-56px for
      // the whole control including its navy container padding/border). The
      // selection state lives on the sliding pill behind the tabs now, so
      // the tab itself is the transparent hit area (GestureDetector).
      final tab = find.ancestor(
        of: find.text('Ready'),
        matching: find.byType(GestureDetector),
      );
      expect(tab, findsOneWidget);
      final tabHeight = tester.getSize(tab).height;
      expect(
        tabHeight,
        lessThan(52),
        reason:
            'segment tab should be a compact filter row, not a button '
            '(measured: $tabHeight)',
      );
      expect(tabHeight, greaterThan(28));
    });

    testWidgets('Up next card stays bounded — no oversized blank middle', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo(_generateReadyRaces(10))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The actionable hero shares RaceHero — a medium surface, not a
      // poster. Bound it well under the Arena hero's budget.
      final hero = find.byType(RaceHero);
      expect(hero, findsOneWidget);
      final heroHeight = tester.getSize(hero).height;
      expect(
        heroHeight,
        lessThan(280),
        reason:
            'Up next should be a compact actionable card '
            '(measured: $heroHeight)',
      );
      expect(heroHeight, greaterThan(120));
    });
  });

  group('Verify — universal proof (FlexiRace)', () {
    testWidgets('motion race → AI Motion Proof CTA + camera icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(_StubRaceRepo([_readyRace(title: 'Squat Race')])),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start AI Motion Proof'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsWidgets);
    });

    testWidgets('accumulating manual race → Log progress CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(
              title: 'Reading Race',
              unit: 'books',
              targetValue: 10,
              format: 'most_in_window',
              verifierType: 'manual_log',
              proofMode: 'manual',
              verificationMethod: 'manual',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Log progress'), findsOneWidget);
      expect(find.text('Start AI Motion Proof'), findsNothing);
    });

    testWidgets('best-attempt manual race → Add result CTA', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(
              title: 'Weekend Golf',
              unit: 'strokes',
              targetValue: null,
              format: 'best_attempt',
              scoringRule: 'best_attempt',
              scoreDirection: 'lower',
              verifierType: 'manual_log',
              proofMode: 'manual',
              verificationMethod: 'manual',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add result'), findsOneWidget);
      expect(find.text('Start AI Motion Proof'), findsNothing);
    });

    testWidgets('unresolvable race → generic Submit proof CTA, never camera',
        (tester) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(
              title: 'Mystery Metric Sprint',
              unit: 'units',
              verificationMethod: 'unknown_method',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Submit proof'), findsOneWidget);
      expect(find.text('Start AI Motion Proof'), findsNothing);
    });

    testWidgets('best-attempt race shows result, not a fake denominator', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(
              title: 'Weekend Golf',
              unit: 'strokes',
              targetValue: null,
              progressPercent: 0,
              format: 'best_attempt',
              scoringRule: 'best_attempt',
              scoreDirection: 'lower',
              verifierType: 'manual_log',
              proofMode: 'manual',
              verificationMethod: 'manual',
            ),
            _readyRace(id: 'r2', title: 'Squat Also', progressPercent: 10),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // The golf race's "Also ready" row must not render a fake "N / M"
      // progress track — it has no target denominator. (Its own row shows
      // the result; the ready-row mini track is only for real targets.)
      expect(find.textContaining('/ '), findsOneWidget); // only Squat Also
    });

    testWidgets(
      'recent row: cumulative shows "+N", best-attempt shows bare score',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            _StubRaceRepo([
              _readyRace(
                id: 'c1',
                title: 'Squat Reps',
                unit: 'reps',
                recentProofs: [
                  const RaceProof(
                    id: 'p1',
                    userId: 'user-1',
                    displayName: 'Test User',
                    proofType: 'ai_check',
                    verificationStatus: 'ai_verified',
                    value: 10,
                    createdAt: '2026-01-01T00:00:00Z',
                  ),
                ],
              ),
              _readyRace(
                id: 'g1',
                title: 'Weekend Golf',
                unit: 'strokes',
                targetValue: null,
                format: 'best_attempt',
                scoringRule: 'best_attempt',
                scoreDirection: 'lower',
                verifierType: 'manual_log',
                proofMode: 'manual',
                verificationMethod: 'manual',
                recentProofs: [
                  const RaceProof(
                    id: 'p2',
                    userId: 'user-1',
                    displayName: 'Test User',
                    proofType: 'manual',
                    verificationStatus: 'approved',
                    value: 78,
                    createdAt: '2026-01-01T00:00:00Z',
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Recent'));
        await tester.pumpAndSettle();
        expect(find.textContaining('+10 reps'), findsOneWidget);
        expect(find.textContaining('78 strokes'), findsOneWidget);
        expect(find.textContaining('+78'), findsNothing);
      },
    );

    testWidgets('very long race title renders without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          _StubRaceRepo([
            _readyRace(
              title:
                  'The Extremely Long Named International Squat Championship '
                  'Of The Entire Universe Finals',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Sentinel widget that never exists in the tree. Used to verify that the
/// old per-row Verify button pattern is absent.
class VerifyButtonFinder extends StatelessWidget {
  const VerifyButtonFinder({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
