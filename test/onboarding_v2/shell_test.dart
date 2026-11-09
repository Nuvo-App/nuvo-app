// OnboardingShell widget contract: the CTA slot's geometry is identical on
// every step, reduce-motion takes the no-animation path, and the XP rail
// fills when a "+N" chip lands.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/onboarding/flow/onboarding_step.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell.dart';
import 'package:nuvo/features/onboarding/shell/onboarding_shell_controller.dart';
import 'package:nuvo/features/onboarding/shell/track_painter.dart';
import 'package:nuvo/features/onboarding/shell/xp_rail.dart';

Widget _app({
  required OnboardingShellController shell,
  required OnboardingStep step,
  String ctaLabel = 'Next',
  bool disableAnimations = false,
}) => MaterialApp(
  // copyWith so the real viewInsets survive — a fresh MediaQueryData here
  // would zero the keyboard inset the dock is supposed to read.
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: OnboardingShellScope(
    controller: shell,
    child: Stack(
      children: [
        OnboardingShell(
          step: step,
          hero: const SizedBox.expand(),
          title: 'Step ${step.index}',
          ctaLabel: ctaLabel,
          onCta: () {},
        ),
        XpFlyOverlay(controller: shell),
      ],
    ),
  ),
);

/// The fixed CTA slot — found by the key the dock stamps on its container.
Finder _cta() => find.byKey(const ValueKey('onboarding-cta'));

void main() {
  group('OnboardingShell', () {
    testWidgets('CTA position + size are identical across steps', (
      tester,
    ) async {
      Rect? first;
      for (final step in [
        OnboardingStep.introRace,
        OnboardingStep.signIn,
        OnboardingStep.code,
        OnboardingStep.playerCard,
        OnboardingStep.arenaTour,
        OnboardingStep.tourCrew,
      ]) {
        final shell = OnboardingShellController();
        await tester.pumpWidget(
          _app(shell: shell, step: step, ctaLabel: 'Go ${step.index}'),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(_cta());
        expect(rect.height, 56, reason: step.name);
        if (first == null) {
          first = rect;
        } else {
          expect(rect, first, reason: 'CTA moved on ${step.name}');
        }
        shell.dispose();
      }
    });

    testWidgets('CTA docks above the keyboard', (tester) async {
      // viewInsets is physical pixels — pin DPR 1:1 so 300 means 300.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final shell = OnboardingShellController();
      await tester.pumpWidget(_app(shell: shell, step: OnboardingStep.email));
      await tester.pumpAndSettle();
      final before = tester.getRect(_cta());

      // Open the keyboard.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final after = tester.getRect(_cta());
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // The dock's bottom edge sits exactly on top of the keyboard.
      expect(after.bottom, lessThan(before.bottom));
      expect(after.bottom, closeTo(screenH - 300, 1));
      shell.dispose();
    });

    testWidgets('reduce-motion: the track snaps (no pan), content renders', (
      tester,
    ) async {
      final shell = OnboardingShellController()
        ..trackFrom = 2
        ..trackIndex = 5;
      await tester.pumpWidget(
        _app(
          shell: shell,
          step: OnboardingStep.playerCard,
          disableAnimations: true,
        ),
      );
      await tester.pump();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(TrackBackground),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter
              as TrackPainter;
      // Under reduce-motion the camera teleports — zero frames of pan.
      expect(painter.pathProgress, 5);
      expect(painter.beadProgress, 5);
      expect(painter.avatarProgress, 5);
      expect(
        find.text('Step ${OnboardingStep.playerCard.index}'),
        findsOneWidget,
      );
      shell.dispose();
    });

    testWidgets('XP rail fills only after the +N flight lands', (tester) async {
      final shell = OnboardingShellController();
      await tester.pumpWidget(_app(shell: shell, step: OnboardingStep.code));
      await tester.pumpAndSettle();
      expect(find.text('0 XP'), findsOneWidget);

      shell.award(10);
      // Mid-flight: the chip exists but the rail hasn't grown yet.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('10 XP'), findsNothing);

      // Flight done (600 ms) — the rail now shows the landed XP.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('10 XP'), findsOneWidget);
      expect(find.text('+10'), findsNothing);
      shell.dispose();
    });

    testWidgets('reduce-motion: XP lands instantly, no chip flies', (
      tester,
    ) async {
      final shell = OnboardingShellController();
      await tester.pumpWidget(
        _app(shell: shell, step: OnboardingStep.code, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      shell.award(30);
      await tester.pump();
      expect(find.text('30 XP'), findsOneWidget);
      expect(find.text('+30'), findsNothing);
      shell.dispose();
    });

    testWidgets('pre-auth steps show dots, post-auth steps show the rail', (
      tester,
    ) async {
      final shell = OnboardingShellController();
      await tester.pumpWidget(
        _app(shell: shell, step: OnboardingStep.introHow),
      );
      await tester.pumpAndSettle();
      expect(find.byType(XpRail), findsNothing);

      await tester.pumpWidget(_app(shell: shell, step: OnboardingStep.code));
      await tester.pumpAndSettle();
      expect(find.byType(XpRail), findsOneWidget);
      shell.dispose();
    });
  });
}
