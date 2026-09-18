import 'dart:convert';

import 'motion_capabilities.dart';
import 'motion_catalog.dart';
import 'motion_catalog_cache.dart';
import 'race_api.dart';
import 'verifier_release_repository.dart';

class MotionCatalogRepository {
  MotionCatalogRepository(
    this._api,
    this._cache, {
    VerifierReleaseRepository? releases,
  }) : _releases = releases;

  final RaceApi _api;
  final MotionCatalogCache _cache;
  final VerifierReleaseRepository? _releases;
  MotionCatalogSnapshot? _snapshot;
  Future<MotionCatalogSnapshot>? _inFlight;

  MotionCatalogSnapshot get bundled => MotionCatalogSnapshot.bundled();

  Future<MotionCatalogSnapshot> load({bool force = false}) {
    final inFlight = _inFlight;
    if (!force && inFlight != null) return inFlight;
    final request = _load(force: force);
    _inFlight = request;
    request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
    return request;
  }

  Future<MotionCatalogSnapshot> _load({required bool force}) async {
    if (_snapshot != null && !force) return _snapshot!;

    final cached = await _readCache();
    if (cached != null) _snapshot = cached;

    try {
      final fetched = await _api.getMotionCatalog(etag: cached?.etag);
      if (fetched.notModified && cached != null) {
        await _releases?.prefetch(cached);
        return cached;
      }
      if (fetched.json == null) return _snapshot ?? bundled;
      final next = MotionCatalogSnapshot.fromJson(
        fetched.json!,
        etag: fetched.etag,
      );
      _snapshot = next;
      await _cache.write(jsonEncode(next.toJson()));
      await _releases?.prefetch(next);
      return next;
    } catch (_) {
      // Last-known-good first; the bundled catalog is the first-launch and
      // corrupted-cache fallback. Never erase a valid previous snapshot.
      return _snapshot ?? bundled;
    }
  }

  Future<MotionCatalogSnapshot?> _readCache() async {
    final raw = await _cache.read();
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return MotionCatalogSnapshot.fromJson(
        json,
        etag: json['etag'] as String?,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Set<String> get capabilities => MotionCapabilities.current();
}
