/// MotionPackage V1 — the OTA envelope that rides inside an immutable
/// verifier release (`spec_json.package` + `spec_json.activity`).
///
/// Packages are data, never code. Everything here is allowlisted and bounded;
/// engines interpret these descriptors — they are never executed themselves.
/// See docs/motion_runtime/motion_package_v1.md.
library;

/// Server-owned activity identity delivered inside a release so a motion the
/// app was not compiled with can still present camera framing, instructions,
/// and measurement semantics without a [MotionActivityDefinition].
class RemoteActivityInfo {
  const RemoteActivityInfo({
    required this.displayName,
    required this.measurementType,
    required this.defaultTarget,
    required this.preferredCameraView,
    required this.instructions,
    this.unit,
    this.coachingTextActive,
    this.coachingTextIncomplete,
  });

  /// Human name shown anywhere the motion is referenced.
  final String displayName;

  /// 'repetitions' or 'duration'.
  final String measurementType;

  final int defaultTarget;

  /// 'front' | 'side' | 'front_or_angle' — camera framing hint only.
  final String preferredCameraView;

  final List<String> instructions;

  /// Plural unit label for progress text ("reach taps", "seconds").
  final String? unit;
  final String? coachingTextActive;
  final String? coachingTextIncomplete;

  bool get isDuration => measurementType == 'duration';

  static RemoteActivityInfo? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    for (final key in json.keys) {
      if (!_allowedKeys.contains(key)) return null;
    }
    final displayName = _string(json['displayName']);
    final measurement = _string(json['measurementType']);
    if (displayName == null || measurement == null) return null;
    if (measurement != 'repetitions' && measurement != 'duration') return null;
    final camera = _string(json['preferredCameraView']) ?? 'front';
    if (!{'front', 'side', 'front_or_angle'}.contains(camera)) return null;
    final target = json['defaultTarget'];
    final defaultTarget = target is num && target >= 1 && target <= 100000
        ? target.toInt()
        : 1;
    final instructions = <String>[];
    final rawInstructions = json['instructions'];
    if (rawInstructions is List) {
      if (rawInstructions.length > 6) return null;
      for (final entry in rawInstructions) {
        final text = _string(entry);
        if (text == null) return null;
        instructions.add(text);
      }
    }
    return RemoteActivityInfo(
      displayName: displayName,
      measurementType: measurement,
      defaultTarget: defaultTarget,
      preferredCameraView: camera,
      instructions: instructions,
      unit: _string(json['unit']),
      coachingTextActive: _string(json['coachingTextActive']),
      coachingTextIncomplete: _string(json['coachingTextIncomplete']),
    );
  }

  static const _allowedKeys = {
    'displayName',
    'measurementType',
    'defaultTarget',
    'preferredCameraView',
    'instructions',
    'unit',
    'coachingTextActive',
    'coachingTextIncomplete',
  };

  static String? _string(Object? value) => value is String &&
          value.trim().isNotEmpty &&
          value.length <= 140
      ? value.trim()
      : null;
}

/// One downloadable, content-addressed asset inside a package manifest.
class MotionPackageAsset {
  const MotionPackageAsset({
    required this.id,
    required this.type,
    required this.sha256,
    required this.url,
    required this.bytes,
    required this.required,
  });

  final String id;
  final String type;
  final String sha256;
  final String url;
  final int bytes;
  final bool required;

  static const types = {
    'preview_v1',
    'motion_v2_spec_v1',
    'onnx_model',
    'test_vectors_v1',
  };

  /// Per-type download caps — the client refuses assets over these even if
  /// the manifest declares a larger size.
  static const maxBytes = {
    'preview_v1': 256 * 1024,
    'motion_v2_spec_v1': 512 * 1024,
    'onnx_model': 50 * 1024 * 1024,
    'test_vectors_v1': 2 * 1024 * 1024,
  };
}

/// The asset manifest inside a release spec. `assets` may be empty — a
/// spec-only package installs entirely from the immutable release payload.
class MotionPackageManifest {
  const MotionPackageManifest({
    required this.packageSchemaVersion,
    required this.assets,
  });

  final int packageSchemaVersion;
  final List<MotionPackageAsset> assets;

  static const maxAssets = 8;
  static const maxTotalBytes = 64 * 1024 * 1024;

  List<MotionPackageAsset> get requiredAssets =>
      assets.where((asset) => asset.required).toList();

  /// Parses and validates a `package` block. Returns null for absent or
  /// malformed manifests — callers treat null as "spec-only release" only
  /// when the engine does not require assets.
  static MotionPackageManifest? tryParse(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    for (final key in json.keys) {
      if (key != 'packageSchemaVersion' && key != 'assets') return null;
    }
    final version = json['packageSchemaVersion'];
    if (version != 1) return null;
    final rawAssets = json['assets'];
    if (rawAssets is! List || rawAssets.length > maxAssets) return null;
    final assets = <MotionPackageAsset>[];
    var totalBytes = 0;
    final seenIds = <String>{};
    for (final entry in rawAssets) {
      if (entry is! Map) return null;
      final asset = Map<String, dynamic>.from(entry);
      for (final key in asset.keys) {
        if (!_assetKeys.contains(key)) return null;
      }
      final id = _string(asset['id'], 64);
      final type = _string(asset['type'], 64);
      final sha256 = _string(asset['sha256'], 80)?.toLowerCase();
      final url = _string(asset['url'], 512);
      final bytesRaw = asset['bytes'];
      final required = asset['required'] == true;
      if (id == null ||
          type == null ||
          sha256 == null ||
          url == null ||
          bytesRaw is! num) {
        return null;
      }
      if (!MotionPackageAsset.types.contains(type)) return null;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) return null;
      final bytes = bytesRaw.toInt();
      final cap = MotionPackageAsset.maxBytes[type]!;
      if (bytes <= 0 || bytes > cap) return null;
      if (!seenIds.add(id)) return null;
      totalBytes += bytes;
      if (totalBytes > maxTotalBytes) return null;
      assets.add(
        MotionPackageAsset(
          id: id,
          type: type,
          sha256: sha256,
          url: url,
          bytes: bytes,
          required: required,
        ),
      );
    }
    return MotionPackageManifest(
      packageSchemaVersion: 1,
      assets: assets,
    );
  }

  static const _assetKeys = {
    'id',
    'type',
    'sha256',
    'url',
    'bytes',
    'required',
  };

  static String? _string(Object? value, int max) =>
      value is String && value.trim().isNotEmpty && value.length <= max
          ? value.trim()
          : null;
}
