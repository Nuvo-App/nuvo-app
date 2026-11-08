import 'dart:convert';

import 'package:uuid/uuid.dart';

// Persistence backend: JSON file in app documents on native, localStorage on
// web. Same conditional-import pattern as secure_token_store.dart.
import '_analytics_kv_io.dart'
    if (dart.library.html) '_analytics_kv_web.dart'
    as kv;

/// Install-scoped analytics persistence — the "Help improve Nuvo" opt-in flag
/// and the anonymous install id PostHog reports as its distinct id.
///
/// Follows the FirstUseStore contract: [ensureLoaded] runs once at launch
/// (main awaits it before runApp so the first frame sees the persisted
/// choice), every read/write failure is swallowed — a corrupt store must
/// never block launch, it just falls back to defaults (enabled, fresh id).
class AnalyticsStore {
  AnalyticsStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _memoryOnly = false,
       _read = read ?? kv.readAnalyticsPrefs,
       _write = write ?? kv.writeAnalyticsPrefs;

  /// In-memory store for tests — never touches disk.
  AnalyticsStore.memory()
    : _memoryOnly = true,
      _read = (() async => null),
      _write = ((_) async {});

  final bool _memoryOnly;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  static const _uuid = Uuid();

  bool _loaded = false;
  bool _enabled = true;
  String? _distinctId;

  bool get enabled => _enabled;

  /// The anonymous install id — generated once on first launch, then stable.
  /// It is deliberately NOT derived from account, device, or name.
  String get distinctId => _distinctId ??= _uuid.v4();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _read();
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _enabled = decoded['enabled'] != false;
          final id = decoded['distinctId'];
          if (id is String && id.isNotEmpty) _distinctId = id;
        }
      }
    } catch (_) {
      // Swallow — defaults are safe.
    }
    _distinctId ??= _uuid.v4();
    // Persist eagerly so the generated id is durable even if the process
    // dies before the first toggle.
    await _persist();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _persist();
  }

  Future<void> _persist() async {
    if (_memoryOnly) return;
    try {
      await _write(
        jsonEncode({'enabled': _enabled, 'distinctId': _distinctId}),
      );
    } catch (_) {
      // Persistence failure is not worth a crash — the choice just reverts.
    }
  }
}
