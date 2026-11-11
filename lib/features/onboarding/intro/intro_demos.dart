import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';

/// The five intro demos. Each is ONE purposeful, flat animation that shows
/// the thing the page says — nothing decorative. They draw straight on the
/// page's color field (no card, no shadow, no tilt) and loop on [t] in 0..1.
/// With reduce-motion the page passes the finished frame (t = 1).
class IntroDemo extends StatelessWidget {
  const IntroDemo({super.key, required this.kind, required this.t});

  final int kind;
  final double t;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: switch (kind) {
          0 => _RacePainter(t),
          1 => _RepPainter(t),
          2 => _BoardPainter(t),
          3 => _CrewPainter(t),
          _ => _LevelPainter(t),
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

final _stroke = Paint()
  ..color = V13.navy
  ..style = PaintingStyle.stroke
  ..strokeWidth = 3
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

double _ease(double x) => NuvoMotion.spring.transform(x.clamp(0.0, 1.0));

void _text(
  Canvas c,
  String s,
  Offset at, {
  double size = 22,
  Color color = V13.navy,
  bool center = true,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: V13.title.copyWith(fontSize: size, color: color, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
}

/// 1 — three racers run the lane; YOU (blue) wins.
class _RacePainter extends CustomPainter {
  _RacePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    const speeds = [0.86, 1.0, 0.7];
    final laneH = math.min(54.0, s.height / 4.2);
    final top = (s.height - laneH * 3) / 2;
    final x0 = 28.0, x1 = s.width - 56.0;
    for (var i = 0; i < 3; i++) {
      final y = top + laneH * i + laneH / 2;
      canvas(c, y, x0, x1, s.width);
      final p = ((t * 1.15) * speeds[i]).clamp(0.0, 1.0);
      final x = x0 + (x1 - x0) * p;
      final you = i == 1;
      c.drawCircle(
        Offset(x, y),
        17,
        Paint()..color = you ? V13.blue : V13.white,
      );
      c.drawCircle(Offset(x, y), 17, _stroke);
      if (you) _text(c, 'YOU', Offset(x, y), size: 9, color: V13.white);
    }
  }

  void canvas(Canvas c, double y, double x0, double x1, double w) {
    c.drawLine(Offset(x0, y), Offset(x1 + 14, y), _stroke..strokeWidth = 2);
    _stroke.strokeWidth = 3;
    // checkered flag
    final fx = x1 + 22;
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

  @override
  bool shouldRepaint(_RacePainter o) => o.t != t;
}

/// 2 — a stick figure squats, the counter ticks 1-2-3 on each bottom.
class _RepPainter extends CustomPainter {
  _RepPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width * 0.36;
    final floorY = s.height * 0.82;
    final reps = (t * 3).floor().clamp(0, 2);
    final phase = (t * 3) % 1.0; // 0..1 within a rep
    final depth = math.sin(phase * math.pi); // 0 standing .. 1 bottom
    final hip = Offset(cx - 24 * depth, floorY - 94 + 42 * depth);
    final knee = Offset(cx + 28 * depth, floorY - 47 + 4 * depth);
    final foot = Offset(cx, floorY);
    final shoulder = hip.translate(14 * depth, -58 + 6 * depth);
    final head = shoulder.translate(4 * depth, -24);
    c.drawLine(Offset(cx - 40, floorY), Offset(cx + 70, floorY), _stroke);
    c.drawLine(foot, knee, _stroke);
    c.drawLine(knee, hip, _stroke);
    c.drawLine(hip, shoulder, _stroke);
    c.drawLine(shoulder, shoulder.translate(34 * depth, 8 * depth), _stroke);
    c.drawCircle(head, 13, Paint()..color = V13.white);
    c.drawCircle(head, 13, _stroke);
    final shown = (phase > 0.5 ? reps + 1 : reps).clamp(0, 3);
    final pop = phase > 0.5
        ? 1 + 0.25 * math.sin((phase - 0.5) * 2 * math.pi)
        : 1.0;
    _text(c, '$shown', Offset(s.width * 0.74, s.height * 0.46), size: 84 * pop);
    if (t > 0.92) {
      _text(c, 'VERIFIED', Offset(s.width * 0.74, s.height * 0.72), size: 16);
    }
  }

  @override
  bool shouldRepaint(_RepPainter o) => o.t != t;
}

/// 3 — YOU climb from 3rd to 1st.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final rowH = math.min(52.0, s.height / 4);
    final w = s.width - 56;
    const names = ['Maya', 'Leo', 'YOU'];
    const scores = [68.0, 54.0, 24.0];
    final climb = _ease((t - 0.15) / 0.55);
    // YOU rank position 2 -> 0; the others shift down.
    double slot(int i) {
      if (i == 2) return 2 - 2 * climb;
      return i + climb * (i < 2 ? 1 : 0);
    }

    final top = (s.height - rowH * 3) / 2;
    for (var i = 0; i < 3; i++) {
      final y = top + slot(i) * rowH;
      final you = i == 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(28, y + 4, w, rowH - 8),
        const Radius.circular(14),
      );
      c.drawRRect(rect, Paint()..color = you ? V13.blue : V13.white);
      c.drawRRect(rect, _stroke..strokeWidth = 2.5);
      _stroke.strokeWidth = 3;
      final score = scores[i] + (you ? 50 * climb : 0);
      _text(
        c,
        names[i],
        Offset(52, y + rowH / 2),
        size: 18,
        color: you ? V13.white : V13.navy,
        center: false,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: score.round().toString(),
          style: V13.title.copyWith(
            fontSize: 18,
            color: you ? V13.white : V13.navy,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(28 + w - 18 - tp.width, y + rowH / 2 - tp.height / 2));
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
    final r = math.min(s.width, s.height) * 0.34;
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2 + math.pi / 4;
      final pos = center + Offset(math.cos(a), math.sin(a)) * r;
      final p = _ease((t - 0.12 - i * 0.16) / 0.3);
      if (p <= 0) continue;
      final end = Offset.lerp(center, pos, p)!;
      c.drawLine(center, end, _stroke..strokeWidth = 2);
      _stroke.strokeWidth = 3;
      c.drawCircle(end, 26 * p, Paint()..color = colors[i]);
      c.drawCircle(end, 26 * p, _stroke);
      if (p > 0.6) _text(c, labels[i], end, size: 20);
    }
    c.drawCircle(center, 32, Paint()..color = V13.blue);
    c.drawCircle(center, 32, _stroke);
    _text(c, 'YOU', center, size: 14, color: V13.white);
  }

  @override
  bool shouldRepaint(_CrewPainter o) => o.t != t;
}

/// 5 — XP fills, LEVEL 1 becomes LEVEL 2.
class _LevelPainter extends CustomPainter {
  _LevelPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final fill = ((t - 0.1) / 0.6).clamp(0.0, 1.0);
    final level2 = fill >= 1.0;
    final barW = s.width - 80;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(40, s.height * 0.62, barW, 28),
      const Radius.circular(14),
    );
    c.drawRRect(bar, Paint()..color = V13.white);
    c.save();
    c.clipRRect(bar);
    c.drawRect(
      Rect.fromLTWH(40, s.height * 0.62, barW * fill, 28),
      Paint()..color = V13.blue,
    );
    c.restore();
    c.drawRRect(bar, _stroke);
    final pop = level2
        ? 1 + 0.18 * math.sin(((t - 0.7) / 0.2).clamp(0.0, 1.0) * math.pi)
        : 1.0;
    _text(
      c,
      level2 ? 'LEVEL 2' : 'LEVEL 1',
      Offset(s.width / 2, s.height * 0.34),
      size: 54 * pop,
    );
    _text(
      c,
      '+${(100 * fill).round()} XP',
      Offset(s.width / 2, s.height * 0.82),
      size: 20,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.t != t;
}
