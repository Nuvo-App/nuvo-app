/// An immutable remote model release for System B — the general Nuvo Motion
/// Intelligence model (and auxiliary model families). Independent of System A
/// verifier releases: a verifier decides HOW a movement is verified; a model
/// release is the artifact the generic runtime loads to understand motion.
///
/// Remote payloads are declarative only — a release describes an artifact and
/// the contract the shipped binary already knows how to execute. Anything
/// outside the contract (unknown runtime family, unknown schema version, a
/// newer minimum app build) is rejected by the client before download.
class MotionModelRelease {
  const MotionModelRelease({
    required this.modelReleaseId,
    required this.modelVersion,
    required this.modelFamily,
    required this.runtimeFamily,
    required this.inputSchemaVersion,
    required this.artifactSha256,
    this.outputSchemaVersion,
    this.preprocessingVersion,
    this.normalizationVersion,
    this.embeddingSchemaVersion,
    this.minimumAppBuild,
    this.artifactKey,
    this.artifactSizeBytes,
    this.status = 'production',
    this.evaluationId,
    this.supportedMotionIds = const [],
    this.metadata = const {},
  });

  final String modelReleaseId;
  final String modelVersion;
  final String modelFamily;
  final String runtimeFamily;
  final int inputSchemaVersion;
  final int? outputSchemaVersion;
  final int? preprocessingVersion;
  final int? normalizationVersion;
  final int? embeddingSchemaVersion;
  final int? minimumAppBuild;
  final String? artifactKey;
  final String artifactSha256;
  final int? artifactSizeBytes;
  final String status;
  final String? evaluationId;
  final List<String> supportedMotionIds;
  final Map<String, dynamic> metadata;

  /// Cache identity: a release is only interchangeable when version and
  /// checksum both match.
  String get cacheKey => '$modelVersion:$artifactSha256';

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Motion model release missing "$key".');
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int || value < 1) {
      throw FormatException('Motion model release missing "$key".');
    }
    return value;
  }

  static int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    return value is int ? value : null;
  }

  factory MotionModelRelease.fromJson(Map<String, dynamic> json) {
    return MotionModelRelease(
      modelReleaseId: _requiredString(json, 'modelReleaseId'),
      modelVersion: _requiredString(json, 'modelVersion'),
      modelFamily: _requiredString(json, 'modelFamily'),
      runtimeFamily: _requiredString(json, 'runtimeFamily'),
      inputSchemaVersion: _requiredInt(json, 'inputSchemaVersion'),
      artifactSha256: _requiredString(json, 'artifactSha256').toLowerCase(),
      outputSchemaVersion: _optionalInt(json, 'outputSchemaVersion'),
      preprocessingVersion: _optionalInt(json, 'preprocessingVersion'),
      normalizationVersion: _optionalInt(json, 'normalizationVersion'),
      embeddingSchemaVersion: _optionalInt(json, 'embeddingSchemaVersion'),
      minimumAppBuild: _optionalInt(json, 'minimumAppBuild'),
      artifactKey: json['artifactKey'] is String ? json['artifactKey'] as String : null,
      artifactSizeBytes: _optionalInt(json, 'artifactSizeBytes'),
      status: json['status'] is String ? json['status'] as String : 'production',
      evaluationId: json['evaluationId'] is String ? json['evaluationId'] as String : null,
      supportedMotionIds: json['supportedMotionIds'] is List
          ? [for (final m in json['supportedMotionIds'] as List) if (m is String) m]
          : const [],
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'modelReleaseId': modelReleaseId,
        'modelVersion': modelVersion,
        'modelFamily': modelFamily,
        'runtimeFamily': runtimeFamily,
        'inputSchemaVersion': inputSchemaVersion,
        'outputSchemaVersion': outputSchemaVersion,
        'preprocessingVersion': preprocessingVersion,
        'normalizationVersion': normalizationVersion,
        'embeddingSchemaVersion': embeddingSchemaVersion,
        'minimumAppBuild': minimumAppBuild,
        'artifactKey': artifactKey,
        'artifactSha256': artifactSha256,
        'artifactSizeBytes': artifactSizeBytes,
        'status': status,
        'evaluationId': evaluationId,
        'supportedMotionIds': supportedMotionIds,
        'metadata': metadata,
      };

  /// The contract the installed binary was reviewed with. A release can only
  /// be adopted when every declared contract field is one this build knows
  /// how to execute — anything else requires an app update, not a download.
  bool isCompatibleWith({
    required String runtimeFamily,
    required int inputSchemaVersion,
    required int outputSchemaVersion,
    required int appBuild,
  }) {
    if (this.runtimeFamily != runtimeFamily) return false;
    if (this.inputSchemaVersion != inputSchemaVersion) return false;
    final out = this.outputSchemaVersion;
    if (out != null && out != outputSchemaVersion) return false;
    final min = minimumAppBuild;
    if (min != null && min > appBuild) return false;
    return true;
  }
}

/// The general-motion encoder contract shipped in this binary: MotionBERT
/// `pose[1,T≤243,17,3]` (H36M) → `rep[1,T,17,512]`. Any release declaring a
/// different runtime or schema cannot be executed by this build.
const String kMotionV2EncoderFamily = 'motion_v2_encoder';
const String kMotionV2EncoderRuntimeFamily = 'motionbert_rep_v1';
const int kMotionV2EncoderInputSchema = 1;
const int kMotionV2EncoderOutputSchema = 1;
const int kMotionV2EncoderEmbeddingSchema = 1;

/// Identity of the model bundled in the app asset — the launch baseline the
/// remote plane can improve on. Reported in diagnostics when no remote
/// release is installed.
const String kBundledMotionEncoderVersion = 'motion_v2_encoder_release_action_fp16_bundled';
