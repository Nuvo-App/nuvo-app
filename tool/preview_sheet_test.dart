// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/presentation/widgets/nuvo_character_painter.dart';
import 'package:nuvo/features/races/presentation/widgets/preset_movement_demos.dart';

void main() {
  testWidgets('sheet', (tester) async {
    final only = (Platform.environment['PREVIEW_TYPES'] ?? '').split(',').where((e) => e.isNotEmpty).toSet();
    final types = MotionActivityType.values
        .where((t) => movementDemoForType(t) != null && (only.isEmpty || only.contains(t.name)))
        .toList();
    final outPath = Platform.environment['PREVIEW_OUT'] ?? '/home/server1/.claude/jobs/972235da/tmp/previews.png';
    const cw = 210.0, ch = 150.0, cols = 5;
    final w = cw * cols, h = (ch + 22) * types.length;
    await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final sc = double.tryParse(Platform.environment['PREVIEW_SCALE'] ?? '') ?? 1.0;
      c.scale(sc);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
      for (var r = 0; r < types.length; r++) {
        final demo = movementDemoForType(types[r])!;
        final y0 = r * (ch + 22);
        final tp = TextPainter(text: TextSpan(text: types[r].name, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
        tp.paint(c, Offset(6, y0 + 3));
        for (var i = 0; i < cols; i++) {
          final t = i / (cols - 1) * 0.999;
          c.save();
          c.translate(i * cw, y0 + 22);
          c.clipRect(Rect.fromLTWH(0, 0, cw, ch));
          c.drawRect(Rect.fromLTWH(0, 0, cw, ch), Paint()..color = const Color(0xFFF2F2F2));
          NuvoCharacterPainter(pose: demo.poseAt(t), view: demo.sideView ? NuvoCharacterView.side : NuvoCharacterView.front).paint(c, const Size(cw, ch));
          c.restore();
        }
      }
      final img = await rec.endRecording().toImage((w * (double.tryParse(Platform.environment['PREVIEW_SCALE'] ?? '') ?? 1.0)).toInt(), (h * (double.tryParse(Platform.environment['PREVIEW_SCALE'] ?? '') ?? 1.0)).toInt());
      final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
      File(outPath).writeAsBytesSync(bytes.buffer.asUint8List());
    });
  });
}
