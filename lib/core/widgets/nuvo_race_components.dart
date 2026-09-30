import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_geometry.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';
import 'nuvo_race_path.dart';
import 'pressable_scale.dart';

/// Canonical race components for Nuvo.
///
/// Visual grammar:
///   RaceHero    — the one loud navy surface (Compete featured, Verify Up Next)
///   RaceRow     — active race row (Compete "Your races", Verify "Also ready")
///   RaceResultRow — finished race row (Compete Finished, Verify Completed)
///   RaceActivityRow — recent proof activity (Verify Recent)
///
/// Shared primitives:
///   RacePlacement — quiet rank treatment (not a colored badge)
///   RaceProgress  — progress that works at 0%, partial, and complete
///   RacePeople    — avatar stack with count
///
/// Design rules:
///   - Movement + title dominate. Badges/pills are secondary.
///   - Rank is a quiet number, not a colored square. Podium gets color only
///     on the number itself, not a container.
///   - Progress at 0% shows a start-line marker, not an empty bar.
///   - No chevrons. Rows are tappable; the press scale is the affordance.

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

Color? _placementColor(int? rank) {
  if (rank == null) return null;
  return switch (rank) {
    1 => NuvoColors.position1,
    2 => NuvoColors.position2,
    3 => NuvoColors.position3,
    _ => null,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// RacePlacement — quiet rank, not a colored badge
// ──────────────────────────────────────────────────────────────────────────────

/// Quiet placement treatment.
///
/// Shows rank as a number with placement color (gold/silver/bronze for 1-3).
/// No container, no badge shape — just the number. The color communicates
/// podium status without a generic rounded square.
class RacePlacement extends StatelessWidget {
  const RacePlacement({
    super.key,
    required this.rank,
    this.size = 16,
    this.onDark = false,
    this.prefix = '#',
  });

  final int? rank;
  final double size;
  final bool onDark;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    if (rank == null) return const SizedBox.shrink();

    final color = _placementColor(rank);
    final fgColor = onDark
        ? (color ?? NuvoColors.white.withValues(alpha: 0.85))
        : (color ?? context.themeColors.ink);

    return Text(
      '$prefix$rank',
      style: AppTextStyles.statLarge(
        size,
        color: fgColor,
        weight: FontWeight.w800,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceProgress — progress that works at every state
// ──────────────────────────────────────────────────────────────────────────────

/// Race progress track.
///
/// - 0%: start-line marker (a small dot at the left). No empty bar.
/// - partial: filled portion + position dot
/// - 100%: finish-line check at the right
///
/// Does NOT look like a Material slider. The track is thin, the fill is
/// blue (or green at completion), and the position marker has a navy ring
/// so it reads as "you are here on the track."
class RaceProgress extends StatelessWidget {
  const RaceProgress({
    super.key,
    required this.progressPercent,
    this.onDark = false,
    this.trackHeight = 3.0,
    this.dotDiameter = 10.0,
    this.fillColor,
  });

  final int progressPercent;
  final bool onDark;
  final double trackHeight;
  final double dotDiameter;

  /// Optional accent for the fill/marker — state or activity color. The
  /// 100% finish-line treatment still wins over any accent.
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final progress = (progressPercent / 100).clamp(0.0, 1.0);
    final trackColor = onDark
        ? Colors.white.withValues(alpha: 0.16)
        : c.track;
    final fillColor = progress >= 1
        ? NuvoColors.success
        : this.fillColor ?? NuvoColors.actionBlue;

    return SizedBox(
      height: dotDiameter,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final fillWidth = (totalWidth * progress).clamp(0.0, totalWidth);

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track
              Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                ),
              ),
              // Fill (only when progress > 0)
              if (progress > 0)
                Container(
                  width: fillWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
              // 0%: start-line marker — small, quiet
              if (progress == 0)
                Positioned(
                  left: 0,
                  child: Container(
                    width: dotDiameter * 0.7,
                    height: dotDiameter * 0.7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: onDark
                          ? Colors.white.withValues(alpha: 0.30)
                          : c.border,
                    ),
                  ),
                ),
              // Partial: position dot with navy ring
              if (progress > 0 && progress < 1)
                Positioned(
                  left: (fillWidth - dotDiameter / 2).clamp(
                    0.0,
                    totalWidth - dotDiameter,
                  ),
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: BoxDecoration(
                      color: fillColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 1.5),
                    ),
                  ),
                ),
              // 100%: finish-line check at right
              if (progress >= 1)
                Positioned(
                  right: 0,
                  child: Container(
                    width: dotDiameter,
                    height: dotDiameter,
                    decoration: BoxDecoration(
                      color: NuvoColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 7,
                      color: NuvoColors.white,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceMarkerTrack — named marks on one lane
// ──────────────────────────────────────────────────────────────────────────────

/// One named mark on a [RaceMarkerTrack] — a competitor's dot and its label.
class RaceTrackMarker {
  const RaceTrackMarker({
    required this.fraction,
    required this.label,
    required this.color,
    this.isViewer = false,
    this.size,
    this.haloColor,
    this.ringColor,
  });

  /// Position on the lane, 0..1. Callers normalize against the race target.
  final double fraction;
  final String label;
  final Color color;

  /// The viewer's mark — it also drives the lane's fill and reads
  /// physically larger than rival marks.
  final bool isViewer;

  /// Dot diameter. Rivals default smaller than the viewer; a tied race
  /// passes the viewer's size so equal standings read as equal marks.
  final double? size;

  /// A soft glow behind the mark — the "leading" treatment (green).
  final Color? haloColor;

  /// A hard outer ring around the mark — the takeover payoff (gold).
  /// Reserved for the brief lead-take moment; never ambient.
  final Color? ringColor;
}

/// The race as a single lane: the viewer's mark, rivals' marks, and the goal
/// ring at the finish — each named. This is the same track language Verify
/// uses for its hero: positions are named people, not an anonymous bar.
///
/// Labels sit above the lane and resolve collisions right-to-left so close
/// standings never overlap. The viewer's fraction fills the lane in their
/// color; rivals are solid dots; the goal is an open ring.
class RaceMarkerTrack extends StatelessWidget {
  const RaceMarkerTrack({
    super.key,
    required this.markers,
    this.goalLabel,
    this.fillColor = NuvoColors.actionBlue,
    this.goalReached = false,
    this.hasGoal = true,
    this.compact = false,
    this.hero = false,
  });

  /// Marks in any order — the viewer's mark carries [isViewer] and fills
  /// the lane. Rivals render as navy dots with their name + score.
  final List<RaceTrackMarker> markers;

  /// Label pinned to the goal ring ("Goal 50"). Null draws the ring alone.
  /// Ignored in [compact] mode — quick lanes never carry labels.
  final String? goalLabel;

  /// Lane fill color — the viewer's state color (blue = racing).
  final Color fillColor;

  /// The finish-line ring fills green when the race is over — the only
  /// finished signal on the lane itself.
  final bool goalReached;

  /// Whether a literal finish-line ring exists. Best-attempt and
  /// lower-wins races spread marks across a relative-competition lane and
  /// must not draw a goal ring — there is no denominator to reach.
  final bool hasGoal;

  /// Quick-view density: no labels, a shorter lane, smaller marks. Same
  /// marks and animation — less chrome.
  final bool compact;

  /// Hero scale — the lane as the screen's primary graphic: a heavier
  /// track, physically larger marks, and bigger labels. Same canonical
  /// geometry, animation, and collision rules — roughly 2x the default.
  final bool hero;

  static const double _labelWidth = 64;
  static const double _heroLabelWidth = 84;
  static const double _trackHeight = 4;
  static const double _viewerSize = 11;
  static const double _rivalSize = 8;

  // Hero geometry — the same marks, physically louder.
  static const double _heroTrackHeight = 7;
  static const double _heroViewerSize = 20;
  static const double _heroRivalSize = 13;

  // Compact geometry — the same marks on a tighter lane.
  static const double _compactTrackHeight = 3;
  static const double _compactViewerSize = 9;
  static const double _compactRivalSize = 7;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    // Lane geometry — same marks, density decides how loud they read.
    final trackHeight =
        compact ? _compactTrackHeight : hero ? _heroTrackHeight : _trackHeight;
    final laneTop = compact ? 7.0 : hero ? 34.0 : 25.0;
    final goalSize = compact ? 10.0 : hero ? 22.0 : 13.0;
    final height = compact ? 16.0 : hero ? 78.0 : 40.0;
    final labelWidth = hero ? _heroLabelWidth : _labelWidth;
    final labelSize = hero ? 12.5 : 10.5;

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final viewer = markers
            .where((m) => m.isViewer)
            .firstOrNull;
        final viewerX = (viewer?.fraction ?? 0).clamp(0.0, 1.0) * w;

        // Label slots centered on each mark — placed right-to-left so close
        // standings never overlap: each label slides left until it clears
        // the label on its right.
        final lw = labelWidth;
        final labelSpots = <(double x, String text, Color color)>[
          if (!compact && hasGoal && goalLabel != null)
            (w - 4, goalLabel!, c.inkMuted),
          if (!compact)
            for (final m in markers)
              (m.fraction.clamp(0.0, 1.0) * w, m.label, m.color),
        ]..sort((a, b) => b.$1.compareTo(a.$1));
        var nextRight = w;
        final resolved = <({double left, String text, Color color})>[];
        for (final spot in labelSpots) {
          var left = (spot.$1 - lw / 2).clamp(0.0, (w - lw).clamp(0.0, w));
          if (left + lw > nextRight) {
            left = (nextRight - lw - 2).clamp(0.0, (w - lw).clamp(0.0, w));
          }
          nextRight = left;
          resolved.add((left: left, text: spot.$2, color: spot.$3));
        }

        const slide = Duration(milliseconds: 260);
        const slideCurve = Curves.easeOutCubic;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              for (final r in resolved)
                AnimatedPositioned(
                  top: 0,
                  left: r.left,
                  width: lw,
                  duration: slide,
                  curve: slideCurve,
                  child: Text(
                    r.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelUppercase(
                      labelSize,
                    ).copyWith(color: r.color),
                  ),
                ),
              // Lane + viewer fill.
              Positioned(
                top: laneTop,
                left: 0,
                right: 0,
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: c.track,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
              ),
              if (viewerX > 0)
                AnimatedPositioned(
                  top: laneTop,
                  left: 0,
                  width: viewerX,
                  duration: slide,
                  curve: slideCurve,
                  child: AnimatedContainer(
                    duration: slide,
                    curve: slideCurve,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius:
                          BorderRadius.circular(trackHeight / 2),
                    ),
                  ),
                ),
              // Goal ring at the finish — open while racing, fills green
              // when the race is done. Best-attempt and lower-wins lanes
              // have no finish ring — there is no denominator to reach.
              if (hasGoal)
                Positioned(
                  top: laneTop + trackHeight / 2 - goalSize / 2,
                  left: w - goalSize,
                  child: AnimatedContainer(
                    duration: slide,
                    curve: slideCurve,
                    width: goalSize,
                    height: goalSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: goalReached ? NuvoColors.success : c.page,
                      border: Border.all(
                        color:
                            goalReached ? NuvoColors.success : fillColor,
                        width: hero ? 2.5 : 2,
                      ),
                    ),
                  ),
                ),
              // Rivals draw first, viewer last — an overtake visibly slides
              // the viewer's mark OVER the rival it just passed.
              for (final m in [...markers]..sort(
                  (a, b) => (a.isViewer ? 1 : 0).compareTo(b.isViewer ? 1 : 0),
                ))
                Builder(builder: (context) {
                  final extent = _markExtent(m);
                  return AnimatedPositioned(
                    top: laneTop + trackHeight / 2 - extent / 2,
                    left: ((m.fraction.clamp(0.0, 1.0) * w) - extent / 2)
                        .clamp(0.0, w - extent),
                    duration: slide,
                    curve: slideCurve,
                    width: extent,
                    height: extent,
                    child: _mark(m, c),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  /// One lane mark. The viewer is the physical object — larger, navy-edged,
  /// with a hard offset nub — while rivals stay solid navy dots. State is
  /// carried by the wrappers: a soft [haloColor] glow while leading, a hard
  /// [ringColor] ring for the takeover moment only.
  /// Outer extent of a mark including its halo/ring — the lane positions
  /// marks by their visual edge so the dot stays centered on its fraction.
  double _markExtent(RaceTrackMarker m) =>
      _markSize(m) +
      (m.haloColor != null ? 6 : 0) +
      (m.ringColor != null ? 9 : 0);

  double _markSize(RaceTrackMarker m) => m.size ??
      (m.isViewer
          ? (compact
              ? _compactViewerSize
              : hero
                  ? _heroViewerSize
                  : _viewerSize)
          : (compact
              ? _compactRivalSize
              : hero
                  ? _heroRivalSize
                  : _rivalSize));

  Widget _mark(RaceTrackMarker m, NuvoThemeColors c) {
    final size = _markSize(m);
    Widget dot = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: m.color,
        // The viewer's mark is a physical bead — navy edge + offset shade
        // so it reads as something that slid down the track.
        border: m.isViewer
            ? Border.all(color: c.inkShadow, width: hero ? 2 : 1.5)
            : null,
        boxShadow: m.isViewer
            ? [
                BoxShadow(
                  color: c.inkShadow.withValues(alpha: 0.35),
                  offset: Offset(hero ? 2.5 : 1.5, hero ? 2.5 : 1.5),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
    );
    if (m.ringColor != null) {
      // Hard payoff ring — gold takeover flash.
      dot = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: m.ringColor!, width: 2),
        ),
        child: dot,
      );
    }
    if (m.haloColor != null) {
      dot = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: m.haloColor!.withValues(alpha: 0.25),
        ),
        child: dot,
      );
    }
    return Center(child: dot);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RacePeople — avatar stack with count
// ──────────────────────────────────────────────────────────────────────────────

/// Avatar stack that understands crew completeness.
///
/// Filled avatars + dashed empty slots when waiting for crew.
/// The +N overflow bubble shows total people beyond the visible stack.
class RacePeople extends StatelessWidget {
  const RacePeople({
    super.key,
    required this.avatars,
    required this.total,
    this.emptySlots = 0,
    this.size = 24,
    this.max = 3,
    this.borderColor,
  });

  final List<({String initials, String? photoUrl, String id})> avatars;
  final int total;
  final int emptySlots;
  final double size;
  final int max;

  /// Ring around each avatar so stacked faces separate cleanly. Defaults
  /// to the ambient surface so the ring matches whatever the row sits on
  /// in both themes.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = this.borderColor ?? context.themeColors.surface;
    final filled = avatars.length;
    final showEmpty = emptySlots > 0;
    final overflow = total > max;
    final visibleFilled = overflow
        ? filled.clamp(0, max - 1)
        : filled.clamp(0, max);
    final visibleEmpty = showEmpty
        ? (overflow
              ? emptySlots.clamp(0, (max - visibleFilled - 1).clamp(0, max))
              : emptySlots.clamp(0, max - visibleFilled))
        : 0;

    final totalSlots = overflow
        ? visibleFilled + 1 + visibleEmpty
        : visibleFilled + visibleEmpty;

    if (totalSlots == 0) return const SizedBox.shrink();

    final overlap = (size * 0.32).clamp(8.0, 13.0);
    final stepWidth = size - overlap;
    final stackWidth = size + stepWidth * (totalSlots - 1);
    final ringWidth = size <= NuvoAvatarSizes.xs ? 1.5 : 2.0;

    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < visibleFilled; i++)
            Positioned(
              left: i * stepWidth,
              child: NuvoAvatar(
                initials: avatars[i].initials,
                photoUrl: avatars[i].photoUrl,
                size: size,
                bgColor: nuvoAvatarColorFor(avatars[i].id),
                textColor: NuvoColors.white,
                borderColor: borderColor,
                borderWidth: ringWidth,
              ),
            ),
          for (var j = 0; j < visibleEmpty; j++)
            Positioned(
              left: (visibleFilled + j) * stepWidth,
              child: _EmptyCrewSlot(size: size),
            ),
          if (overflow)
            Positioned(
              left: (visibleFilled + visibleEmpty) * stepWidth,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.themeColors.panel,
                  border: Border.all(color: borderColor, width: ringWidth),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${total - visibleFilled}',
                  style: TextStyle(
                    fontSize: (size * 0.3).clamp(6.0, 10.0),
                    fontWeight: FontWeight.w800,
                    color: context.themeColors.ink,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyCrewSlot extends StatelessWidget {
  const _EmptyCrewSlot({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.page,
        border: Border.all(
          color: c.border.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.add_rounded,
        size: size * 0.42,
        color: c.inkDim,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceProgressLabel — score + target context line
// ──────────────────────────────────────────────────────────────────────────────

/// Progress context line: "12 reps to 100 reps" or "20% to finish".
class RaceProgressLabel extends StatelessWidget {
  const RaceProgressLabel({
    super.key,
    required this.progressLabel,
    required this.targetLabel,
    this.onDark = false,
    this.compact = false,
  });

  final String progressLabel;
  final String targetLabel;
  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final labelColor = onDark
        ? NuvoColors.white.withValues(alpha: 0.85)
        : c.ink;
    final targetColor = onDark
        ? NuvoColors.white.withValues(alpha: 0.55)
        : c.inkSubtle;
    final valueStyle = AppTextStyles.statLarge(
      compact ? 13 : 15,
      color: labelColor,
      weight: FontWeight.w800,
    );
    final targetStyle = AppTextStyles.raceRowMeta.copyWith(color: targetColor);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: progressLabel, style: valueStyle),
          // A best-attempt / lowest-wins race has no denominator — callers
          // pass targetLabel '' and the score stands alone ("78 strokes").
          if (targetLabel.isNotEmpty)
            TextSpan(text: ' to $targetLabel', style: targetStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceHero — the one loud navy surface
// ──────────────────────────────────────────────────────────────────────────────

/// Hero race card. The strongest object on the page — the one race that is
/// happening right now, presented as a standing, not a card of metadata.
///
/// Two body modes:
///   - [trackMarkers] provided → stat anchor + named marker lane (the same
///     race-track language as the Verify hero): big viewer score, "You /
///     Noah / Goal" marks, then the stakes line.
///   - [trackMarkers] omitted → the identity [NuvoRacePath] / linear
///     [RaceProgress] fallback for callers without a numeric target.
///
/// Layout (marker mode):
///   race title + header action + placement
///   movement · target
///   big viewer score / target          ← the anchor
///   named marker lane                  ← rivalry is visible, not implied
///   stakes line (contextNote)
///   blue action strip: crew + CTA
class RaceHero extends StatelessWidget {
  const RaceHero({
    super.key,
    required this.activityLabel,
    required this.targetLabel,
    required this.raceTitle,
    required this.progressPercent,
    required this.progressLabel,
    required this.racerStack,
    this.rank,
    required this.onOpen,
    this.actionLabel = 'View leaderboard',
    this.ctaIcon,
    this.showRank = true,
    this.raceId,
    this.headerAction,
    this.contextNote,
    this.anchorValue,
    this.anchorSuffix,
    this.trackMarkers,
    this.goalLabel,
    this.trackFillColor = NuvoColors.actionBlue,
    this.trackHasGoal = true,
    this.goalReached = false,
  });

  final String activityLabel;
  final String targetLabel;
  final String raceTitle;
  final int progressPercent;
  final String progressLabel;
  final Widget racerStack;
  final int? rank;
  final VoidCallback onOpen;
  final String actionLabel;
  final IconData? ctaIcon;
  final bool showRank;

  /// Big stat anchor — the viewer's current score ("39", "1:42") rendered
  /// large in action blue above the lane so position reads before detail.
  final String? anchorValue;

  /// Target context beside the anchor — "/ 50 reps".
  final String? anchorSuffix;

  /// Named marks for the lane — viewer first, then rivals. When provided
  /// the lane is [RaceMarkerTrack]; when omitted, the identity path or
  /// plain linear bar stays. Callers supply this only when the race has a
  /// numeric target to normalize against.
  final List<RaceTrackMarker>? trackMarkers;

  /// Label pinned at the goal ring ("Goal 50") — only used with
  /// [trackMarkers].
  final String? goalLabel;

  /// Lane fill — the viewer's state color. Blue while racing, green when
  /// leading the field to the line.
  final Color trackFillColor;

  /// Whether the lane ends in a finish ring. False for best-attempt and
  /// lower-wins races — their marks sit on a relative-competition lane.
  final bool trackHasGoal;

  /// The race is over — the goal ring fills green.
  final bool goalReached;

  /// The race's stable identity. When provided, the track is rendered as
  /// [NuvoRacePath] — a curved path whose shape is unique to this race but
  /// deterministic (same race, same path, every rebuild). When omitted, this
  /// falls back to the plain linear [RaceProgress] bar for callers that
  /// don't have a stable race identity to seed from.
  final String? raceId;

  /// Optional quiet control pinned to the title row's trailing edge (the
  /// featured card's "Updates ↻" flip affordance). Kept small — the title
  /// stays dominant and the CTA strip keeps its single action.
  final Widget? headerAction;

  /// Optional canonical stakes line rendered under the "movement · target"
  /// meta ("Beat Noah. 14 to take #2" / "11 reps to the finish line").
  /// Callers compose it from canonical race state (ChaseContext /
  /// viewerContext); the hero only renders the string. Null = unchanged.
  final String? contextNote;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final hasProof = progressPercent > 0;

    return PressableScale(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NuvoRadii.lg),
          border: Border.all(color: c.border, width: 2),
          boxShadow: AppShadows.hardOffset(c.inkShadow, offset: const Offset(7, 7)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NuvoRadii.lg - 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Raised body: race identity + track lane ──
              Container(
                color: c.surface,
                // Tightened from a flat NuvoSpacing.lg (16) on every edge —
                // this card (Compete's featured race, Verify's Up Next) was
                // taller than its five lines of content needed. Same
                // padding rhythm, less of it.
                padding: const EdgeInsets.fromLTRB(
                  NuvoSpacing.lg,
                  NuvoSpacing.md,
                  NuvoSpacing.lg,
                  NuvoSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Race title (+ optional quiet header action + placement).
                    // The rank sits at the title line's trailing edge — the
                    // card's verdict is visible before the lane is read.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            raceTitle,
                            style: AppTextStyles.featuredRaceTitle.copyWith(
                              color: c.ink,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (headerAction != null) ...[
                          const SizedBox(width: 8),
                          headerAction!,
                        ],
                        if (trackMarkers != null &&
                            showRank &&
                            rank != null &&
                            hasProof) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _ordinal(rank!),
                              style: AppTextStyles.placementLabel(
                                color: _placementColor(rank) ?? c.ink,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Movement · target
                    Text(
                      targetLabel.isEmpty
                          ? activityLabel
                          : '$activityLabel · $targetLabel',
                      style: AppTextStyles.raceRowMeta.copyWith(
                        color: c.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (trackMarkers != null && trackMarkers!.isNotEmpty) ...[
                      // Stat anchor — the viewer's score at Verify scale.
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            anchorValue ?? '$progressPercent%',
                            style: AppTextStyles.statLarge(
                              30,
                              color: NuvoColors.actionBlue,
                              weight: FontWeight.w800,
                            ),
                          ),
                          if (anchorSuffix != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                anchorSuffix!,
                                style: AppTextStyles.statLarge(
                                  15,
                                  color: c.inkMuted,
                                  weight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Named lane — You vs the field vs the goal ring.
                      RaceMarkerTrack(
                        markers: trackMarkers!,
                        goalLabel: goalLabel,
                        fillColor: trackFillColor,
                        hasGoal: trackHasGoal,
                        goalReached: goalReached,
                      ),
                      // Stakes — why the next proof matters ("11 reps to
                      // take 1st"), straight from canonical race state.
                      if (contextNote != null &&
                          contextNote!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          contextNote!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: NuvoColors.actionBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ] else ...[
                      // Stakes — why this proof matters. Blue (forward
                      // action), one line, canonical copy only.
                      if (contextNote != null &&
                          contextNote!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          contextNote!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelMedium.copyWith(
                            color: NuvoColors.actionBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: NuvoSpacing.md),
                      // Race lane — prominent track on white. A
                      // unique-per-race curved path when we have a stable
                      // race identity to seed it from; otherwise the plain
                      // linear bar.
                      if (raceId != null)
                        NuvoRacePath(
                          key: ValueKey('race-path-$raceId'),
                          raceId: raceId!,
                          progress: progressPercent / 100,
                          variant: NuvoRacePathVariant.compact,
                        )
                      else
                        RaceProgress(
                          progressPercent: progressPercent,
                          onDark: false,
                          trackHeight: 5,
                          dotDiameter: 16,
                        ),
                      const SizedBox(height: 6),
                      // Lane context
                      Row(
                        children: [
                          if (!hasProof)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: NuvoColors.actionBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Start line',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: c.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            )
                          else
                            Expanded(
                              child: RaceProgressLabel(
                                progressLabel: progressLabel,
                                targetLabel: targetLabel,
                                onDark: false,
                                compact: true,
                              ),
                            ),
                          if (showRank && rank != null && hasProof)
                            Text(
                              _ordinal(rank!),
                              style: AppTextStyles.placementLabel(
                                color: _placementColor(rank) ?? c.ink,
                                size: 13,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // ── Blue action strip: crew + CTA ──
              Container(
                color: NuvoColors.actionBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: NuvoSpacing.lg,
                  vertical: NuvoSpacing.sm,
                ),
                child: Row(
                  children: [
                    racerStack,
                    const SizedBox(width: 8),
                    // Flexible, not a bare Row after a Spacer — a long label
                    // ("View leaderboard") plus the racer stack could exceed
                    // the strip's width on a narrow phone; this shrinks the
                    // label (ellipsis) instead of overflowing the Row.
                    Expanded(
                      child: GestureDetector(
                        onTap: onOpen,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                actionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: NuvoColors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              ctaIcon ?? Icons.arrow_forward_rounded,
                              color: NuvoColors.white,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceRow — active race row
// ──────────────────────────────────────────────────────────────────────────────

/// Active race row for "Your races" lists — the canonical QUICK view.
///
/// Answers in ~1 second: what race, where am I, how close.
///
/// Layout:
///   race title (≤2 lines)          rank / "Start line"
///   progress value (blue)          ← the second-strongest text
///   compact marker lane            ← you + nearest rival + goal ring
///   chase context · participants   [avatars]
///
/// The lane is a compact [RaceMarkerTrack] when [trackMarkers] is
/// provided (viewer + the rival directly ahead), else the plain
/// [RaceProgress] bar. Lower-wins and best-attempt races pass
/// `hasGoal: false` so no finish ring implies a denominator that
/// doesn't exist.
class RaceRow extends StatelessWidget {
  const RaceRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.progressLabel,
    required this.progressPercent,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
    this.rewardLabel,
    this.remainingLabel,
    this.trackMarkers,
    this.hasGoal = true,
    this.goalReached = false,
    this.contextNote,
    this.contextColor,
    this.leading,
    this.raised = false,
    this.rewardArtifact = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: NuvoSpacing.md,
      vertical: NuvoSpacing.md,
    ),
  });

  final String raceTitle;
  final String movementLabel;
  final String progressLabel;
  final int progressPercent;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  /// Deterministic progression hint ("Finish · +25 XP") — server-declared
  /// constants only, shown when finishing would pay out.
  final String? rewardLabel;

  /// Distance still to the finish line ("22 left") — the bottom context
  /// line when no [contextNote] is provided.
  final String? remainingLabel;

  /// Viewer + nearest-rival marks for the compact lane. When null the row
  /// draws the plain [RaceProgress] bar instead.
  final List<RaceTrackMarker>? trackMarkers;

  /// Whether the compact lane ends in a finish ring — false for
  /// best-attempt and lower-wins races (relative-competition lanes).
  final bool hasGoal;

  /// Fills the goal ring green — a completed race's quiet signal.
  final bool goalReached;

  /// Canonical stakes line ("3 reps to pass Noah") — replaces the
  /// remaining/movement meta when present.
  final String? contextNote;

  /// Chase-state tint for [contextNote] — blue chasing, green leading,
  /// gold for the takeover moment. Muted when null.
  final Color? contextColor;

  /// Optional leading slot (a movement icon well on Profile) — the row's
  /// composition stays identical to its left.
  final Widget? leading;

  /// Lifts the row off a section plane — white surface, restrained navy
  /// edge, small offset shadow. Opt-in: a race with real progress is an
  /// interactive object, not another line on the field.
  final bool raised;

  /// Renders [rewardLabel] as a compact tag at the trailing edge of the
  /// context line instead of a second text line — the reward reads as an
  /// artifact attached to the race, not more metadata.
  final bool rewardArtifact;

  /// Row padding — lists that already carry their own horizontal gutter
  /// (Profile's racing-now section) pass a vertical-only padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final hasProof = progressPercent > 0;
    final contextLine = contextNote ??
        [
          movementLabel,
          ?remainingLabel,
          '$participantCount ${participantCount == 1 ? 'racer' : 'racers'}',
        ].join(' · ');

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: padding,
          decoration: raised
              ? BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(NuvoRadii.md),
                  border: Border.all(color: c.border, width: 1.25),
                  // A quiet offset — the object stands off its field
                  // without shouting over the hero.
                  boxShadow: AppShadows.hardOffset(
                    c.inkShadow,
                    offset: const Offset(2.5, 2.5),
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: NuvoSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasProof) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: NuvoColors.actionBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Expanded(
                          child: Text(
                            raceTitle,
                            style: AppTextStyles.raceRowTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: NuvoSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: hasProof
                              ? RacePlacement(rank: rank, size: 15)
                              : Text(
                                  'Start line',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: c.inkSubtle,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    if (hasProof) ...[
                      const SizedBox(height: 4),
                      // The progress value is the second read — blue and
                      // weighted, never folded into the gray meta line.
                      Text(
                        progressLabel,
                        style: AppTextStyles.statLarge(
                          13.5,
                          color: NuvoColors.actionBlue,
                          weight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      if (trackMarkers != null)
                        RaceMarkerTrack(
                          markers: trackMarkers!,
                          compact: true,
                          hasGoal: hasGoal,
                          goalReached: goalReached,
                        )
                      else
                        RaceProgress(
                          progressPercent: progressPercent,
                          trackHeight: 3,
                          dotDiameter: 9,
                        ),
                      const SizedBox(height: 6),
                    ] else
                      const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contextLine,
                            style: AppTextStyles.raceRowMeta.copyWith(
                              color: contextColor ?? c.inkSubtle,
                              fontWeight: contextNote != null
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (rewardArtifact && rewardLabel != null) ...[
                          const SizedBox(width: NuvoSpacing.sm),
                          // The payout docks at the context line's trailing
                          // edge — a small ice tag the race carries, not a
                          // dangling second line of metadata.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.panel,
                              borderRadius:
                                  BorderRadius.circular(NuvoRadii.pill),
                            ),
                            child: Text(
                              rewardLabel!,
                              style: AppTextStyles.raceRowMeta.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: NuvoColors.actionBlue,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (avatars.isNotEmpty) ...[
                          const SizedBox(width: NuvoSpacing.sm),
                          RacePeople(
                            avatars: avatars,
                            total: participantCount,
                            size: 20,
                            max: 3,
                          ),
                        ],
                      ],
                    ),
                    if (!rewardArtifact && rewardLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        rewardLabel!,
                        style: AppTextStyles.raceRowMeta.copyWith(
                          color: NuvoColors.actionBlue,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceResultRow — finished race row
// ──────────────────────────────────────────────────────────────────────────────

/// Finished race row. Shows placement, not progress.
///
/// Layout:
///   race title (dominant)
///   movement · racer count (meta line)
///   people + placement (right-aligned)
///
/// No progress bar — the absence of progress communicates "this is over."
class RaceResultRow extends StatelessWidget {
  const RaceResultRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.rank,
    required this.participantCount,
    required this.avatars,
    required this.onTap,
  });

  final String raceTitle;
  final String movementLabel;
  final int? rank;
  final int participantCount;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final placementStr = rank != null ? _ordinal(rank!) : '--';

    return Semantics(
      button: true,
      label: raceTitle,
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: NuvoSpacing.md,
            vertical: NuvoSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$movementLabel · $participantCount ${participantCount == 1 ? 'racer' : 'racers'}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              if (avatars.isNotEmpty) ...[
                RacePeople(
                  avatars: avatars,
                  total: participantCount,
                  size: 22,
                  max: 3,
                ),
                const SizedBox(width: NuvoSpacing.sm),
              ],
              Text(
                placementStr,
                style: AppTextStyles.placementLabel(
                  color: _placementColor(rank) ?? context.themeColors.inkSubtle,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceActivityRow — recent proof activity
// ──────────────────────────────────────────────────────────────────────────────

/// Recent proof activity row for Verify Recent.
///
/// Prioritizes race/movement and verification outcome, NOT the actor.
/// The actor is secondary (small avatar) because it's usually the same user.
///
/// Layout:
///   small avatar (secondary)
///   race title (dominant)
///   movement · value · status (meta line)
///   status indicator (right)
class RaceActivityRow extends StatelessWidget {
  const RaceActivityRow({
    super.key,
    required this.raceTitle,
    required this.movementLabel,
    required this.actorName,
    required this.actorInitial,
    required this.actorPhotoUrl,
    required this.actorId,
    required this.valueStr,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
    this.statusNote,
  });

  final String raceTitle;
  final String movementLabel;
  final String actorName;
  final String actorInitial;
  final String? actorPhotoUrl;
  final String actorId;
  final String? valueStr;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onTap;

  /// Optional consequence line under the verdict ("#9 → #8") — what the
  /// proof changed. Kept out of the meta line so it can't get ellipsized
  /// away by a long title.
  final String? statusNote;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$raceTitle · $statusLabel',
      child: PressableScale(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: NuvoSpacing.md,
            vertical: NuvoSpacing.md,
          ),
          child: Row(
            children: [
              // Small avatar — secondary
              NuvoAvatar(
                initials: actorInitial,
                photoUrl: actorPhotoUrl,
                size: 28,
                bgColor: nuvoAvatarColorFor(actorId),
                textColor: NuvoColors.white,
              ),
              const SizedBox(width: NuvoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      raceTitle,
                      style: AppTextStyles.raceRowTitle.copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // "who moved · what · how much" — an activity row is
                      // about the person, not just the race.
                      '$actorName · $movementLabel${valueStr != null ? ' · $valueStr' : ''}',
                      style: AppTextStyles.raceRowMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NuvoSpacing.sm),
              // Status — quiet text, no pill container; the rank move it
              // caused sits right under the verdict.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    statusLabel,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  if (statusNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        statusNote!,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: context.themeColors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceSummary — waiting/finished summary header
// ──────────────────────────────────────────────────────────────────────────────

/// Summary row for waiting-for-crew races — a flat toggle row on the page,
/// not a card. Shows the incompleteness structurally: filled avatars +
/// dashed empty slots.
class RaceWaitingSummary extends StatelessWidget {
  const RaceWaitingSummary({
    super.key,
    required this.raceCount,
    required this.totalWaitingSlots,
    required this.avatars,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final int raceCount;
  final int totalWaitingSlots;
  final List<({String initials, String? photoUrl, String id})> avatars;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final subtitle =
        '$raceCount ${raceCount == 1 ? 'race' : 'races'} need crew';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NuvoSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Waiting for crew',
                        style: AppTextStyles.sectionTitle,
                      ),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                if (avatars.isNotEmpty) ...[
                  RacePeople(
                    avatars: avatars,
                    total: avatars.length,
                    emptySlots: totalWaitingSlots.clamp(0, 3),
                    size: 22,
                    max: 3,
                  ),
                  const SizedBox(width: NuvoSpacing.sm),
                ],
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: c.inkDim,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

/// Summary row for finished races — the payoff line. Flat on the page; a
/// restrained gold trophy marks the win record without a banner.
class RaceFinishedSummary extends StatelessWidget {
  const RaceFinishedSummary({
    super.key,
    required this.raceCount,
    required this.wonCount,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final int raceCount;
  final int wonCount;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    final subtitle =
        '$raceCount ${raceCount == 1 ? 'race' : 'races'}'
        ' · $wonCount ${wonCount == 1 ? 'win' : 'wins'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressableScale(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: NuvoSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Finished', style: AppTextStyles.sectionTitle),
                      Text(subtitle, style: AppTextStyles.raceRowMeta),
                    ],
                  ),
                ),
                // A win record is the payoff — a quiet gold mark, not a
                // banner, so the summary communicates results at a glance.
                if (wonCount > 0) ...[
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: NuvoColors.gold,
                    size: 18,
                  ),
                  const SizedBox(width: NuvoSpacing.sm),
                ],
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: c.inkDim,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// RaceQuickStart — quick start tile
// ──────────────────────────────────────────────────────────────────────────────

/// Quick start tile. Movement identity leads, target is secondary.
class RaceQuickStart extends StatelessWidget {
  const RaceQuickStart({
    super.key,
    required this.icon,
    required this.movementName,
    required this.target,
    required this.onTap,
  });

  final IconData icon;
  final String movementName;
  final String target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.themeColors;
    return PressableScale(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NuvoSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(NuvoRadii.md),
          border: Border.all(color: c.border, width: 1.25),
        ),
        child: Row(
          children: [
            Icon(icon, color: c.ink, size: 20),
            const SizedBox(width: NuvoSpacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    movementName,
                    style: AppTextStyles.raceRowTitle.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    target,
                    style: AppTextStyles.statLarge(
                      11,
                      color: c.inkMuted,
                      weight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Legacy aliases — keep old names working during migration
// ──────────────────────────────────────────────────────────────────────────────

/// Legacy alias for [RacePeople].
typedef NuvoRacerStack = RacePeople;

/// Legacy alias for [RaceProgress].
/// Note: old NuvoRaceLane had a different API; use RaceProgress directly.
class NuvoRaceLane extends RaceProgress {
  const NuvoRaceLane({
    super.key,
    required super.progressPercent,
    super.onDark = false,
    super.trackHeight = 3.0,
    super.dotDiameter = 12.0,
    Duration delay = Duration.zero,
  }) : super();
}

/// Legacy alias for [RaceProgressLabel].
typedef NuvoRaceProgressLane = RaceProgressLabel;

/// Legacy alias for [RaceWaitingSummary].
typedef NuvoWaitingCrewSummary = RaceWaitingSummary;

/// Legacy alias for [RaceFinishedSummary].
typedef NuvoFinishedSummary = RaceFinishedSummary;

/// Legacy alias for [RaceQuickStart].
typedef NuvoQuickStart = RaceQuickStart;

/// Legacy alias for [RaceHero].
typedef NuvoFeaturedRaceCard = RaceHero;

/// Legacy alias for [RaceRow].
typedef NuvoRaceRow = RaceRow;

/// The canonical QUICK presentation — [RaceRow] is the quick view: title,
/// blue progress value, compact marker lane, chase context, avatars.
/// Named explicitly so screens pick a presentation mode, not a widget.
typedef NuvoRaceQuickView = RaceRow;

/// The canonical FOCUSED presentation — [RaceHero] is the single-race
/// view: large viewer score, named marker lane, stakes, one CTA.
typedef NuvoRaceFocusedView = RaceHero;

/// Legacy alias for [RaceResultRow].
typedef NuvoFinishedRaceRow = RaceResultRow;
