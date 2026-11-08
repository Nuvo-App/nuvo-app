import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_service.dart';
import '../../../core/v13/v13.dart';
import '../../onboarding/data/first_use_store.dart';
import '../data/race_models.dart';
import '../domain/camera_verification_resolver.dart';
import 'motion_catalog_provider.dart';

/// The one production entry into AI Motion Proof.
///
/// Every proof launch — Verify queue, Ready Next, Race Detail, the proof
/// screen's Begin — funnels here so the destination is decided BEFORE
/// navigation. A camera-verifiable race first lands on the proof screen's
/// pre-verify setup (`/race/:id/proof`: the motion character preview and
/// Begin); its Begin calls back with [fromPreview] and goes on to the
/// fullscreen verifier (`/race/:id/proof/ai-motion`). Manual races keep the
/// proof chooser. No route pushes an intermediate page and forwards.
///
/// The first camera launch per install shows the "why the camera" primer —
/// the OS prompt itself is raised by the camera plugin inside the verifier.
Future<void> openAiMotionProof(
  BuildContext context,
  WidgetRef ref,
  Race race, {
  required String routeAction,
  bool fromPreview = false,
}) async {
  final eligibility = resolveCameraVerification(
    race,
    remoteDefinitions: availableMotionActivities(
      ref.read(motionCatalogProvider).valueOrNull,
      ref.read(motionCapabilitiesProvider),
    ),
  );
  debugLogCameraVerificationDecision(
    race,
    eligibility,
    routeAction: routeAction,
  );

  // Not camera-verifiable → the chooser. Camera-verifiable but not yet seen
  // the pre-verify setup → show the motion preview first; its Begin returns
  // here with fromPreview so the user is never dropped into the camera cold.
  if (!eligibility.isCameraVerifiable ||
      (!fromPreview && eligibility.movementType != null)) {
    if (context.mounted) {
      await context.push('/race/${race.id}/proof');
    }
    return;
  }

  final firstUse = ref.read(firstUseStoreProvider);
  if (!firstUse.isCameraPrimerSeen) {
    if (!context.mounted) return;
    final proceed = await showV13Sheet<bool>(
      context,
      builder: (_) => const CameraPrimerSheet(),
    );
    if (proceed != true) return;
    await firstUse.markCameraPrimerSeen();
  }

  if (!context.mounted) return;
  // The one funnel entry for camera proofs — fires exactly once, no matter
  // which surface called openAiMotionProof. The verifier screen itself is
  // untouched; its submit/attempt events ride the race controller seams.
  ref
      .read(analyticsProvider)
      .proofStarted(activityId: race.activityId ?? 'unknown');
  await context.push('/race/${race.id}/proof/ai-motion');
}

/// One-time "why the camera" education shown before the first AI Motion
/// launch. Install-scoped via [FirstUseStore.isCameraPrimerSeen]; a dismissed
/// primer asks again next time.
class CameraPrimerSheet extends StatelessWidget {
  const CameraPrimerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapLg,
        V13.pagePad,
        V13.gapXxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: V13IconTile(
              icon: Icons.accessibility_new_rounded,
              color: V13.sky,
              size: 56,
              radius: V13.radiusTileLg,
              iconSize: 28,
            ),
          ),
          const SizedBox(height: V13.gapLg),
          Text(
            'Move. We’ll verify it.',
            textAlign: TextAlign.center,
            style: V13.title.copyWith(letterSpacing: -0.5),
          ),
          const SizedBox(height: V13.gapSm),
          Text(
            'Nuvo uses your camera to track your movement while you race.',
            textAlign: TextAlign.center,
            style: V13.body.copyWith(color: V13.muted),
          ),
          const SizedBox(height: V13.gapXl),
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
                if (i > 0) const SizedBox(width: V13.gapSm),
                Expanded(
                  child: Column(
                    children: [
                      Icon(fact.icon, color: V13.blue, size: 22),
                      const SizedBox(height: 6),
                      Text(
                        fact.label,
                        textAlign: TextAlign.center,
                        style: V13.caption.copyWith(
                          color: V13.navy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: V13.gapXl),
          V13Button.primary(
            label: 'Continue',
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          V13Button.ghost(
            label: 'Not now',
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
