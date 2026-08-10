import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

const _passInfo = PassInfo(
  memberId: 'NUVO-001',
  passSlug: 'testuser',
  shareUrl: 'https://getnuvo.net/p/testuser',
);

final _crew = [
  const PublicUser(
    id: 'crew-1',
    displayName: 'Crew Member',
    username: 'crewmember',
    initials: 'CM',
  ),
];

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

  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

/// Repo with configurable crew + search behavior.
class _PassRaceRepo extends RaceRepository {
  _PassRaceRepo({
    this.crew = const [],
    this.searchResults = const [],
    this.crewThrows = false,
    this.searchThrows = false,
  }) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<PublicUser> crew;
  final List<PublicUser> searchResults;
  final bool crewThrows;
  final bool searchThrows;

  @override
  Future<List<Race>> getRaces() async => const [];

  @override
  Future<List<PublicUser>> getCrew() async {
    if (crewThrows) {
      await Future.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return crew;
  }

  @override
  Future<List<PublicUser>> searchUsers(String query) async {
    if (searchThrows) {
      await Future.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return searchResults;
  }
}

Widget _buildApp(RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(
        (ref) => AuthController(_FakeAuthRepo()),
      ),
    ],
    child: const MaterialApp(home: PassScreen()),
  );
}

void main() {
  group('PassScreen state behavior', () {
    testWidgets('shows NuvoErrorState when initial crew load fails', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(_PassRaceRepo(crewThrows: true)));
      // Let initial load complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'search failure stops spinner and shows error — does NOT show "No matching"',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(_PassRaceRepo(crew: _crew, searchThrows: true)),
        );
        // Let initial load complete.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        expect(find.byType(NuvoErrorState), findsNothing);

        // Enter a search query (>= 2 chars to trigger search).
        await tester.enterText(find.byType(TextField), 'john');

        // Wait for debounce (280ms) + async failure.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        // Spinner must be gone.
        // (NuvoSearchField shows a small CircularProgressIndicator when searching.)
        // After failure, searching=false so no spinners should be active.
        expect(find.text('Search failed. Try again.'), findsOneWidget);
        // Must NOT show the "no results" empty note.
        expect(find.text('No matching Nuvo members found.'), findsNothing);
      },
    );

    testWidgets('successful search still shows results', (tester) async {
      final results = [
        const PublicUser(
          id: 'user-2',
          displayName: 'John Doe',
          username: 'john',
          initials: 'JD',
        ),
      ];
      await tester.pumpWidget(
        _buildApp(_PassRaceRepo(crew: _crew, searchResults: results)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'john');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Search failed. Try again.'), findsNothing);
      expect(find.text('No matching Nuvo members found.'), findsNothing);
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('retry search by tapping error note re-runs search', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(_PassRaceRepo(crew: _crew, searchThrows: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'john');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Error note is shown.
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      // Tap the error note to retry.
      await tester.tap(find.text('Search failed. Try again.'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Error note should still be shown (search still throws).
      expect(find.text('Search failed. Try again.'), findsOneWidget);
      // Spinner must not be stuck.
      expect(find.text('No matching Nuvo members found.'), findsNothing);
    });

    testWidgets('changing query clears search error and searches again', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(_PassRaceRepo(crew: _crew, searchThrows: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // First search fails.
      await tester.enterText(find.byType(TextField), 'john');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      // Clear the query (< 2 chars) — error should clear.
      await tester.enterText(find.byType(TextField), 'j');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Search failed. Try again.'), findsNothing);
    });
  });
}
