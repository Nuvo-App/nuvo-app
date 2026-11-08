import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Confetti burst — a CustomPainter celebration for joining, accepting or
/// earning. Palette colors only; no package.
///
/// [showV13Confetti] fires it as a full-screen overlay that removes itself;
/// the widget can also be placed inline (plays once on mount).
class V13Confetti extends StatefulWidget {
  const V13Confetti({
    super.key,
    this.particleCount = 80,
    this.duration = const Duration(milliseconds: 1600),
    this.onDone,
  });

  final int particleCount;
  final Duration duration;
  final VoidCallback? onDone;

  @override
  State<V13Confetti> createState() => _V13ConfettiState();
}

/// Fires a confetti burst over [context]'s overlay. Fire-and-forget — the
/// entry removes itself when the burst settles.
void showV13Confetti(BuildContext context) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(child: V13Confetti(onDone: () => entry.remove())),
    ),
  );
  overlay.insert(entry);
}

class _V13ConfettiState extends State<V13Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final List<_Particle> _particles;

  static const _colors = [
    V13.blue,
    V13.coral,
    V13.sun,
    V13.lilac,
    V13.mint,
    V13.gold,
    V13.navy,
  ];

  bool _started = false;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(
      widget.particleCount,
      (_) => _Particle(
        angle: rng.nextDouble() * 2 * math.pi,
        speed: 0.55 + rng.nextDouble() * 0.75,
        upBias: 0.55 + rng.nextDouble() * 0.65,
        color: _colors[rng.nextInt(_colors.length)],
        size: 5 + rng.nextDouble() * 6,
        spin: (rng.nextDouble() - 0.5) * 9,
        sway: rng.nextDouble() * 2 * math.pi,
        swayAmp: 8 + rng.nextDouble() * 26,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onDone?.call(),
      );
    } else {
      _ctrl.forward().then((_) => widget.onDone?.call());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(_particles, _ctrl.value),
        size: Size.infinite,
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.upBias,
    required this.color,
    required this.size,
    required this.spin,
    required this.sway,
    required this.swayAmp,
  });

  final double angle;
  final double speed;
  final double upBias;
  final Color color;
  final double size;
  final double spin;
  final double sway;
  final double swayAmp;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final origin = Offset(size.width / 2, size.height * 0.28);
    final paint = Paint();
    for (final p in particles) {
      final life = t.clamp(0.0, 1.0);
      final dx =
          math.cos(p.angle) * p.speed * life * size.width * 0.55 +
          math.sin(life * 4 + p.sway) * p.swayAmp * life;
      final dy =
          (math.sin(p.angle) * p.speed - p.upBias) * life * size.height * 0.55 +
          life * life * size.height * 0.85;
      final opacity = life < 0.75 ? 1.0 : (1 - (life - 0.75) / 0.25);
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * life * math.pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.62,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
