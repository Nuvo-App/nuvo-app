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
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
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

/// Repo whose getRaces() returns [races] on every call.
class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;

  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

/// Repo whose getRaces() throws on every call.
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

/// Repo whose getRaces() throws on the first call then succeeds.
class _RetryRaceRepo extends RaceRepository {
  _RetryRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<Race> races;
  int _calls = 0;

  @override
  Future<List<Race>> getRaces() {
    _calls++;
    // The controller waits for auth before its first request, then retry succeeds.
    if (_calls == 1) {
      return Future.error(const ApiException(500, 'Internal Server Error'));
    }
    return Future.value(races);
  }
}

Race _cameraRace({String id = 'race-1', String title = 'Pushup Race'}) => Race(
  id: id,
  creatorId: 'user-1',
  title: title,
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'reps',
  proofRequirement: 'ai_check',
  proofMode: 'ai_check',
  verificationMethod: 'camera_pose',
  status: 'active',
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
    child: const MaterialApp(home: CompeteScreen()),
  );
}

void main() {
  group('CompeteScreen state behavior', () {
    testWidgets('shows CircularProgressIndicator on initial load', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_PendingRaceRepo()));
      // PendingRaceRepo never completes so loading state persists.
      await tester.pump();
      expect(find.byKey(const ValueKey('compete-skeleton')), findsOneWidget);
    });

    testWidgets('shows race content when loaded with data', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo([_cameraRace()])));
      await tester.pump(const Duration(milliseconds: 100));
      // Loading should be done; hero + content should be visible.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Pushup Race'), findsWidgets);
    });

    testWidgets('shows empty state when loaded with no races', (tester) async {
      await tester.pumpWidget(_buildApp(_StubRaceRepo(const [])));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NuvoErrorState), findsNothing);
      expect(find.text('No races yet'), findsOneWidget);
    });

    testWidgets('shows NuvoErrorState (not raw text) on load failure', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_ThrowRaceRepo()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NuvoErrorState), findsOneWidget);
      // Raw backend error must NOT be visible.
      expect(find.text('Internal Server Error'), findsNothing);
      // Friendly copy should be visible.
      expect(find.text("Couldn't load your races."), findsOneWidget);
    });

    testWidgets('retry after failure reloads races', (tester) async {
      final repo = _RetryRaceRepo([_cameraRace()]);
      await tester.pumpWidget(_buildApp(repo));
      // Let the auth-gated first load complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      // First load failed → error state.
      expect(find.byType(NuvoErrorState), findsOneWidget);

      // Tap "Try again".
      await tester.tap(find.text('Try again'));
      // Let the second (succeeding) load complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Manual retry succeeded → content visible.
      expect(find.byType(NuvoErrorState), findsNothing);
      expect(find.text('Pushup Race'), findsWidgets);
    });
  });
}
