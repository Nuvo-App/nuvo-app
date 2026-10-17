// First-viewport contract coverage — docs/ui/MAIN_SCREEN_LAYOUT_CONTRACT.md.
//
// The invariant under test: above the floating dock, content ends at a
// logical component boundary with a small breathing zone. A component is
// either fully above the dock or starts below the first viewport — never
// bisected under the nav. These are geometry invariants, not goldens: they
// hold under copy tweaks and small paddings, but fail the moment a row or
// tile is clipped by the dock again.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:nuvo/features/profile/data/progression_api.dart';
import 'package:nuvo/features/profile/data/progression_models.dart';
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


const _sizes = [(320.0, 568.0), (375.0, 667.0), (390.0, 844.0), (393.0, 852.0), (430.0, 932.0)];

void main() {
  for (final s in _sizes) {
    for (final inset in [0.0, 34.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          final name = '${s.$1.toInt()}x${s.$2.toInt()} inset$inset '
              '${dark ? "dark" : "light"} x$scale';
          testWidgets('Compete at a glance $name', (tester) async {
            tester.view.physicalSize = Size(s.$1, s.$2);
            tester.view.devicePixelRatio = 1;
            tester.view.padding = FakeViewPadding(top: 47, bottom: inset);
            tester.view.viewPadding = FakeViewPadding(top: 47, bottom: inset);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetViewPadding);
            final router = GoRouter(
              initialLocation: '/compete',
              routes: [
                ShellRoute(
                  builder: (c, st, child) => MainShell(child: child),
                  routes: [
                    GoRoute(
                      path: '/compete',
                      builder: (c, st) => const CompeteScreen(),
                    ),
                  ],
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
                    (ref) async => const {'2026-01-05': 2},
                  ),
                  secureTokenStoreProvider.overrideWithValue(_FakeStore()),
                ],
                child: MediaQuery(
                  data: MediaQueryData(
                    size: Size(s.$1, s.$2),
                    padding: EdgeInsets.only(top: 47, bottom: inset),
                    textScaler: TextScaler.linear(scale),
                    platformBrightness:
                        dark ? Brightness.dark : Brightness.light,
                  ),
                  child: MaterialApp.router(
                    routerConfig: router,
                    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            final navTop = tester.getTopLeft(find.byType(NuvoBottomNav)).dy;
            final fade = find.byKey(const ValueKey('nuvo-bottom-fade'));
            final hasFade = fade.evaluate().isNotEmpty;
            for (final e in find.byType(Text).evaluate()) {
              final f = find.byWidget(e.widget);
              final r = tester.getRect(f);
              if (r.top >= navTop - 0.5 || r.bottom <= 0) continue; // fully under the nav: hidden
              expect(r.bottom <= s.$2 + 0.5, isTrue,
                  reason: '$name: "${(e.widget as Text).data}" crosses viewport bottom $r');
              if (!hasFade) {
                expect(r.top < navTop - 0.5 && r.bottom > navTop + 0.5, isFalse,
                    reason: '$name: "${(e.widget as Text).data}" straddles nav top $navTop: $r');
              }
            }
            if (scale == 1.0) {
              for (final t in ['Compete', 'Start a race']) {
                for (final e in find.descendant(of: find.byType(CompeteScreen), matching: find.text(t)).evaluate()) {
                  final ro = e.renderObject;
                  if (ro is RenderParagraph) {
                    expect(ro.didExceedMaxLines, isFalse,
                        reason: '$name: "$t" ellipsized');
                  }
                }
              }
            }
          });
        }
      }
    }
  }
}
