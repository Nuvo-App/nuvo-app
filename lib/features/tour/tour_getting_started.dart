import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/v13/v13.dart';
import 'tour_controller.dart';
import 'tour_script.dart';

/// The slim "Getting started" row on Arena for people who skipped the tour:
/// five missions as progress dots. Tapping picks the tour back up at the
/// earliest owed stop. Renders nothing unless the tour feature is on, the
/// tour was skipped and a mission is still open.
class TourGettingStartedRow extends ConsumerWidget {
  const TourGettingStartedRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(tourGettingStartedVisibleProvider)) {
      return const SizedBox.shrink();
    }
    final missions = ref.watch(tourMissionsProvider);
    final done = missions.where((m) => m.done).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V13.pagePad,
        V13.gapLg,
        V13.pagePad,
        0,
      ),
      child: NuvoPressable(
        key: const ValueKey('tour-getting-started'),
        onTap: () => ref.read(tourControllerProvider.notifier).resume(),
        shadow: V13.shadow3,
        borderRadius: BorderRadius.circular(V13.radiusTileLg),
        semanticLabel: 'Getting started, $done of ${missions.length} done',
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V13.gapLg,
            vertical: V13.gapMd,
          ),
          decoration: BoxDecoration(
            color: V13.card,
            borderRadius: BorderRadius.circular(V13.radiusTileLg),
            border: Border.all(color: V13.navy, width: V13.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Getting started',
                  style: V13.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final m in missions)
                Container(
                  key: ValueKey('tour-dot-${m.id}'),
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: V13.gapXs + 2),
                  decoration: BoxDecoration(
                    color: m.done ? V13.blue : V13.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: V13.navy, width: V13.outline),
                  ),
                ),
              const SizedBox(width: V13.gapSm),
              const Icon(Icons.chevron_right_rounded, color: V13.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings > Help: replay the tour from the first stop.
Future<void> replayTour(WidgetRef ref) =>
    ref.read(tourControllerProvider.notifier).replay();

/// Label for a mission (kept next to the row that lists them).
String tourMissionName(String id) => tourMissionLabel(id);
