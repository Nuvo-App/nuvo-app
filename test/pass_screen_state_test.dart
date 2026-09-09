import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/widgets/nuvo_error_state.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/notifications/application/notification_controller.dart';
import 'package:nuvo/features/notifications/data/notification_models.dart';
import 'package:nuvo/features/notifications/data/notification_repository.dart';
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

  @override
  Future<PassInfo> getMemberPass() async => _passInfo;
}

class _PassRaceRepo extends RaceRepository {
  _PassRaceRepo({
    this.searchResults = const [],
    this.searchThrows = false,
  }) : super(RaceApi(), SecureTokenStore(), AuthApi());

  final List<PublicUser> searchResults;
  final bool searchThrows;

  @override
  Future<List<Race>> getRaces() async => const [];

  @override
  Future<List<PublicUser>> searchUsers(String query) async {
    if (searchThrows) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return searchResults;
  }
}

class _FakeCrewRepo implements CrewRepository {
  _FakeCrewRepo({this.throws = false});
  final bool throws;

  @override
  Future<List<PublicUser>> getCrew() async {
    if (throws) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      throw const ApiException(500, 'Internal Server Error');
    }
    return const [];
  }

  @override
  Future<List<PublicUser>> getRequests() async => const [];
  @override
  Future<PublicProfileCard> getUser(String userId) => throw UnimplementedError();
  @override
  Future<ConnectOutcome> add(String userId) async => ConnectOutcome.active;
  @override
  Future<void> acceptRequest(String userId) async {}
  @override
  Future<void> declineRequest(String userId) async {}
  @override
  Future<void> remove(String userId) async {}
}

class _FakeNotifRepo implements NotificationRepository {
  @override
  Future<NotificationPage> list({String? cursor}) async =>
      const NotificationPage(items: [], unreadCount: 0);
  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> markAllRead() async {}
}

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _buildApp(_PassRaceRepo repo, {bool crewThrows = false}) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      crewRepositoryProvider.overrideWithValue(_FakeCrewRepo(throws: crewThrows)),
      notificationRepositoryProvider.overrideWithValue(_FakeNotifRepo()),
      authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
    ],
    child: const MaterialApp(home: PassScreen()),
  );
}

Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400)); // debounce
  await tester.pump(); // microtask drain
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  group('PassScreen crew section', () {
    testWidgets('crew error surfaces in the crew section', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(_PassRaceRepo(), crewThrows: true));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(NuvoErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('PassScreen search behavior', () {
    testWidgets('search failure shows error, not "no results"', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(_PassRaceRepo(searchThrows: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.byType(NuvoErrorState), findsNothing);

      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);

      expect(find.text('Search failed. Try again.'), findsOneWidget);
      expect(find.text('No matching Nuvo members found.'), findsNothing);
    });

    testWidgets('successful search shows results', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(
        _buildApp(_PassRaceRepo(searchResults: const [
          PublicUser(id: 'u2', displayName: 'John Doe', username: 'john', initials: 'JD'),
        ])),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);

      expect(find.text('Search failed. Try again.'), findsNothing);
      expect(find.text('No matching Nuvo members found.'), findsNothing);
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('retry after error re-runs the search', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(_PassRaceRepo(searchThrows: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      await tester.tap(find.text('Search failed. Try again.'));
      await _settleSearch(tester);
      // Still shows the error (still failing) — the tap re-ran, didn't crash.
      expect(find.text('Search failed. Try again.'), findsOneWidget);
    });

    testWidgets('clearing the query clears the error', (tester) async {
      _tallViewport(tester);
      await tester.pumpWidget(_buildApp(_PassRaceRepo(searchThrows: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'john');
      await _settleSearch(tester);
      expect(find.text('Search failed. Try again.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.text('Search failed. Try again.'), findsNothing);
    });
  });
}
