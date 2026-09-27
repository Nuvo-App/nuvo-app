import 'dart:typed_data';

import 'motion_model_release.dart';
import 'motion_model_store_io.dart'
    if (dart.library.html) 'motion_model_store_web.dart' as platform;

/// A verified remote model artifact persisted for last-known-good use.
///
/// Bytes are only ever written after `MotionModelArtifactIntegrity` passes, so
/// anything readable from this store already matched its release checksum.
class CachedMotionModel {
  const CachedMotionModel({required this.release, required this.bytes});

  final MotionModelRelease release;
  final Uint8List bytes;
}

/// Last-known-good store for remote model artifacts.
///
/// Priority contract the encoder relies on:
///   compatible remote release → this store → bundled asset.
/// All failures (read, parse, missing file, checksum drift) degrade silently
/// to the next tier — a corrupt store can never take Motion down.
class MotionModelStore {
  Future<void> persist(String family, MotionModelRelease release, Uint8List bytes) =>
      platform.persistMotionModel(family, release, bytes);

  Future<CachedMotionModel?> read(
      String family, String modelVersion, String sha256) async {
    final hit = await platform.readMotionModel(family, modelVersion, sha256);
    if (hit == null) return null;
    return CachedMotionModel(release: hit.release, bytes: hit.bytes);
  }

  /// The most recently persisted verified release for a family — the
  /// last-known-good used when resolution or download fails.
  Future<CachedMotionModel?> lastKnownGood(String family) async {
    final hit = await platform.readLastKnownGoodMotionModel(family);
    if (hit == null) return null;
    return CachedMotionModel(release: hit.release, bytes: hit.bytes);
  }
}
