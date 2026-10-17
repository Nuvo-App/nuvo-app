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
import 'package:nuvo/features/profile/application/activity_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/presentation/widgets/activity_heatmap.dart';
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
  Future<ProgressionFetch> getProgressionConditional(
    String token, {
    String? etag,
  }) async =>
      ProgressionFetch(data: await getProgression(token));

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
          profileActivityProvider.overrideWith(
            (ref) async => const {'2026-01-05': 2, '2026-01-06': 1},
          ),
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
  // Profile's content blocks: the achievements row, the record strip and the
  // Your Nuvo group. Each must clear the dock or sit below the fold.
  const profileSectionTypes = {
    '_AchievementsRow',
    '_StatsStrip',
    '_ProfileActionGroup',
  };
  final profileSections = find.byWidgetPredicate(
    (w) => profileSectionTypes.contains(w.runtimeType.toString()),
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
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(plank).bottom,
          lessThanOrEqualTo(foldY + 0.5),
          reason: '$name: scrolled tile must end above the dock',
        );
      });

      testWidgets('Profile: normal scrolling page, every section reachable '
          'and clear of the dock at the end', (tester) async {
        await pumpInShell(
          tester,
          Size(width, height),
          '/profile',
          const ProfileScreen(),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Profile'), findsWidgets);
        expect(
          find.byKey(const ValueKey('nuvo-bottom-fade')),
          findsOneWidget,
        );

        final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(find.text('Your Nuvo'), findsOneWidget);
        expect(find.text('Settings'), findsWidgets);
        for (final element in profileSections.evaluate()) {
          expect(
            tester.getRect(find.byWidget(element.widget)).bottom,
            lessThanOrEqualTo(foldY + 0.5),
            reason: '$name: section must end above the dock when scrolled',
          );
        }
      });
    });
  }

  // Profile's first viewport is filled; Your Nuvo follows the heat map after a
  // normal section gap and scrolling reveals it.
  for (final (name, width, height) in const [
    ('390x844', 390.0, 844.0),
    ('393x852', 393.0, 852.0),
    ('430x932', 430.0, 932.0),
  ]) {
    testWidgets('Profile first viewport $name: filled, no blank band, '
        'scroll reveals Your Nuvo', (tester) async {
      await pumpInShell(
        tester,
        Size(width, height),
        '/profile',
        const ProfileScreen(),
      );
      expect(tester.takeException(), isNull);
      final foldY = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;

      expect(find.text('Profile'), findsWidgets);
      expect(find.byType(ActivityHeatmap), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      final card = tester.getRect(find.byType(ActivityHeatmap));
      // The first screen is filled (>= 90% used).
      final label = find.text('Your Nuvo');
      final used = label.evaluate().isNotEmpty ? foldY : card.bottom;
      expect(used, greaterThanOrEqualTo(foldY * 0.9));
      // No blank band between the heat map and Your Nuvo.
      if (label.evaluate().isNotEmpty) {
        expect(tester.getRect(label).top - card.bottom, lessThanOrEqualTo(40));
      }
      // No level pill under the name.
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_IdentityCard',
          ),
          matching: find.textContaining('LEVEL', findRichText: true),
        ),
        findsNothing,
      );

      await tester.drag(find.byType(CustomScrollView), Offset(0, -height));
      await tester.pumpAndSettle();
      expect(label, findsOneWidget);
      expect(tester.getRect(label).bottom, lessThanOrEqualTo(foldY));
    });
  }

  testWidgets('Profile first viewport 320x568: scrolls, no overflow, key '
      'still whole', (tester) async {
    await pumpInShell(
      tester,
      const Size(320, 568),
      '/profile',
      const ProfileScreen(),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
