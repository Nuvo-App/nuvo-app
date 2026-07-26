import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
  late final AnimationController _rotationController;
  double _fromProgress = 0;
  double _toProgress = 0;
  double _rotation = 0;
  bool _hasInitialized = false;

  static const _baselineOrbitWidth = 500.0;
  static const _baselineOrbitHeight = 190.0;

  static const _rankAngles = <int, double>{
    1: math.pi / 2,
    2: math.pi * 0.84,
    3: math.pi * 0.16,
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
    _rotationController = AnimationController.unbounded(vsync: this)
      ..value = _rotation
      ..addListener(() {
        setState(() => _rotation = _rotationController.value);
      });
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
    _rotationController.dispose();
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
    const center = Offset(_baselineOrbitWidth / 2, 64);
    final angle = (_rankAngles[p.rank] ?? math.pi / 2) + _rotation;
    final rx = _baselineOrbitWidth * 0.47;
    final ry = _baselineOrbitHeight * 0.42;
    return Offset(
          center.dx + math.cos(angle) * rx,
          center.dy + math.sin(angle) * ry,
        ) *
        _s;
  }

  double _depthForParticipant(TrackSideOrbitParticipant p) {
    final angle = (_rankAngles[p.rank] ?? math.pi / 2) + _rotation;
    return ((math.sin(angle) + 1) / 2).clamp(0.0, 1.0);
  }

  void _startRotate(DragStartDetails details) {
    _rotationController.stop();
  }

  void _rotate(DragUpdateDetails details) {
    final delta = details.primaryDelta;
    if (delta == null) return;
    _rotationController.value = _rotation - delta / (260 * _s);
  }

  void _endRotate(DragEndDetails details) {
    if (MediaQuery.of(context).disableAnimations) return;
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < 80) return;
    final angularVelocity = -velocity / (760 * _s);
    _rotationController.animateWith(
      FrictionSimulation(1.1, _rotation, angularVelocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.participants]
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final visible = sorted.take(3).toList();
    final orbitWidth = _baselineOrbitWidth * _s;
    final orbitHeight = _baselineOrbitHeight * _s;
    final reduced = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _startRotate,
      onHorizontalDragUpdate: _rotate,
      onHorizontalDragEnd: _endRotate,
      child: SizedBox(
        width: orbitWidth,
        height: orbitHeight + 38 * _s,
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
                  size: Size(orbitWidth, orbitHeight),
                  painter: _OrbitPainter(
                    progress: progress,
                    scale: _s,
                    rotation: _rotation,
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
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.progress,
    required this.scale,
    required this.rotation,
  });

  final double progress;
  final double scale;
  final double rotation;

  static const _baselineA = 235.0;
  static const _baselineB = 80.0;
  static const _baselineCX = 250.0;
  static const _baselineCY = 64.0;

  static const _startAngle = 2.72;
  static const _maxSweep = 4.58;

  @override
  void paint(Canvas canvas, Size size) {
    final a = _baselineA * scale;
    final b = _baselineB * scale;
    final center = Offset(_baselineCX * scale, _baselineCY * scale);

    final rear = Paint()
      ..color = _kTrackGray.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 * scale
      ..isAntiAlias = true;

    // Three concentric rear ellipses.
    for (var i = 3; i > 0; i--) {
      final ratio = 0.58 + i * 0.12;
      final rect = Rect.fromCenter(
        center: center,
        width: a * ratio * 2,
        height: b * ratio * 2,
      );
      canvas.drawOval(rect, rear);
    }

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * scale
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale)
      ..isAntiAlias = true;

    final rim = Paint()
      ..color = const Color(0xFF10294A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final active = Paint()
      ..color = _kBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13 * scale
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final outerRect = Rect.fromCenter(
      center: center,
      width: a * 2,
      height: b * 2,
    );

    final start = _startAngle + rotation;
    canvas.save();
    canvas.translate(0, 9 * scale);
    canvas.drawArc(outerRect, start, -_maxSweep, false, shadow);
    canvas.restore();
    canvas.drawArc(outerRect, start, -_maxSweep, false, rim);
    if (progress <= 0) return;
    canvas.drawArc(outerRect, start, -_maxSweep * progress, false, active);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.scale != scale ||
      oldDelegate.rotation != rotation;
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
    final baseSize = widget.participant.rank == 1 ? 34.0 : 29.0;
    final portraitSize = (baseSize + 10 * widget.depth) * s;
    final isUser = widget.participant.isCurrentUser;

    return AnimatedPositioned(
      duration: widget.reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: widget.point.dx - portraitSize / 2,
      top: widget.point.dy - portraitSize / 2,
      child: AnimatedBuilder(
        animation: _selectionController,
        builder: (context, child) {
          final t = _selectionController.value;
          final scale = 0.88 + widget.depth * 0.16 + t * 0.06;
          final ringColor = isUser ? _kBlue : _kWhite;
          final ringWidth = isUser ? 3.0 * s : 2.0 * s;

          return GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.translucent,
            child: SizedBox(
              width: math.max(44.0, portraitSize + 8 * s),
              height: math.max(44.0, portraitSize + 8 * s),
              child: Transform.scale(
                scale: scale,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: portraitSize + 4 * s,
                      height: portraitSize + 4 * s,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.14 + 0.18 * widget.depth,
                            ),
                            blurRadius: (7 + 8 * widget.depth) * s,
                            offset: Offset(0, (4 + 5 * widget.depth) * s),
                          ),
                          if (t > 0.01)
                            BoxShadow(
                              color: _kBlue.withValues(alpha: 0.45 * t),
                              blurRadius: 12 * s,
                              spreadRadius: 2 * s,
                            ),
                        ],
                      ),
                    ),
                    NuvoAvatar(
                      initials: widget.participant.initials,
                      photoUrl: widget.participant.photoUrl,
                      photoAsset: widget.participant.photoAsset,
                      size: portraitSize,
                      bgColor: nuvoAvatarColorFor(widget.participant.id),
                      textColor: _kWhite,
                      borderColor: ringColor,
                      borderWidth: ringWidth,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -5 * s,
                      child: Center(
                        child: Container(
                          width: 18 * s,
                          height: 18 * s,
                          decoration: BoxDecoration(
                            color: isUser ? _kBlue : _kWhite,
                            shape: BoxShape.circle,
                            border: Border.all(color: _kNavy, width: 1.5 * s),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${widget.participant.rank}',
                            style: TextStyle(
                              fontSize: 9 * s,
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
