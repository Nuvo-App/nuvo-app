import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/v13/tokens.dart';
import '../../../core/v13/widgets/v13_face.dart';
import '../../../core/v13/widgets/v13_nuvo_qr.dart';
import '../flow/onboarding_copy.dart';

/// The optional "Share my level" card, authored at 1080x1350 (4:5 portrait):
/// avatar, name, Level N, "Join me on Nuvo" and the personal invite in Nuvo
/// QR style. Pure widget — [captureLevelShareCard] turns it into a PNG.
class LevelShareCard extends StatelessWidget {
  const LevelShareCard({
    super.key,
    required this.name,
    required this.level,
    required this.inviteUrl,
    this.photoUrl,
  });

  static const double width = 1080;
  static const double height = 1350;

  final String name;
  final int level;
  final String inviteUrl;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: V13.blue,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: V13.white,
                shape: BoxShape.circle,
                border: Border.all(color: V13.navy, width: 8),
              ),
              child: V13Face(photoUrl: photoUrl, size: 300, name: name),
            ),
            const SizedBox(height: 48),
            Text(
              name,
              style: V13.title.copyWith(fontSize: 72, color: V13.white),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Text(
              'LEVEL $level',
              style: V13.hugeNumber.copyWith(fontSize: 168, color: V13.white),
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: V13.white,
                borderRadius: BorderRadius.circular(56),
                border: Border.all(color: V13.navy, width: 8),
                boxShadow: V13.hardShadow(x: 14, y: 14),
              ),
              child: V13NuvoQr(data: inviteUrl, size: 360),
            ),
            const SizedBox(height: 40),
            Text(
              ObCopy.levelUpShareLine,
              style: V13.title.copyWith(fontSize: 64, color: V13.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the [boundaryKey] boundary (which must wrap a [LevelShareCard]
/// at its natural 1080x1350) to PNG bytes at 1:1.
Future<Uint8List?> captureLevelShareCard(GlobalKey boundaryKey) async {
  final ro = boundaryKey.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary) return null;
  final image = await ro.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Writes [png] to the temp dir and opens the OS share sheet.
Future<void> shareLevelPng(Uint8List png, {Rect? origin}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/nuvo_level.png');
  await file.writeAsBytes(png, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png')],
    text: ObCopy.levelUpShareLine,
    sharePositionOrigin: origin,
  );
}
