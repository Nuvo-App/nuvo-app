import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tokens.dart';

/// Nuvo-branded QR code. Round navy dots, rounded finder eyes with a blue
/// core, and a clean cutout in the middle that holds the bare Nuvo mark
/// (`assets/branding/nuvo_mark.png`) — no modules are drawn under it, so the
/// logo isn't pasted on top of the code. Uses error-correction level H so the
/// cutout stays well inside what scanners can recover.
class V13NuvoQr extends StatelessWidget {
  const V13NuvoQr({super.key, required this.data, this.size = 240});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final image = QrImage(code);
    final count = image.moduleCount;
    final hole = _NuvoQrPainter.holeModules(count);
    final module = size / count;
    final holeSide = hole * module;
    return Semantics(
      label: 'Nuvo QR code',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _NuvoQrPainter(image: image),
            ),
            SizedBox.square(
              dimension: holeSide * 0.78,
              child: Image.asset(
                'assets/branding/nuvo_mark.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NuvoQrPainter extends CustomPainter {
  _NuvoQrPainter({required this.image});

  final QrImage image;

  /// Side of the centre cutout in modules — odd, so it centres exactly, and
  /// about a fifth of the code (well under level-H's 30% recovery budget).
  static int holeModules(int count) {
    var h = (count * 0.24).round();
    if (h.isEven) h += 1;
    return math.max(h, 7);
  }

  bool _inFinder(int r, int c, int n) =>
      (r < 8 && c < 8) || (r < 8 && c >= n - 8) || (r >= n - 8 && c < 8);

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final m = size.width / n;
    final hole = holeModules(n);
    final start = (n - hole) ~/ 2;
    final end = start + hole;

    final dot = Paint()
      ..color = V13.navy
      ..isAntiAlias = true;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (_inFinder(r, c, n)) continue;
        if (r >= start && r < end && c >= start && c < end) continue;
        if (!image.isDark(r, c)) continue;
        canvas.drawCircle(
          Offset((c + .5) * m, (r + .5) * m),
          m * .43,
          dot,
        );
      }
    }

    void eye(int row, int col) {
      final o = Offset(col * m, row * m);
      final ring = Paint()
        ..color = V13.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = m;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx + m / 2, o.dy + m / 2, m * 6, m * 6),
          Radius.circular(m * 2),
        ),
        ring,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(o.dx + m * 2, o.dy + m * 2, m * 3, m * 3),
          Radius.circular(m * 1.1),
        ),
        Paint()..color = V13.blue,
      );
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  @override
  bool shouldRepaint(_NuvoQrPainter old) => old.image != image;
}
