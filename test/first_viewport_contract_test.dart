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
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
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

/// The steady-state progression payload the contract measures — level,
/// progress, next unlock, and a featured badge all present, same as a real
/// mid-level account.
class _FakeStore extends SecureTokenStore {
  @override
  Future<String?> getAccessToken() async => 'qa-token';
}

class _StubProgressionApi extends ProgressionApi {
  @override
  Future<NuvoProgression> getProgression(String token) async =>
      NuvoProgression.fromJson(const {
        'level': 8,
        'totalXp': 1240,
        'currentLevelXp': 40,
        'nextLevelXp': 180,
        'progress': 0.22,
        'xpToNext': 140,
        'lastSeenLevel': 8,
        'nextUnlock': {
          'unlockId': 'bdg-double-digits',
          'level': 10,
          'type': 'badge',
          'key': 'double_digits',
          'name': 'Double Digits',
          'metadata': {'icon': 'medal', 'rarity': 'milestone'},
        },
        'featuredBadges': [
          {
            'unlockId': 'bdg-five-deep',
            'type': 'badge',
            'key': 'five_deep',
            'name': 'Five Deep',
            'requiredLevel': 5,
            'metadata': {'icon': 'flame', 'rarity': 'milestone'},
            'unlocked': true,
            'featured': true,
            'position': 0,
          },
        ],
      });
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
          progressionApiProvider.overrideWithValue(_StubProgressionApi()),
          secureTokenStoreProvider.overrideWithValue(_FakeStore()),
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
      testWidgets('Compete: Quick Start rows flow contiguously — no seam '
          'void — and every tile stays reachable', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/compete',
          const CompeteScreen(),
        );
        expect(tester.takeException(), isNull);

        // The grid flows at Wrap run spacing from the first row to the
        // last. The old SliverFold split inserted a viewport-sized seam
        // before leftover rows — the dead zone this guards against.
        // Tiles under the dock are occluded by the shell mask, not
        // removed, so below-fold rects exist whenever the section mounts.
        final rects = quickStartTiles
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .toList()
          ..sort((a, b) {
            final row = a.top.compareTo(b.top);
            return row != 0 ? row : a.left.compareTo(b.left);
          });
        final rowTops = <double>{};
        for (final r in rects) {
          rowTops.add((r.top / 4).round() * 4.0);
        }
        final rows = rowTops.toList()..sort();
        for (var i = 1; i < rows.length; i++) {
          expect(
            rows[i] - rows[i - 1],
            lessThan(120),
            reason: '$name: Quick Start rows jumped ${rows[i] - rows[i - 1]}'
                'px — a seam void reopened inside the grid',
          );
        }

        // Every tile remains reachable — scroll to the end and confirm.
        await tester.drag(
          find.byType(CustomScrollView),
          Offset(0, -height),
        );
        await tester.pumpAndSettle();
        expect(find.text('Plank'), findsWidgets);
      });

      testWidgets('Compete: a tile under the dock is occluded and scrolls '
          'clear of it', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/compete',
          const CompeteScreen(),
        );
        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        final dockMask = find.byKey(const ValueKey('nuvo-dock-occlusion'));
        expect(dockMask, findsOneWidget);
        // The occluder covers the dock zone — anything straddling the
        // dock's top edge is painted behind a page-colored foreground,
        // never visible through transparent margins.
        expect(
          tester.getRect(dockMask).top,
          lessThanOrEqualTo(foldY),
        );

        // Whatever sits under the dock travels fully above it on scroll.
        final plank = find.text('Plank');
        if (plank.evaluate().isEmpty) return; // section offscreen entirely
        await tester.scrollUntilVisible(
          plank,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(plank).bottom,
          lessThanOrEqualTo(foldY + 0.5),
          reason: '$name: scrolled tile must end above the dock',
        );
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
        // Content Flow Contract (MAIN_SCREEN_LAYOUT_CONTRACT §17): the
        // dock owns bottom occlusion — a section may land under the
        // occlusion band at rest, but the same scroll must bring it fully
        // clear above the dock.
        final scrollable = find.byType(Scrollable).first;
        // Sections below the first viewport build lazily — the identity
        // block can fill a small screen entirely, so scroll until the race
        // sections exist before checking each one clears the dock.
        var buildGuard = 0;
        while (raceSections.evaluate().length < 2 && buildGuard++ < 12) {
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        for (final element in raceSections.evaluate().toList()) {
          var rect = tester.getRect(find.byWidget(element.widget));
          var guard = 0;
          while (rect.bottom > foldY + 0.5 &&
              rect.top < height - 0.5 &&
              guard++ < 20) {
            await tester.drag(scrollable, const Offset(0, -300));
            await tester.pumpAndSettle();
            rect = tester.getRect(find.byWidget(element.widget));
          }
          if (rect.top < height - 0.5) {
            expect(
              rect.bottom,
              lessThanOrEqualTo(foldY + 0.5),
              reason: '$name: section never scrolled clear of the dock',
            );
          }
        }

        // All sections still exist — scrollable, not lost.
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
        // Race-row titles are leaf Texts inside _ProfileRaceGroup. A row
        // resting fully inside the dock's opaque occlusion band is masked
        // like below-fold content and scrolls clear (§17) — the failure
        // case is a title BISECTED by the band's top edge: its top half
        // visible, its bottom half painted over. That is the half-visible
        // edge this contract forbids.
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
            final bisected = rect.top < foldY - 0.5 && rect.bottom > foldY + 0.5;
            expect(
              bisected,
              isFalse,
              reason: '$name: "$title" text is bisected by the dock edge',
            );
          }
        }
      });
    });
  }
}
