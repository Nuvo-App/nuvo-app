import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tokens.dart';

/// Nuvo-branded QR code in the "connected rounded lines" style: adjacent
/// dark modules in a row or column merge into continuous bars with fully
/// rounded ends, isolated modules are rounded squares, the finder eyes are a
/// thick rounded-square ring around a large circle, and a circular cutout in
/// the centre holds the official logo graphic
/// (`assets/branding/nuvo_logo_graphic.png`) on the card itself — no tile.
///
/// Error correction H; the cutout is sized by [holeFraction] (share of the
/// QR width) and was verified to decode with multiple decoders at full and
/// half size (see test/v13/nuvo_qr_scan_test.dart).
class V13NuvoQr extends StatelessWidget {
  const V13NuvoQr({
    super.key,
    required this.data,
    this.size = 240,
    this.holeFraction = defaultHoleFraction,
  });

  final String data;
  final double size;
  final double holeFraction;

  /// Largest circle that still decoded reliably in the scan check.
  static const double defaultHoleFraction = 0.30;

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final image = QrImage(code);
    final hole = size * holeFraction;
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
              painter: NuvoQrPainter(image: image, holeFraction: holeFraction),
            ),
            SizedBox.square(
              // The logo is a touch wider than tall; inside the circle's
              // inscribed square with a sliver of breathing room.
              dimension: hole * 0.78,
              child: Image.asset(
                'assets/branding/nuvo_logo_graphic.png',
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

/// Paints the rounded-liquid QR. Public so the scan test can render it
/// without the asset.
class NuvoQrPainter extends CustomPainter {
  NuvoQrPainter({
    required this.image,
    this.holeFraction = V13NuvoQr.defaultHoleFraction,
    this.color = V13.navy,
  });

  final QrImage image;
  final double holeFraction;
  final Color color;

  bool _inFinder(int r, int c, int n) =>
      (r < 8 && c < 8) || (r < 8 && c >= n - 8) || (r >= n - 8 && c < 8);

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final m = size.width / n;
    final centre = Offset(size.width / 2, size.height / 2);
    // Clear ring of white padding around the logo: drop any module whose
    // square touches the circle grown by half a module.
    final clearR = size.width * holeFraction / 2 + m * 0.5;

    bool dark(int r, int c) {
      if (r < 0 || c < 0 || r >= n || c >= n) return false;
      if (_inFinder(r, c, n)) return false;
      if (!image.isDark(r, c)) return false;
      final cx = (c + .5) * m, cy = (r + .5) * m;
      // Nearest point of the module square to the centre.
      final nx = (centre.dx).clamp(c * m, (c + 1) * m);
      final ny = (centre.dy).clamp(r * m, (r + 1) * m);
      final d = (Offset(nx, ny) - centre).distance;
      if (d < clearR) return false;
      return cx >= 0 && cy >= 0;
    }

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    final full = Radius.circular(m / 2);
    // One path, filled once — separate draws leave anti-aliased hairline
    // seams where neighbouring modules meet.
    final path = Path();
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!dark(r, c)) continue;
        final left = dark(r, c - 1), right = dark(r, c + 1);
        final up = dark(r - 1, c), down = dark(r + 1, c);
        final rect = Rect.fromLTWH(c * m, r * m, m, m);
        if (!left && !right && !up && !down) {
          // Isolated module: a rounded square.
          path.addRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(m * 0.32)),
          );
          continue;
        }
        // Each corner is rounded only where neither adjoining side
        // continues — runs fuse into bars with fully round ends.
        path.addRRect(
          RRect.fromRectAndCorners(
            // Square sides overlap their neighbour a hair so the union has
            // no sub-pixel gaps.
            Rect.fromLTRB(
              rect.left - (left ? 0.5 : 0),
              rect.top - (up ? 0.5 : 0),
              rect.right + (right ? 0.5 : 0),
              rect.bottom + (down ? 0.5 : 0),
            ),
            topLeft: (up || left) ? Radius.zero : full,
            topRight: (up || right) ? Radius.zero : full,
            bottomLeft: (down || left) ? Radius.zero : full,
            bottomRight: (down || right) ? Radius.zero : full,
          ),
        );
      }
    }
    canvas.drawPath(path, paint);

    void eye(int row, int col) {
      final o = Offset(col * m, row * m);
      final stroke = m * 1.15;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            o.dx + stroke / 2,
            o.dy + stroke / 2,
            m * 7 - stroke,
            m * 7 - stroke,
          ),
          Radius.circular(m * 2.1),
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..isAntiAlias = true,
      );
      canvas.drawCircle(o + Offset(m * 3.5, m * 3.5), m * 1.75, paint);
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  @override
  bool shouldRepaint(NuvoQrPainter old) =>
      old.image != image || old.holeFraction != holeFraction;

  /// Module count for [data] at level H — the lowest version that fits.
  static int moduleCountFor(String data) => QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.H),
  ).moduleCount;
}
