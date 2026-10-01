import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/nuvo_button.dart';
import '../../onboarding/data/first_use_store.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import 'motion_catalog_provider.dart';

/// The one production entry into AI Motion Proof.
///
/// Every proof launch — Verify queue, Ready Next, Race Detail, the proof
/// screen's Begin — funnels here so the destination is decided BEFORE
/// navigation: camera-verifiable races go straight to the fullscreen verifier
/// (`/race/:id/proof/ai-motion`), everything else goes to the proof chooser
/// (`/race/:id/proof`). No route pushes an intermediate page and forwards.
///
/// The first camera launch per install shows the "why the camera" primer —
/// the OS prompt itself is raised by the camera plugin inside the verifier.
Future<void> openAiMotionProof(
  BuildContext context,
  WidgetRef ref,
  Race race, {
  required String routeAction,
}) async {
  final eligibility = resolveCameraVerification(
    race,
    remoteDefinitions: availableMotionActivities(
      ref.read(motionCatalogProvider).valueOrNull,
      ref.read(motionCapabilitiesProvider),
    ),
  );
  debugLogCameraVerificationDecision(race, eligibility, routeAction: routeAction);

  if (!eligibility.isCameraVerifiable) {
    if (context.mounted) {
      await context.push('/race/${race.id}/proof');
    }
    return;
  }

  final firstUse = ref.read(firstUseStoreProvider);
  if (!firstUse.isCameraPrimerSeen) {
    if (!context.mounted) return;
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.themeColors.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const CameraPrimerSheet(),
    );
    if (proceed != true) return;
    await firstUse.markCameraPrimerSeen();
  }

  if (!context.mounted) return;
  await context.push('/race/${race.id}/proof/ai-motion');
}

/// One-time "why the camera" education shown before the first AI Motion
/// launch. Install-scoped via [FirstUseStore.isCameraPrimerSeen]; a dismissed
/// primer asks again next time.
class CameraPrimerSheet extends StatelessWidget {
  const CameraPrimerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.panel,
                  border: Border.all(color: c.ink, width: 1.6),
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  color: NuvoColors.blue,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Move. We’ll verify it.',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium.copyWith(
                color: c.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Nuvo uses your camera to track your movement while you race.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: c.inkMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final (i, fact) in const [
                  (
                    icon: Icons.accessibility_new_rounded,
                    label: 'Processed for motion',
                  ),
                  (
                    icon: Icons.videocam_off_rounded,
                    label: 'Video isn’t uploaded',
                  ),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Icon(fact.icon, color: NuvoColors.blue, size: 22),
                        const SizedBox(height: 6),
                        Text(
                          fact.label,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            NuvoPrimaryButton(
              label: 'Continue',
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: AppTextStyles.titleMedium.copyWith(
                  color: c.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
