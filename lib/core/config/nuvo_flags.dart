import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../features/races/ai/motion_v2/engine/demo_clip.dart' as clip;
import '../network/api_base.dart';

/// Server-controlled switches (`GET /config` on the worker). Fail-closed: if
/// the worker is unreachable or silent, custom AI movements stay hidden.
class NuvoFlags {
  NuvoFlags._();

  /// Teach Nuvo / custom camera-counted movements. Off until the worker says on.
  static final ValueNotifier<bool> customMotion = ValueNotifier<bool>(false);

  static bool get customMotionOn => customMotion.value;

  static Future<void> load({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('$kNuvoApiBase/config'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body is! Map) return;
      customMotion.value = body['custom_motion'] == true;
      final settle = body['clip_settle_factor'];
      if (settle is num && settle >= 1.0 && settle <= 2.0) {
        clip.clipSettleFactor = settle.toDouble();
      }
    } catch (_) {
      // Keep the safe defaults.
    } finally {
      if (client == null) c.close();
    }
  }
}
