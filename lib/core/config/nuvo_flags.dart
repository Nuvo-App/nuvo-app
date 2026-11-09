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

  /// Onboarding v2 — the guided first-run flow (Part 0+ build, spec:
  /// docs/redesign/onboarding-v2-spec.md). Compile-time only: off in every
  /// shipped build until the flow is complete; a dev/QA build opts in with
  /// `--dart-define=NUVO_ONBOARDING_V2=true`. When on, the v2 flow replaces
  /// the old onboarding destinations via router-level redirects —
  /// auth_gate's flags-only rule and the flag-off path are untouched.
  static const bool onboardingV2 =
      String.fromEnvironment('NUVO_ONBOARDING_V2') == 'true';

  /// Teach Nuvo / custom camera-counted movements. Off until the worker says on.
  static final ValueNotifier<bool> customMotion = ValueNotifier<bool>(false);

  /// Crew groups. Off until the worker advertises them, so a build that
  /// ships before (or after a rollback of) the backend never shows a dead entry.
  static final ValueNotifier<bool> crews = ValueNotifier<bool>(false);

  static bool get customMotionOn => customMotion.value;

  /// [token] (optional access token) lets the server turn the feature on for
  /// specific accounts only.
  static Future<void> load({http.Client? client, String? token}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(
            Uri.parse('$kNuvoApiBase/config'),
            headers: {
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body is! Map) return;
      customMotion.value = body['custom_motion'] == true;
      crews.value = body['crews'] == true;
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
