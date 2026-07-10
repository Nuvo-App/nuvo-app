import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_text_styles.dart';
import 'nuvo_avatar.dart';

const _kRaceTrackBackground = Color(0xFFEFEFEF);
const _kRaceTrackNavy = Color(0xFF0A1A33);
const _kRaceTrackBlue = Color(0xFF5096F9);
const _kRaceTrackMuted = Color(0xFFBBBEC4);
const _kRaceTrackWhite = Color(0xFFFFFFFF);
const _kRaceTrackGold = Color(0xFFD4A24C);

/// Display data for a competitor on [AnimatedRaceTrack].
///
/// [progress] is normalized from 0.0 to 1.0. Keep [rank] 1-based. Exactly one
/// competitor should set [isCurrentUser] to true.
class AnimatedRaceTrackCompetitor {
  const AnimatedRaceTrackCompetitor({
    required this.id,
    required this.name,
    required this.initials,
    required this.progress,
    required this.rank,
    this.avatarImageUrl,
    this.isCurrentUser = false,
  });

  final String id;
  final String name;
  final String initials;
  final double progress;
  final int rank;
  final String? avatarImageUrl;
  final bool isCurrentUser;

  double get clampedProgress => progress.clamp(0.0, 1.0);
}

/// A polished, reusable circular race-result update widget.
///
/// The widget does not fetch or mutate data. It only renders supplied
/// competitors, animates progress/rank changes, and triggers haptics when the
/// current user's supplied rank improves.
class AnimatedRaceTrack extends StatefulWidget {
  const AnimatedRaceTrack({
    super.key,
    required this.competitors,
    required this.totalGoal,
    this.size = 260,
    this.trackWidth = 9,
    this.animationDuration = const Duration(milliseconds: 1050),
    this.curve = Curves.easeInOutCubic,
    this.showLeaderboard = true,
  }) : assert(competitors.length >= 2, 'AnimatedRaceTrack needs 2+ players.'),
       assert(competitors.length <= 20, 'AnimatedRaceTrack supports up to 20.'),
       assert(totalGoal > 0, 'totalGoal must be greater than zero.');

  final List<AnimatedRaceTrackCompetitor> competitors;
  final int totalGoal;
  final double size;
  final double trackWidth;
  final Duration animationDuration;
  final Curve curve;
  final bool showLeaderboard;

  @override
  State<AnimatedRaceTrack> createState() => _AnimatedRaceTrackState();
}

class _AnimatedRaceTrackState extends State<AnimatedRaceTrack>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _rankPulseController;
  late Map<String, double> _fromProgressById;
  late Map<String, double> _toProgressById;
  int? _lastCurrentRank;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..value = 1;
    _rankPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _fromProgressById = _progressMap(widget.competitors);
    _toProgressById = _progressMap(widget.competitors);
    _lastCurrentRank = _currentUser(widget.competitors).rank;
  }

  @override
  void didUpdateWidget(covariant AnimatedRaceTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _progressController.duration = widget.animationDuration;

    final oldProgress = {
      for (final competitor in oldWidget.competitors)
        competitor.id: _animatedProgressFor(competitor.id),
    };
    _fromProgressById = oldProgress;
    _toProgressById = _progressMap(widget.competitors);
    _progressController.forward(from: 0);

    final newRank = _currentUser(widget.competitors).rank;
    final oldRank = _lastCurrentRank;
    if (oldRank != null && newRank < oldRank) {
      HapticFeedback.mediumImpact();
      _rankPulseController.forward(from: 0);
    }
    _lastCurrentRank = newRank;
  }

  @override
  void dispose() {
    _progressController.dispose();
    _rankPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _currentUser(widget.competitors);
    final sorted = _sortedByRank(widget.competitors);
    final leaderboardHeight = widget.showLeaderboard
        ? sorted.length * _RaceTrackLeaderboardRow.height
        : 0.0;

    return ColoredBox(
      color: _kRaceTrackBackground,
      child: SizedBox(
        width: widget.size,
        height:
            widget.size + (widget.showLeaderboard ? 18 + leaderboardHeight : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: widget.size,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _progressController,
                  _rankPulseController,
                ]),
                builder: (context, _) {
                  final currentProgress = _animatedProgressFor(currentUser.id);
                  final placements = _markerPlacements(widget.competitors);

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size.square(widget.size),
                        painter: _RaceTrackPainter(
                          progress: currentProgress,
                          trackWidth: widget.trackWidth,
                        ),
                      ),
                      _CenterResult(
                        rank: currentUser.rank,
                        progressValue: _progressValue(currentProgress),
                        totalGoal: widget.totalGoal,
                        pulseValue: _rankPulseController.value,
                      ),
                      for (final placement in placements)
                        _TrackAvatarMarker(
                          competitor: placement.competitor,
                          point: _pointForProgress(
                            progress: _animatedProgressFor(
                              placement.competitor.id,
                            ),
                            size: widget.size,
                            radialOffset: placement.radialOffset,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (widget.showLeaderboard) ...[
              const SizedBox(height: 18),
              _AnimatedRaceTrackLeaderboard(
                competitors: sorted,
                totalGoal: widget.totalGoal,
                animatedProgressFor: _animatedProgressFor,
                duration: widget.animationDuration,
                curve: widget.curve,
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _progressValue(double progress) => (progress * widget.totalGoal).round();

  double _animatedProgressFor(String id) {
    final from = _fromProgressById[id] ?? _toProgressById[id] ?? 0;
    final to = _toProgressById[id] ?? from;
    final t = widget.curve.transform(_progressController.value);
    return from + (to - from) * t;
  }

  static Map<String, double> _progressMap(
    List<AnimatedRaceTrackCompetitor> competitors,
  ) => {
    for (final competitor in competitors)
      competitor.id: competitor.clampedProgress,
  };

  static AnimatedRaceTrackCompetitor _currentUser(
    List<AnimatedRaceTrackCompetitor> competitors,
  ) {
    return competitors.firstWhere(
      (competitor) => competitor.isCurrentUser,
      orElse: () => competitors.first,
    );
  }

  static List<AnimatedRaceTrackCompetitor> _sortedByRank(
    List<AnimatedRaceTrackCompetitor> competitors,
  ) {
    return [...competitors]..sort((a, b) {
      final rankCompare = a.rank.compareTo(b.rank);
      if (rankCompare != 0) return rankCompare;
      return b.progress.compareTo(a.progress);
    });
  }

  List<_MarkerPlacement> _markerPlacements(
    List<AnimatedRaceTrackCompetitor> competitors,
  ) {
    final sortedByAngle = [...competitors]
      ..sort(
        (a, b) =>
            _animatedProgressFor(a.id).compareTo(_animatedProgressFor(b.id)),
      );
    final offsets = <String, double>{};
    const closeThreshold = 0.075;
    const radialSteps = [0.0, 9.0, -8.0, 14.0, -12.0];

    var clusterStart = 0;
    while (clusterStart < sortedByAngle.length) {
      var clusterEnd = clusterStart;
      while (clusterEnd + 1 < sortedByAngle.length) {
        final current = _animatedProgressFor(sortedByAngle[clusterEnd].id);
        final next = _animatedProgressFor(sortedByAngle[clusterEnd + 1].id);
        if ((next - current).abs() > closeThreshold) break;
        clusterEnd++;
      }

      for (var i = clusterStart; i <= clusterEnd; i++) {
        final clusterIndex = i - clusterStart;
        offsets[sortedByAngle[i].id] =
            radialSteps[clusterIndex % radialSteps.length];
      }
      clusterStart = clusterEnd + 1;
    }

    if (sortedByAngle.length > 1) {
      final first = sortedByAngle.first;
      final last = sortedByAngle.last;
      final wrapGap =
          _animatedProgressFor(first.id) + 1 - _animatedProgressFor(last.id);
      if (wrapGap < closeThreshold) {
        offsets[first.id] = offsets[first.id] == 0 ? 13 : offsets[first.id]!;
        offsets[last.id] = offsets[last.id] == 0 ? -10 : offsets[last.id]!;
      }
    }

    return competitors
        .map(
          (competitor) => _MarkerPlacement(
            competitor: competitor,
            radialOffset: offsets[competitor.id] ?? 0,
          ),
        )
        .toList();
  }
}

class _RaceTrackPainter extends CustomPainter {
  const _RaceTrackPainter({required this.progress, required this.trackWidth});

  final double progress;
  final double trackWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 38;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final basePaint = Paint()
      ..color = _kRaceTrackMuted.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, basePaint);

    final tickPaint = Paint()
      ..color = _kRaceTrackMuted.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + (i / 10) * 2 * math.pi;
      final inner = radius - 7;
      final outer = radius + 7;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tickPaint,
      );
    }

    final finishPaint = Paint()
      ..color = _kRaceTrackNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + Offset(0, -radius - 12),
      center + Offset(0, -radius + 10),
      finishPaint,
    );

    if (progress <= 0) return;
    final activePaint = Paint()
      ..color = _kRaceTrackBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      progress.clamp(0.0, 1.0) * 2 * math.pi,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RaceTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackWidth != trackWidth;
  }
}

class _CenterResult extends StatelessWidget {
  const _CenterResult({
    required this.rank,
    required this.progressValue,
    required this.totalGoal,
    required this.pulseValue,
  });

  final int rank;
  final int progressValue;
  final int totalGoal;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + math.sin(pulseValue * math.pi) * 0.08;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: scale,
          child: Text(
            '#$rank',
            style: AppTextStyles.number(
              34,
              color: _kRaceTrackNavy,
              weight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$progressValue / $totalGoal',
          style: AppTextStyles.labelLarge.copyWith(
            color: _kRaceTrackMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TrackAvatarMarker extends StatelessWidget {
  const _TrackAvatarMarker({required this.competitor, required this.point});

  final AnimatedRaceTrackCompetitor competitor;
  final Offset point;

  @override
  Widget build(BuildContext context) {
    final size = competitor.isCurrentUser ? 44.0 : 36.0;
    final borderColor = competitor.isCurrentUser
        ? _kRaceTrackBlue
        : competitor.rank == 1
        ? _kRaceTrackGold
        : _kRaceTrackWhite;
    final borderWidth = competitor.isCurrentUser ? 3.0 : 2.0;

    return Positioned(
      left: point.dx - size / 2,
      top: point.dy - size / 2,
      width: size,
      height: size,
      child: NuvoAvatar(
        initials: competitor.initials,
        size: size,
        photoUrl: competitor.avatarImageUrl,
        bgColor: nuvoAvatarColorFor(competitor.id),
        textColor: _kRaceTrackWhite,
        borderColor: borderColor,
        borderWidth: borderWidth,
      ),
    );
  }
}

class _AnimatedRaceTrackLeaderboard extends StatelessWidget {
  const _AnimatedRaceTrackLeaderboard({
    required this.competitors,
    required this.totalGoal,
    required this.animatedProgressFor,
    required this.duration,
    required this.curve,
  });

  final List<AnimatedRaceTrackCompetitor> competitors;
  final int totalGoal;
  final double Function(String id) animatedProgressFor;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: competitors.length * _RaceTrackLeaderboardRow.height,
      child: Stack(
        children: [
          for (var i = 0; i < competitors.length; i++)
            AnimatedPositioned(
              key: ValueKey(competitors[i].id),
              duration: duration,
              curve: curve,
              left: 0,
              right: 0,
              top: i * _RaceTrackLeaderboardRow.height,
              height: _RaceTrackLeaderboardRow.height,
              child: _RaceTrackLeaderboardRow(
                competitor: competitors[i],
                progressValue:
                    (animatedProgressFor(competitors[i].id) * totalGoal)
                        .round(),
              ),
            ),
        ],
      ),
    );
  }
}

class _RaceTrackLeaderboardRow extends StatelessWidget {
  const _RaceTrackLeaderboardRow({
    required this.competitor,
    required this.progressValue,
  });

  static const height = 42.0;

  final AnimatedRaceTrackCompetitor competitor;
  final int progressValue;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: competitor.isCurrentUser
            ? _kRaceTrackWhite.withValues(alpha: 0.74)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${competitor.rank}',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMedium.copyWith(
                  color: competitor.rank == 1
                      ? _kRaceTrackGold
                      : _kRaceTrackMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            NuvoAvatar(
              initials: competitor.initials,
              size: 26,
              photoUrl: competitor.avatarImageUrl,
              bgColor: nuvoAvatarColorFor(competitor.id),
              textColor: _kRaceTrackWhite,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                competitor.isCurrentUser ? 'You' : competitor.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  color: _kRaceTrackNavy,
                  fontWeight: competitor.isCurrentUser
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$progressValue',
              style: AppTextStyles.number(
                16,
                color: competitor.isCurrentUser
                    ? _kRaceTrackBlue
                    : _kRaceTrackNavy,
                weight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerPlacement {
  const _MarkerPlacement({
    required this.competitor,
    required this.radialOffset,
  });

  final AnimatedRaceTrackCompetitor competitor;
  final double radialOffset;
}

Offset _pointForProgress({
  required double progress,
  required double size,
  required double radialOffset,
}) {
  final center = Offset(size / 2, size / 2);
  final radius = (size / 2) - 38 + radialOffset;
  final angle = -math.pi / 2 + progress.clamp(0.0, 1.0) * 2 * math.pi;
  return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}
