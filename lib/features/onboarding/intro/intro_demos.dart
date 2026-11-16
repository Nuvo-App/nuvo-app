import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';

// The five intro scenes (see docs/redesign/onboarding-v2-motion-brief.md).
//
// Every scene is a FULL-SCREEN layer drawn edge to edge under the text and
// the CTA: no clip, no inner demo box. The page's hero lives in [stage] (the
// zone between the header and the title block, with >= 20px margins); effects
// (ring waves, confetti, flashes) are drawn in screen space and fade out
// before they would ever need cropping. Each page tells one idea with the
// same shape — anticipation (a slow-down, a held beat), a CLIMAX (burst, ring
// waves, camera push, strong haptic) and a settle — and plays ONCE over t in
// 0..1, then holds its final frame. Flat fills only.

/// Climax time (fraction of the play) per page.
const introClimax = [0.88, 0.86, 0.78, 0.64, 0.82];

/// (t, kind) haptic marks per page — 'tick' | 'thud' | 'burst' | 'success'.
const introHapticMarks = <List<(double, String)>>[
  // 1 race: launch ticks, the held breath as the crawl begins, ticks while
  // it crawls, the finish
  [
    (0.20, 'tick'),
    (0.32, 'tick'),
    (0.42, 'tick'),
    (0.52, 'thud'),
    (0.66, 'tick'),
    (0.76, 'tick'),
    (0.88, 'burst'),
  ],
  // 2 reps
  [
    (0.26, 'tick'),
    (0.42, 'tick'),
    (0.52, 'thud'),
    (0.70, 'tick'),
    (0.86, 'burst'),
  ],
  // 3 board: four overtakes then the top
  [
    (0.36, 'tick'),
    (0.48, 'tick'),
    (0.60, 'tick'),
    (0.70, 'thud'),
    (0.78, 'burst'),
  ],
  // 4 crew: a tick per arrival (escalating), the payoff
  [
    (0.12, 'tick'),
    (0.24, 'tick'),
    (0.34, 'tick'),
    (0.42, 'tick'),
    (0.49, 'tick'),
    (0.55, 'tick'),
    (0.64, 'burst'),
  ],
  // 5 level: slow ticks up the ring, the held breath, the break
  [
    (0.18, 'tick'),
    (0.30, 'tick'),
    (0.42, 'tick'),
    (0.54, 'tick'),
    (0.66, 'tick'),
    (0.74, 'tick'),
    (0.78, 'thud'),
    (0.82, 'success'),
  ],
];

/// One scene. Fills its parent; [stage] is where the hero is laid out.
class IntroDemo extends StatelessWidget {
  const IntroDemo({
    super.key,
    required this.kind,
    required this.t,
    required this.stage,
  });

  final int kind;
  final double t;
  final Rect stage;

  @override
  Widget build(BuildContext context) {
    if (kind == 1) return _JackScene(t: t, stage: stage);
    return RepaintBoundary(
      child: CustomPaint(
        painter: switch (kind) {
          0 => _RaceScene(t, stage),
          2 => _BoardScene(t, stage),
          3 => _CrewScene(t, stage),
          _ => _LevelScene(t, stage),
        },
        size: Size.infinite,
      ),
    );
  }
}

// ── shared helpers ─────────────────────────────────────────────────────

Paint _line(double w, [Color c = V13.navy]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fill(Color c) => Paint()..color = c;

/// The app's spring (a little overshoot): pops and slams.
double _pop(double x) => NuvoMotion.spring.transform(x.clamp(0.0, 1.0));

/// Almost no overshoot: travel and climbs.
double _soft(double x) => NuvoMotion.softSpring.transform(x.clamp(0.0, 1.0));

double _out(double x) {
  final v = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - v, 3).toDouble();
}

double _inOut(double x) {
  final v = x.clamp(0.0, 1.0);
  return v < 0.5 ? 4 * v * v * v : 1 - math.pow(-2 * v + 2, 3).toDouble() / 2;
}

double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// 0 -> 1 -> 0 over x in [0,1]; 0 outside.
double _bump(double x) => (x <= 0 || x >= 1) ? 0 : math.sin(x * math.pi);

/// Burst progress delayed by [d] that still ends exactly at 1.
double _stag(double bt, double d) => (bt - d) / (1 - d);

TextPainter _tp(String s, double size, Color color) => TextPainter(
  text: TextSpan(
    text: s,
    style: V13.title.copyWith(fontSize: size, color: color, height: 1),
  ),
  textDirection: TextDirection.ltr,
)..layout();

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

const _confettiColors = [
  V13.navy,
  V13.white,
  V13.sun,
  V13.coral,
  V13.blue,
  V13.mint,
];

/// A ring wave that expands and fades; it always vanishes before bt == 1.
void _wave(
  Canvas c,
  Offset at,
  double bt, {
  double from = 10,
  required double to,
  double width = 6,
  Color color = V13.navy,
}) {
  if (bt <= 0 || bt >= 1) return;
  final e = _out(bt);
  c.drawCircle(
    at,
    from + (to - from) * e,
    _line(width * (1 - bt) + 1, color.withValues(alpha: (1 - bt) * (1 - bt))),
  );
}

/// Flat confetti that bursts out of [origin] and FALLS across the screen
/// (gravity), fading well before it reaches the bottom — nothing is ever
/// cropped mid-shape by a container.
void _confettiFall(
  Canvas c,
  Offset origin,
  double bt,
  Size screen, {
  int count = 34,
  double spread = 1.0,
}) {
  if (bt <= 0 || bt >= 1) return;
  final tau = bt * 1.6;
  final paint = Paint();
  for (var i = 0; i < count; i++) {
    final r1 = ((i * 53) % 97) / 97.0;
    final r2 = ((i * 31) % 89) / 89.0;
    final a = -math.pi / 2 + (r1 - 0.5) * math.pi * 1.5 * spread;
    final speed = 260 + 360 * r2;
    final x = origin.dx + math.cos(a) * speed * tau * 0.55;
    final y = origin.dy + math.sin(a) * speed * tau * 0.55 + 520 * tau * tau;
    final fade = bt < 0.6 ? 1.0 : (1 - (bt - 0.6) / 0.4);
    paint.color = _confettiColors[i % _confettiColors.length].withValues(
      alpha: fade,
    );
    final s = 5.0 + 5.0 * r1;
    c.save();
    c.translate(x, y);
    c.rotate(tau * (2 + r2 * 6) * (i.isEven ? 1 : -1));
    if (i % 3 == 0) {
      c.drawCircle(Offset.zero, s * 0.7, paint);
    } else {
      c.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s * 1.8, height: s),
        paint,
      );
    }
    c.restore();
  }
}

/// A full-screen white flash that decays.
void _flash(
  Canvas c,
  Size screen,
  double bt, {
  double strength = 0.55,
  double span = 0.16,
}) {
  if (bt <= 0 || bt >= span) return;
  c.drawRect(
    Offset.zero & screen,
    _fill(V13.white.withValues(alpha: strength * (1 - bt / span))),
  );
}

// ── 1. RACE ─────────────────────────────────────────────────────────────

/// The old onboarding's route (thick navy S-curve with a thin blue progress
/// stroke, a start dot, the Nuvo flag) scaled to the stage. YOU launch, then
/// the page CRAWLS toward the finish with the rivals closing in, then SPRINTS
/// across the line.
class _RaceScene extends CustomPainter {
  _RaceScene(this.t, this.stage);
  final double t;
  final Rect stage;

  /// Route progress with the speed profile: ease-in launch, the crawl, then
  /// the sprint. 0..1 along the route.
  double get _progress {
    if (t < 0.12) return 0;
    if (t < 0.50) return 0.72 * _inOut(_seg(t, 0.12, 0.50) * 0.92 + 0.0);
    if (t < 0.80) return 0.72 + 0.21 * _seg(t, 0.50, 0.80); // the crawl
    if (t < 0.88) return 0.93 + 0.07 * _out(_seg(t, 0.80, 0.88)); // the sprint
    return 1.0;
  }

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[0];
    final bt = (t - climax) / (1 - climax);
    // Leave headroom above the finish for the "1st" pill (never into the header).
    final d = stage.deflate(20);
    final r = Rect.fromLTRB(d.left, d.top + 56, d.right - 24, d.bottom);
    Offset p(double fx, double fy) =>
        Offset(r.left + r.width * fx, r.top + r.height * fy);
    // The old route, spread over the stage.
    final path = Path()
      ..moveTo(p(0.04, 0.86).dx, p(0.04, 0.86).dy)
      ..cubicTo(
        p(0.24, 0.04).dx,
        p(0.24, 0.04).dy,
        p(0.60, 1.0).dx,
        p(0.60, 1.0).dy,
        p(0.80, 0.14).dx,
        p(0.80, 0.14).dy,
      );
    final m = path.computeMetrics().first;
    final len = m.length;
    final end = m.getTangentForOffset(len)!.position;
    final start = m.getTangentForOffset(0)!.position;
    final prog = _progress;

    // Camera: a slow push toward the finish during the crawl, easing back.
    final push =
        0.07 * _inOut(_seg(t, 0.50, 0.80)) * (1 - 0.6 * _seg(t, 0.88, 1.0));
    c.save();
    c.translate(end.dx, end.dy);
    c.scale(1 + push);
    c.translate(-end.dx, -end.dy);

    // Route: draws in, then the blue progress stroke follows YOU.
    final reveal = _out(_seg(t, 0.0, 0.14));
    c.drawPath(m.extractPath(0, len * reveal), _line(14, V13.navy));
    c.drawPath(m.extractPath(0, len * prog), _line(6, V13.blue));
    c.drawCircle(start, 10, _fill(V13.blue));
    c.drawCircle(start, 10, _line(3));

    // Rivals close the gap during the crawl.
    final tension = _seg(t, 0.50, 0.86);
    for (var i = 0; i < 2; i++) {
      final gap = (i == 0 ? 0.16 : 0.28) * (1 - 0.82 * tension);
      final rp = (prog - gap).clamp(0.0, 1.0);
      if (prog <= 0.001) continue;
      final pos = m.getTangentForOffset(len * rp)!.position;
      c.drawCircle(pos, 11, _fill(V13.white));
      c.drawCircle(pos, 11, _line(3));
    }

    // Finish flag (the old Nuvo flag shape), popping at the payoff.
    _flag(c, end, 1.5 + 0.5 * _bump(bt * 2.4));

    // YOU: the old racer dot, bigger — navy core, white center, blue halo.
    if (prog > 0.001) {
      final pos = m.getTangentForOffset(len * prog)!.position;
      final pop = _pop(_seg(t, 0.10, 0.22));
      final halo = 22 + 6 * _bump(((t * 6) % 1.0)) + 10 * tension;
      c.drawCircle(pos, halo * pop, _fill(V13.blue.withValues(alpha: 0.28)));
      c.drawCircle(pos, 14 * pop, _fill(V13.navy));
      c.drawCircle(pos, 6.5 * pop, _fill(V13.white));
    }
    c.restore();

    // PAYOFF, in screen space.
    _flash(c, s, bt, strength: 0.6);
    final reach = math.max(s.width, s.height);
    _wave(c, end, bt, to: reach * 0.7, width: 10, color: V13.navy);
    _wave(c, end, _stag(bt, 0.10), to: reach * 0.55, width: 7, color: V13.blue);
    _wave(c, end, _stag(bt, 0.20), to: reach * 0.4, width: 4, color: V13.white);
    _confettiFall(c, end, bt, s);
    if (t >= climax) {
      final pp = _pop(bt * 2.6);
      final w = 120.0 * pp, h = 62.0 * pp;
      final center = Offset(
        (end.dx - 34).clamp(70.0, s.width - 70),
        math.max(end.dy - 74, stage.top + 36),
      );
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: w, height: h),
        Radius.circular(31 * pp),
      );
      c.drawRRect(rr, _fill(V13.white));
      c.drawRRect(rr, _line(4));
      if (pp > 0.6) _textAt(c, '1st', center, size: 34 * pp);
    }
  }

  void _flag(Canvas c, Offset anchor, double scale) {
    final poleX = anchor.dx + 12 * scale;
    final top = anchor.dy - 24 * scale;
    final bottom = anchor.dy + 16 * scale;
    c.drawLine(Offset(poleX, top), Offset(poleX, bottom), _line(2.4 * scale));
    final flag = Path()
      ..moveTo(poleX + scale, top + scale)
      ..cubicTo(
        poleX + 9 * scale,
        top - 3 * scale,
        poleX + 18 * scale,
        top + 7 * scale,
        poleX + 27 * scale,
        top + 3 * scale,
      )
      ..lineTo(poleX + 27 * scale, top + 19 * scale)
      ..cubicTo(
        poleX + 18 * scale,
        top + 23 * scale,
        poleX + 9 * scale,
        top + 13 * scale,
        poleX + scale,
        top + 19 * scale,
      )
      ..close();
    c.drawPath(flag, _fill(V13.blue));
    c.drawPath(flag, _line(1.6 * scale));
  }

  @override
  bool shouldRepaint(_RaceScene o) => o.t != t || o.stage != stage;
}

// ── 2. JUMPING JACKS ────────────────────────────────────────────────────

/// The app's real jumping-jack figure, LARGE and centered; a full-bleed scan
/// frame at the screen edges; a rep ring around the figure; slow-mo on the
/// last rep; a huge VERIFIED stamp slam.
class _JackScene extends StatelessWidget {
  const _JackScene({required this.t, required this.stage});
  final double t;
  final Rect stage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => _build(context, Size(c.maxWidth, c.maxHeight)),
  );

  Widget _build(BuildContext context, Size screen) {
    final climax = introClimax[1];
    final bt = (t - climax) / (1 - climax);
    final done = t >= climax;
    final count = done ? 3 : (t >= 0.42 ? 2 : (t >= 0.26 ? 1 : 0));
    final side = math.min(stage.width * 0.66, stage.height * 0.78);
    final center = stage.center;
    // camera push at the climax (scale on a transparent layer: no edges)
    final push = 0.06 * _bump(bt * 2.2);
    final dim = 0.16 * _inOut(_seg(t, 0.50, 0.70)) * (done ? 0 : 1);
    return Stack(
      fit: StackFit.expand,
      children: [
        // slow-mo: the field dims slightly while the last rep crawls
        if (dim > 0)
          Positioned.fill(
            child: ColoredBox(color: V13.navy.withValues(alpha: dim)),
          ),
        Transform.scale(
          scale: 1 + push,
          alignment: Alignment(
            (center.dx / screen.width) * 2 - 1,
            (center.dy / screen.height) * 2 - 1,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: center.dx - side / 2,
                top: center.dy - side / 2,
                width: side,
                height: side,
                child: RiveJumpingJackPreview(
                  fallback: Icon(
                    Icons.accessibility_new_rounded,
                    size: side * .5,
                    color: V13.navy,
                  ),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _JackFx(t, stage, side)),
                ),
              ),
              // counter
              Positioned(
                left: stage.left + 30,
                top: stage.top + 22,
                width: stage.width * 0.5,
                child: Transform.scale(
                  scale: done ? 1 + 0.5 * _bump(bt * 2.6) : 1,
                  alignment: Alignment.topLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: V13.hugeNumber.copyWith(
                            fontSize: math.min(88, stage.height * 0.24),
                            color: V13.navy,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '/ 3 reps',
                            style: V13.bodyStrong.copyWith(color: V13.navy),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // the stamp
              if (done)
                Positioned(
                  left: 24,
                  right: 24,
                  top: stage.bottom - 64,
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + 1.4 * (1 - _pop(bt * 2.8)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: V13.white,
                            borderRadius: BorderRadius.circular(V13.radiusPill),
                            border: Border.all(color: V13.navy, width: 4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                size: 28,
                                color: V13.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'VERIFIED',
                                style: V13.title.copyWith(fontSize: 26),
                              ),
                            ],
                          ),
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
  }
}

class _JackFx extends CustomPainter {
  _JackFx(this.t, this.stage, this.side);
  final double t;
  final Rect stage;
  final double side;

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[1];
    final bt = (t - climax) / (1 - climax);
    final center = stage.center;

    // Full-bleed scan frame: brackets slide in from beyond the screen edges
    // and lock at 14px, then tighten a touch during the slow-mo rep.
    final lockIn = _soft(_seg(t, 0.0, 0.22));
    final tighten = 8 * _inOut(_seg(t, 0.50, 0.84));
    final inset = -60 + (14 + 60) * lockIn + tighten;
    final frame = Rect.fromLTRB(
      inset,
      math.max(inset, stage.top - 24 + tighten),
      s.width - inset,
      math.min(s.height - inset, stage.bottom + 24 - tighten),
    );
    final arm = 34.0;
    final col = t >= climax ? V13.blue : V13.navy;
    final p = _line(5, col);
    for (final k in [
      [frame.topLeft, 1.0, 1.0],
      [frame.topRight, -1.0, 1.0],
      [frame.bottomLeft, 1.0, -1.0],
      [frame.bottomRight, -1.0, -1.0],
    ]) {
      final o = k[0] as Offset;
      final dx = k[1] as double, dy = k[2] as double;
      c.drawLine(o, o.translate(arm * dx, 0), p);
      c.drawLine(o, o.translate(0, arm * dy), p);
    }

    // Rep ring around the figure: two quick segments, then the crawl.
    final rr = side * 0.52;
    final rect = Rect.fromCircle(center: center, radius: rr);
    c.drawCircle(center, rr, _line(9, V13.navy.withValues(alpha: 0.14)));
    const gap = 0.16;
    final seg = (2 * math.pi - 3 * gap) / 3;
    double fillFor(int i) {
      if (i == 0) return _out(_seg(t, 0.18, 0.28));
      if (i == 1) return _out(_seg(t, 0.34, 0.44));
      if (t >= introClimax[1]) return 1.0;
      return 0.92 * _seg(t, 0.46, 0.84); // the crawl
    }

    for (var i = 0; i < 3; i++) {
      final a0 = -math.pi / 2 + i * (seg + gap);
      c.drawArc(rect, a0, seg * fillFor(i), false, _line(12, V13.blue));
    }

    // PAYOFF.
    _flash(c, s, bt, strength: 0.6);
    final reach = math.max(s.width, s.height);
    _wave(c, center, bt, from: rr, to: reach * 0.7, width: 10, color: V13.blue);
    _wave(c, center, _stag(bt, 0.12), from: rr, to: reach * 0.55, width: 6);
    _confettiFall(c, center, bt, s);
  }

  @override
  bool shouldRepaint(_JackFx o) => o.t != t || o.stage != stage;
}

// ── 3. LEADERBOARD ──────────────────────────────────────────────────────

/// Five big rows. YOU start 5th and overtake four rows (a slide each, almost
/// no overshoot); the last pass is the slow one. Then #1: flash, waves,
/// confetti.
class _BoardScene extends CustomPainter {
  _BoardScene(this.t, this.stage);
  final double t;
  final Rect stage;

  // (start, end) of each overtake leg in t; the last is the slow one.
  static const _legs = [(0.28, 0.38), (0.40, 0.50), (0.52, 0.62), (0.70, 0.78)];

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[2];
    final bt = (t - climax) / (1 - climax);
    final rh = math.min(66.0, stage.height / 5.2);
    final left = stage.left + 20;
    final w = stage.width - 40;
    final top = stage.top + 26 + (stage.height - 26 - rh * 5) / 2;
    final leg = [
      for (var k = 0; k < _legs.length; k++)
        // the last pass holds under #1 (the beat), then slides on the climax
        k == 3
            ? _inOut(_seg(t, _legs[k].$1, _legs[k].$2))
            : _soft(_seg(t, _legs[k].$1, _legs[k].$2)),
    ];
    // The slower last leg eases in more gently.
    final legSum = leg.fold<double>(0, (a, b) => a + b);
    // Rows: 0..3 are the others; row i is passed by leg (3 - i).
    const names = ['Maya', 'Leo', 'Sam', 'Alex'];
    const base = [96.0, 84.0, 70.0, 58.0];
    final order = <int>[0, 1, 2, 3, 4];
    for (final i in [0, 1, 2, 3, 4]) {
      final you = i == 4;
      final slot = you ? 4 - legSum : i + leg[3 - i];
      final enter = _pop(_seg(t, i * 0.05, 0.22 + i * 0.05));
      if (enter <= 0) continue;
      final y = top + slot * rh + (1 - enter.clamp(0.0, 1.0)) * 36;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y + 4, w, rh - 8),
        Radius.circular(rh * 0.3),
      );
      final fg = you ? V13.white : V13.navy;
      c.saveLayer(
        rect.outerRect.inflate(14),
        Paint()..color = Color.fromRGBO(0, 0, 0, enter.clamp(0.0, 1.0)),
      );
      c.drawRRect(rect, _fill(you ? V13.blue : V13.white));
      c.drawRRect(rect, _line(3));
      if (you && bt > 0 && bt < 0.6) {
        c.drawRRect(
          rect.inflate(5 + 8 * bt),
          _line(5, V13.sun.withValues(alpha: 1 - bt / 0.6)),
        );
      }
      final cy = y + rh / 2;
      final rank = (slot + 0.5).floor() + 1;
      _textAt(c, '$rank', Offset(left + 26, cy), size: rh * 0.36, color: fg);
      final av = Offset(left + 70, cy);
      final ar = rh * 0.32;
      c.drawCircle(av, ar, _fill(you ? V13.white : V13.sky));
      c.drawCircle(av, ar, _line(3));
      if (you) {
        final head = _fill(V13.blue);
        c.drawCircle(av.translate(0, -ar * 0.22), ar * 0.3, head);
        c.drawArc(
          Rect.fromCenter(
            center: av.translate(0, ar * 0.68),
            width: ar * 1.1,
            height: ar,
          ),
          math.pi,
          math.pi,
          true,
          head,
        );
      } else {
        _textAt(c, names[i][0], av, size: ar * 0.95);
      }
      final nm = _tp(you ? 'You' : names[i], rh * 0.34, fg);
      nm.paint(c, Offset(left + 106, cy - nm.height / 2));
      final score = you ? 30 + 70 * (legSum / 4) : base[i];
      final sc = _tp(score.round().toString(), rh * 0.38, fg);
      sc.paint(c, Offset(left + w - 24 - sc.width, cy - sc.height / 2));
      c.restore();
    }
    // PAYOFF at the top row.
    final topRow = Offset(left + w / 2, top + rh / 2);
    _flash(c, s, bt, strength: 0.5);
    final reach = math.max(s.width, s.height);
    _wave(c, topRow, bt, from: 24, to: reach * 0.65, width: 9, color: V13.blue);
    _wave(c, topRow, _stag(bt, 0.12), from: 24, to: reach * 0.5, width: 5);
    _confettiFall(c, topRow, bt, s);
    // "#1" crown tag drops onto the top row.
    if (t >= climax) {
      final p = _pop(bt * 2.6);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: topRow.translate(w / 2 - 56, -rh * 0.62),
          width: 78 * p,
          height: 36 * p,
        ),
        Radius.circular(18 * p),
      );
      c.drawRRect(r, _fill(V13.sun));
      c.drawRRect(r, _line(3));
      if (p > 0.7) _textAt(c, '#1', r.center, size: 20 * p);
    }
    if (order.isEmpty) return;
  }

  @override
  bool shouldRepaint(_BoardScene o) => o.t != t || o.stage != stage;
}

// ── 4. CREW ─────────────────────────────────────────────────────────────

/// Six faces swoop in from BEYOND the screen edges on curved paths and settle
/// (spring) into a ring around YOU; a counter pops per arrival; at the climax
/// the links draw in, the ring pulses and the count slams to 6.
class _CrewScene extends CustomPainter {
  _CrewScene(this.t, this.stage);
  final double t;
  final Rect stage;

  static const _joins = [0.08, 0.20, 0.30, 0.38, 0.45, 0.51];
  static const _colors = [
    V13.coral,
    V13.sun,
    V13.mint,
    V13.white,
    V13.sky,
    V13.lilac,
  ];
  static const _labels = ['A', 'M', 'L', 'S', 'J', 'K'];

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[3];
    final bt = (t - climax) / (1 - climax);
    final center = stage.center.translate(16, 26);
    final r = math.min(stage.width * 0.29, stage.height * 0.30);
    final face = math.min(34.0, r * 0.44);
    // pulse of the whole crew at the climax
    final pulse = 1 + 0.07 * _bump(bt * 2.4);

    // Links first (behind the faces), drawn in at the climax.
    final link = _out(_seg(t, climax - 0.02, climax + 0.14));
    final homes = <Offset>[];
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3 + math.pi / 6;
      homes.add(center + Offset(math.cos(a), math.sin(a)) * r * pulse);
    }
    for (var i = 0; i < 6; i++) {
      if (link <= 0) break;
      c.drawLine(
        center,
        Offset.lerp(center, homes[i], link)!,
        _line(4, V13.navy),
      );
    }

    var joined = 0;
    for (var i = 0; i < 6; i++) {
      final p = _seg(t, _joins[i], _joins[i] + 0.20);
      if (p <= 0) continue;
      if (p >= 0.6) joined = i + 1;
      // from beyond the screen edge, along a curve, spring-settled
      final a = -math.pi / 2 + i * math.pi / 3 + math.pi / 6;
      final dir = Offset(math.cos(a), math.sin(a));
      final far = center + dir * (math.max(s.width, s.height) * 0.75);
      final bend =
          Offset(-dir.dy, dir.dx) * (s.width * 0.25) * (i.isEven ? 1 : -1);
      final e = _pop(p);
      final ctrl = Offset.lerp(far, homes[i], 0.5)! + bend;
      // quadratic bezier from far -> home with spring-timed parameter
      final u = e.clamp(0.0, 1.1);
      final pos =
          (far * ((1 - u) * (1 - u))) +
          (ctrl * (2 * (1 - u) * u)) +
          (homes[i] * (u * u));
      c.drawCircle(pos, face, _fill(_colors[i]));
      c.drawCircle(pos, face, _line(4));
      _textAt(c, _labels[i], pos, size: face * 0.85);
      // ripple on arrival
      _wave(
        c,
        homes[i],
        _seg(t, _joins[i] + 0.14, _joins[i] + 0.30),
        from: face,
        to: face * 2.1,
        width: 4,
        color: V13.navy,
      );
    }

    // YOU, the anchor.
    final core = _pop(_seg(t, 0.0, 0.16));
    final coreR = (face * 1.35) * core * (1 + 0.14 * _bump(bt * 2.6));
    c.drawCircle(center, coreR, _fill(V13.blue));
    c.drawCircle(center, coreR, _line(5));
    if (core > 0.6)
      _textAt(c, 'You', center, size: face * 0.8, color: V13.white);

    // The counter (top-left, clear of the formation) pops per arrival,
    // then slams to 6.
    final cnt = t >= climax ? 6 : joined;
    final popBeat = t >= climax ? _bump(bt * 2.4) * 0.5 : 0.0;
    final label = _tp(
      '$cnt',
      math.min(60, stage.height * 0.18) * (1 + popBeat),
      V13.navy,
    );
    label.paint(c, Offset(stage.left + 28, stage.top + 8));
    final sub = _tp('in your crew', 16, V13.navy);
    sub.paint(c, Offset(stage.left + 28, stage.top + 8 + label.height + 4));

    // PAYOFF.
    _flash(c, s, bt, strength: 0.5);
    final reach = math.max(s.width, s.height);
    _wave(
      c,
      center,
      bt,
      from: coreR,
      to: reach * 0.7,
      width: 10,
      color: V13.blue,
    );
    _wave(c, center, _stag(bt, 0.12), from: coreR, to: reach * 0.55, width: 6);
    _confettiFall(c, center, bt, s, count: 26);
  }

  @override
  bool shouldRepaint(_CrewScene o) => o.t != t || o.stage != stage;
}

// ── 5. LEVEL UP ─────────────────────────────────────────────────────────

/// A big XP ring. It fills fast, CRAWLS, HOLDS with a rising tremble, then
/// BREAKS: the ring shatters outward, shock rings, a flash, a camera push,
/// LEVEL 1 -> 2 slams in, the badge lands.
class _LevelScene extends CustomPainter {
  _LevelScene(this.t, this.stage);
  final double t;
  final Rect stage;

  double get _fillAmt {
    final climax = introClimax[4];
    if (t >= climax) return 1.0;
    if (t < 0.08) return 0;
    if (t < 0.50) return _out(_seg(t, 0.08, 0.50)) * 0.9;
    if (t < 0.78) return 0.9 + 0.08 * _seg(t, 0.50, 0.78);
    return 0.98;
  }

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[4];
    final bt = (t - climax) / (1 - climax);
    // Ring + XP + badge are laid out as one block, centered in the stage.
    final rr = math.min(stage.width * 0.34, (stage.height - 104) / 2);
    final block = 2 * rr + 104;
    final center = Offset(
      stage.center.dx,
      stage.top + (stage.height - block) / 2 + rr,
    );
    final fill = _fillAmt;

    // Anticipation tremble (rises through the hold), then the camera push.
    final hold = _seg(t, 0.74, 0.82);
    final trem = t < climax
        ? Offset(math.sin(t * 190) * 2.4 * hold, math.cos(t * 230) * 2.0 * hold)
        : Offset.zero;
    final push = 0.10 * _bump(bt * 2.0);
    c.save();
    c.translate(center.dx + trem.dx, center.dy + trem.dy);
    c.scale(1 + push);
    c.translate(-center.dx, -center.dy);

    final rect = Rect.fromCircle(center: center, radius: rr);
    if (t < climax) {
      c.drawCircle(center, rr, _line(16, V13.navy.withValues(alpha: 0.14)));
      c.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fill,
        false,
        _line(18, V13.blue),
      );
      // a bright head that leads the fill
      final a = -math.pi / 2 + 2 * math.pi * fill;
      final head = center + Offset(math.cos(a), math.sin(a)) * rr;
      c.drawCircle(head, 13 + 4 * hold, _fill(V13.white));
      c.drawCircle(head, 13 + 4 * hold, _line(4));
    } else {
      // The ring SHATTERS: 12 arcs fly outward and fade.
      final e = _out(bt * 1.4);
      for (var i = 0; i < 12; i++) {
        final a0 = i * math.pi / 6;
        final mid = a0 + math.pi / 12;
        final shift = Offset(math.cos(mid), math.sin(mid)) * (rr * 1.15 * e);
        final alpha = (1 - _seg(bt, 0.1, 0.8)).clamp(0.0, 1.0);
        if (alpha <= 0) continue;
        c.drawArc(
          rect.shift(shift),
          a0 + 0.04,
          math.pi / 6 - 0.08,
          false,
          _line(18 * (1 - 0.6 * e), V13.blue.withValues(alpha: alpha)),
        );
      }
      // after the break a calm settled ring remains
      final rest = _soft(_seg(bt, 0.3, 0.8));
      c.drawCircle(
        center,
        rr * (0.6 + 0.4 * rest),
        _line(10, V13.blue.withValues(alpha: rest)),
      );
    }

    // LEVEL numeral: 1, then 2 slams in big and settles.
    final labelY = center.dy - rr * 0.46;
    _textAt(
      c,
      'LEVEL',
      Offset(center.dx, labelY),
      size: rr * 0.20,
      color: V13.navy,
    );
    if (t < climax) {
      _textAt(c, '1', center.translate(0, rr * 0.08), size: rr * 0.95);
    } else {
      final slam = _pop(_seg(bt, 0.0, 0.26));
      final size = rr * 0.95 * (1 + 0.9 * (1 - slam));
      final oldA = (1 - _seg(bt, 0.0, 0.12)).clamp(0.0, 1.0);
      if (oldA > 0)
        _textAt(
          c,
          '1',
          center.translate(0, rr * 0.08),
          size: rr * 0.95 * (1 - 0.5 * (1 - oldA)),
          color: V13.navy.withValues(alpha: oldA),
        );
      _textAt(
        c,
        '2',
        center.translate(0, rr * 0.08),
        size: size,
        color: V13.navy.withValues(alpha: slam.clamp(0.0, 1.0)),
      );
    }
    c.restore();

    // XP count under the ring.
    final xp = t >= climax ? 100 : math.min(98, (100 * (fill / 0.98)).round());
    _textAt(
      c,
      '+$xp XP',
      Offset(s.width / 2, center.dy + rr + 40),
      size: 30 * (t >= climax ? 1 + 0.35 * _bump(bt * 2.4) : 1),
    );

    // PAYOFF in screen space.
    _flash(c, s, bt, strength: 0.7, span: 0.18);
    final reach = math.max(s.width, s.height);
    _wave(
      c,
      center,
      bt,
      from: rr,
      to: reach * 0.85,
      width: 12,
      color: V13.white,
    );
    _wave(
      c,
      center,
      _stag(bt, 0.08),
      from: rr,
      to: reach * 0.7,
      width: 8,
      color: V13.navy,
    );
    _wave(
      c,
      center,
      _stag(bt, 0.16),
      from: rr,
      to: reach * 0.55,
      width: 5,
      color: V13.blue,
    );
    _confettiFall(c, center, bt, s, count: 40);

    // Badge slams in.
    final bb = _seg(t, climax + 0.10, climax + 0.22);
    if (bb > 0) {
      final p = _pop(bb);
      final w = 190.0 * p, h = 50.0 * p;
      final cy = center.dy + rr + 82;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s.width / 2, cy), width: w, height: h),
        Radius.circular(25 * p),
      );
      c.drawRRect(r, _fill(V13.sun));
      c.drawRRect(r, _line(4));
      if (p > 0.7) _textAt(c, 'Day One badge', r.center, size: 19 * p);
    }
  }

  @override
  bool shouldRepaint(_LevelScene o) => o.t != t || o.stage != stage;
}

/// Soft, flat background shapes that drift slowly behind the pages (depth
/// without shadows); full-screen, so no shape is ever cut by a container.
class CloudsPainter extends CustomPainter {
  CloudsPainter({required this.pos, required this.drift});

  final double pos;
  final double drift; // 0..1 loop

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = V13.white.withValues(alpha: 0.26);
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
