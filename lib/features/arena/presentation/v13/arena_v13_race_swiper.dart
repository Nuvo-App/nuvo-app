import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nuvo/core/v13/v13.dart';
import 'package:nuvo/features/races/domain/race_display.dart';
import 'package:nuvo/features/races/presentation/race_controller.dart';
import 'package:nuvo/features/races/presentation/v13/submit_proof_entry.dart';

import 'arena_v13_data.dart';

/// The Arena race swiper — one snapping card per active race (~318 px wide
/// with the next card peeking), then a dashed "Up for another one?" card as
/// the last page, dots underneath. With zero active races the dashed card is
/// the only page — still a real next action.
class ArenaRaceSwiper extends ConsumerStatefulWidget {
  const ArenaRaceSwiper({
    super.key,
    required this.cards,
    this.plusBursts = const {},
    this.onPlusDone,
  });

  /// One card per active race, already in display order.
  final List<ArenaCardData> cards;

  /// "+N" floats keyed by race id — set by the screen when a proof lands.
  final Map<String, int> plusBursts;

  /// Called when a race's "+N" float finishes so the screen clears the flag.
  final void Function(String raceId)? onPlusDone;

  /// Swiper height — cards fill it so every page reads the same size.
  static const double height = 336;

  @override
  ConsumerState<ArenaRaceSwiper> createState() => _ArenaRaceSwiperState();
}

class _ArenaRaceSwiperState extends ConsumerState<ArenaRaceSwiper> {
  PageController? _controller;
  int _page = 0;

  /// ~318 px card + 12 px gap → 330 px page as a fraction of the viewport.
  PageController _ensureController(double viewportWidth) {
    final fraction = math.min(1.0, 330.0 / viewportWidth);
    final current = _controller;
    if (current == null) {
      return _controller = PageController(viewportFraction: fraction);
    }
    if ((current.viewportFraction - fraction).abs() > 0.001) {
      final page = current.hasClients
          ? (current.page?.round() ?? _page)
          : _page;
      _controller = PageController(
        viewportFraction: fraction,
        initialPage: page.clamp(0, widget.cards.length),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return _controller!;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.cards.length + 1;
    return Padding(
      padding: const EdgeInsets.only(left: V13.pagePad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controller = _ensureController(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: ArenaRaceSwiper.height,
                child: PageView.builder(
                  controller: controller,
                  padEnds: false,
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final child = i == widget.cards.length
                        ? const ArenaAnotherCard()
                        : ArenaRaceCard(
                            data: widget.cards[i],
                            plus: widget.plusBursts[widget.cards[i].race.id],
                            onPlusDone: widget.onPlusDone == null
                                ? null
                                : () => widget.onPlusDone!(
                                    widget.cards[i].race.id,
                                  ),
                          );
                    return Padding(
                      padding: const EdgeInsets.only(right: V13.gapMd),
                      child: child,
                    );
                  },
                ),
              ),
              if (pageCount > 1) ...[
                const SizedBox(height: V13.gapMd),
                Row(
                  children: [
                    for (var i = 0; i < pageCount; i++)
                      V13Pressable(
                        onTap: () {
                          V13Haptics.select();
                          controller.animateToPage(
                            i,
                            duration: V13Motion.medium,
                            curve: V13Motion.spring,
                          );
                        },
                        pressDepth: 1,
                        haptic: false,
                        semanticLabel: 'Page ${i + 1} of $pageCount',
                        child: Padding(
                          padding: const EdgeInsets.only(right: V13.gapSm - 2),
                          child: AnimatedContainer(
                            duration: V13Motion.fast,
                            curve: V13Motion.spring,
                            width: i == _page ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page ? V13.navy : V13.divider,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One active race as a v13 card — deterministic race color, leader faces,
/// movement + count, time left, big score with goal, place, progress, gap
/// line, and the Submit proof action.
class ArenaRaceCard extends ConsumerWidget {
  const ArenaRaceCard({
    super.key,
    required this.data,
    this.plus,
    this.onPlusDone,
  });

  final ArenaCardData data;

  /// Non-null → the "+N" float that rides over the score once.
  final int? plus;
  final VoidCallback? onPlusDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final race = data.race;
    return V13Card(
      color: V13.raceColor(race.id),
      radius: V13.radiusCard,
      shadow: V13.shadow6,
      padding: const EdgeInsets.all(V13.gapMd + 2),
      onTap: () => context.push('/race/${Uri.encodeComponent(race.id)}'),
      semanticLabel: race.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              V13FaceStack(
                faces: [
                  for (final f in data.leaderFaces)
                    V13FaceInfo(
                      id: f.userId,
                      photoUrl: f.photoUrl,
                      name: f.name,
                      isMe: f.isMe,
                    ),
                ],
                max: 3,
                size: 30,
                total: data.racerCount,
                onFaceTap: (face) {
                  final id = face.id;
                  if (id != null) openPerson(context, ref, id);
                },
              ),
              const SizedBox(width: V13.gapSm),
              Expanded(
                child: Text(
                  '${data.movementLabel} · ${data.racerCount} ${data.racerCount == 1 ? 'racer' : 'racers'}',
                  style: V13.caption.copyWith(
                    color: V13.navy,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (data.timeLeft != null) ...[
                const SizedBox(width: V13.gapSm),
                V13Pill(label: data.timeLeft!, icon: Icons.schedule_rounded),
              ],
            ],
          ),
          const SizedBox(height: V13.gapMd - 2),
          Text(
            race.title,
            style: V13.cardTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapXs),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          V13NumberPop(
                            value: data.score,
                            style: V13.hugeNumber,
                            format: (_) => data.scoreText,
                          ),
                          if (data.goalText != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: V13.gapXs,
                                bottom: V13.gapMd,
                              ),
                              child: Text(
                                '/ ${data.goalText}',
                                style: V13.bodyStrong,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: V13.gapSm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      data.rank == null
                          ? Text('—', style: V13.number)
                          : V13NumberPop(
                              value: data.rank!,
                              style: V13.number,
                              format: (_) => raceOrdinal(data.rank!),
                            ),
                      Text('of ${data.total}', style: V13.caption),
                    ],
                  ),
                ],
              ),
              if (plus != null)
                Positioned(
                  left: 0,
                  top: -V13.gapSm,
                  child: V13FloatingPlus(value: plus!, onDone: onPlusDone),
                ),
            ],
          ),
          const SizedBox(height: V13.gapMd),
          V13ProgressBar(value: data.progress, semanticLabel: 'Race progress'),
          const SizedBox(height: V13.gapSm + 2),
          SizedBox(
            height: 20,
            child: data.gapLine == null
                ? null
                : Text(
                    data.gapLine!,
                    style: V13.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const Spacer(),
          V13Button.primary(
            label: 'Submit proof',
            icon: Icons.photo_camera_rounded,
            fullWidth: true,
            onPressed: () async {
              await openSubmitProof(context, ref, race);
              if (!context.mounted) return;
              // Back from proof — pull fresh standings so a landed score
              // change animates the card (+N, number pop).
              ref.read(raceControllerProvider.notifier).markStale();
            },
          ),
        ],
      ),
    );
  }
}

/// The dashed last page — "Up for another one?" — and the hero card when
/// there are no active races.
class ArenaAnotherCard extends StatelessWidget {
  const ArenaAnotherCard({super.key});

  @override
  Widget build(BuildContext context) {
    return V13Card.dashed(
      padding: const EdgeInsets.all(V13.gapLg + 2),
      semanticLabel: 'Start or join a race',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Up for another one?',
            style: V13.cardTitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V13.gapLg),
          V13Button.primary(
            label: 'Start a race',
            icon: Icons.flag_rounded,
            fullWidth: true,
            onPressed: () => context.push('/races/new'),
          ),
          const SizedBox(height: V13.gapSm),
          Center(
            child: V13Button.ghost(
              label: 'Join a race',
              onPressed: () => context.go('/compete'),
            ),
          ),
        ],
      ),
    );
  }
}
