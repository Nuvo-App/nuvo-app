import 'dart:typed_data';

import 'motion_model_release.dart';

// Web has no Motion V2 path — the store is a no-op so the bundled asset
// contract degrades safely.
Future<void> persistMotionModel(
  String family,
  MotionModelRelease release,
  Uint8List bytes,
) async {}

Future<({MotionModelRelease release, Uint8List bytes})?> readMotionModel(
  String family,
  String modelVersion,
  String sha256,
) async =>
    null;

Future<({MotionModelRelease release, Uint8List bytes})?>
    readLastKnownGoodMotionModel(String family) async =>
        null;
