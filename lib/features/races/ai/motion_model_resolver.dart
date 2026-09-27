import 'dart:typed_data';

import '../data/motion_capabilities.dart';
import '../data/race_api.dart';
import 'motion_model_artifact_integrity.dart';
import 'motion_model_release.dart';

/// Downloads a remote model release's artifact and proves it against the
/// release checksum before it can reach the runtime.
class MotionV2ModelSource {
  const MotionV2ModelSource({
    required this.resolveModel,
    required this.fetchArtifact,
    int? appBuild,
    this.channel = 'stable',
  }) : appBuild = appBuild ?? 0;

  /// Channel-resolution hook — returns the raw `model` JSON or null.
  final Future<Map<String, dynamic>?> Function(String family) resolveModel;

  /// Artifact fetch hook — returns bytes + version/sha headers.
  final Future<MotionModelArtifactFetch> Function(String modelVersion)
      fetchArtifact;

  /// The build's own number. `local` dev builds are treated as newest so a
  /// `minimumAppBuild` gate never strangles development.
  final int appBuild;
  final String channel;

  /// Resolved build number with the dev fallback applied.
  int get effectiveAppBuild =>
      appBuild > 0 ? appBuild : (int.tryParse(MotionCapabilities.appBuild) ?? 1 << 30);

  /// The release the channel currently assigns this app, or null. Any
  /// malformed or incompatible release resolves to null so callers fall back
  /// to last-known-good/bundled — bad metadata can never replace a model.
  Future<MotionModelRelease?> resolve(String family) async {
    final json = await resolveModel(family);
    if (json == null) return null;
    final release = MotionModelRelease.fromJson(json);
    if (release.modelFamily != family) {
      throw const FormatException('Resolved model is for a different family.');
    }
    if (!release.isCompatibleWith(
      runtimeFamily: kMotionV2EncoderRuntimeFamily,
      inputSchemaVersion: kMotionV2EncoderInputSchema,
      outputSchemaVersion: kMotionV2EncoderOutputSchema,
      appBuild: effectiveAppBuild,
    )) {
      return null;
    }
    return release;
  }

  /// Download + checksum-verify the release artifact.
  Future<VettedMotionModelArtifact> fetchVerified(
      MotionModelRelease release) async {
    final fetch = await fetchArtifact(release.modelVersion);
    final bytes = fetch.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Model artifact body was empty.');
    }
    return MotionModelArtifactIntegrity.verify(
      requestedModelVersion: release.modelVersion,
      bytes: Uint8List.fromList(bytes),
      artifactModelVersion: fetch.modelVersion,
      expectedSha256: release.artifactSha256,
    );
  }
}
