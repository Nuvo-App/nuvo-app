import 'package:flutter/material.dart';

/// Nuvo's custom hand-drawn icon set, ported from the design prototype's
/// inline SVG `<symbol>` defs. Rendered with [CustomPainter] so no new
/// package (e.g. flutter_svg) is required — the exact path data is parsed
/// from the same "d" strings the prototype uses, at a 24x24 viewBox.
enum NuvoIconType {
  flag,
  crown,
  fire,
  trendUp,
  check,
  checkCircle,
  camera,
  hand,
  users,
  user,
  plus,
  lock,
  bolt,
  bell,
  close,
  arrow,
  back,
}

class NuvoIcon extends StatelessWidget {
  const NuvoIcon(this.type, {super.key, this.size = 20, this.color});

  final NuvoIconType type;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;
    return CustomPaint(
      size: Size.square(size),
      painter: _NuvoIconPainter(_specs[type]!, resolved),
    );
  }
}

// ── Shape primitives ───────────────────────────────────────────────────────────

sealed class _Shape {
  const _Shape();
}

class _FillPath extends _Shape {
  const _FillPath(this.d);
  final String d;
}

class _StrokePath extends _Shape {
  const _StrokePath(this.d, {this.width = 1.8, this.cap = StrokeCap.round});
  final String d;
  final double width;
  final StrokeCap cap;
}

class _FillRRect extends _Shape {
  const _FillRRect(this.rect, this.radius);
  final Rect rect;
  final double radius;
}

class _StrokeRRect extends _Shape {
  const _StrokeRRect(this.rect, this.radius, {this.width = 1.7});
  final Rect rect;
  final double radius;
  final double width;
}

class _FillCircle extends _Shape {
  const _FillCircle(this.center, this.r);
  final Offset center;
  final double r;
}

class _StrokeCircle extends _Shape {
  const _StrokeCircle(this.center, this.r, {this.width = 1.8});
  final Offset center;
  final double r;
  final double width;
}

// ── Icon specs — path data copied verbatim from the prototype's <defs> ────────

final Map<NuvoIconType, List<_Shape>> _specs = {
  NuvoIconType.flag: const [
    _FillRRect(Rect.fromLTWH(4.5, 2, 2, 20), 1),
    _FillPath('M6.5 3h11l-2.3 3.6L17.5 10h-11z'),
  ],
  NuvoIconType.crown: const [
    _FillPath('M3 18.5h18l-1.3-8-4.2 3.3L12 6l-3.5 7.8-4.2-3.3L3 18.5z'),
  ],
  NuvoIconType.fire: const [
    _FillPath(
      'M12 2c1.1 3-1.7 4.2-1.9 6.8a2.6 2.6 0 0 0 5.2.2c0-.9-.4-1.6-.8-2.2 '
      '1 .5 2.5 2.1 2.5 5A6 6 0 1 1 5.5 12c0-3.6 2.1-5.6 3-6.7-.3 1.2.4 2 1.2 2'
      'C10.6 5.6 10.6 3.6 12 2z',
    ),
  ],
  NuvoIconType.trendUp: const [
    _StrokePath('M4 17l6-6 4 4 6-8', width: 2.1),
    _StrokePath('M15 6h5v5', width: 2.1),
  ],
  NuvoIconType.check: const [
    _StrokePath('M4.5 12.5l5 5L20 6.5', width: 2.2),
  ],
  NuvoIconType.checkCircle: const [
    _StrokeCircle(Offset(12, 12), 9, width: 1.8),
    _StrokePath('M8 12.3l2.6 2.6L16 9.3', width: 1.8),
  ],
  NuvoIconType.camera: const [
    _StrokeRRect(Rect.fromLTWH(3, 7.5, 18, 12), 2.4, width: 1.7),
    _StrokePath('M9 7.5l1.1-1.8h3.8l1.1 1.8', width: 1.7, cap: StrokeCap.butt),
    _StrokeCircle(Offset(12, 13.4), 3, width: 1.7),
  ],
  NuvoIconType.hand: const [
    _FillPath(
      'M8.6 13V4.6a1.3 1.3 0 0 1 2.6 0V10h.5V3.4a1.3 1.3 0 0 1 2.6 0V10h.5V5.2a1.3 1.3 0 0 1 2.6 0V14'
      'c0 3.1-2.2 5.6-5.5 5.6h-.9c-2.6 0-4.3-1.8-4.3-4.2v-2.2a1 1 0 0 1 2-.3z',
    ),
  ],
  NuvoIconType.users: const [
    _FillCircle(Offset(9, 8), 3.3),
    _FillPath('M2.8 20a6.2 6.2 0 0 1 12.4 0z'),
    _FillCircle(Offset(17, 9.2), 2.5),
    _FillPath('M14.6 20a5 5 0 0 1 8-4.3v.2c0 .5-.3 1-.8 1.1a11 11 0 0 0-3.4 1.6c-.3.2-.5.6-.5 1z'),
  ],
  NuvoIconType.user: const [
    _FillCircle(Offset(12, 8), 4.1),
    _FillPath('M3.6 20a8.4 8.4 0 0 1 16.8 0z'),
  ],
  NuvoIconType.plus: const [
    _FillPath('M11 4.2h2V11h6.8v2H13v6.8h-2V13H4.2v-2H11z'),
  ],
  NuvoIconType.lock: const [
    _FillRRect(Rect.fromLTWH(5, 11, 14, 9.5), 2.3),
    _StrokePath('M8 11V8.3a4 4 0 0 1 8 0V11', width: 1.9, cap: StrokeCap.butt),
  ],
  NuvoIconType.bolt: const [
    _FillPath('M13 2 4 14h6l-1 8 9-12h-6z'),
  ],
  NuvoIconType.bell: const [
    _StrokePath(
      'M12 3a5.5 5.5 0 0 0-5.5 5.5v3.2c0 .7-.3 1.4-.8 1.9L4.5 15h15l-1.2-1.4a2.7 2.7 0 0 1-.8-1.9V8.5A5.5 5.5 0 0 0 12 3z',
      width: 1.8,
      cap: StrokeCap.butt,
    ),
    _StrokePath('M9.5 18a2.5 2.5 0 0 0 5 0', width: 1.8),
  ],
  NuvoIconType.close: const [
    _StrokePath('M5 5l14 14M19 5L5 19', width: 2.1),
  ],
  NuvoIconType.arrow: const [
    _StrokePath('M4 12h16M13 5l7 7-7 7', width: 2.1),
  ],
  NuvoIconType.back: const [
    _StrokePath('M20 12H4M11 5l-7 7 7 7', width: 2.1),
  ],
};

// ── SVG path-data parser ────────────────────────────────────────────────────────

final RegExp _tokenPattern = RegExp(r'[MmLlHhVvCcAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');

/// Parses the subset of the SVG path "d" mini-language used by Nuvo's icon
/// set (M/m L/l H/h V/v C/c A/a Z/z) into a Flutter [Path], preserving
/// implicit command repeats and the "5.2.2" decimal-shorthand SVG allows.
Path parseSvgPath(String d) {
  final tokens = _tokenPattern.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();

  var i = 0;
  var curX = 0.0, curY = 0.0;
  var startX = 0.0, startY = 0.0;
  var cmd = '';

  bool isCommand(String s) => s.length == 1 && RegExp(r'[A-Za-z]').hasMatch(s);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      cmd = tokens[i];
      i++;
    }
    switch (cmd) {
      case 'M':
        curX = next();
        curY = next();
        path.moveTo(curX, curY);
        startX = curX;
        startY = curY;
        cmd = 'L';
      case 'm':
        curX += next();
        curY += next();
        path.moveTo(curX, curY);
        startX = curX;
        startY = curY;
        cmd = 'l';
      case 'L':
        curX = next();
        curY = next();
        path.lineTo(curX, curY);
      case 'l':
        curX += next();
        curY += next();
        path.lineTo(curX, curY);
      case 'H':
        curX = next();
        path.lineTo(curX, curY);
      case 'h':
        curX += next();
        path.lineTo(curX, curY);
      case 'V':
        curY = next();
        path.lineTo(curX, curY);
      case 'v':
        curY += next();
        path.lineTo(curX, curY);
      case 'C':
        {
          final x1 = next(), y1 = next();
          final x2 = next(), y2 = next();
          final x = next(), y = next();
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
        }
      case 'c':
        {
          final x1 = curX + next(), y1 = curY + next();
          final x2 = curX + next(), y2 = curY + next();
          final x = curX + next(), y = curY + next();
          path.cubicTo(x1, y1, x2, y2, x, y);
          curX = x;
          curY = y;
        }
      case 'A':
      case 'a':
        {
          final rx = next(), ry = next();
          final rotation = next();
          final largeArc = next() != 0;
          final sweep = next() != 0;
          double x, y;
          if (cmd == 'A') {
            x = next();
            y = next();
          } else {
            x = curX + next();
            y = curY + next();
          }
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
          curX = x;
          curY = y;
        }
      case 'Z':
      case 'z':
        path.close();
        curX = startX;
        curY = startY;
      default:
        i++;
    }
  }
  return path;
}

class _NuvoIconPainter extends CustomPainter {
  _NuvoIconPainter(this.shapes, this.color);

  final List<_Shape> shapes;
  final Color color;

  static final Map<String, Path> _pathCache = {};

  Path _cached(String d) => _pathCache.putIfAbsent(d, () => parseSvgPath(d));

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final shape in shapes) {
      switch (shape) {
        case _FillPath(:final d):
          canvas.drawPath(_cached(d), fillPaint);
        case _FillRRect(:final rect, :final radius):
          canvas.drawRRect(RRect.fromRectXY(rect, radius, radius), fillPaint);
        case _FillCircle(:final center, :final r):
          canvas.drawCircle(center, r, fillPaint);
        case _StrokePath(:final d, :final width, :final cap):
          canvas.drawPath(
            _cached(d),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..strokeCap = cap
              ..strokeJoin = StrokeJoin.round
              ..isAntiAlias = true,
          );
        case _StrokeRRect(:final rect, :final radius, :final width):
          canvas.drawRRect(
            RRect.fromRectXY(rect, radius, radius),
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..isAntiAlias = true,
          );
        case _StrokeCircle(:final center, :final r, :final width):
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = width
              ..isAntiAlias = true,
          );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NuvoIconPainter oldDelegate) => oldDelegate.color != color || oldDelegate.shapes != shapes;
}
