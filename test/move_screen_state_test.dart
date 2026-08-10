import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
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
  Future<AuthUser?> restoreSession() async => const AuthUser(
    id: 'user-1',
    email: 'test@getnuvo.net',
    fullName: 'Test User',
    username: 'testuser',
    onboardingComplete: true,
    hasMemberPass: true,
    termsAccepted: true,
  );
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

/// Repo whose getRaces() never completes (for loading-state tests).
class _PendingRaceRepo extends RaceRepository {
  _PendingRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());

  final completer = Completer<List<Race>>();

  @override
  Future<List<Race>> getRaces() => completer.future;
}

class _RetryRaceRepo extends RaceRepository {
  _RetryRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  int _calls = 0;

  @override
  Future<List<Race>> getRaces() {
    _calls++;
    // Throw on first 2 calls (constructor + auth listener), succeed on 3rd (retry).
    if (_calls <= 2) {
      return Future.error(const ApiException(500, 'Internal Server Error'));
    }
    return Future.value(races);
  }
}

/// A camera-verifiable race where the user has NOT hit 100% yet (ready to move).
Race _readyRace({String id = 'race-1', String title = 'Squat Race'}) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 50,
  unit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
  participants: [
    const RaceParticipant(
      id: 'part-1',
      userId: 'user-1',
      displayName: 'Test User',
      progressValue: 20,
      progressPercent: 40,
      joinedAt: '2026-01-01T00:00:00Z',
    ),
  ],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

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
  group('MoveScreen state behavior', () {
    testWidgets('shows CircularProgressIndicator on initial load', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows race content when loaded with data', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_readyRace()])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Squat Race'), findsWidgets);
    });

    testWidgets('shows empty state when loaded with no races', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NuvoErrorState), findsNothing);
      expect(find.text('No active races yet.'), findsOneWidget);
    });

    testWidgets(
      'FAILED LOAD does NOT show empty state — shows NuvoErrorState instead',
      (tester) async {
        await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
        await tester.pump(const Duration(milliseconds: 100));
        // Error state must be shown, NOT the empty state.
        expect(find.byType(NuvoErrorState), findsOneWidget);
        expect(find.text('No active races yet.'), findsNothing);
        // Raw backend error must NOT be visible.
        expect(find.text('Internal Server Error'), findsNothing);
        // Friendly copy should be visible.
        expect(find.text("Couldn't load your races."), findsOneWidget);
      },
    );

    testWidgets('retry after failure reloads races', (tester) async {
      final repo = _RetryRaceRepo([_readyRace()]);
      await tester.pumpWidget(_buildApp(repo));
      // Let the first (failing) load complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(NuvoErrorState), findsOneWidget);

      await tester.tap(find.text('Try again'));
      // Let the second (succeeding) load complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(NuvoErrorState), findsNothing);
      expect(find.text('Squat Race'), findsWidgets);
    });
  });
}
