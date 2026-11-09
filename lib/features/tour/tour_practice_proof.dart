import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/v13/v13.dart';
import 'tour_controller.dart';
import 'tour_script.dart';

/// Submit proof on the practice race (S10).
///
/// Honest scope: the practice race is client-only, so it cannot go through
/// the real Submit proof sheet (that is bound to a server race and to the AI
/// Motion camera screen, which this build leaves untouched). The camera path
/// is therefore not wired here; the sheet offers the spec's fallback, "Skip
/// camera for now", which completes as a Practice proof worth 10 XP instead
/// of 30. Nothing is sent to the server.
Future<void> openTourPracticeProof(BuildContext context, WidgetRef ref) async {
  final skip = await showV13Sheet<bool>(
    context,
    builder: (_) => const TourPracticeProofSheet(),
  );
  if (skip != true) return;
  if (context.mounted) showV13Confetti(context);
  await ref
      .read(tourControllerProvider.notifier)
      .practiceProofDone(fallback: true);
}

class TourPracticeProofSheet extends StatelessWidget {
  const TourPracticeProofSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('tour-practice-proof'),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapMd,
        V13.pagePad,
        V13.gapLg + bottom,
      ),
      decoration: const BoxDecoration(
        color: V13.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(V13.radiusCardLg),
        ),
        border: Border(
          top: BorderSide(color: V13.navy, width: V13.outlineThick),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: V13.divider,
                borderRadius: BorderRadius.circular(V13.radiusPill),
              ),
            ),
          ),
          const SizedBox(height: V13.gapLg),
          const V13Pill(label: 'Practice'),
          const SizedBox(height: V13.gapSm),
          Text('Practice proof', style: V13.cardTitle),
          const SizedBox(height: V13.gapSm),
          Text(
            kTourPracticeCamera,
            style: V13.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapXs),
          Text(
            'This race is practice, so the camera is optional here.',
            style: V13.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapLg),
          NuvoPressable(
            key: const ValueKey('tour-skip-camera'),
            onTap: () => Navigator.of(context).pop(true),
            shadow: V13.shadow3,
            borderRadius: BorderRadius.circular(V13.radiusButton),
            semanticLabel: 'Skip camera for now',
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: V13.blue,
                borderRadius: BorderRadius.circular(V13.radiusButton),
                border: Border.all(color: V13.navy, width: V13.outlineThick),
              ),
              child: Text(
                'Skip camera for now',
                style: V13.bodyStrong.copyWith(color: V13.card),
              ),
            ),
          ),
          const SizedBox(height: V13.gapSm),
          NuvoPressable(
            key: const ValueKey('tour-practice-cancel'),
            onTap: () => Navigator.of(context).pop(false),
            semanticLabel: 'Not now',
            child: Container(
              height: 44,
              alignment: Alignment.center,
              child: Text(
                'Not now',
                style: V13.bodyStrong.copyWith(color: V13.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
