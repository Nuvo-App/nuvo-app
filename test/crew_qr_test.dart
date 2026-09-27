// Structural coverage for the Crew screen's non-negotiable requirement: the
// QR / Nuvo Pass must never be permanently visible on the page — only
// reachable by tapping "My code". Also covers the crew count now living
// inside the hero (not a separate "12 people" card) and "Find people"
// sitting in a sane position after the header.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/crew/application/crew_controller.dart';
import 'package:nuvo/features/crew/data/crew_api.dart';
import 'package:nuvo/features/crew/data/crew_repository.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/social/data/invite_api.dart';
import 'package:nuvo/features/social/data/invite_models.dart';
import 'package:nuvo/features/social/data/invite_repository.dart';
import 'package:nuvo/features/social/presentation/my_nuvo_screen.dart';
import 'package:nuvo/features/social/social_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeAuthRepo extends AuthRepository {
  _FakeAuthRepo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => RestoreOk(
    const AuthUser(
      id: 'user-1',
      email: 'test@getnuvo.net',
      fullName: 'Test User',
      username: 'testuser',
      onboardingComplete: true,
      hasMemberPass: true,
      termsAccepted: true,
    ),
  );

  // The screen's content phase only renders once the member pass resolves —
  // without this the fake hits the (blocked) network and the page parks on
  // its error state instead.
  @override
  Future<PassInfo> getMemberPass() async => const PassInfo(
    memberId: 'NUVO-0001',
    passSlug: 'test-user',
    shareUrl: 'https://getnuvo.net/pass/test-user',
  );
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo() : super(RaceApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<Race>> getRaces() => Future.value(const []);
}

class _StubCrewRepo extends CrewRepository {
  _StubCrewRepo() : super(CrewApi(), SecureTokenStore(), AuthApi());
  @override
  Future<List<PublicUser>> getCrew() async => const [];
  @override
  Future<CrewRequestPage> getRequestPage() async => const CrewRequestPage();
}

// "My code" mints a crew_connect invite before rendering the QR — stub it so
// the sheet reaches its QR state without a network.
class _StubInviteRepo extends InviteRepository {
  _StubInviteRepo() : super(InviteApi(), SecureTokenStore(), AuthApi());
  @override
  Future<MintedInvite> mintMyCrewInvite() async => const MintedInvite(
    token: 'test-token',
    url: 'https://getnuvo.net/i/test-token',
    kind: 'crew_connect',
  );
}

Widget _buildApp() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const PassScreen()),
      GoRoute(path: '/my-nuvo', builder: (_, __) => const MyNuvoScreen()),
      GoRoute(path: '/scan', builder: (_, __) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(_StubRaceRepo()),
      crewRepositoryProvider.overrideWithValue(_StubCrewRepo()),
      inviteRepositoryProvider.overrideWithValue(_StubInviteRepo()),
      authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('QR is absent from the base Crew page', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(QrImageView),
      findsNothing,
      reason: 'the QR/Nuvo Pass must never be permanently visible on the Crew page',
    );
  });

  testWidgets('tapping the QR header icon opens My Nuvo, not the page body', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.qr_code_rounded).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(
      find.byType(MyNuvoScreen),
      findsOneWidget,
      reason: 'the header icon routes to the dedicated My Nuvo surface',
    );
    expect(
      find.byType(QrImageView),
      findsOneWidget,
      reason: 'My Nuvo mints + renders the member QR',
    );
  });

  testWidgets('empty crew shows the flat find-people surface', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // With no crew loaded yet in this stub, the header carries the
    // find-people subtitle and the two ways-in sit below the strip —
    // no bordered hero card, no second roster.
    expect(find.text('Find people to race with.'), findsOneWidget);
    expect(find.text('Find people'), findsOneWidget);
    expect(find.text('Your member code'), findsOneWidget);
  });
}
