import 'dart:convert';

import 'package:web/web.dart';

const _key = 'nuvo_verifier_releases';

Future<Map<String, dynamic>> readVerifierReleases() async {
  try {
    final raw = window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  } catch (_) {
    return {};
  }
}

Future<void> writeVerifierReleases(Map<String, dynamic> value) async {
  try {
    window.localStorage.setItem(_key, jsonEncode(value));
  } catch (_) {
    // A cache write must never block a valid release from being used.
  }
}
