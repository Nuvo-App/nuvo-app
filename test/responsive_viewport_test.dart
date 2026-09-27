// Layout regression coverage for the responsive-system rework: Arena's
// content-driven hero, the Crew screen's new header, and Compete/Verify at a
// genuinely compact width (320px) that the existing quality-gate suite
// didn't cover. The invariant under test throughout is the one from the
// design brief: no RenderFlex overflow, no clipped primary controls, no
// exceptions — at compact, standard, and large viewports.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/features/arena/presentation/arena_screen.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/move/presentation/move_screen.dart';
import 'package:nuvo/features/pass/presentation/pass_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

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
}

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _race({
  String id = 'race-1',
  String title = 'Pushup Race',
  int progressPercent = 20,
}) {
  return Race(
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
    participants: [
      RaceParticipant(
        id: 'part-1',
        userId: 'user-1',
        displayName: 'Test User',
        progressValue: progressPercent,
        progressPercent: progressPercent,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
      RaceParticipant(
        id: 'part-2',
        userId: 'user-2',
        displayName: 'Crew Mate',
        progressValue: 10,
        progressPercent: 10,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
    ],
  );
}

Widget _buildApp(Widget child, RaceRepository repo) {
  return ProviderScope(
    overrides: [
      raceRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith((ref) => AuthController(_FakeAuthRepo())),
    ],
    child: MaterialApp(home: child),
  );
}

// Compact/standard/large, per the design brief's three target buckets.
// 320 is the narrowest width the brief names; 932-tall is the "large,
// tall" bucket.
const _sizes = [
  ('compact (320x568)', 320.0, 568.0),
  ('standard (390x844)', 390.0, 844.0),
  ('large (430x932)', 430.0, 932.0),
];

void main() {
  for (final (name, width, height) in _sizes) {
    group('Responsive viewport — $name', () {
      testWidgets('Arena renders without overflow inside MainShell', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);

        final router = GoRouter(
          initialLocation: '/arena',
          routes: [
            ShellRoute(
              builder: (c, s, child) => MainShell(child: child),
              routes: [
                GoRoute(
                  path: '/arena',
                  builder: (c, s) => const ArenaScreen(preview: true),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // The hero must never balloon past a sane share of the usable
        // viewport — the concrete regression this suite guards against.
        final heroHeight = tester.getSize(find.byType(PageView).first).height;
        expect(
          heroHeight,
          lessThan(height * 0.55),
          reason: '$name: hero must not dominate the viewport',
        );
      });

      testWidgets('Compete renders without overflow at this width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(
            const CompeteScreen(),
            _StubRaceRepo([_race(id: 'r1'), _race(id: 'r2', title: 'Squat Race')]),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Verify renders without overflow at this width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _buildApp(
            const MoveScreen(),
            _StubRaceRepo([_race(id: 'r1'), _race(id: 'r2', title: 'Squat Race')]),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'Crew renders its header (hero + metadata + actions) without overflow',
        (tester) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            _buildApp(const PassScreen(), _StubRaceRepo(const [])),
          );
          // PassScreen has continuous/QR-adjacent animation surfaces — pump a
          // few frames rather than waiting for a settle that may never come.
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          expect(find.text('Crew'), findsOneWidget);
          // Header actions are icon affordances with semantics labels —
          // search opens Add to Crew, the QR icon opens My Nuvo.
          expect(find.bySemanticsLabel('Find people'), findsOneWidget);
          expect(find.bySemanticsLabel('Show my member code'), findsOneWidget);
          // QR must not be visible on the page itself — only reachable via
          // the member-code icon.
          expect(find.byType(Image), findsNothing);
        },
      );
    });
  }

  // Two independent tests (fresh tester each) rather than two pumps sharing
  // one tester — reusing a tester across two full app pumps sometimes races
  // a pending postFrameCallback from the first tree against disposal, which
  // is a test-harness artifact, not a real app bug.
  final measuredHeroHeights = <String, double>{};

  Future<void> pumpAndMeasure(WidgetTester tester, String tag, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/arena',
      routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/arena',
              builder: (c, s) => const ArenaScreen(preview: true),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    measuredHeroHeights[tag] = tester.getSize(find.byType(PageView).first).height;
  }

  testWidgets('Arena hero height at compact viewport (320x568)', (tester) async {
    await pumpAndMeasure(tester, 'compact', const Size(320, 568));
  });

  testWidgets(
    'Arena hero height at large viewport (430x932) is taller than compact (no global compact clamp)',
    (tester) async {
      await pumpAndMeasure(tester, 'large', const Size(430, 932));
      expect(
        measuredHeroHeights['large'],
        greaterThan(measuredHeroHeights['compact']!),
        reason: 'a wider/taller phone should get a bigger hero, not the same clamped pixel',
      );
    },
  );
}
