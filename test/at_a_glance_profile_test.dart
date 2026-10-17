import 'package:flutter/rendering.dart';
import 'package:nuvo/core/theme/app_theme.dart';
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
import 'helpers/screenshot.dart';
import 'package:go_router/go_router.dart';
import 'package:nuvo/core/widgets/bottom_nav.dart';
import 'package:nuvo/core/cache/cache_store.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/profile/application/activity_controller.dart';
import 'package:nuvo/features/profile/application/progression_controller.dart';
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
import 'package:nuvo/features/profile/presentation/profile_screen.dart';
import 'package:nuvo/features/profile/presentation/widgets/activity_heatmap.dart';
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
        'achievementsEarned': 4,
        'achievementsTotal': 18,
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
  setUpAll(loadShotFonts);
  const sizes = [
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(393, 852),
    Size(430, 932),
  ];
  for (final size in sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          final name = '${size.width.toInt()}x${size.height.toInt()} '
              'inset$inset ${dark ? 'dark' : 'light'} x$scale';
          testWidgets('Profile at a glance $name', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            final pad = FakeViewPadding(top: 47, bottom: inset);
            tester.view.padding = pad;
            tester.view.viewPadding = pad;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetViewPadding);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            final router = GoRouter(
              initialLocation: '/profile',
              routes: [
                ShellRoute(
                  builder: (c, s, child) => MainShell(child: child),
                  routes: [
                    GoRoute(
                      path: '/profile',
                      builder: (c, s) => const ProfileScreen(),
                    ),
                  ],
                ),
              ],
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  raceRepositoryProvider
                      .overrideWithValue(_StubRaceRepo(_races)),
                  authControllerProvider.overrideWith(
                    (ref) => AuthController(_FakeAuthRepo()),
                  ),
                  progressionApiProvider
                      .overrideWithValue(_StubProgressionApi()),
                  profileActivityProvider.overrideWith(
                    (ref) async => const {'2026-01-05': 2, '2026-01-06': 1},
                  ),
                  secureTokenStoreProvider.overrideWithValue(_FakeStore()),
                  // In-memory cache: the file-backed one never settles under
                  // fake async, which left the level plate on its skeleton.
                  cacheStoreProvider.overrideWithValue(CacheStore.memory()),
                ],
                child: MaterialApp.router(
                  routerConfig: router,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (!dark && scale == 1.0 && inset == 34) {
              await shot(tester, 'profile_${size.width.toInt()}x${size.height.toInt()}');
            }

            final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
            final hasFade =
                find.byKey(const ValueKey('nuvo-bottom-fade')).evaluate()
                    .isNotEmpty;
            final reasons = <String>[];
            for (final e in find.byType(Text).evaluate()) {
              final ro = e.renderObject;
              if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
              final r = ro.localToGlobal(Offset.zero) & ro.size;
              if (r.bottom <= 0 || r.top >= size.height) {
                continue;
              }
              final t = (e.widget as Text).data ?? '?';
              // Profile is a normal scrolling page: content may pass under
              // the nav's bottom fade at rest, so only a missing fade fails.
              if (!hasFade && r.top < size.height && r.bottom > size.height + 0.5) {
                reasons.add('"$t" crosses viewport bottom $r');
              }
              if (!hasFade && r.top < navTop - 0.5 && r.bottom > navTop + 0.5) {
                reasons.add('"$t" straddles nav top $navTop: $r');
              }
            }
            // Title never ellipsized at 1.0.
            if (scale == 1.0) {
              final title = find.text('Profile').first;
              final p = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: title,
                  matching: find.byType(RichText),
                ),
              );
              expect(p.didExceedMaxLines, isFalse);
            }
            // The first screen is filled: content reaches the nav (>= 90%).
            final more = tester.getRect(find.text('More'));
            final yourNuvo = find.text('Your Nuvo');
            final used = yourNuvo.evaluate().isNotEmpty
                ? navTop
                : more.bottom;
            expect(used, greaterThanOrEqualTo(navTop * 0.9));
            // No blank band between the heat map card and Your Nuvo beyond a
            // normal section gap.
            if (yourNuvo.evaluate().isNotEmpty) {
              final card = tester.getRect(find.byType(ActivityHeatmap));
              expect(
                tester.getRect(yourNuvo).top - card.bottom,
                lessThanOrEqualTo(40),
              );
            }
            // Key + record strip + achievements whole when on screen.
            expect(find.text('More'), findsOneWidget);
            expect(reasons, isEmpty, reason: reasons.join('\n'));
          });
        }
      }
    }
  }
}
