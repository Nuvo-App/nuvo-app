import '../ai/remote_verifier_spec.dart';
import '../data/motion_catalog.dart';
import '../data/motion_package_installer.dart';
import '../data/motion_package_store.dart';
import '../data/verifier_release.dart';
import 'motion_activity.dart';
import 'motion_activity_catalog.dart';

/// Why an activity can or cannot run a camera-verified proof on this build.
/// Deliberately finer-grained than a boolean — "needs a download" is not the
/// same as "the bytes failed integrity", and neither is "the control plane
/// turned it off".
enum MotionCapabilityStatus {
  /// Runnable with no package assets (native engine or spec-only release).
  available,

  /// Runnable — all required assets verified on disk.
  installed,

  /// Runnable after a package download; the caller should start
  /// [MotionPackageInstaller.ensureInstalled].
  installPending,

  /// The release needs an engine or capability this build does not own.
  /// Never fixable client-side — only an app update or a different release.
  incompatibleRuntime,

  /// A previous install attempt failed integrity or the manifest was
  /// rejected. The package is refused; the release may be re-attempted when
  /// the control plane publishes corrected bytes.
  integrityFailed,

  /// The control plane is not currently offering this activity (no channel
  /// assignment, rollout bucket miss, or the release was disabled).
  disabled,

  /// The manifest names a required asset that could not be fetched.
  missingRequiredAsset,

  /// No verifier path at all — unknown activity, manual goal, or a spec that
  /// failed strict parsing.
  unresolved,
}

/// The stable app-facing answer to "can this activity be camera-verified?".
/// Agent-facing code must consume THIS — never package JSON internals.
class MotionVerifierCapability {
  const MotionVerifierCapability({
    required this.activityId,
    required this.status,
    this.engineType,
    this.releaseId,
    this.releaseVersion,
    this.reason,
  });

  /// The server-stable activity ID, echoed verbatim — including IDs this
  /// build has no compiled enum for. Never normalized or substituted.
  final String activityId;
  final MotionCapabilityStatus status;

  /// Wire engine name (`state_machine_v1`, `sequence_match_v1`, ...) when a
  /// release was resolved.
  final String? engineType;
  final String? releaseId;

  /// Release semver when known (display/diagnostics only).
  final String? releaseVersion;

  /// Coarse diagnostic tag for unsupported states.
  final String? reason;

  bool get supported =>
      status == MotionCapabilityStatus.available ||
      status == MotionCapabilityStatus.installed ||
      status == MotionCapabilityStatus.installPending;

  bool get installed => status == MotionCapabilityStatus.installed;

  bool get installPending =>
      status == MotionCapabilityStatus.installPending;
}

/// Answers "can this activity be camera-verified on this build right now?"
/// by combining the control-plane catalog, the release's declared
/// compatibility, and the on-device package install state.
///
/// The query is stable-shaped: callers pass an activityId (+ optional
/// measurement type) and never touch spec/package JSON.
class MotionCapabilityService {
  const MotionCapabilityService({
    MotionPackageStore store = const MotionPackageStore(),
  }) : _store = store;

  final MotionPackageStore _store;

  /// Resolves the capability for [activityId] from the catalog snapshot.
  /// [measurementType] narrows ambiguity when the same ID could serve both a
  /// rep and a duration race; a mismatch is reported as unresolved rather
  /// than silently verified under the wrong metric.
  Future<MotionVerifierCapability> check({
    required String activityId,
    String? measurementType,
    required MotionCatalogSnapshot? catalog,
    required Set<String> capabilities,
    required Map<String, VerifierRelease> releases,
  }) async {
    // Compiled native motions are available with no remote involvement.
    final compiled = MotionActivityType.fromBackendValue(activityId);
    if (compiled != null &&
        compiled != MotionActivityType.remote &&
        supportedMotionActivityTypes.contains(compiled)) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.available,
        engineType: 'native_v1',
      );
    }

    final activity = _catalogActivity(catalog, activityId);
    if (activity == null) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.disabled,
        reason: 'not_in_catalog',
      );
    }
    if (activity.availability != 'supported') {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.disabled,
        reason: 'availability_${activity.availability}',
      );
    }
    if (measurementType != null &&
        activity.measurementType != measurementType) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.unresolved,
        reason: 'measurement_type_mismatch',
      );
    }
    if (!activity.requiredCapabilities.every(capabilities.contains)) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.incompatibleRuntime,
        releaseId: activity.releaseId,
        engineType: activity.engineType,
        reason: 'missing_capability',
      );
    }

    final release =
        activity.releaseId == null ? null : releases[activity.releaseId!];
    if (release == null) {
      // Catalog advertises a release that is not retrievable — treated as
      // disabled rather than guessed at.
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.disabled,
        releaseId: activity.releaseId,
        engineType: activity.engineType,
        reason: 'release_unavailable',
      );
    }
    if (activity.releaseChecksum != null &&
        release.checksum != activity.releaseChecksum) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.integrityFailed,
        releaseId: release.id,
        engineType: release.engineType,
        reason: 'release_checksum_mismatch',
      );
    }

    return _releaseStatus(
      activityId: activityId,
      release: release,
      catalogEngine: activity.engineType,
    );
  }

  /// Resolves the capability for a race's already-pinned spec — the same
  /// shape as [check], sourced from the session-pinned payload instead of
  /// the catalog.
  Future<MotionVerifierCapability> checkResolvedSpec(
    RemoteVerifierSpec spec, {
    String? releaseVersion,
  }) =>
      _releaseStatus(
        activityId: spec.activityId,
        spec: spec,
        releaseVersion: releaseVersion,
      );

  Future<MotionVerifierCapability> _releaseStatus({
    required String activityId,
    VerifierRelease? release,
    RemoteVerifierSpec? spec,
    String? catalogEngine,
    String? releaseVersion,
  }) async {
    RemoteVerifierSpec? parsed = spec;
    if (parsed == null && release != null) {
      if (release.engineType == 'native_v1') {
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.available,
          engineType: 'native_v1',
          releaseId: release.id,
          releaseVersion: releaseVersion,
        );
      }
      if (release.engineType == 'object_composition_v1') {
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.available,
          engineType: release.engineType,
          releaseId: release.id,
          releaseVersion: releaseVersion,
        );
      }
      try {
        parsed = RemoteVerifierSpec.fromJson(release.spec);
      } on RemoteVerifierSpecException {
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.incompatibleRuntime,
          engineType: release.engineType,
          releaseId: release.id,
          releaseVersion: releaseVersion,
          reason: 'spec_rejected',
        );
      }
    }
    if (parsed == null) {
      return MotionVerifierCapability(
        activityId: activityId,
        status: MotionCapabilityStatus.unresolved,
        reason: 'no_spec',
      );
    }

    final engineId = parsed.engine.backendValue;
    switch (await _packageStatus(parsed)) {
      case MotionPackageStatus.specOnly:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.available,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
        );
      case MotionPackageStatus.installed:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.installed,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
        );
      case MotionPackageStatus.installPending:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.installPending,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
        );
      case MotionPackageStatus.integrityFailed:
      case MotionPackageStatus.invalidManifestAsset:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.integrityFailed,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
          reason: 'package_integrity',
        );
      case MotionPackageStatus.missingRequiredAsset:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.missingRequiredAsset,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
          reason: 'package_asset_missing',
        );
      case MotionPackageStatus.storeError:
        return MotionVerifierCapability(
          activityId: activityId,
          status: MotionCapabilityStatus.missingRequiredAsset,
          engineType: engineId,
          releaseId: parsed.releaseId,
          releaseVersion: releaseVersion,
          reason: 'store_error',
        );
    }
  }

  /// Read-only package status — mirrors the installer's own check without
  /// starting a download.
  Future<MotionPackageStatus> _packageStatus(RemoteVerifierSpec spec) async {
    final manifest = spec.package;
    if (manifest == null || manifest.requiredAssets.isEmpty) {
      return MotionPackageStatus.specOnly;
    }
    final installed = await _store.read(spec.activityId, spec.releaseId);
    return installed != null
        ? MotionPackageStatus.installed
        : MotionPackageStatus.installPending;
  }

  static MotionCatalogActivity? _catalogActivity(
    MotionCatalogSnapshot? catalog,
    String activityId,
  ) {
    if (catalog == null) return null;
    for (final activity in catalog.activities) {
      if (activity.id == activityId) return activity;
    }
    return null;
  }
}
