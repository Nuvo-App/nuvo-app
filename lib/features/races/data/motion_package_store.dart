import 'dart:typed_data';

import 'motion_package_store_io.dart'
    if (dart.library.html) 'motion_package_store_web.dart'
    as platform;

/// Byte storage for installed remote motion packages.
///
/// A package is release-pinned: `activityId/releaseId` uniquely determines
/// its contents because release IDs are immutable and checksum-bound. The
/// store exposes only verified, whole writes — there is no API for partial
/// mutation.
///
/// Layout (IO): `{appSupport}/motion_packages/{activityId}/{releaseId}/`
/// with `manifest.json` + `assets/{assetId}`; installs stage under
/// `{releaseId}.staging/` and promote via atomic rename.
class MotionPackageStore {
  const MotionPackageStore();

  /// A fully-verified package record, or null when nothing valid is
  /// installed under [releaseId].
  Future<InstalledMotionPackage?> read(String activityId, String releaseId) =>
      platform.readPackage(activityId, releaseId);

  /// Stages one already-downloaded asset. Staging is private to the
  /// installer — nothing outside [promote] can observe it.
  Future<void> stageAsset(
    String activityId,
    String releaseId,
    String assetId,
    Uint8List bytes,
  ) =>
      platform.stageAsset(activityId, releaseId, assetId, bytes);

  /// Persists the install record inside the staging area so the record and
  /// its assets promote together.
  Future<void> stageManifest(
    String activityId,
    String releaseId,
    Map<String, dynamic> record,
  ) =>
      platform.stageManifest(activityId, releaseId, record);

  /// Atomically publishes the staging area. Either the full new package
  /// appears or the previous verified package stays — never a mix.
  Future<void> promote(String activityId, String releaseId) =>
      platform.promotePackage(activityId, releaseId);

  /// Bytes of one installed asset, or null when absent/corrupt.
  Future<Uint8List?> assetBytes(
    String activityId,
    String releaseId,
    String assetId,
  ) =>
      platform.packageAssetBytes(activityId, releaseId, assetId);

  /// All installed package records (for pruning and launch sweeps).
  Future<List<InstalledMotionPackage>> all() => platform.allPackages();

  /// Removes an installed package. Pin policy lives in the installer — the
  /// store itself stays policy-free.
  Future<void> remove(String activityId, String releaseId) =>
      platform.removePackage(activityId, releaseId);

  /// Deletes every abandoned staging area. Safe on launch — a staging dir is
  /// by definition an install that never completed.
  Future<void> sweepStaging() => platform.sweepStaging();
}

/// The verified on-disk shape of one installed package.
class InstalledMotionPackage {
  const InstalledMotionPackage({
    required this.activityId,
    required this.releaseId,
    required this.releaseChecksum,
    required this.assets,
    required this.installedAtMs,
    required this.totalBytes,
  });

  final String activityId;
  final String releaseId;
  final String releaseChecksum;
  final List<InstalledAsset> assets;
  final int installedAtMs;
  final int totalBytes;

  static InstalledMotionPackage? tryParse(
    Object? raw, {
    required String activityId,
    required String releaseId,
  }) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    for (final key in json.keys) {
      if (!_keys.contains(key)) return null;
    }
    if (json['releaseId'] != releaseId || json['activityId'] != activityId) {
      return null;
    }
    final checksum = json['releaseChecksum'];
    // The control plane carries `sha256:<hex>`; the binding is opaque to the
    // store but must still look like a real checksum, never arbitrary text.
    if (checksum is! String ||
        !RegExp(r'^(sha256:)?[0-9a-f]{64}$').hasMatch(checksum)) {
      return null;
    }
    final rawAssets = json['assets'];
    if (rawAssets is! List) return null;
    final assets = <InstalledAsset>[];
    var total = 0;
    for (final entry in rawAssets) {
      if (entry is! Map) return null;
      final asset = InstalledAsset.tryParse(entry);
      if (asset == null) return null;
      total += asset.bytes;
      assets.add(asset);
    }
    final installed = json['installedAtMs'];
    return InstalledMotionPackage(
      activityId: activityId,
      releaseId: releaseId,
      releaseChecksum: checksum,
      assets: assets,
      installedAtMs: installed is num ? installed.toInt() : 0,
      totalBytes: total,
    );
  }

  Map<String, dynamic> toJson() => {
    'activityId': activityId,
    'releaseId': releaseId,
    'releaseChecksum': releaseChecksum,
    'assets': [for (final asset in assets) asset.toJson()],
    'installedAtMs': installedAtMs,
  };

  static const _keys = {
    'activityId',
    'releaseId',
    'releaseChecksum',
    'assets',
    'installedAtMs',
  };
}

/// One verified asset inside an installed package record.
class InstalledAsset {
  const InstalledAsset({
    required this.id,
    required this.type,
    required this.sha256,
    required this.bytes,
    required this.required,
  });

  final String id;
  final String type;
  final String sha256;
  final int bytes;
  final bool required;

  static InstalledAsset? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = json['id'];
    final type = json['type'];
    final sha256 = json['sha256'];
    final bytes = json['bytes'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 64 ||
        type is! String ||
        !MotionPackageAssetTypes.contains(type) ||
        sha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        bytes is! num ||
        bytes <= 0) {
      return null;
    }
    return InstalledAsset(
      id: id,
      type: type,
      sha256: sha256,
      bytes: bytes.toInt(),
      required: json['required'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'sha256': sha256,
    'bytes': bytes,
    'required': required,
  };
}

/// Allowlisted asset types — mirrored from `motion_package.dart` so the
/// store layer can validate records without importing the spec parser.
const MotionPackageAssetTypes = {
  'preview_v1',
  'motion_v2_spec_v1',
  'onnx_model',
  'test_vectors_v1',
};
