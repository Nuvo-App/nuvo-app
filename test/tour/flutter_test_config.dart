import 'dart:async';

import 'package:nuvo/features/onboarding/flow/onboarding_flow_controller.dart';

/// Widget tests tap through steps instantly; the 600ms transition lock is
/// covered by its own tests (test/onboarding_v2/step_lock_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  OnboardingFlowController.appInputLock = Duration.zero;
  await testMain();
}
