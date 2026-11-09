// S11 notification sheet: accepting pays +5 XP, "Maybe later" pays nothing,
// and neither blocks the flow.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/analytics/analytics_service.dart';
import 'package:nuvo/features/onboarding/data/onboarding_v2_store.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_copy.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';
import 'package:nuvo/features/onboarding/tour/notify_opt_in_step.dart';

Future<(OnboardingFlowController, OnboardingShellController)> _pump(
  WidgetTester tester, {
  required bool osAccepts,
}) async {
  final flow = OnboardingFlowController(
    store: OnboardingV2Store.memory(),
    analytics: FakeAnalyticsService(),
    onGraduate: () async {},
  );
  await flow.restore();
  while (flow.state.step != OnboardingStep.notifyOptIn) {
    final s = flow.state.step;
    if (s == OnboardingStep.arenaTour) {
      flow.proofStarted();
      await flow.proofCompleted(cameraFallback: false);
    } else {
      await flow.completeStep(s);
    }
  }
  final shell = OnboardingShellController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingFlowProvider.overrideWith((ref) => flow),
        notifyPermissionRequestProvider.overrideWithValue(
          () async => osAccepts,
        ),
      ],
      child: MaterialApp(
        home: OnboardingShellScope(
          controller: shell,
          child: const ObNotifyOptInStep(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  return (flow, shell);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('accepting the OS prompt pays +5 XP', (tester) async {
    late OnboardingFlowController flow;
    late OnboardingShellController shell;
    (flow, shell) = await _pump(tester, osAccepts: true);
    final before = flow.state.totalXp;
    expect(find.text(ObCopy.notifyTitle), findsOneWidget);
    await tester.tap(find.text(ObCopy.notifyCta));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(flow.state.totalXp - before, 5);
    expect(flow.state.notifyOutcome, 'accepted');
    expect(shell.xpTarget, 5);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('OS denial or Maybe later pays nothing and still advances', (
    tester,
  ) async {
    final (flow, _) = await _pump(tester, osAccepts: false);
    final before = flow.state.totalXp;
    await tester.tap(find.text(ObCopy.notifyCta));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(flow.state.totalXp, before);
    expect(flow.state.notifyOutcome, 'declined');
    expect(flow.state.step, isNot(OnboardingStep.notifyOptIn));
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('Maybe later is a real, working button', (tester) async {
    final (flow, _) = await _pump(tester, osAccepts: true);
    await tester.tap(find.text(ObCopy.notifyLater));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(flow.state.notifyOutcome, 'declined');
    await tester.pump(const Duration(milliseconds: 700));
  });
}
