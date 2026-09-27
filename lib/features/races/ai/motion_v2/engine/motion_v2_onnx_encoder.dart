import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../../motion_model_release.dart';
import '../../motion_model_resolver.dart';
import '../../motion_model_store.dart';
import '../motion_v2_models.dart';
import 'nuvo_to_h36m.dart';
import 'taught_motion_v2.dart';

/// On-device MotionBERT encoder via ONNX Runtime.
///
///   framesToH36m output (T x 51)  ->  rep (T x 17 x 512)
///
/// The bundled model (`assets/models/motion_v2_encoder.onnx`) is the
/// release_action backbone's `return_rep` output, fp16. Bit-close to PyTorch
/// (see `tools/motion_v2/scripts/export_onnx.py`: fp16 MAE ~1e-4).
///
/// Model delivery, System B: when a [MotionV2ModelSource] is configured the
/// encoder resolves the channel's current release, installs its artifact only
/// after checksum verification, and falls back in order:
///
///   compatible remote release → last-known-good cache → bundled asset.
///
/// The loaded model is pinned per session — a session that starts on release A
/// finishes on release A even if the channel promotes B mid-session. New
/// sessions adopt the channel release at their next `load()`.
class MotionV2OnnxEncoder implements MotionEncoderV2 {
  MotionV2OnnxEncoder._(this._session);

  static const String assetPath = 'assets/models/motion_v2_encoder.onnx';
  static const int _maxLen = 243;

  final OrtSession _session;
  bool _disposed = false;

  int _dimRep = 512;
  @override
  int get dimRep => _dimRep;

  static OrtSession? _shared;
  static String _sharedKey = '';

  // ── Remote model delivery ──────────────────────────────────────────────
  static MotionV2ModelSource? _modelSource;
  static MotionModelStore _store = MotionModelStore();

  /// Identity of the model currently loaded — surfaced to session diagnostics
  /// and Teach Nuvo provenance.
  static String activeModelVersion = kBundledMotionEncoderVersion;
  static String? activeModelChecksum;
  static String activeModelSource = 'bundled';

  /// Which encoder release a session is using — written into taught-movement
  /// specs so a learned movement records the model that produced its
  /// reference embeddings.
  static String get activeEncoderId => activeModelVersion;

  /// Cold-init timings (ms), for the learn profile. 0 once warm.
  static int lastAssetLoadMs = 0;
  static int lastSessionCreateMs = 0;
  static bool get isWarm => _shared != null;

  /// Attach the remote model delivery path. Callers that hold an API client
  /// configure this once per session; when unset the encoder uses bundled +
  /// cached models only (offline-safe default).
  static void configureModelSource(
    MotionV2ModelSource? source, {
    MotionModelStore? store,
  }) {
    _modelSource = source;
    if (store != null) _store = store;
  }

  static void _setActiveIdentity(
    String version,
    String? checksum,
    String source,
  ) {
    activeModelVersion = version;
    activeModelChecksum = checksum;
    activeModelSource = source;
  }

  /// Resolve the bytes for the model this build should run:
  ///   1. compatible remote release (cached bytes, else verified download)
  ///   2. last-known-good cached release
  ///   3. bundled launch asset
  /// Every failure degrades silently to the next tier.
  static Future<({Uint8List bytes, String version, String? sha, String source})>
      _resolveBytes() async {
    final source = _modelSource;
    if (source == null) {
      // Offline / unauthenticated default: prefer last-known-good, else bundle.
      final lkg = await _store.lastKnownGood(kMotionV2EncoderFamily);
      if (lkg != null) {
        return (
          bytes: lkg.bytes,
          version: lkg.release.modelVersion,
          sha: lkg.release.artifactSha256,
          source: 'lastKnownGood',
        );
      }
      return (
        bytes: (await rootBundle.load(assetPath)).buffer.asUint8List(),
        version: kBundledMotionEncoderVersion,
        sha: null,
        source: 'bundled',
      );
    }

    MotionModelRelease? release;
    try {
      release = await source.resolve(kMotionV2EncoderFamily);
    } catch (_) {
      release = null;
    }

    if (release != null) {
      // Exact-release cache hit: same version + checksum, already verified at
      // install time.
      final cached = await _store.read(
        kMotionV2EncoderFamily, release.modelVersion, release.artifactSha256);
      if (cached != null) {
        return (
          bytes: cached.bytes,
          version: release.modelVersion,
          sha: release.artifactSha256,
          source: 'cachedRelease',
        );
      }
      try {
        final vetted = await source.fetchVerified(release);
        await _store.persist(kMotionV2EncoderFamily, release, vetted.bytes);
        return (
          bytes: vetted.bytes,
          version: release.modelVersion,
          sha: release.artifactSha256,
          source: 'remote',
        );
      } catch (_) {
        // Corrupt/short/mismatched artifact — never install; fall through to
        // last-known-good.
      }
    }

    final lkg = await _store.lastKnownGood(kMotionV2EncoderFamily);
    if (lkg != null &&
        lkg.release.isCompatibleWith(
          runtimeFamily: kMotionV2EncoderRuntimeFamily,
          inputSchemaVersion: kMotionV2EncoderInputSchema,
          outputSchemaVersion: kMotionV2EncoderOutputSchema,
          appBuild: source.effectiveAppBuild,
        )) {
      return (
        bytes: lkg.bytes,
        version: lkg.release.modelVersion,
        sha: lkg.release.artifactSha256,
        source: 'lastKnownGood',
      );
    }
    return (
      bytes: (await rootBundle.load(assetPath)).buffer.asUint8List(),
      version: kBundledMotionEncoderVersion,
      sha: null,
      source: 'bundled',
    );
  }

  static Future<MotionV2OnnxEncoder> load() async {
    final sw = Stopwatch()..start();
    var resolved = await _resolveBytes();
    final key = '${resolved.version}:${resolved.sha ?? 'bundled'}';
    if (_shared != null && _sharedKey == key) {
      lastAssetLoadMs = 0;
      lastSessionCreateMs = 0;
      return MotionV2OnnxEncoder._(_shared!);
    }
    lastAssetLoadMs = sw.elapsedMilliseconds;
    sw.reset();
    OrtSession session;
    try {
      OrtEnv.instance.init();
      final opts = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(
            GraphOptimizationLevel.ortEnableAll);
      session = OrtSession.fromBuffer(resolved.bytes, opts);
    } catch (_) {
      // A byte-verified artifact can still fail ORT load (corrupt disk read,
      // truncated write). Re-load the bundled asset — Motion must never
      // come down because a model file is unreadable.
      final bundled =
          (await rootBundle.load(assetPath)).buffer.asUint8List();
      session = OrtSession.fromBuffer(bundled, OrtSessionOptions());
      resolved = (
        bytes: bundled,
        version: kBundledMotionEncoderVersion,
        sha: null,
        source: 'bundled',
      );
    }
    // Rotation, not release: an encoder instance handed out before this call
    // still points at its own OrtSession and keeps it for the remainder of
    // its session — a promoted model never swaps mid-session. The previous
    // shared session is left for GC when the last holder finishes.
    _shared = session;
    _sharedKey = '${resolved.version}:${resolved.sha ?? 'bundled'}';
    _setActiveIdentity(resolved.version, resolved.sha, resolved.source);
    lastSessionCreateMs = sw.elapsedMilliseconds;
    return MotionV2OnnxEncoder._(_shared!);
  }

  @override
  Future<List<List<Float32List>>> encode(List<Float32List> h36mSeq) async {
    if (_disposed) throw const MotionV2Exception('encoder disposed');
    var seq = h36mSeq;
    if (seq.isEmpty) return const [];
    if (seq.length > _maxLen) {
      seq = seq.sublist(seq.length - _maxLen);
    }
    final t = seq.length;

    final flat = Float32List(t * kNumJoints * 3);
    var o = 0;
    for (final row in seq) {
      for (var k = 0; k < kNumJoints * 3; k++) {
        flat[o++] = row[k];
      }
    }

    final input = OrtValueTensor.createTensorWithDataList(
      <Float32List>[flat],
      [1, t, kNumJoints, 3],
    );
    final runOpts = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      outs = await _session.runAsync(runOpts, {'pose': input}, ['rep']);
    } finally {
      input.release();
      runOpts.release();
    }
    if (outs == null || outs.isEmpty || outs.first == null) {
      throw const MotionV2Exception('encoder produced no output');
    }
    // (1, T, 17, D) nested List<double>
    final nested = outs.first!.value as List;
    final batch = nested.first as List; // T
    final rep = <List<Float32List>>[];
    for (final frame in batch) {
      final joints = <Float32List>[];
      for (final joint in (frame as List)) {
        final jl = joint as List;
        final f = Float32List(jl.length);
        for (var k = 0; k < jl.length; k++) {
          f[k] = (jl[k] as num).toDouble();
        }
        joints.add(f);
      }
      rep.add(joints);
    }
    for (final v in outs) {
      v?.release();
    }
    if (rep.isNotEmpty && rep.first.isNotEmpty) {
      _dimRep = rep.first.first.length;
    }
    return rep;
  }

  void dispose() {
    // The OrtSession is process-shared and cheap to keep; only tear down on
    // an explicit app-wide shutdown, which we don't need here.
    _disposed = true;
  }

  @visibleForTesting
  static void resetSharedForTest() {
    _shared = null;
    _sharedKey = '';
    _modelSource = null;
    _store = MotionModelStore();
    _setActiveIdentity(kBundledMotionEncoderVersion, null, 'bundled');
  }
}
