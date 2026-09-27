import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/network/api_base.dart';
import '../ai/motion_model_artifact_integrity.dart';
import '../ai/remote_verifier_spec.dart';
import 'motion_package.dart';
import 'motion_package_store.dart';

/// How runnable a release's package is on this install.
///
/// These states are deliberately distinct — a release that merely needs a
/// download is not the same as one whose bytes failed integrity, and the UI
/// and diagnostics need to tell them apart.
enum MotionPackageStatus {
  /// No package block, or a manifest with no required assets — the inline
  /// spec alone is sufficient.
  specOnly,

  /// Every required asset is verified on disk under the pinned release dir.
  installed,

  /// Required assets exist in the manifest but are not installed yet. The
  /// caller should kick off [MotionPackageInstaller.ensureInstalled].
  installPending,

  /// A declared required asset could not be fetched (network, 404, or the
  /// response never arrived complete).
  missingRequiredAsset,

  /// Downloaded bytes did not match the manifest — size, sha256, or the
  /// type's minimum sanity check. The package is refused.
  integrityFailed,

  /// The manifest declared a URL this build will not fetch (non-first-party
  /// host or malformed path) or an asset shape the parser never allows.
  invalidManifestAsset,

  /// The store itself failed (disk full, permission, etc.).
  storeError,
}

extension on MotionPackageStatus {
  bool get runnable =>
      this == MotionPackageStatus.specOnly ||
      this == MotionPackageStatus.installed;
}

/// Result of a completed (or refused) install attempt.
class MotionPackageInstallResult {
  const MotionPackageInstallResult({
    required this.status,
    this.package,
    this.failureReason,
  });

  final MotionPackageStatus status;
  final InstalledMotionPackage? package;

  /// Coarse diagnostic tag — never contains remote content, only the
  /// failure class (`checksum_mismatch`, `download_failed`, ...).
  final String? failureReason;

  bool get runnable => status.runnable;
}

/// Downloads package assets. Injected so tests can serve fixture bytes
/// without a socket; production wires [defaultMotionAssetDownloader].
typedef MotionAssetDownloader = Future<Uint8List?> Function(
  String url,
  int maxBytes,
);

/// Installs remote motion packages onto the device.
///
/// Lifecycle:
///   resolve spec → check installed record → stage each asset (byte cap →
///   sha256 → type sanity) → write install record into staging → atomic
///   promote → prune.
///
/// Invariants:
/// - A race NEVER sees a partially-installed package. Until [promote] the
///   staging area is invisible to `read`/`assetBytes`.
/// - A failed install leaves the previous verified package untouched.
/// - Release id + checksum uniquely determine bytes; a changed payload is a
///   new release directory, never in-place mutation.
/// - Optional assets (previews, test vectors) never block installation —
///   the production phone doesn't even download `test_vectors_v1`.
class MotionPackageInstaller {
  MotionPackageInstaller({
    MotionPackageStore? store,
    MotionAssetDownloader? downloader,
    this.nowMs,
  })  : _store = store ?? const MotionPackageStore(),
        _downloader = downloader ?? defaultMotionAssetDownloader;

  final MotionPackageStore _store;
  final MotionAssetDownloader _downloader;

  /// Injectable clock for tests.
  final int Function()? nowMs;

  /// Asset types the device skips entirely — promotion material that has no
  /// runtime purpose on a phone (test vectors are replayed by tooling, not
  /// by installed apps).
  static const skippedTypes = {'test_vectors_v1'};

  /// Cache policy.
  static const maxReleasesPerActivity = 2;
  static const maxCacheBytes = 128 * 1024 * 1024;

  final _inFlight = <String, Future<MotionPackageInstallResult>>{};
  final _pinned = <String>{};

  /// Marks a release's package as in use by an active verification session —
  /// pruning must never remove it while pinned.
  void pin(String releaseId) => _pinned.add(releaseId);

  void unpin(String releaseId) => _pinned.remove(releaseId);

  /// Launch-time hygiene: removes staging dirs left by a killed install and
  /// applies the cache policy. Call once early; it never throws.
  Future<void> startupSweep() async {
    await _store.sweepStaging();
    await prune();
  }

  /// The current install state for [spec] without starting a download.
  Future<MotionPackageStatus> status(RemoteVerifierSpec spec) async {
    final manifest = spec.package;
    if (manifest == null || _required(manifest).isEmpty) {
      return MotionPackageStatus.specOnly;
    }
    final installed = await _store.read(spec.activityId, spec.releaseId);
    return installed != null
        ? MotionPackageStatus.installed
        : MotionPackageStatus.installPending;
  }

  /// Installs [spec]'s package if needed. Idempotent and single-flighted —
  /// concurrent callers share one download. [releaseChecksum] is the
  /// session-pinned checksum — the installed record binds to it so a
  /// re-published release is never confused with the pinned bytes.
  Future<MotionPackageInstallResult> ensureInstalled(
    RemoteVerifierSpec spec, {
    required String releaseChecksum,
  }) {
    final manifest = spec.package;
    if (manifest == null || _required(manifest).isEmpty) {
      return Future.value(
        const MotionPackageInstallResult(
          status: MotionPackageStatus.specOnly,
        ),
      );
    }
    return _inFlight.putIfAbsent(
      spec.releaseId,
      // NB: the callback must not RETURN the removed future — whenComplete
      // would await the very future it lives on, deadlocking the install.
      () => _install(spec, manifest, releaseChecksum).whenComplete(() {
        _inFlight.remove(spec.releaseId);
      }),
    );
  }

  List<MotionPackageAsset> _required(MotionPackageManifest manifest) =>
      manifest.assets
          .where((a) => a.required && !skippedTypes.contains(a.type))
          .toList();

  List<MotionPackageAsset> _fetchable(MotionPackageManifest manifest) =>
      manifest.assets
          .where((a) => !skippedTypes.contains(a.type))
          .toList();

  Future<MotionPackageInstallResult> _install(
    RemoteVerifierSpec spec,
    MotionPackageManifest manifest,
    String releaseChecksum,
  ) async {
    // Already installed and intact — the fastest path is a record read.
    final existing = await _store.read(spec.activityId, spec.releaseId);
    if (existing != null &&
        existing.releaseChecksum == releaseChecksum &&
        _covers(existing, manifest)) {
      return MotionPackageInstallResult(
        status: MotionPackageStatus.installed,
        package: existing,
      );
    }

    // Stage every fetchable asset. A required-asset failure aborts the whole
    // install; an optional-asset failure is skipped with a diagnostic.
    final staged = <InstalledAsset>[];
    for (final asset in _fetchable(manifest)) {
      final outcome = await _stageOne(spec, asset);
      if (outcome == null) {
        if (asset.required) {
          return const MotionPackageInstallResult(
            status: MotionPackageStatus.missingRequiredAsset,
            failureReason: 'download_failed',
          );
        }
        continue; // optional asset absent — preview degrades, nothing else
      }
      if (outcome.asset == null) {
        if (asset.required) {
          return MotionPackageInstallResult(
            status: outcome.invalidUrl
                ? MotionPackageStatus.invalidManifestAsset
                : MotionPackageStatus.integrityFailed,
            failureReason: outcome.failureReason,
          );
        }
        continue;
      }
      staged.add(outcome.asset!);
    }

    // The record travels inside staging so record+assets promote atomically.
    final record = InstalledMotionPackage(
      activityId: spec.activityId,
      releaseId: spec.releaseId,
      releaseChecksum: releaseChecksum,
      assets: staged,
      installedAtMs: nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch,
      totalBytes: staged.fold(0, (sum, a) => sum + a.bytes),
    );
    try {
      await _store.stageManifest(
        spec.activityId,
        spec.releaseId,
        record.toJson(),
      );
      await _store.promote(spec.activityId, spec.releaseId);
    } catch (_) {
      return const MotionPackageInstallResult(
        status: MotionPackageStatus.storeError,
        failureReason: 'promote_failed',
      );
    }
    await prune();
    return MotionPackageInstallResult(
      status: MotionPackageStatus.installed,
      package: record,
    );
  }

  /// The installed record must cover the CURRENT manifest — an install
  /// predating a re-published manifest is not reusable.
  bool _covers(
    InstalledMotionPackage installed,
    MotionPackageManifest manifest,
  ) {
    final byId = {for (final a in installed.assets) a.id: a};
    for (final asset in _required(manifest)) {
      final have = byId[asset.id];
      if (have == null ||
          have.sha256 != asset.sha256 ||
          have.bytes != asset.bytes) {
        return false;
      }
    }
    return true;
  }

  Future<_StagedOutcome?> _stageOne(
    RemoteVerifierSpec spec,
    MotionPackageAsset asset,
  ) async {
    final url = _resolveAssetUrl(spec, asset);
    if (url == null) {
      return const _StagedOutcome.invalidUrl();
    }
    Uint8List? bytes;
    try {
      // A throwing downloader is just a failed fetch — the release must
      // fail closed, not crash the install path.
      bytes = await _downloader(url, asset.bytes);
    } catch (_) {
      return null;
    }
    if (bytes == null) return null;
    if (bytes.length != asset.bytes) {
      return const _StagedOutcome.bad('size_mismatch');
    }
    if (sha256Hex(bytes) != asset.sha256) {
      return const _StagedOutcome.bad('checksum_mismatch');
    }
    if (!_sanity(asset.type, bytes)) {
      return const _StagedOutcome.bad('invalid_asset');
    }
    await _store.stageAsset(spec.activityId, spec.releaseId, asset.id, bytes);
    return _StagedOutcome.ok(
      InstalledAsset(
        id: asset.id,
        type: asset.type,
        sha256: asset.sha256,
        bytes: asset.bytes,
        required: asset.required,
      ),
    );
  }

  /// Assets are fetched only from the same first-party Worker that served
  /// the release — a manifest naming any other host is refused outright.
  /// Remote delivery is data to a compiled runtime, never code or arbitrary
  /// filesystem content.
  static String? _resolveAssetUrl(
    RemoteVerifierSpec spec,
    MotionPackageAsset asset,
  ) {
    final api = Uri.parse(kNuvoApiBase);
    final expectedPath =
        '/motion/releases/${spec.releaseId}/assets/${asset.id}';
    final raw = asset.url;
    final Uri uri;
    if (raw.startsWith('/')) {
      uri = api.replace(path: raw);
    } else {
      final parsed = Uri.tryParse(raw);
      if (parsed == null || !parsed.isScheme('https')) return null;
      uri = parsed;
    }
    if (uri.host != api.host) return null;
    if (uri.path != expectedPath) return null;
    return uri.toString();
  }

  /// Minimum content sanity past the checksum — JSON types must decode;
  /// a model must at least look like a serialized payload, not an error page.
  static bool _sanity(String type, Uint8List bytes) {
    switch (type) {
      case 'preview_v1':
      case 'motion_v2_spec_v1':
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          return decoded is Map;
        } catch (_) {
          return false;
        }
      case 'onnx_model':
        return bytes.length >= 16;
      default:
        return bytes.isNotEmpty;
    }
  }

  /// Cache policy: newest [maxReleasesPerActivity] per activity, global byte
  /// cap [maxCacheBytes], and pinned releases are never evicted. Eviction
  /// removes the oldest non-pinned install first.
  Future<void> prune() async {
    try {
      final packages = await _store.all();
      final unpinned = packages
          .where((p) => !_pinned.contains(p.releaseId))
          .toList()
        ..sort((a, b) => a.installedAtMs.compareTo(b.installedAtMs));

      // Per-activity cap — keep newest N.
      final byActivity = <String, List<InstalledMotionPackage>>{};
      for (final p in packages) {
        byActivity.putIfAbsent(p.activityId, () => []).add(p);
      }
      final evict = <InstalledMotionPackage>{};
      for (final group in byActivity.values) {
        group.sort((a, b) => b.installedAtMs.compareTo(a.installedAtMs));
        for (final old in group.skip(maxReleasesPerActivity)) {
          if (!_pinned.contains(old.releaseId)) evict.add(old);
        }
      }

      // Global byte cap — evict LRU non-pinned until under.
      var total = packages.fold(0, (sum, p) => sum + p.totalBytes) -
          evict.fold(0, (sum, p) => sum + p.totalBytes);
      for (final candidate in unpinned) {
        if (total <= maxCacheBytes) break;
        if (evict.contains(candidate)) continue;
        evict.add(candidate);
        total -= candidate.totalBytes;
      }

      for (final package in evict) {
        await _store.remove(package.activityId, package.releaseId);
      }
    } catch (_) {
      // Pruning is hygiene — never let it break an install.
    }
  }
}

/// Production downloader — streams the first-party URL into memory with a
/// hard byte ceiling (maxBytes is the manifest-declared size, already
/// capped per type by the spec parser) and a 30s overall timeout.
/// Any non-200 response or oversize body returns null.
Future<Uint8List?> defaultMotionAssetDownloader(String url, int maxBytes) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url));
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      return null;
    }
    if (response.contentLength != null &&
        response.contentLength! > maxBytes) {
      await response.stream.drain<void>();
      return null;
    }
    final buffer = BytesBuilder();
    await for (final chunk in response.stream) {
      buffer.add(chunk);
      if (buffer.length > maxBytes) return null;
    }
    return buffer.takeBytes();
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

class _StagedOutcome {
  const _StagedOutcome.ok(this.asset)
      : failureReason = null,
        invalidUrl = false;
  const _StagedOutcome.bad(this.failureReason)
      : asset = null,
        invalidUrl = false;
  const _StagedOutcome.invalidUrl()
      : asset = null,
        failureReason = 'invalid_url',
        invalidUrl = true;

  final InstalledAsset? asset;
  final String? failureReason;
  final bool invalidUrl;
}
