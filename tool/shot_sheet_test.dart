// ignore_for_file: avoid_print
// Combines screenshots <prefix>_<w>x<h>.png from SHEET_IN into one image,
// phones side by side at the same scale (so size differences are visible).
//   SHEET_IN=dir SHEET_PREFIX=profile SHEET_OUT=out.png \
//     flutter test tool/shot_sheet_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sheet', (tester) async {
    final env = Platform.environment;
    final dir = env['SHEET_IN']!;
    final prefix = env['SHEET_PREFIX']!;
    final out = env['SHEET_OUT']!;
    final scale = double.tryParse(env['SHEET_SCALE'] ?? '') ?? 0.6;
    await tester.runAsync(() async {
      final files = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) {
            final n = f.uri.pathSegments.last;
            return n.startsWith('${prefix}_') && n.endsWith('.png');
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final imgs = <ui.Image>[];
      for (final f in files) {
        final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
        imgs.add((await codec.getNextFrame()).image);
      }
      const gap = 16.0;
      var w = gap, h = 0.0;
      for (final i in imgs) {
        w += i.width * scale + gap;
        if (i.height * scale > h) h = i.height * scale;
      }
      h += 2 * gap;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF888888));
      var x = gap;
      for (final i in imgs) {
        final dst = Rect.fromLTWH(x, gap, i.width * scale, i.height * scale);
        c.drawImageRect(
          i,
          Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
        x += i.width * scale + gap;
      }
      final img = await rec.endRecording().toImage(w.ceil(), h.ceil());
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      File(out).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
