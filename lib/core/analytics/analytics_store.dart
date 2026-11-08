import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/data/_ls_stub.dart'
    if (dart.library.html) '../../features/auth/data/_ls_web.dart' as ls;

/// Install-scoped analytics persistence — the "Help improve Nuvo" opt-in flag
/// and the anonymous install id PostHog reports as its distinct id.
///
/// The distinct id lives in flutter_secure_storage under `anon_id` — a random
/// UUID, deliberately NOT derived from account, device, or name. The opt-in
/// flag sits beside it under `nuvo_analytics_enabled`. On the web preview the
/// same two keys land in localStorage.
///
/// Follows the FirstUseStore contract: [ensureLoaded] runs once at launch
/// (main awaits it before runApp so the first frame sees the persisted
/// choice — nothing starts before consent is resolved), every read/write
/// failure is swallowed — a corrupt store must never block launch, it just
/// falls back to defaults (enabled, fresh id).
class AnalyticsStore {
  AnalyticsStore({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
    Future<void> Function(String key)? delete,
  }) : _memoryOnly = false,
       _read = read ?? _defaultRead,
       _write = write ?? _defaultWrite,
       _delete = delete ?? _defaultDelete;

  /// In-memory store for tests — never touches disk or the keychain.
  AnalyticsStore.memory()
    : _memoryOnly = true,
      _read = ((_) async => null),
      _write = ((_, _) async {}),
      _delete = ((_) async {});

  /// The anonymous install id — the one key the privacy model depends on.
  static const anonIdKey = 'anon_id';
  static const _enabledKey = 'nuvo_analytics_enabled';

  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<String?> _defaultRead(String key) =>
      kIsWeb ? Future.sync(() => ls.getItem(key)) : _secure.read(key: key);
  static Future<void> _defaultWrite(String key, String value) => kIsWeb
      ? Future.sync(() => ls.setItem(key, value))
      : _secure.write(key: key, value: value);
  static Future<void> _defaultDelete(String key) =>
      kIsWeb ? Future.sync(() => ls.removeItem(key)) : _secure.delete(key: key);

  final bool _memoryOnly;
  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;
  static const _uuid = Uuid();

  bool _loaded = false;
  bool _enabled = true;
  String? _distinctId;

  bool get enabled => _enabled;

  /// The anonymous install id — generated once on first launch, then stable.
  String get distinctId => _distinctId ??= _uuid.v4();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _enabled = (await _read(_enabledKey)) != 'false';
      final id = await _read(anonIdKey);
      if (id != null && id.isNotEmpty) _distinctId = id;
    } catch (_) {
      // Swallow — defaults are safe.
    }
    _distinctId ??= _uuid.v4();
    // Persist eagerly so the generated id is durable even if the process
    // dies before the first toggle.
    await _persistEnabled();
    await _persistId();
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _persistEnabled();
  }

  /// Wipe the install id — reset() rotates the anonymous identity.
  Future<void> rotateDistinctId() async {
    _distinctId = _uuid.v4();
    await _persistId();
  }

  Future<void> _persistEnabled() async {
    if (_memoryOnly) return;
    try {
      await _write(_enabledKey, _enabled ? 'true' : 'false');
    } catch (_) {}
  }

  Future<void> _persistId() async {
    if (_memoryOnly) return;
    try {
      await _write(anonIdKey, _distinctId!);
    } catch (_) {}
  }

  /// Full wipe — sign-out/debug only; the next launch regenerates both keys.
  Future<void> clear() async {
    _distinctId = null;
    _enabled = true;
    try {
      await _delete(anonIdKey);
      await _delete(_enabledKey);
    } catch (_) {}
  }
}
