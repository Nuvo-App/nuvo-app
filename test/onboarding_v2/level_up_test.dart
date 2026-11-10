// S15 level-up: reward tiles show the server's numbers, the timeline
// reaches the CTA, tap-to-skip never traps, graduation retries inline, and
// the reward parser stays additive-safe.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/auth/data/auth_api.dart';
import 'package:nuvo/features/auth/data/auth_models.dart';
import 'package:nuvo/features/auth/data/auth_repository.dart';
import 'package:nuvo/features/auth/data/secure_token_store.dart';
import 'package:nuvo/features/auth/presentation/auth_controller.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/levelup/level_up_step.dart';
import 'package:nuvo/features/onboarding/levelup/onboarding_reward.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';

const _user = AuthUser(
  id: 'u1',
  email: 'a@b.co',
  fullName: 'Ada',
  onboardingComplete: false,
  hasMemberPass: true,
  termsAccepted: true,
);

class _Repo extends AuthRepository {
  _Repo() : super(AuthApi(), SecureTokenStore());
  @override
  Future<RestoreResult> restoreSession() async => const RestoreOk(_user);
}

Future<OnboardingFlowController> _pump(
  WidgetTester tester, {
  required OnboardingReward reward,
  required Future<void> Function() onGraduate,
}) async {
  final flow = OnboardingFlowController(
    store: OnboardingV2Store.memory(),
    analytics: FakeAnalyticsService(),
    onGraduate: onGraduate,
  );
  await flow.restore();
  final shell = OnboardingShellController();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingFlowProvider.overrideWith((ref) => flow),
        onboardingRewardFetcherProvider.overrideWithValue(() async => reward),
        authControllerProvider.overrideWith((ref) => AuthController(_Repo())),
      ],
      child: MaterialApp(
        home: OnboardingShellScope(
          controller: shell,
          child: const ObLevelUpStep(),
        ),
      ),
    ),
  );
  return flow;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reward parser reads the additive server object', () {
    final r = OnboardingReward.fromResponse({
      'ok': true,
      'reward': {
        'xpGranted': 100,
        'level': 2,
        'previousLevel': 1,
        'badge': {'key': 'day_one', 'name': 'Day One'},
        'streakDays': 1,
      },
    })!;
    expect(r.xpTile, '+100 XP');
    expect(r.levelFromLabel, 'LEVEL 1');
    expect(r.levelToLabel, 'LEVEL 2');
    expect(r.badgeName, 'Day One');
    expect(r.streakTile, ObCopy.levelUpStreakTile);
    expect(r.fromServer, isTrue);
  });

  test('old server (no reward object) and repeat calls stay safe', () {
    expect(OnboardingReward.fromResponse({'ok': true}), isNull);
    final repeat = OnboardingReward.fromResponse({
      'reward': {'xpGranted': 0, 'level': 2, 'previousLevel': 2},
    })!;
    expect(repeat.fromLevel, 1);
    expect(repeat.toLevel, 2);
    expect(repeat.xp, 100);
  });

  testWidgets('tiles show server numbers and the CTA graduates', (
    tester,
  ) async {
    var graduated = 0;
    await _pump(
      tester,
      reward: const OnboardingReward(
        xp: 100,
        fromLevel: 1,
        toLevel: 2,
        badgeName: 'Day One',
        streakDays: 3,
        fromServer: true,
      ),
      onGraduate: () async => graduated++,
    );
    await tester.pump(const Duration(milliseconds: 50));
    // Tap before 900 ms must not skip.
    await tester.tap(find.byType(ObLevelUpStep), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(ObCopy.levelUpCta), findsOneWidget);
    // Run the timeline to the end.
    await tester.pump(const Duration(milliseconds: 4000));
    expect(find.text('+100 XP'), findsOneWidget);
    expect(find.text('Day One'), findsOneWidget);
    expect(find.text('3 day streak'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-cta')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(graduated, 1);
  });

  testWidgets('a failed graduation never blocks the player (no retry UI)', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      reward: OnboardingReward.fallback,
      onGraduate: () async {
        attempts++;
        throw Exception('offline');
      },
    );
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.tap(find.byKey(const ValueKey('onboarding-cta')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    // The write was attempted once in the foreground; failure shows no
    // inline error — the flow completes and retries in the background.
    expect(attempts, greaterThanOrEqualTo(1));
    expect(find.text(ObCopy.genericRetry), findsNothing);
    // Let the background retry schedule run out (all attempts fail here).
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 30));
    }
    expect(attempts, greaterThan(1));
  });

  testWidgets('tapping after 900 ms fast-forwards to the CTA', (tester) async {
    await _pump(
      tester,
      reward: OnboardingReward.fallback,
      onGraduate: () async {},
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tapAt(const Offset(40, 300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 700));
    final cta = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text(ObCopy.levelUpCta),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(cta.opacity, closeTo(1.0, 0.01));
  });
}
