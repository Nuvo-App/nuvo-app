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
/// the last page, dots underneath. With zero active races the designed
/// first-race hero is the only page — still a real next action.
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

  /// Card height at 1.0 text scale — cards fill it so every page reads
  /// the same size. The swiper grows it with the text scale and adds room
  /// for the hard shadow, so nothing clips.
  static const double height = 336;

  /// Most race cards the swiper shows before the "See all" card.
  static const int maxCards = 8;

  /// Card base colours, cycled by position (never by race id) so neighbours
  /// never match — including the wrap from the last card to the first.
  static const List<Color> palette = [
    V13.mint,
    V13.sky,
    V13.coral,
    V13.sun,
    V13.lilac,
    Color(0xFFA8E6F0), // aqua
    Color(0xFFFFD6A5), // apricot
  ];

  static Color colorAt(int index, int count) {
    var c = index % palette.length;
    // Last card would repeat the first's colour on a wrap: shift it.
    if (count > 1 && index == count - 1 && c == 0) c = 1;
    return palette[c];
  }

  @override
  ConsumerState<ArenaRaceSwiper> createState() => _ArenaRaceSwiperState();
}

class _ArenaRaceSwiperState extends ConsumerState<ArenaRaceSwiper> {
  PageController? _controller;
  int _page = 0;

  /// ~318 px card + 12 px gap → 330 px page as a fraction of the viewport.
  PageController _ensureController(double viewportWidth) {
    // Centred card at ~88% of the width; neighbours peek in on both sides.
    const fraction = 0.88;
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

  static int _pageToDot(int page, int pages) =>
      pages <= 8 ? page : (page * 7 / (pages - 1)).round();
  static int _dotToPage(int dot, int pages) =>
      pages <= 8 ? dot : (dot * (pages - 1) / 7).round();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.cards.take(ArenaRaceSwiper.maxCards).toList();
    final overflow = widget.cards.length - shown.length;
    final pageCount = shown.length + 1;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final cardHeight = ArenaRaceSwiper.height * (0.55 + 0.45 * textScale);
    return Padding(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controller = _ensureController(constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                // + room for the 6pt hard shadow under/right of each card.
                height: cardHeight + 8,
                child: PageView.builder(
                  controller: controller,
                  clipBehavior: Clip.none,
                  padEnds: true,
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final child = i == shown.length
                        ? (overflow > 0
                              ? ArenaSeeAllCard(total: widget.cards.length)
                              : shown.isEmpty
                              ? const ArenaFirstRaceCard()
                              : const ArenaAnotherCard())
                        : ArenaRaceCard(
                            data: shown[i],
                            color: ArenaRaceSwiper.colorAt(i, shown.length),
                            plus: widget.plusBursts[shown[i].race.id],
                            onPlusDone: widget.onPlusDone == null
                                ? null
                                : () => widget.onPlusDone!(shown[i].race.id),
                          );
                    return Padding(
                      // Balanced gutters; the extra 6pt on the right/bottom
                      // is the hard shadow's room.
                      padding: const EdgeInsets.fromLTRB(5, 0, 11, 8),
                      child: child,
                    );
                  },
                ),
              ),
              if (pageCount > 1) ...[
                const SizedBox(height: V13.gapMd),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // At most 8 dots; with more pages each dot covers a
                    // stretch of them so the row never runs off screen.
                    for (var i = 0; i < math.min(pageCount, 8); i++)
                      V13Pressable(
                        onTap: () {
                          V13Haptics.select();
                          controller.animateToPage(
                            _dotToPage(i, pageCount),
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
                            width: i == _pageToDot(_page, pageCount) ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _pageToDot(_page, pageCount)
                                  ? V13.navy
                                  : V13.divider,
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
    this.color,
    this.plus,
    this.onPlusDone,
  });

  final ArenaCardData data;

  /// Position-based base colour from the swiper; falls back to the race's.
  final Color? color;

  /// Non-null → the "+N" float that rides over the score once.
  final int? plus;
  final VoidCallback? onPlusDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final race = data.race;
    return V13Card(
      color: color ?? V13.raceColor(race.id),
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

/// The brand-new-account hero: a coral card the size of a race card with a
/// ghost race preview, one sentence and the one blue CTA.
class ArenaFirstRaceCard extends StatelessWidget {
  const ArenaFirstRaceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return V13EmptyHero(
      color: V13.coral,
      expandArt: true,
      art: const V13GhostRace(),
      title: 'Your first race',
      body: 'Challenge a friend and prove it on camera.',
      ctaLabel: 'Start a race',
      ctaIcon: Icons.flag_rounded,
      onCta: () => context.push('/races/new'),
      linkLabel: 'Join a race',
      onLink: () => context.go('/compete'),
      semanticLabel: 'Your first race',
    );
  }
}

/// The dashed last page — "Up for another one?" — shown after the race
/// cards.
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

/// Last swiper page when more than [ArenaRaceSwiper.maxCards] races are
/// live — sends the rest to Compete instead of an endless swipe.
class ArenaSeeAllCard extends StatelessWidget {
  const ArenaSeeAllCard({super.key, required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return V13Card.dashed(
      padding: const EdgeInsets.all(V13.gapLg + 2),
      semanticLabel: 'See all $total races',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$total races live',
            style: V13.cardTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V13.gapLg),
          V13Button.primary(
            label: 'See all $total races',
            icon: Icons.grid_view_rounded,
            fullWidth: true,
            onPressed: () => context.go('/compete'),
          ),
        ],
      ),
    );
  }
}
