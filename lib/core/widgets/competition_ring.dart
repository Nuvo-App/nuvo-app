import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/nuvo_tokens.dart';

/// A reusable circular race progress component.
///
/// This is the signature visual element of Nuvo: a ring that represents one
/// race, with participants positioned around the edge and progress shown by
/// the filled sweep. It does not depend on any screen and has no hardcoded
/// demo data.
class CompetitionRing extends StatefulWidget {
  const CompetitionRing({
    super.key,
    required this.size,
    required this.participants,
    this.currentUserId,
    this.centerLabel,
    this.animate = true,
    this.duration = NuvoTokens.duration320,
  });

  /// Visual size of the ring. Use [CompetitionRingSize.small],
  /// [CompetitionRingSize.medium], or [CompetitionRingSize.large].
  final CompetitionRingSize size;

  /// Participant data used to render the ring and position markers.
  /// Each entry carries a display name, optional photo, and progress.
  final List<CompetitionRingParticipant> participants;

  /// The user ID to highlight with the blue ring.
  final String? currentUserId;

  /// Optional text shown in the center of the ring.
  final String? centerLabel;

  /// Whether progress should animate from the previous value to the new one.
  final bool animate;

  /// Duration of the progress and marker animation.
  final Duration duration;

  @override
  State<CompetitionRing> createState() => _CompetitionRingState();
}

/// T-shirt sizes for the ring.
enum CompetitionRingSize {
  /// 96 logical pixels — lists, notifications, widgets.
  small(
    diameter: 96,
    ringThickness: 5,
    markerSize: 18,
    avatarSize: 18,
    labelStyleSize: NuvoTokens.type12,
  ),

  /// 160 logical pixels — race detail hero, profile history.
  medium(
    diameter: 160,
    ringThickness: 8,
    markerSize: 28,
    avatarSize: 28,
    labelStyleSize: NuvoTokens.type14,
  ),

  /// 240 logical pixels — arena hero, share cards.
  large(
    diameter: 240,
    ringThickness: 10,
    markerSize: 40,
    avatarSize: 40,
    labelStyleSize: NuvoTokens.type18,
  );

  const CompetitionRingSize({
    required this.diameter,
    required this.ringThickness,
    required this.markerSize,
    required this.avatarSize,
    required this.labelStyleSize,
  });

  final double diameter;
  final double ringThickness;
  final double markerSize;
  final double avatarSize;
  final double labelStyleSize;
}

/// Participant data required to render a marker on the ring.
class CompetitionRingParticipant {
  const CompetitionRingParticipant({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.progressPercent,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final int progressPercent;
}

class _CompetitionRingState extends State<CompetitionRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_ParticipantPosition> _positions;
  late int _maxProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _positions = _computePositions(widget.participants);
    _maxProgress = _computeMaxProgress(widget.participants);
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant CompetitionRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPositions = _computePositions(widget.participants);
    final newMax = _computeMaxProgress(widget.participants);
    if (_maxProgress != newMax ||
        !_participantListsEqual(oldWidget.participants, widget.participants)) {
      setState(() {
        _positions = newPositions;
        _maxProgress = newMax;
      });
      if (widget.animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final ringPadding = size.markerSize * 0.35;
    final usableDiameter = size.diameter - (ringPadding * 2);
    final ringInset = ringPadding + (size.ringThickness / 2);
    final arcRect = Rect.fromLTWH(
      ringInset,
      ringInset,
      size.diameter - ringInset * 2,
      size.diameter - ringInset * 2,
    );
    final center = Offset(size.diameter / 2, size.diameter / 2);

    return SizedBox(
      width: size.diameter,
      height: size.diameter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(size.diameter, size.diameter),
            painter: _RingPainter(
              arcRect: arcRect,
              ringThickness: size.ringThickness,
              progressPercent: _maxProgress,
              progress: _controller.value,
            ),
            child: Stack(
              children: [
                if (widget.centerLabel != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(NuvoTokens.space16),
                      child: Text(
                        widget.centerLabel!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NuvoTokens.fontFamily,
                          fontSize: size.labelStyleSize,
                          fontWeight: NuvoTokens.weightBold,
                          color: NuvoTokens.navy,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                for (final pos in _positions)
                  _buildMarker(
                    participant: pos.participant,
                    rank: pos.rank,
                    angle: pos.angle,
                    radius: usableDiameter / 2,
                    center: center,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarker({
    required CompetitionRingParticipant participant,
    required int rank,
    required double angle,
    required double radius,
    required Offset center,
  }) {
    final x = center.dx + radius * math.cos(angle);
    final y = center.dy + radius * math.sin(angle);
    final isCurrentUser = participant.userId == widget.currentUserId;
    final ringColor = _rankRingColor(rank, isCurrentUser);

    final avatar = Container(
      width: widget.size.markerSize,
      height: widget.size.markerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NuvoTokens.card,
        border: Border.all(
          color: ringColor ?? NuvoTokens.borderColor,
          width: NuvoTokens.avatarRingThickness,
        ),
        boxShadow: NuvoTokens.shadow1,
      ),
      clipBehavior: Clip.antiAlias,
      child: _avatarContent(participant),
    );

    return Positioned(
      left: x - widget.size.markerSize / 2,
      top: y - widget.size.markerSize / 2,
      child: avatar,
    );
  }

  Widget _avatarContent(CompetitionRingParticipant participant) {
    final initials = _initials(participant.displayName);
    final url = participant.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => _initialsFallback(initials),
        errorWidget: (_, _, _) => _initialsFallback(initials),
      );
    }
    return _initialsFallback(initials);
  }

  Widget _initialsFallback(String initials) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: NuvoTokens.fontFamily,
          fontSize: widget.size.avatarSize * 0.42,
          fontWeight: NuvoTokens.weightBold,
          color: NuvoTokens.gray600,
        ),
      ),
    );
  }

  Color? _rankRingColor(int rank, bool isCurrentUser) {
    if (rank == 1) return NuvoTokens.gold;
    if (rank == 2) return NuvoTokens.silver;
    if (rank == 3) return NuvoTokens.bronze;
    if (isCurrentUser) return NuvoTokens.royalBlue;
    return null;
  }

  List<_ParticipantPosition> _computePositions(
    List<CompetitionRingParticipant> participants,
  ) {
    if (participants.isEmpty) return [];
    final sorted = [...participants]
      ..sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    final count = sorted.length;

    // For two participants, place them at 10 o'clock and 2 o'clock so they
    // face each other across the ring. For three+, distribute evenly starting
    // from the top-left quadrant.
    final startAngle = -math.pi * 0.75;
    final spacing = count <= 2 ? math.pi : (2 * math.pi) / count;

    return sorted.asMap().entries.map((entry) {
      final rank = entry.key + 1;
      final angle = startAngle + (entry.key * spacing);
      return _ParticipantPosition(
        participant: entry.value,
        rank: rank,
        angle: angle,
      );
    }).toList();
  }

  int _computeMaxProgress(List<CompetitionRingParticipant> participants) {
    if (participants.isEmpty) return 0;
    return participants
        .map((p) => p.progressPercent)
        .reduce((a, b) => a > b ? a : b);
  }

  bool _participantListsEqual(
    List<CompetitionRingParticipant> a,
    List<CompetitionRingParticipant> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final pa = a[i];
      final pb = b[i];
      if (pa.userId != pb.userId ||
          pa.progressPercent != pb.progressPercent ||
          pa.photoUrl != pb.photoUrl ||
          pa.displayName != pb.displayName) {
        return false;
      }
    }
    return true;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0].toUpperCase();
    final last = parts.length > 1 && parts.last.isNotEmpty
        ? parts.last[0].toUpperCase()
        : '';
    return '$first$last';
  }
}

class _ParticipantPosition {
  const _ParticipantPosition({
    required this.participant,
    required this.rank,
    required this.angle,
  });

  final CompetitionRingParticipant participant;
  final int rank;
  final double angle;
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.arcRect,
    required this.ringThickness,
    required this.progressPercent,
    required this.progress,
  });

  final Rect arcRect;
  final double ringThickness;
  final int progressPercent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = arcRect.width / 2;

    // Track ring
    final trackPaint = Paint()
      ..color = NuvoTokens.gray200
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, trackPaint);

    // Race-track tick marks
    final tickCount = 60;
    final tickPaint = Paint()
      ..color = NuvoTokens.gray200.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < tickCount; i++) {
      final angle = (2 * math.pi * i / tickCount) - math.pi / 2;
      final isMajor = i % 5 == 0;
      final tickInset = ringThickness + (isMajor ? 3 : 6);
      final tickLength = isMajor ? 4 : 2;
      final start =
          center +
          Offset(
            (radius - tickInset) * math.cos(angle),
            (radius - tickInset) * math.sin(angle),
          );
      final end =
          center +
          Offset(
            (radius - tickInset + tickLength) * math.cos(angle),
            (radius - tickInset + tickLength) * math.sin(angle),
          );
      canvas.drawLine(start, end, tickPaint);
    }

    // Gradient progress arc
    final sweep = (2 * math.pi) * ((progressPercent / 100) * progress);
    if (sweep > 0) {
      final gradientShader = SweepGradient(
        center: Alignment.center,
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + sweep,
        colors: const [NuvoColors.blue, NuvoColors.blue2, NuvoColors.navy],
        stops: const [0.0, 0.5, 1.0],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(arcRect);

      final progressPaint = Paint()
        ..shader = gradientShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringThickness
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcRect, -math.pi / 2, sweep, false, progressPaint);

      // Soft glow at the leading edge
      final headAngle = -math.pi / 2 + sweep;
      final headCenter =
          center +
          Offset(radius * math.cos(headAngle), radius * math.sin(headAngle));
      final glowPaint = Paint()
        ..color = NuvoColors.blue2.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(headCenter, ringThickness * 1.4, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.progressPercent != progressPercent;
}
