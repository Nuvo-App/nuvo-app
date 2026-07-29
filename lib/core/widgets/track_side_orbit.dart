import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nuvo_avatar.dart';

const _kNavy = Color(0xFF071B35);
const _kBlue = Color(0xFF2F7CFF);
const _kWhite = Color(0xFFF8FAFD);
const _kTrackGray = Color(0xFF415A7A);

class TrackSideOrbitParticipant {
  const TrackSideOrbitParticipant({
    required this.id,
    required this.name,
    required this.initials,
    required this.rank,
    required this.progressValue,
    this.photoUrl,
    this.photoAsset,
    this.isCurrentUser = false,
  });

  final String id;
  final String name;
  final String initials;
  final int rank;
  final int progressValue;
  final String? photoUrl;
  final String? photoAsset;
  final bool isCurrentUser;
}

class TrackSideOrbit extends StatefulWidget {
  const TrackSideOrbit({
    super.key,
    required this.scale,
    required this.totalGoal,
    required this.currentUserValue,
    required this.currentUserRank,
    required this.participants,
    this.selectedParticipantId,
    this.onParticipantTap,
  });

  /// Screen-width scale relative to the 390 pt design baseline.
  final double scale;
  final int totalGoal;
  final int currentUserValue;
  final int currentUserRank;
  final List<TrackSideOrbitParticipant> participants;
  final String? selectedParticipantId;
  final ValueChanged<String>? onParticipantTap;

  @override
  State<TrackSideOrbit> createState() => _TrackSideOrbitState();
}

class _TrackSideOrbitState extends State<TrackSideOrbit>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  double _fromProgress = 0;
  double _toProgress = 0;
  bool _hasInitialized = false;

  static const _kOrbitWidth = 346.0;
  static const _kOrbitHeight = 170.0;
  static const _kCenter = Offset(_kOrbitWidth / 2, 81.0);
  static const _kA = 118.0;
  static const _kB = 80.0;

  static final _rankAngles = <int, double>{
    1: math.pi / 2,
    2: math.pi - math.asin(0.25),
    3: math.asin(0.25),
  };

  @override
  void initState() {
    super.initState();
    _toProgress = (widget.currentUserValue / widget.totalGoal).clamp(0.0, 1.0);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: _toProgress,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progressController.duration = _motionDuration;
    if (!_hasInitialized) {
      _hasInitialized = true;
      _progressController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant TrackSideOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.currentUserValue / widget.totalGoal;
    if (target != _toProgress) {
      _updateProgress(target: target);
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _updateProgress({required double target}) {
    _fromProgress = _animatedProgressValue;
    _toProgress = target.clamp(0.0, 1.0);
    _progressController
      ..duration = _motionDuration
      ..forward(from: 0);
  }

  double get _animatedProgressValue {
    final t = _progressController.status == AnimationStatus.dismissed
        ? 0.0
        : Curves.easeOutCubic.transform(_progressController.value);
    return _fromProgress + (_toProgress - _fromProgress) * t;
  }

  Duration get _motionDuration {
    final disabled = MediaQuery.of(context).disableAnimations;
    return disabled ? Duration.zero : const Duration(milliseconds: 320);
  }

  double get _s => widget.scale;

  Offset _pointForParticipant(TrackSideOrbitParticipant p) {
    final theta = _rankAngles[p.rank] ?? math.pi / 2;
    return Offset(
      (_kCenter.dx + _kA * math.cos(theta)) * _s,
      (_kCenter.dy + _kB * math.sin(theta)) * _s,
    );
  }

  double _depthForParticipant(TrackSideOrbitParticipant p) {
    return ((math.sin(_rankAngles[p.rank] ?? math.pi / 2) + 1) / 2)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.participants]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final visible = sorted.take(3).toList();
    final reduced = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: _kOrbitWidth * _s,
      height: _kOrbitHeight * _s,
      child: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          final progress = _animatedProgressValue;
          final depthSorted = [...visible]
            ..sort(
              (a, b) =>
                  _depthForParticipant(a).compareTo(_depthForParticipant(b)),
            );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(_kOrbitWidth * _s, _kOrbitHeight * _s),
                painter: _OrbitPainter(
                  progress: progress,
                  scale: _s,
                ),
              ),
              for (final p in depthSorted)
                _OrbitMarker(
                  key: ValueKey(p.id),
                  participant: p,
                  point: _pointForParticipant(p),
                  depth: _depthForParticipant(p),
                  scale: _s,
                  selected: widget.selectedParticipantId == p.id,
                  reducedMotion: reduced,
                  onTap: () => widget.onParticipantTap?.call(p.id),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.scale,
  });

  final double progress;
  final double scale;

  static const _kCenter = Offset(173.0, 81.0);
  static const _kA = 173.0;
  static const _kB = 80.0;

  static const _startAngle = 2.05;
  static const _maxSweep = 3.75;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    final a = _kA * s;
    final b = _kB * s;
    final center = Offset(_kCenter.dx * s, _kCenter.dy * s);

    final rear = Paint()
      ..color = _kTrackGray.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * s
      ..isAntiAlias = true;

    // Five thin concentric rear ellipses for the Image A track density.
    for (var i = 4; i > 0; i--) {
      final ratio = 0.64 + i * 0.09;
      final rect = Rect.fromCenter(
        center: center,
        width: a * ratio * 2,
        height: b * ratio * 2,
      );
      canvas.drawOval(rect, rear);
    }

    final active = Paint()
      ..color = _kBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13.5 * s
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final outerRect = Rect.fromCenter(
      center: center,
      width: a * 2,
      height: b * 2,
    );

    final sweep = -_maxSweep * progress.clamp(0.0, 1.0);
    canvas.drawArc(outerRect, _startAngle, sweep, false, active);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scale != scale;
}

class _OrbitMarker extends StatefulWidget {
  const _OrbitMarker({
    super.key,
    required this.participant,
    required this.point,
    required this.depth,
    required this.scale,
    required this.selected,
    required this.reducedMotion,
    this.onTap,
  });

  final TrackSideOrbitParticipant participant;
  final Offset point;
  final double depth;
  final double scale;
  final bool selected;
  final bool reducedMotion;
  final VoidCallback? onTap;

  @override
  State<_OrbitMarker> createState() => _OrbitMarkerState();
}

class _OrbitMarkerState extends State<_OrbitMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectionController;

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.selected ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _OrbitMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selectionController
        ..duration = widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 250)
        ..animateTo(widget.selected ? 1 : 0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final isFirst = widget.participant.rank == 1;
    final portraitSize = (isFirst ? 39.0 : 33.0) * s;
    final badgeSize = 18.0 * s;
    final isUser = widget.participant.isCurrentUser;
    final ringColor = isUser ? _kBlue : _kWhite;

    return Positioned(
      left: widget.point.dx - 22.0 * s,
      top: widget.point.dy - 22.0 * s,
      child: AnimatedBuilder(
        animation: _selectionController,
        builder: (context, child) {
          final t = _selectionController.value;
          final targetScale = 1.0 + t * 0.06;

          return GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.translucent,
            child: SizedBox(
              width: 44.0 * s,
              height: 44.0 * s,
              child: Transform.scale(
                scale: targetScale,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    NuvoAvatar(
                      initials: widget.participant.initials,
                      photoUrl: widget.participant.photoUrl,
                      photoAsset: widget.participant.photoAsset,
                      size: portraitSize,
                      bgColor: nuvoAvatarColorFor(widget.participant.id),
                      textColor: _kWhite,
                      borderColor: ringColor,
                      borderWidth: isUser ? 3.0 * s : 2.0 * s,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -2.0 * s,
                      child: Center(
                        child: Container(
                          width: badgeSize,
                          height: badgeSize,
                          decoration: BoxDecoration(
                            color: isUser ? _kBlue : _kWhite,
                            shape: BoxShape.circle,
                            border: Border.all(color: _kNavy, width: 1.5 * s),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${widget.participant.rank}',
                            style: TextStyle(
                              fontSize: 9.0 * s,
                              fontWeight: FontWeight.w800,
                              color: isUser ? _kWhite : _kNavy,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
