import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import '../../../core/v13/tokens.dart';
import '../../races/presentation/widgets/rive_movement_preview.dart';

/// The five intro moments. Every page has ONE story told with the same
/// shape — anticipation (a slow-down, a held beat), a CLIMAX (burst, ring
/// wave, camera push, strong haptic) and a settle — and plays ONCE over
/// [t] in 0..1, then holds the final frame. Flat fills only: no shadows, no
/// tilt, no floating cards.
///
/// Climax time (real t) per page, and the haptic marks the page fires as the
/// play passes them (see [introHapticMarks]).
const introClimax = [0.80, 0.80, 0.72, 0.62, 0.82];

/// (t, kind) — kind is 'tick' | 'thud' | 'burst' | 'success'.
const introHapticMarks = <List<(double, String)>>[
  // 1 race: three ticks while the line is drawn, a held breath, the finish
  [
    (0.18, 'tick'),
    (0.32, 'tick'),
    (0.46, 'tick'),
    (0.58, 'thud'),
    (0.80, 'burst'),
  ],
  // 2 reps: a tick per rep, the held breath before rep 3, the verify
  [(0.22, 'tick'), (0.36, 'tick'), (0.50, 'thud'), (0.80, 'burst')],
  // 3 board: a tick per overtake, the payoff on 1st
  [(0.36, 'tick'), (0.50, 'tick'), (0.72, 'burst')],
  // 4 crew: a tick as each friend joins (escalating), the payoff
  [
    (0.10, 'tick'),
    (0.26, 'tick'),
    (0.38, 'tick'),
    (0.46, 'tick'),
    (0.62, 'burst'),
  ],
  // 5 level: slow ticks up the bar, the held breath, the break
  [
    (0.20, 'tick'),
    (0.32, 'tick'),
    (0.44, 'tick'),
    (0.56, 'tick'),
    (0.66, 'tick'),
    (0.74, 'tick'),
    (0.78, 'thud'),
    (0.82, 'success'),
  ],
];

/// How hard the camera pushes in at each page's climax (fraction of scale).
const _push = [0.05, 0.06, 0.04, 0.04, 0.10];

class IntroDemo extends StatelessWidget {
  const IntroDemo({super.key, required this.kind, required this.t});

  final int kind;
  final double t;

  @override
  Widget build(BuildContext context) {
    final Widget body = kind == 1
        ? _RepDemo(t: t)
        : RepaintBoundary(
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
    // Camera push: a brief scale pulse right at the climax.
    final push = _push[kind] * _bump((t - introClimax[kind]) / 0.28);
    if (push <= 0) return body;
    return Transform.scale(scale: 1 + push, child: body);
  }
}

// ── shared helpers ─────────────────────────────────────────────────────

Paint _line(double w, [Color c = V13.navy]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// The app's spring (a little overshoot) — for pops and slams.
double _pop(double x) => NuvoMotion.spring.transform(x.clamp(0.0, 1.0));

/// Almost no overshoot — for travel and climbs.
double _soft(double x) => NuvoMotion.softSpring.transform(x.clamp(0.0, 1.0));

/// Ease-out for counters (numbers never overshoot).
double _out(double x) {
  final v = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - v, 3).toDouble();
}

/// A burst progress delayed by [d] but still ending exactly at 1.
double _stag(double bt, double d) => (bt - d) / (1 - d);

/// 0 -> 1 -> 0 over x in [0,1]; 0 outside.
double _bump(double x) => (x <= 0 || x >= 1) ? 0 : math.sin(x * math.pi);

/// Time dilation: real time [s, e] runs at [factor] speed in story time, so
/// the page visibly slows down for suspense, then speeds up after. Returns
/// story time in 0..1.
double _dilate(double t, double s, double e, double factor) {
  final total = s + (e - s) * factor + (1 - e);
  final story = t <= s
      ? t
      : t <= e
      ? s + (t - s) * factor
      : s + (e - s) * factor + (t - e);
  return (story / total).clamp(0.0, 1.0);
}

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

const _confetti = [V13.navy, V13.white, V13.sun, V13.coral, V13.blue, V13.mint];

/// Flat particles bursting out of [at]; [bt] 0..1 since the burst.
void _particles(
  Canvas c,
  Offset at,
  double bt, {
  int count = 16,
  double reach = 120,
  double size = 7,
}) {
  if (bt <= 0 || bt >= 1) return;
  final e = _out(bt);
  final paint = Paint();
  for (var i = 0; i < count; i++) {
    final a = i * 2 * math.pi / count + (i.isEven ? 0.18 : -0.12);
    final r = reach * (0.55 + 0.45 * ((i * 7) % 5) / 4) * e;
    final p = at + Offset(math.cos(a), math.sin(a)) * (14 + r);
    paint.color = _confetti[i % _confetti.length].withValues(
      alpha: 1 - bt * bt,
    );
    final s = size * (1 - bt * 0.6);
    if (i % 3 == 0) {
      c.drawRect(Rect.fromCenter(center: p, width: s * 1.6, height: s), paint);
    } else {
      c.drawCircle(p, s, paint);
    }
  }
}

/// An expanding ring that fades.
void _ring(
  Canvas c,
  Offset at,
  double bt, {
  double from = 10,
  double to = 150,
  double width = 5,
  Color color = V13.navy,
}) {
  if (bt <= 0 || bt >= 1) return;
  final e = _out(bt);
  c.drawCircle(
    at,
    from + (to - from) * e,
    _line(width * (1 - bt) + 1, color.withValues(alpha: 1 - bt)),
  );
}

// ── 1. RACE: one line, drawn toward the finish ─────────────────────────

/// A single race line is drawn across the screen by YOU (blue); two rivals
/// chase close behind. Near the end the page SLOWS for suspense, then YOU
/// cross first — ring wave, particles, "1st".
class _RacePainter extends CustomPainter {
  _RacePainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    const slowS = 0.50, slowE = 0.80, factor = 0.16;
    final climax = introClimax[0];
    final u = _dilate(t, slowS, slowE, factor);
    final uEnd = _dilate(slowE, slowS, slowE, factor);
    final prog = (u / uEnd).clamp(0.0, 1.0);

    final a = Offset(28, s.height * 0.68);
    final b = Offset(s.width - 56, s.height * 0.34);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(
        s.width * 0.35,
        s.height * 0.95,
        s.width * 0.55,
        s.height * 0.05,
        b.dx,
        b.dy,
      );
    final metric = path.computeMetrics().first;
    final len = metric.length;

    // The line itself: faint full course, bold part already drawn.
    c.drawPath(path, _line(3, V13.navy.withValues(alpha: 0.18)));
    final drawn = metric.extractPath(0, len * prog);
    c.drawPath(drawn, _line(5));

    // Rivals: white dots chasing; they close in during the slow region.
    final suspense = ((t - slowS) / (slowE - slowS)).clamp(0.0, 1.0);
    for (var i = 0; i < 2; i++) {
      final gap = (i == 0 ? 0.09 : 0.16) * (1 - 0.7 * suspense);
      final rp = (prog - gap).clamp(0.0, 1.0);
      final pos = metric.getTangentForOffset(len * rp)!.position;
      c.drawCircle(pos, 12, Paint()..color = V13.white);
      c.drawCircle(pos, 12, _line(3));
    }

    // YOU.
    final you = metric.getTangentForOffset(len * prog)!.position;
    final pop = _pop((t - 0.04) / 0.2);
    c.drawCircle(you, 19 * pop, Paint()..color = V13.blue);
    c.drawCircle(you, 19 * pop, _line(3.5));
    if (pop > 0.8) _textAt(c, 'YOU', you, size: 10, color: V13.white);

    // Finish: a flag at the end of the line.
    final fx = b.dx + 26;
    c.drawLine(Offset(fx, b.dy + 16), Offset(fx, b.dy - 24), _line(3));
    for (var r = 0; r < 3; r++) {
      for (var k = 0; k < 2; k++) {
        c.drawRect(
          Rect.fromLTWH(fx + 1 + k * 8, b.dy - 24 + r * 8, 8, 8),
          Paint()..color = (r + k).isEven ? V13.navy : V13.white,
        );
      }
    }

    // CLIMAX: crossing first.
    final bt = (t - climax) / (1 - climax);
    _ring(c, b, bt, to: math.min(s.width, s.height) * 0.55, width: 6);
    _ring(
      c,
      b,
      _stag(bt, 0.12),
      to: math.min(s.width, s.height) * 0.4,
      width: 4,
      color: V13.blue,
    );
    _particles(c, b, bt, count: 18, reach: 110);
    if (t >= climax) {
      final p = _pop(bt * 2.4);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: b.translate(-8, -62),
          width: 66 * p,
          height: 38 * p,
        ),
        Radius.circular(19 * p),
      );
      c.drawRRect(r, Paint()..color = V13.white);
      c.drawRRect(r, _line(3));
      if (p > 0.7) _textAt(c, '1st', b.translate(-8, -62), size: 19);
    }
  }

  @override
  bool shouldRepaint(_RacePainter o) => o.t != t;
}

// ── 2. PROVE IT: the app's jumping-jack figure + scan, reps, verify ────

class _RepDemo extends StatelessWidget {
  const _RepDemo({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final climax = introClimax[1];
    final done = t >= climax;
    // Reps 1-2 land fast; rep 3 is the slow, held one.
    final count = t >= climax
        ? 3
        : t >= 0.36
        ? 2
        : t >= 0.22
        ? 1
        : 0;
    final bt = (t - climax) / (1 - climax);
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxHeight, c.maxWidth * 0.58);
        final figure = Rect.fromLTWH(0, (c.maxHeight - side) / 2, side, side);
        final rw = c.maxWidth - side - 8;
        final ringR = math.min(rw * 0.42, c.maxHeight * 0.26);
        final ringC = Offset(side + 8 + rw / 2, c.maxHeight * 0.4);
        return Stack(
          children: [
            Positioned.fromRect(
              rect: figure,
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
                child: CustomPaint(painter: _RepFx(t, figure, ringC, ringR)),
              ),
            ),
            Positioned(
              left: ringC.dx - ringR,
              top: ringC.dy - ringR,
              width: ringR * 2,
              height: ringR * 2,
              child: Center(
                child: Transform.scale(
                  scale: done ? 1 + 0.35 * _bump(bt * 3) : 1,
                  child: Text(
                    '$count',
                    style: V13.hugeNumber.copyWith(
                      fontSize: ringR * 1.15,
                      color: V13.navy,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            if (done)
              Positioned(
                left: ringC.dx - rw / 2,
                width: rw,
                top: ringC.dy + ringR + 14,
                child: Center(
                  child: Transform.scale(
                    // Stamp slam: oversized, snaps down onto the page.
                    scale: 1 + 0.9 * (1 - _pop(bt * 3)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: V13.white,
                          borderRadius: BorderRadius.circular(V13.radiusPill),
                          border: Border.all(
                            color: V13.navy,
                            width: V13.outlineThick,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              size: 18,
                              color: V13.blue,
                            ),
                            const SizedBox(width: 6),
                            Text('VERIFIED', style: V13.label),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RepFx extends CustomPainter {
  _RepFx(this.t, this.figure, this.ringC, this.ringR);
  final double t;
  final Rect figure;
  final Offset ringC;
  final double ringR;

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[1];
    // Scan brackets: start wide and LOCK onto the figure.
    final lock = _soft((t - 0.06) / 0.24);
    final inset = 22 * (1 - lock) - 4;
    final r = figure.inflate(-inset.clamp(-4, 40).toDouble());
    final arm = math.min(r.width, r.height) * 0.18;
    final pulse = 1 + 0.06 * _bump((t - climax) / 0.18);
    final br = Rect.fromCenter(
      center: r.center,
      width: r.width * pulse,
      height: r.height * pulse,
    );
    final col = t >= climax ? V13.blue : V13.navy;
    final p = _line(4, col);
    for (final corner in [
      [br.topLeft, 1.0, 1.0],
      [br.topRight, -1.0, 1.0],
      [br.bottomLeft, 1.0, -1.0],
      [br.bottomRight, -1.0, -1.0],
    ]) {
      final o = corner[0] as Offset;
      final dx = corner[1] as double, dy = corner[2] as double;
      c.drawLine(o, o.translate(arm * dx, 0), p);
      c.drawLine(o, o.translate(0, arm * dy), p);
    }

    // Rep ring: three segments. 1 and 2 fill quickly; 3 CRAWLS (the held,
    // slowed rep) until the verify snaps it shut.
    final rect = Rect.fromCircle(center: ringC, radius: ringR);
    c.drawCircle(ringC, ringR, _line(7, V13.navy.withValues(alpha: 0.16)));
    const gap = 0.10;
    final seg = (2 * math.pi - 3 * gap) / 3;
    double fillFor(int i) {
      switch (i) {
        case 0:
          return _out((t - 0.14) / 0.10);
        case 1:
          return _out((t - 0.28) / 0.10);
        default:
          // crawl: 0 -> 0.9 over 0.42..0.78, then snap to 1 at the climax
          final crawl = ((t - 0.42) / 0.36).clamp(0.0, 1.0) * 0.9;
          return t >= introClimax[1] ? 1.0 : crawl;
      }
    }

    for (var i = 0; i < 3; i++) {
      final start = -math.pi / 2 + i * (seg + gap);
      c.drawArc(rect, start, seg * fillFor(i), false, _line(8, V13.blue));
    }

    // Climax: ring wave + particles from the counter.
    final bt = (t - climax) / (1 - climax);
    _ring(
      c,
      ringC,
      bt,
      from: ringR,
      to: ringR * 2.6,
      width: 6,
      color: V13.blue,
    );
    _ring(c, ringC, _stag(bt, 0.12), from: ringR, to: ringR * 2.0, width: 4);
    _particles(c, ringC, bt, count: 18, reach: ringR * 2.2);
  }

  @override
  bool shouldRepaint(_RepFx o) => o.t != t;
}

// ── 3. BOARD: climb to 1st (almost no overshoot) ───────────────────────

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[2];
    final rowH = math.min(58.0, s.height / 3.4);
    final w = s.width - 8;
    const x0 = 4.0;
    // The climb: critically damped (no bounce), with a slow final approach.
    // YOU reach 1st exactly at the climax: fast at first, then a slow,
    // held final approach.
    final x = ((t - 0.26) / (climax - 0.26)).clamp(0.0, 1.0);
    final u = x < 0.5
        ? 1.2 * x
        : 0.6 + 0.4 * (1 - math.pow(1 - (x - 0.5) / 0.5, 2).toDouble());
    final climb = _soft(u);
    final count = _out(x);
    const names = ['Maya', 'Leo', 'You'];
    const base = [68.0, 54.0, 24.0];
    double slot(int i) => i == 2 ? 2 - 2 * climb : i + climb;
    final top = (s.height - rowH * 3) / 2;
    final bt = (t - climax) / (1 - climax);

    for (final i in [0, 1, 2]) {
      final enter = _pop((t - i * 0.08) / 0.3);
      if (enter <= 0) continue;
      final y = top + slot(i) * rowH + (1 - enter.clamp(0.0, 1.0)) * 24;
      final you = i == 2;
      final score = base[i] + (you ? 52 * count : 0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, y + 4, w, rowH - 8),
        const Radius.circular(16),
      );
      c.saveLayer(
        rect.outerRect.inflate(6),
        Paint()..color = Color.fromRGBO(0, 0, 0, enter.clamp(0.0, 1.0)),
      );
      c.drawRRect(rect, Paint()..color = you ? V13.blue : V13.white);
      c.drawRRect(rect, _line(2.5));
      // 1st-place flash: a bright outline pulse on the player's row.
      if (you && bt > 0 && bt < 0.5) {
        c.drawRRect(
          rect.inflate(4 + 6 * bt),
          _line(4, V13.sun.withValues(alpha: 1 - bt * 2)),
        );
      }
      final fg = you ? V13.white : V13.navy;
      final cy = y + rowH / 2;
      final rank = (slot(i) + 0.5).floor() + 1;
      _textAt(c, '$rank', Offset(x0 + 24, cy), size: 17, color: fg);
      final av = Offset(x0 + 62, cy);
      c.drawCircle(av, 17, Paint()..color = you ? V13.white : V13.sky);
      c.drawCircle(av, 17, _line(2.5));
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
        _textAt(c, names[i][0], av, size: 15);
      }
      final name = _tp(names[i], 18, fg);
      name.paint(c, Offset(x0 + 92, cy - name.height / 2));
      final sc = _tp(score.round().toString(), 20, fg);
      sc.paint(c, Offset(x0 + w - 20 - sc.width, cy - sc.height / 2));
      c.restore();
    }

    // CLIMAX: YOU hit 1st — ring waves + particles from the top row.
    final topRow = Offset(s.width / 2, top + rowH / 2);
    _ring(
      c,
      topRow,
      bt,
      from: 20,
      to: s.width * 0.55,
      width: 6,
      color: V13.blue,
    );
    _ring(c, topRow, _stag(bt, 0.14), from: 20, to: s.width * 0.4, width: 4);
    _particles(c, topRow, bt, count: 20, reach: s.width * 0.32);
  }

  @override
  bool shouldRepaint(_BoardPainter o) => o.t != t;
}

// ── 4. CREW: friends join with escalating rhythm, then the crew lands ──

class _CrewPainter extends CustomPainter {
  _CrewPainter(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[3];
    final center = Offset(s.width / 2, s.height / 2);
    const labels = ['A', 'M', 'L', 'S'];
    const colors = [V13.coral, V13.sun, V13.mint, V13.white];
    // Faster and faster: 0.10, 0.26, 0.38, 0.46.
    const joins = [0.10, 0.26, 0.38, 0.46];
    final r = math.min(s.width * 0.34, s.height * 0.34);
    final face = math.min(26.0, r * 0.42);
    for (var i = 0; i < 4; i++) {
      final a = -math.pi / 2 + i * math.pi / 2 + math.pi / 4;
      final pos = center + Offset(math.cos(a), math.sin(a)) * r;
      final p = _pop((t - joins[i]) / 0.22);
      if (p <= 0) continue;
      final end = Offset.lerp(center, pos, p.clamp(0.0, 1.1))!;
      c.drawLine(center, end, _line(2.5));
      c.drawCircle(end, face * p, Paint()..color = colors[i]);
      c.drawCircle(end, face * p, _line(3));
      if (p > 0.6) _textAt(c, labels[i], end, size: face * 0.8);
      // a small ripple at each arrival
      _ring(
        c,
        end,
        (t - joins[i] - 0.1) / 0.16,
        from: face,
        to: face * 1.9,
        width: 3,
      );
    }
    final core = _pop(t / 0.18);
    final bt = (t - climax) / (1 - climax);
    final beat = 1 + 0.16 * _bump(bt * 3);
    c.drawCircle(center, 32 * core * beat, Paint()..color = V13.blue);
    c.drawCircle(center, 32 * core * beat, _line(3));
    if (core > 0.7) _textAt(c, 'You', center, size: 15, color: V13.white);

    // CLIMAX: the crew is assembled.
    _ring(
      c,
      center,
      bt,
      from: 34,
      to: math.min(s.width, s.height) * 0.62,
      width: 6,
      color: V13.blue,
    );
    _ring(
      c,
      center,
      _stag(bt, 0.12),
      from: 34,
      to: math.min(s.width, s.height) * 0.46,
      width: 4,
    );
    _particles(c, center, bt, count: 18, reach: r * 1.5);
    if (t >= climax) {
      final p = _pop(bt * 2.4);
      _textAt(
        c,
        'Crew of 4',
        Offset(s.width / 2, s.height * 0.94),
        size: 22 * p,
      );
    }
  }

  @override
  bool shouldRepaint(_CrewPainter o) => o.t != t;
}

// ── 5. LEVEL UP: the biggest moment ────────────────────────────────────

/// The XP bar fills with suspense: fast, then it CRAWLS toward the edge and
/// HOLDS a beat at 98%. Then it breaks: flash, three screen-wide shock rings,
/// camera push, LEVEL 1 rolls to LEVEL 2 with weight, particles, a badge
/// slams in.
class _LevelPainter extends CustomPainter {
  _LevelPainter(this.t);
  final double t;

  double get _fill {
    final climax = introClimax[4];
    if (t >= climax) return 1.0;
    if (t < 0.08) return 0;
    if (t < 0.50) return _out((t - 0.08) / 0.42) * 0.9;
    if (t < 0.78) return 0.9 + 0.08 * ((t - 0.50) / 0.28); // the crawl
    return 0.98; // the held beat
  }

  @override
  void paint(Canvas c, Size s) {
    final climax = introClimax[4];
    final bt = (t - climax) / (1 - climax);
    final fill = _fill;
    final center = Offset(s.width / 2, s.height * 0.42);

    // Flash: the whole field blinks white for a moment.
    if (bt > 0 && bt < 0.18) {
      c.drawRect(
        Offset.zero & s,
        Paint()..color = V13.white.withValues(alpha: 0.6 * (1 - bt / 0.18)),
      );
    }

    // Bar.
    final barW = s.width - 8;
    final barY = s.height * 0.70;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(4, barY, barW, 32),
      const Radius.circular(16),
    );
    c.drawRRect(bar, Paint()..color = V13.white);
    c.save();
    c.clipRRect(bar);
    c.drawRect(
      Rect.fromLTWH(4, barY, barW * fill, 32),
      Paint()..color = V13.blue,
    );
    c.restore();
    c.drawRRect(bar, _line(3));

    // Number: counts up with the bar.
    final xp = (100 * (fill / 0.98).clamp(0.0, 1.0)).round();
    final xpSize = 22.0 * (t >= climax ? 1 + 0.4 * _bump(bt * 2.5) : 1);
    _textAt(
      c,
      '+${t >= climax ? 100 : math.min(98, xp)} XP',
      Offset(s.width / 2, barY + 62),
      size: xpSize,
    );

    // LEVEL: rolls with weight at the climax.
    final size = math.min(60.0, s.width * 0.17);
    final roll = _pop((t - climax) / 0.14);
    c.save();
    c.clipRect(Rect.fromLTWH(0, center.dy - size, s.width, size * 2));
    if (t < climax) {
      _textAt(c, 'LEVEL 1', center, size: size);
    } else {
      final slide = size * 1.4;
      // old leaves upward, new slams in from below, oversized then settles
      _textAt(
        c,
        'LEVEL 1',
        center.translate(0, -slide * roll),
        size: size * (1 - 0.1 * roll),
      );
      _textAt(
        c,
        'LEVEL 2',
        center.translate(0, slide * (1 - roll)),
        size: size * (1 + 0.28 * (1 - roll)),
      );
    }
    c.restore();

    // Three screen-wide shock rings + particles.
    final reach = math.max(s.width, s.height) * 0.8;
    _ring(c, center, bt, from: 20, to: reach, width: 9, color: V13.white);
    _ring(
      c,
      center,
      _stag(bt, 0.10),
      from: 20,
      to: reach * 0.85,
      width: 6,
      color: V13.navy,
    );
    _ring(
      c,
      center,
      _stag(bt, 0.20),
      from: 20,
      to: reach * 0.7,
      width: 4,
      color: V13.blue,
    );
    _particles(
      c,
      center,
      bt,
      count: 28,
      reach: math.min(s.width, s.height) * 0.5,
      size: 8,
    );

    // Badge slam (after the number lands).
    final bb = (t - (climax + 0.08)) / 0.14;
    if (bb > 0) {
      final p = _pop(bb);
      final w = 150.0 * p, h = 40.0 * p;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width / 2, s.height * 0.12),
          width: w,
          height: h,
        ),
        Radius.circular(20 * p),
      );
      c.drawRRect(r, Paint()..color = V13.sun);
      c.drawRRect(r, _line(3));
      if (p > 0.7) {
        _textAt(
          c,
          'Day One badge',
          Offset(s.width / 2, s.height * 0.12),
          size: 15 * p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.t != t;
}

/// Soft, flat background shapes that drift slowly behind the pages (depth
/// without shadows), parallaxed by the page position and the slow [drift].
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
