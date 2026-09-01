import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Generic "human motion space" anchors used only for the separation margin in
/// [TaughtMotionV2.matchEncoded] — how much closer an attempt is to the taught
/// motion than to unrelated motion. These are NOT recognized movement types.
///
/// Built offline from `tools/motion_v2` synthetic motions and bundled as
/// `assets/models/motion_v2_background.json` (schema `motion_v2_background/2`).
class MotionV2Background {
  MotionV2Background._(this.protos);

  /// N descriptor vectors, each `dimRep` long (mean-pooled encoder reps).
  final List<Float32List> protos;

  static const String assetPath = 'assets/models/motion_v2_background.json';
  static List<Float32List>? _cached;

  /// Loads (once) and caches the background bank. Returns `null` if the asset is
  /// missing — the matcher then simply skips the separation-rescue path.
  static Future<List<Float32List>?> load() async {
    if (_cached != null) return _cached;
    try {
      final raw = await rootBundle.loadString(assetPath);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _cached = [
        for (final p in j['protos'] as List)
          Float32List.fromList([for (final x in p as List) (x as num).toDouble()])
      ];
      return _cached;
    } catch (_) {
      return null;
    }
  }

  static void resetForTest() => _cached = null;
}
