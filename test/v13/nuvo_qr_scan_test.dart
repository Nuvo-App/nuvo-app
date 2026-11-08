// Renders the Nuvo QR at a realistic invite URL so it can be decoded by
// external scanners. With QR_DIR set, writes PNGs (white card + quiet zone)
// for each cutout size; otherwise just checks it renders without errors.
//
//   QR_DIR=/tmp/qr flutter test test/v13/nuvo_qr_scan_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/core/v13/v13.dart';

const _url =
    'https://nuvo-api.getnuvoapp.workers.dev/j/WMpwCaU9RwZ2IOlrNyWZdMCSZ8DYTHhRHpYyXSNYAJS';

void main() {
  for (final frac in [0.30, 0.28, 0.26, 0.24]) {
    testWidgets('Nuvo QR renders with a ${(frac * 100).round()}% cutout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(40),
                child: V13NuvoQr(data: _url, size: 300, holeFraction: frac),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/branding/nuvo_logo_graphic.png'),
          tester.element(find.byType(V13NuvoQr)),
        );
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dir = Platform.environment['QR_DIR'];
      if (dir == null || dir.isEmpty) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(dir).createSync(recursive: true);
        File(
          '$dir/qr_${(frac * 100).round()}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }

  test('payload stays at the lowest version that fits', () {
    // 85-char invite URL at level H → version 9 (53 modules), the lowest
    // that fits; a shorter link is the only way to fewer modules.
    expect(NuvoQrPainter.moduleCountFor(_url), lessThanOrEqualTo(53));
  });
}
