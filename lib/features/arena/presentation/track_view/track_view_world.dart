import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'track_view_fixture.dart';
import 'track_view_geometry.dart';
import 'track_view_racer.dart';

class TrackViewWorld extends StatefulWidget {
  const TrackViewWorld({
    super.key,
    required this.race,
    required this.focusedParticipant,
    required this.onFocusParticipant,
  });

  final TrackViewRaceData race;
  final ValueNotifier<TrackViewParticipantData?> focusedParticipant;
  final ValueChanged<TrackViewParticipantData> onFocusParticipant;

  static const worldWidthMultiplier = 1.9;

  @override
  State<TrackViewWorld> createState() => _TrackViewWorldState();
}

class _TrackViewWorldState extends State<TrackViewWorld> {
  final ScrollController _scrollController = ScrollController();
  var _viewportWidth = 0.0;
  var _isProgrammaticScroll = false;

  double get _worldWidth =>
      _viewportWidth * TrackViewWorld.worldWidthMultiplier;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateFocusedParticipant);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrentUser());
  }

  @override
  void didUpdateWidget(covariant TrackViewWorld oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.race != widget.race) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrentUser());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateFocusedParticipant);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _currentUser;
    final currentProgress = TrackViewGeometry.normalizeProgress(
      completedAmount: currentUser.completedAmount,
      goal: widget.race.goal,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_viewportWidth != constraints.maxWidth) {
          _viewportWidth = constraints.maxWidth;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _centerCurrentUser(animate: false),
          );
        }

        return AnimatedBuilder(
          animation: _scrollController,
          builder: (context, _) {
            final viewportCenter =
                (_scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0) +
                constraints.maxWidth / 2;
            return SingleChildScrollView(
              key: const ValueKey('track-view-scrollable'),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: SizedBox(
                width: _worldWidth,
                height: constraints.maxHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _TrackDialPainter(
                            width: _worldWidth,
                            height: constraints.maxHeight,
                            completedProgress: currentProgress,
                            viewportCenter: viewportCenter,
                            viewportWidth: constraints.maxWidth,
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TrackViewParticipantData?>(
                      valueListenable: widget.focusedParticipant,
                      builder: (context, focused, _) {
                        final sorted = [...widget.race.participants]
                          ..sort((a, b) {
                            final aDepth = _depthForParticipant(a);
                            final bDepth = _depthForParticipant(b);
                            return aDepth.compareTo(bDepth);
                          });
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final participant in sorted)
                              _RacerPosition(
                                race: widget.race,
                                participant: participant,
                                width: _worldWidth,
                                height: constraints.maxHeight,
                                viewportCenter: viewportCenter,
                                viewportWidth: constraints.maxWidth,
                                isFocused: participant.id == focused?.id,
                                onTap: () {
                                  widget.onFocusParticipant(participant);
                                  _centerParticipant(participant);
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _centerCurrentUser({bool animate = true}) {
    _centerParticipant(_currentUser, animate: animate);
  }

  void _centerParticipant(
    TrackViewParticipantData participant, {
    bool animate = true,
  }) {
    if (!_scrollController.hasClients || _viewportWidth <= 0) return;
    final progress = TrackViewGeometry.normalizeProgress(
      completedAmount: participant.completedAmount,
      goal: widget.race.goal,
    );
    final x = TrackViewGeometry.worldXForProgress(
      normalizedProgress: progress,
      worldWidth: _worldWidth,
    );
    final target = (x - _viewportWidth / 2).clamp(
      0.0,
      (_worldWidth - _viewportWidth).clamp(0.0, double.infinity),
    );
    if (animate) {
      _isProgrammaticScroll = true;
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) _isProgrammaticScroll = false;
          });
    } else {
      _isProgrammaticScroll = true;
      _scrollController.jumpTo(target);
      _isProgrammaticScroll = false;
    }
  }

  void _updateFocusedParticipant() {
    if (_isProgrammaticScroll ||
        !_scrollController.hasClients ||
        _viewportWidth <= 0) {
      return;
    }
    final center = _scrollController.offset + _viewportWidth / 2;
    TrackViewParticipantData? nearest;
    var nearestDistance = double.infinity;
    for (final participant in widget.race.participants) {
      final progress = TrackViewGeometry.normalizeProgress(
        completedAmount: participant.completedAmount,
        goal: widget.race.goal,
      );
      final x = TrackViewGeometry.worldXForProgress(
        normalizedProgress: progress,
        worldWidth: _worldWidth,
      );
      final distance = (x - center).abs();
      if (distance < nearestDistance) {
        nearest = participant;
        nearestDistance = distance;
      }
    }
    if (nearest != null) {
      widget.onFocusParticipant(nearest);
    }
  }

  TrackViewParticipantData get _currentUser =>
      widget.race.participants.firstWhere(
        (participant) =>
            participant.isCurrentUser ||
            participant.id == widget.race.currentUserId,
      );

  double _depthForParticipant(TrackViewParticipantData participant) {
    final progress = TrackViewGeometry.normalizeProgress(
      completedAmount: participant.completedAmount,
      goal: widget.race.goal,
    );
    return math.sin(progress * math.pi);
  }
}

class _RacerPosition extends StatelessWidget {
  const _RacerPosition({
    required this.race,
    required this.participant,
    required this.width,
    required this.height,
    required this.viewportCenter,
    required this.viewportWidth,
    required this.isFocused,
    required this.onTap,
  });

  final TrackViewRaceData race;
  final TrackViewParticipantData participant;
  final double width;
  final double height;
  final double viewportCenter;
  final double viewportWidth;
  final bool isFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = TrackViewGeometry.normalizeProgress(
      completedAmount: participant.completedAmount,
      goal: race.goal,
    );
    final rank =
        race.participants
            .where(
              (candidate) =>
                  candidate.completedAmount > participant.completedAmount,
            )
            .length +
        1;
    final markerSize = isFocused ? 56.0 : 44.0;
    final x = TrackViewGeometry.worldXForProgress(
      normalizedProgress: progress,
      worldWidth: width,
    );
    final y = TrackViewGeometry.worldYForProgress(
      normalizedProgress: progress,
      availableHeight: height,
    );
    final trackDepth = math.sin(progress * math.pi).clamp(0.0, 1.0);
    final distanceFromCenter = ((x - viewportCenter).abs() / viewportWidth)
        .clamp(0.0, 1.0);
    final centerLift = 1 - distanceFromCenter;
    final depth = (trackDepth * 0.72 + centerLift * 0.28).clamp(0.0, 1.0);
    final visualScale = (0.72 + depth * 0.45) * (isFocused ? 1.06 : 1.0);
    final yLift = -depth * 10;

    return Positioned(
      left: x - markerSize / 2,
      top: y - markerSize / 2 + yLift,
      child: Transform.scale(
        scale: visualScale,
        child: TrackViewRacer(
          participant: participant,
          rank: rank,
          isFocused: isFocused,
          depth: depth,
          isCurrentUser:
              participant.isCurrentUser || participant.id == race.currentUserId,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TrackDialPainter extends CustomPainter {
  const _TrackDialPainter({
    required this.width,
    required this.height,
    required this.completedProgress,
    required this.viewportCenter,
    required this.viewportWidth,
  });

  final double width;
  final double height;
  final double completedProgress;
  final double viewportCenter;
  final double viewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = _trackOvalRect();
    final arcBounds = Rect.fromLTWH(
      viewportCenter - viewportWidth * 0.52,
      0,
      viewportWidth * 1.04,
      height,
    );
    final guidePaint = Paint()
      ..color = const Color(0x304E6685)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..isAntiAlias = true;
    final shadowPaint = Paint()
      ..color = const Color(0x95000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 48
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
      ..isAntiAlias = true;
    final underRimPaint = Paint()
      ..color = const Color(0xFF102744)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 44
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final trackPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF152B49), Color(0xFF315075), Color(0xFF1B3557)],
      ).createShader(arcBounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 32
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1E64F7), Color(0xFF55A2FF), Color(0xFF2F7DFF)],
      ).createShader(arcBounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 32
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final highlightPaint = Paint()
      ..color = const Color(0x8BBBD8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var index = 0; index < 5; index++) {
      canvas.drawOval(ovalRect.deflate(index * 16.0), guidePaint);
    }

    canvas.save();
    canvas.translate(0, 22);
    canvas.drawPath(_arcPath(0, 1), shadowPaint);
    canvas.restore();
    canvas.save();
    canvas.translate(0, 12);
    canvas.drawPath(_arcPath(0, 1), underRimPaint);
    canvas.restore();
    canvas.drawPath(_arcPath(0, 1), trackPaint);
    canvas.drawPath(_arcPath(0, completedProgress), progressPaint);
    canvas.save();
    canvas.translate(0, -8);
    canvas.drawPath(
      _arcPath(0.04, completedProgress.clamp(0.04, 0.96)),
      highlightPaint,
    );
    canvas.restore();
  }

  Rect _trackOvalRect() {
    final edgePadding = TrackViewGeometry.horizontalEdgePadding(
      worldWidth: width,
    );
    final centerY = height * 0.16;
    final radiusY = height * 0.68;
    return Rect.fromLTRB(
      edgePadding,
      centerY - radiusY,
      width - edgePadding,
      centerY + radiusY,
    );
  }

  Path _arcPath(double start, double end) {
    final path = Path();
    const samples = 120;
    for (var index = 0; index <= samples; index++) {
      final progress = start + (end - start) * index / samples;
      final x = TrackViewGeometry.worldXForProgress(
        normalizedProgress: progress,
        worldWidth: width,
      );
      final y = TrackViewGeometry.worldYForProgress(
        normalizedProgress: progress,
        availableHeight: height,
      );
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _TrackDialPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height ||
        oldDelegate.completedProgress != completedProgress;
  }
}
