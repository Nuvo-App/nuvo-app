import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saves the current frame as `$SHOTS_DIR/<name>.png` when the SHOTS_DIR
/// environment variable is set; a no-op otherwise, so normal test runs are
/// unaffected. Used to LOOK at screens across phone sizes:
///
///   SHOTS_DIR=/tmp/shots flutter test test/at_a_glance_profile_test.dart
Future<void> shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHOTS_DIR'];
  if (dir == null || dir.isEmpty) return;
  await tester.runAsync(() async {
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer;
    if (layer is! OffsetLayer) return;
    final image = await layer.toImage(renderView.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Loads the real Manrope + Material Icons glyphs so screenshots show real
/// text instead of the test font's blocks. Call from `setUpAll`. A no-op when
/// SHOTS_DIR is unset (normal runs keep their existing font setup).
Future<void> loadShotFonts() async {
  final dir = Platform.environment['SHOTS_DIR'];
  if (dir == null || dir.isEmpty) return;
  final bytes = ByteData.sublistView(
    await File('test/fonts/Manrope-VariableFont_wght.ttf').readAsBytes(),
  );
  for (final weight in [200, 300, 400, 500, 600, 700, 800]) {
    final family = 'Manrope_${weight == 400 ? 'regular' : weight}';
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

  // google_fonts asks the asset bundle for Manrope-<Weight>.ttf; serve the
  // bundled variable font for every weight so it never touches the network.
  final manifest =
      const StandardMessageCodec().decodeMessage(
            await rootBundle.load('AssetManifest.bin'),
          )
          as Map<Object?, Object?>;
  for (final v in [
    'ExtraLight',
    'Light',
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    final key = 'test/fonts/Manrope-$v.ttf';
    manifest[key] = [
      {'asset': key},
    ];
  }
  final encoded = const StandardMessageCodec().encodeMessage(manifest);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'AssetManifest.bin') return encoded;
        if (key.startsWith('test/fonts/Manrope')) return bytes;
        return null;
      });
}
