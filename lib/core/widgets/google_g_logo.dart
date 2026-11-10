import 'package:flutter/material.dart';

/// The official four-colour Google "G" (Google's own 48x48 artwork), drawn
/// with a CustomPainter so no asset or SVG package is needed. Never tinted.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Google',
    child: CustomPaint(size: Size.square(size), painter: _GPainter()),
  );
}

const _paths = <(Color, String)>[
  (
    Color(0xFFEA4335),
    'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
        '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
  ),
  (
    Color(0xFF4285F4),
    'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
        '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
  ),
  (
    Color(0xFFFBBC05),
    'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
        'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
  ),
  (
    Color(0xFF34A853),
    'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
        '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
  ),
];

/// Minimal SVG path parser: M m L l H h V v C c S s Z z (all the G needs).
Path parseSvgPath(String d) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)',
  ).allMatches(d).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  double x = 0, y = 0, sx = 0, sy = 0, cx = 0, cy = 0;
  var cmd = 'M';
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'[A-Za-z]').hasMatch(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = n() + (rel ? x : 0);
        y = n() + (rel ? y : 0);
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L';
      case 'L':
        x = n() + (rel ? x : 0);
        y = n() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'H':
        x = n() + (rel ? x : 0);
        path.lineTo(x, y);
      case 'V':
        y = n() + (rel ? y : 0);
        path.lineTo(x, y);
      case 'C':
        final x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
        final x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
      case 'S':
        final x1 = 2 * x - cx, y1 = 2 * y - cy;
        final x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        cx = x2;
        cy = y2;
        x = ex;
        y = ey;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
    }
  }
  return path;
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, d) in _paths) {
      canvas.drawPath(parseSvgPath(d), Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GPainter old) => false;
}
