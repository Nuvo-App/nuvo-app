// First-viewport contract coverage — docs/ui/MAIN_SCREEN_LAYOUT_CONTRACT.md.
//
// The invariant under test: above the floating dock, content ends at a
// logical component boundary with a small breathing zone. A component is
// either fully above the dock or starts below the first viewport — never
// bisected under the nav. These are geometry invariants, not goldens: they
// hold under copy tweaks and small paddings, but fail the moment a row or
// tile is clipped by the dock again.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/compete/presentation/compete_screen_fixed.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/races/data/race_api.dart';
import 'package:nuvo/features/races/data/race_models.dart';
import 'package:nuvo/features/races/data/race_repository.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/shell/presentation/main_shell.dart';

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

class _StubRaceRepo extends RaceRepository {
  _StubRaceRepo(this.races) : super(RaceApi(), SecureTokenStore(), AuthApi());
  final List<Race> races;
  @override
  Future<List<Race>> getRaces() => Future.value(races);
}

Race _race({
  required String id,
  required String title,
  required String status,
  int meValue = 8,
  int opponentValue = 12,
}) {
  return Race(
    id: id,
    creatorId: 'user-1',
    title: title,
    activityId: 'pushups',
    goalType: 'first_to_goal',
    targetValue: 50,
    unit: 'reps',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'camera_pose',
    status: status,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    completedAt: status == 'completed' ? '2026-01-02T00:00:00Z' : null,
    participants: [
      RaceParticipant(
        id: 'part-me-$id',
        userId: 'user-1',
        displayName: 'Test User',
        progressValue: meValue,
        progressPercent: meValue,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
      RaceParticipant(
        id: 'part-crew-$id',
        userId: 'user-2',
        displayName: 'Crew Mate',
        progressValue: opponentValue,
        progressPercent: opponentValue,
        joinedAt: '2026-01-01T00:00:00Z',
      ),
    ],
  );
}

/// Enough races that both Profile sections have real content and Compete's
/// populated state renders.
final _races = [
  _race(id: 'active-1', title: 'Pushup Race', status: 'active'),
  _race(id: 'active-2', title: 'Squat Race', status: 'active'),
  _race(id: 'active-3', title: 'Lunge Race', status: 'active'),
  _race(id: 'done-1', title: 'Plank Race', status: 'completed'),
  _race(id: 'done-2', title: 'Burpee Race', status: 'completed'),
  _race(id: 'done-3', title: 'Jack Race', status: 'completed'),
];

const _sizes = [
  ('short (320x568)', 320.0, 568.0),
  ('standard (390x844)', 390.0, 844.0),
  ('tall (430x932)', 430.0, 932.0),
];

/// The contract: a widget is either fully above the dock (with a slice of
/// breathing room) or starts at/past the viewport's bottom edge — never
/// stranded across the dock's top edge.
void expectFoldRespected(
  WidgetTester tester,
  Finder finder,
  double viewportHeight,
  double foldY,
  String label,
) {
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    final aboveFold = rect.bottom <= foldY;
    final belowViewport = rect.top >= viewportHeight - 0.5;
    expect(
      aboveFold || belowViewport,
      isTrue,
      reason:
          '$label: ${element.widget.runtimeType} rect $rect is bisected by '
          'the dock (fold at $foldY, viewport ends $viewportHeight)',
    );
  }
}

void main() {
  Future<void> pumpInShell(
    WidgetTester tester,
    Size size,
    String path,
    Widget screen,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: path,
      routes: [
        ShellRoute(
          builder: (c, s, child) => MainShell(child: child),
          routes: [GoRoute(path: path, builder: (c, s) => screen)],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          raceRepositoryProvider.overrideWithValue(_StubRaceRepo(_races)),
          authControllerProvider.overrideWith(
            (ref) => AuthController(_FakeAuthRepo()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  final quickStartTiles = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_QuickStartTile',
  );
  final raceSections = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_RaceSection',
  );

  for (final (name, width, height) in _sizes) {
    group('First-viewport contract — $name', () {
      testWidgets('Compete: every Quick Start tile is whole above the dock '
          'or below the fold', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/compete',
          const CompeteScreen(),
        );
        expect(tester.takeException(), isNull);

        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        // On short viewports the section may start past the cache extent —
        // that's the fold working, not a failure. Check whatever mounted.
        expectFoldRespected(tester, quickStartTiles, height, foldY, name);

        // Every tile remains reachable — the fold moves content below the
        // viewport, it never removes it. Scroll to the end and confirm.
        await tester.drag(
          find.byType(CustomScrollView),
          Offset(0, -height),
        );
        await tester.pumpAndSettle();
        expect(find.text('Plank'), findsWidgets);
      });

      testWidgets('Compete: the last above-fold tile keeps breathing room '
          'above the dock', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/compete',
          const CompeteScreen(),
        );
        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        for (final element in quickStartTiles.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          if (rect.top < height - 0.5) {
            expect(
              rect.bottom,
              lessThanOrEqualTo(foldY - 4),
              reason:
                  '$name: a visible Quick Start ends inside the breathing '
                  'zone — no intentional gap above the dock',
            );
          }
        }
      });

      testWidgets('Profile: every race section is whole above the dock or '
          'below the fold', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/profile',
          const ProfileScreen(),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Profile'), findsWidgets);

        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        expectFoldRespected(tester, raceSections, height, foldY, name);

        // Sections the fold pushed down still exist — scrollable, not
        // lost. _RaceSection labels compose as 'Recent results · 3'.
        expect(find.textContaining('Recent results'), findsWidgets);
        expect(find.textContaining('Account'), findsWidgets);
      });

      testWidgets('Profile: a result row is never the half-visible edge',
          (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/profile',
          const ProfileScreen(),
        );
        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        // Race-row titles are leaf Texts inside _ProfileRaceGroup — if one
        // is visible, its row must not terminate inside the dock.
        for (final title in [
          'Pushup Race',
          'Squat Race',
          'Lunge Race',
          'Plank Race',
          'Burpee Race',
          'Jack Race',
        ]) {
          for (final element in find.text(title).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            if (rect.top < height - 0.5) {
              expect(
                rect.bottom,
                lessThanOrEqualTo(foldY + 0.5),
                reason: '$name: "$title" text runs under the dock',
              );
            }
          }
        }
      });
    });
  }
}
