import 'verifier_release.dart';
import 'verifier_release_cache.dart';
import 'motion_catalog.dart';
import 'race_api.dart';

class VerifierReleaseRepository {
  VerifierReleaseRepository(this._api, this._cache);

  final RaceApi _api;
  final VerifierReleaseCache _cache;
  Map<String, VerifierRelease>? _releases;

  Future<VerifierRelease?> load(
    String releaseId, {
    String? expectedChecksum,
    bool force = false,
  }) async {
    final releases = await _read();
    final cached = releases[releaseId];
    if (!force &&
        cached != null &&
        (expectedChecksum == null || cached.checksum == expectedChecksum)) {
      return cached;
    }

    try {
      final response = await _api.getMotionRelease(
        releaseId,
        etag: cached == null ? null : '"${cached.id}:${cached.checksum}"',
      );
      if (response.notModified && cached != null) return cached;
      if (response.json == null) return cached;
      final release = VerifierRelease.fromJson(response.json!);
      if (release.id != releaseId ||
          (expectedChecksum != null && release.checksum != expectedChecksum)) {
        return cached;
      }
      releases[release.id] = release;
      await _cache.write({
        for (final entry in releases.entries) entry.key: entry.value.toJson(),
      });
      return release;
    } catch (_) {
      return cached;
    }
  }

  Future<void> prefetch(MotionCatalogSnapshot snapshot) async {
    final entries = snapshot.activities
        .where(
          (activity) =>
              activity.releaseId != null && activity.releaseChecksum != null,
        )
        .toList();
    await Future.wait([
      for (final activity in entries)
        load(activity.releaseId!, expectedChecksum: activity.releaseChecksum),
    ]);
  }

  Future<Map<String, VerifierRelease>> _read() async {
    final existing = _releases;
    if (existing != null) return existing;
    final raw = await _cache.read();
    final parsed = <String, VerifierRelease>{};
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      try {
        final release = VerifierRelease.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        parsed[release.id] = release;
      } catch (_) {
        // Invalid cache entries are ignored; other valid releases survive.
      }
    }
    _releases = parsed;
    return parsed;
  }
}
