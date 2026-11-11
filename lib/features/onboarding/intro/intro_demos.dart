import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';

/// The five intro demos. Each is ONE purposeful, flat animation that shows
/// the thing the page says. They draw straight on the page's color field (no
/// card, no shadow, no tilt) and play ONCE over [t] in 0..1, then hold the
/// final frame. With reduce-motion the page passes t = 1.
class IntroDemo extends StatelessWidget {
  const IntroDemo({super.key, required this.kind, required this.t});

  final int kind;
  final double t;

  @override
  Widget build(BuildContext context) {
    if (kind == 1) return _RepDemo(t: t);
    return RepaintBoundary(
      child: CustomPaint(
        painter: switch (kind) {
          0 => _RacePainter(t),
          2 => _BoardPainter(t),
          3 => _CrewPainter(t),
          _ => _LevelPainter(t),
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

Paint get _stroke => Paint()
  ..color = V13.navy
  ..style = PaintingStyle.stroke
  ..strokeWidth = 3
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// Soft ease with a little overshoot (the app's spring).
double _ease(double x) => NuvoMotion.spring.transform(x.clamp(0.0, 1.0));

/// Gentle ease-out for counters (no overshoot: numbers never overshoot).
double _out(double x) {
  final v = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - v, 3).toDouble();
}

TextPainter _tp(String s, double size, Color color, {double? maxWidth}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: V13.title.copyWith(fontSize: size, color: color, height: 1),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  return tp;
}

void _textAt(
  Canvas c,
  String s,
  Offset center, {
  double size = 22,
  Color color = V13.navy,
}) {
  final tp = _tp(s, size, color);
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// 1 — three racers run the lane; YOU (blue ring) wins.
class _RacePainter extends CustomPainter {
  _RacePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    const speeds = [0.84, 1.0, 0.68];
    final laneH = math.min(60.0, s.height / 4.0);
    final top = (s.height - laneH * 3) / 2;
    final x0 = 30.0;
    final x1 = s.width - 70.0;
    final run = _out((t - 0.05) / 0.85);
    for (var i = 0; i < 3; i++) {
      final y = top + laneH * i + laneH / 2;
      final enter = _ease((t - i * 0.06) / 0.25); // lanes ease in, staggered
      final lane = _stroke..strokeWidth = 2.5;
      c.drawLine(Offset(x0, y), Offset(x0 + (x1 + 12 - x0) * enter, y), lane);
      // finish flag
      if (enter > 0.6) {
        final fx = x1 + 26;
        c.drawLine(Offset(fx, y + 14), Offset(fx, y - 18), _stroke);
        for (var r = 0; r < 2; r++) {
          for (var k = 0; k < 2; k++) {
            c.drawRect(
              Rect.fromLTWH(fx + 1 + k * 7, y - 18 + r * 7, 7, 7),
              Paint()..color = (r + k).isEven ? V13.navy : V13.white,
            );
          }
        }
      }
      final p = (run * speeds[i]).clamp(0.0, 1.0);
      final x = x0 + (x1 - x0) * p;
      final you = i == 1;
      final r = 18.0 * enter;
      c.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = you ? V13.blue : V13.white,
      );
      c.drawCircle(Offset(x, y), r, _stroke);
      if (you && enter > 0.8) {
        _textAt(c, 'YOU', Offset(x, y), size: 9, color: V13.white);
      }
    }
  }

  @override
  bool shouldRepaint(_RacePainter o) => o.t != t;
}

/// 2 — the app's own jumping-jack figure (the AI Motion preview rig) with a
/// rep counter that counts to 3 once and the AI-verified tag.
class _RepDemo extends StatelessWidget {
  const _RepDemo({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final count = (_out((t - 0.1) / 0.7) * 3).round().clamp(0, 3);
    final verified = _ease((t - 0.82) / 0.18);
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxHeight, c.maxWidth * 0.62);
        return Row(
          children: [
            SizedBox.square(
              dimension: side,
              child: RiveJumpingJackPreview(
                fallback: Icon(
                  Icons.accessibility_new_rounded,
                  size: side * .5,
                  color: V13.navy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$count',
                      style: V13.hugeNumber.copyWith(
                        fontSize: math.min(96, c.maxHeight * 0.5),
                        color: V13.navy,
                        height: 1,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: verified.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - verified.clamp(0.0, 1.0))),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: V13.white,
                            borderRadius: BorderRadius.circular(V13.radiusPill),
                            border: Border.all(
                              color: V13.navy,
                              width: V13.outline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: V13.blue,
                              ),
                              const SizedBox(width: 6),
                              Text('AI verified', style: V13.caption),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 3 — a real leaderboard: rank, avatar, name, score. The highlighted row is
/// the player ("You", blue, with a person avatar); it climbs from 3rd to 1st
/// as its score counts up, the rows it passes slide down.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final rowH = math.min(58.0, s.height / 3.4);
    final w = s.width - 8;
    final x0 = 4.0;
    final climb = _ease((t - 0.3) / 0.45);
    final count = _out((t - 0.3) / 0.45);
    const names = ['Maya', 'Leo', 'You'];
    const base = [68.0, 54.0, 24.0];
    // slot (0 = top): the player 2 -> 0; the two above shift down by one.
    double slot(int i) => i == 2 ? 2 - 2 * climb : i + climb;
    final top = (s.height - rowH * 3) / 2;
    // Draw the player last so it passes OVER the others.
    for (final i in [0, 1, 2]) {
      final enter = _ease((t - i * 0.08) / 0.3);
      if (enter <= 0) continue;
      final y = top + slot(i) * rowH + (1 - enter) * 24;
      final you = i == 2;
      final score = base[i] + (you ? 52 * count : 0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, y + 4, w, rowH - 8),
        const Radius.circular(16),
      );
      c.saveLayer(
        rect.outerRect.inflate(4),
        Paint()..color = Color.fromRGBO(0, 0, 0, enter.clamp(0.0, 1.0)),
      );
      c.drawRRect(rect, Paint()..color = you ? V13.blue : V13.white);
      c.drawRRect(rect, _stroke..strokeWidth = 2.5);
      final fg = you ? V13.white : V13.navy;
      final cy = y + rowH / 2;
      // rank
      final rank = (slot(i) + 0.5).floor() + 1;
      _textAt(c, '$rank', Offset(x0 + 24, cy), size: 17, color: fg);
      // avatar
      final av = Offset(x0 + 62, cy);
      c.drawCircle(av, 17, Paint()..color = you ? V13.white : V13.sky);
      c.drawCircle(av, 17, _stroke..strokeWidth = 2.5);
      if (you) {
        final head = Paint()..color = V13.blue;
        c.drawCircle(av.translate(0, -4), 5, head);
        c.drawArc(
          Rect.fromCenter(center: av.translate(0, 11), width: 18, height: 16),
          math.pi,
          math.pi,
          true,
          head,
        );
      } else {
        _textAt(c, names[i][0], av, size: 15, color: V13.navy);
      }
      // name
      final name = _tp(names[i], 18, fg);
      name.paint(c, Offset(x0 + 92, cy - name.height / 2));
      // score
      final sc = _tp(score.round().toString(), 20, fg);
      sc.paint(c, Offset(x0 + w - 20 - sc.width, cy - sc.height / 2));
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_BoardPainter o) => o.t != t;
}

/// 4 — your crew joins one by one.
class _CrewPainter extends CustomPainter {
  _CrewPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    const labels = ['A', 'M', 'L', 'S'];
    const colors = [V13.coral, V13.sun, V13.mint, V13.white];
    final r = math.min(s.width * 0.34, s.height * 0.34);
    final face = math.min(26.0, r * 0.42);
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2 + math.pi / 4;
      final pos = center + Offset(math.cos(a), math.sin(a)) * r;
      final p = _ease((t - 0.15 - i * 0.14) / 0.32);
      if (p <= 0) continue;
      final end = Offset.lerp(center, pos, p.clamp(0.0, 1.2))!;
      c.drawLine(center, end, _stroke..strokeWidth = 2);
      c.drawCircle(end, face * p, Paint()..color = colors[i]);
      c.drawCircle(end, face * p, _stroke..strokeWidth = 3);
      if (p > 0.6) _textAt(c, labels[i], end, size: face * 0.8);
    }
    final core = _ease(t / 0.2);
    c.drawCircle(center, 32 * core, Paint()..color = V13.blue);
    c.drawCircle(center, 32 * core, _stroke..strokeWidth = 3);
    if (core > 0.7) _textAt(c, 'You', center, size: 15, color: V13.white);
  }

  @override
  bool shouldRepaint(_CrewPainter o) => o.t != t;
}

/// 5 — XP fills, the number counts up, LEVEL 1 becomes LEVEL 2 with a soft
/// overshoot.
class _LevelPainter extends CustomPainter {
  _LevelPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final fill = _out((t - 0.12) / 0.55);
    final level2 = fill >= 0.995;
    final barW = s.width - 8;
    final barY = s.height * 0.64;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, barY, barW, 30),
      const Radius.circular(15),
    );
    c.drawRRect(bar, Paint()..color = V13.white);
    c.save();
    c.clipRRect(bar);
    c.drawRect(
      Rect.fromLTWH(4, barY, barW * fill, 30),
      Paint()..color = V13.blue,
    );
    c.restore();
    c.drawRRect(bar, _stroke..strokeWidth = 3);
    final pop = level2
        ? 1 +
              0.16 *
                  _ease((t - 0.72) / 0.28) *
                  (1 - _out((t - 0.72) / 0.28)) *
                  3
        : 1.0;
    _textAt(
      c,
      level2 ? 'LEVEL 2' : 'LEVEL 1',
      Offset(s.width / 2, s.height * 0.32),
      size: math.min(58.0, s.width * 0.16) * pop,
    );
    _textAt(
      c,
      '+${(100 * fill).round()} XP',
      Offset(s.width / 2, barY + 62),
      size: 20,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.t != t;
}

/// Soft, flat background shapes that drift slowly behind the pages (depth
/// without shadows): overlapping translucent circles, parallaxed by the page
/// position and the slow [drift] phase.
class CloudsPainter extends CustomPainter {
  CloudsPainter({required this.pos, required this.drift});

  final double pos;
  final double drift; // 0..1 loop

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = V13.white.withValues(alpha: 0.28);
    void cloud(double bx, double by, double scale, double depth) {
      final dx =
          bx * s.width -
          pos * 70 * depth +
          math.sin(drift * 2 * math.pi + bx * 9) * 14 * depth;
      final dy =
          by * s.height + math.cos(drift * 2 * math.pi + by * 7) * 6 * depth;
      final r = 34 * scale;
      for (final o in const [
        Offset(0, 0),
        Offset(1.1, -0.35),
        Offset(2.2, 0),
        Offset(1.1, 0.35),
      ]) {
        canvas.drawCircle(Offset(dx + o.dx * r, dy + o.dy * r), r, paint);
      }
    }

    cloud(0.08, 0.14, 1.0, 1.0);
    cloud(0.62, 0.3, 0.7, 0.6);
    cloud(0.2, 0.55, 1.3, 1.4);
    cloud(0.78, 0.68, 0.9, 0.9);
  }

  @override
  bool shouldRepaint(CloudsPainter o) => o.pos != pos || o.drift != drift;
}
