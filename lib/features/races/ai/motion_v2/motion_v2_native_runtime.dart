import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/ai_motion_models.dart';
import 'engine/motion_v2_background.dart';
import 'engine/motion_v2_math.dart';
import 'engine/motion_v2_onnx_encoder.dart';
import 'engine/nuvo_to_h36m.dart';
import 'engine/streaming_motion_v2.dart';
import 'engine/taught_motion_v2.dart';
import 'motion_v2_models.dart';
import 'motion_verifier_v2.dart';

/// Result of replaying each teaching demo back through the just-learned
/// verifier. If the model can't recognize its own demonstrations the spec is
/// junk and the user should re-record before we ever say "Movement learned".
class SelfValidationReport {
  const SelfValidationReport({
    required this.passed,
    required this.perDemo,
    this.leaveOneOut = const [],
    required this.worstProtoMargin,
    required this.worstTrajMargin,
  });
  final bool passed;
  final List<bool> perDemo;
  final List<bool> leaveOneOut;
  final double worstProtoMargin;
  final double worstTrajMargin;

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'perDemo': perDemo,
        'leaveOneOut': leaveOneOut,
        'worstProtoMargin': double.parse(worstProtoMargin.toStringAsFixed(3)),
        'worstTrajMargin': double.parse(worstTrajMargin.toStringAsFixed(3)),
      };
}

class MotionV2LearnException implements Exception {
  const MotionV2LearnException(this.message, {this.report});
  final String message;
  final SelfValidationReport? report;
  @override
  String toString() => 'MotionV2LearnException: $message';
}

/// Where the Learn step's time went. Encoder should run 3x (once per demo).
class LearnProfile {
  int modelLoadMs = 0;
  int sessionCreateMs = 0;
  int preprocessMs = 0;
  final List<int> encodeMs = [];
  int buildRefsMs = 0;
  int selfValidateMs = 0;
  int looMs = 0;
  int totalMs = 0;
  bool warmStart = false;

  int get totalEncodeMs => encodeMs.fold(0, (a, b) => a + b);
  int get encoderPasses => encodeMs.length;

  Map<String, dynamic> toJson() => {
        'warmStart': warmStart,
        'modelLoadMs': modelLoadMs,
        'sessionCreateMs': sessionCreateMs,
        'preprocessMs': preprocessMs,
        'encodeMs': encodeMs,
        'totalEncodeMs': totalEncodeMs,
        'encoderPasses': encoderPasses,
        'buildRefsMs': buildRefsMs,
        'selfValidateMs': selfValidateMs,
        'looMs': looMs,
        'totalMs': totalMs,
      };

  String toText() {
    final b = StringBuffer('Motion V2 Learn Profile'
        ' (${warmStart ? "warm" : "cold"})\n');
    if (!warmStart) {
      b.writeln('  model load:        $modelLoadMs ms');
      b.writeln('  session create:    $sessionCreateMs ms');
    }
    b.writeln('  preprocess demos:  $preprocessMs ms');
    for (var i = 0; i < encodeMs.length; i++) {
      b.writeln('  encode demo${i + 1}:      ${encodeMs[i]} ms');
    }
    b.writeln('  build references:  $buildRefsMs ms');
    b.writeln('  self-validation:   $selfValidateMs ms  (0 encoder passes)');
    b.writeln('  leave-one-out:     $looMs ms  (0 encoder passes)');
    b.writeln('  TOTAL:             $totalMs ms  '
        '($encoderPasses encoder passes)');
    return b.toString();
  }
}

/// The default Motion V2 runtime: everything on-device via ONNX Runtime.
/// No Python service, no network. Implements the same [MotionVerifierV2] /
/// [MotionLearnerV2] contract the callers already use.
class MotionV2NativeRuntime implements MotionVerifierV2, MotionLearnerV2 {
  MotionV2NativeRuntime({MotionEncoderV2? encoder}) : _injected = encoder;

  final MotionEncoderV2? _injected;
  MotionEncoderV2? _encoder;
  StreamingMotionV2? _session;
  TaughtMotionV2? _motion;
  List<Float32List>? _background;

  Future<MotionEncoderV2> _enc() async =>
      _encoder ??= _injected ?? await MotionV2OnnxEncoder.load();

  Future<List<Float32List>?> _bg() async =>
      _background ??= await MotionV2Background.load();

  /// Load-time health signal for diagnostics.
  bool get encoderLoaded => _encoder != null;
  String get encoderId => _motion?.encoderId ?? 'release_action';

  LearnProfile? _lastLearnProfile;
  LearnProfile? get lastLearnProfile => _lastLearnProfile;

  @override
  Future<TaughtMotionV2Spec> learn({
    required String movementName,
    required List<List<NuvoPoseFrame>> demos,
  }) async {
    if (demos.length < 2) {
      throw const MotionV2Exception('Need at least 2 demonstrations.');
    }
    final p = LearnProfile()..warmStart = MotionV2OnnxEncoder.isWarm;
    final total = Stopwatch()..start();

    final enc = await _enc();
    final bg = await _bg();
    p.modelLoadMs = MotionV2OnnxEncoder.lastAssetLoadMs;
    p.sessionCreateMs = MotionV2OnnxEncoder.lastSessionCreateMs;

    // ── ONE MotionBERT pass per demo. Everything after runs on these. ──
    final encoded = <MotionEncodedDemo>[];
    for (final frames in demos) {
      final sw = Stopwatch()..start();
      final h36m = framesToH36m(frames);
      p.preprocessMs += sw.elapsedMilliseconds;
      sw.reset();
      final rep = await enc.encode(h36m);
      p.encodeMs.add(sw.elapsedMilliseconds);
      encoded.add((rep: rep, emb: perFrameEmbedding(rep), h36m: h36m));
    }

    final sw = Stopwatch()..start();
    final motion = TaughtMotionV2.learnFromEncoded(
      name: movementName, encoderId: 'release_action', encoded: encoded);
    p.buildRefsMs = sw.elapsedMilliseconds;

    // Self-validation + leave-one-out — pure matcher math on the cached
    // embeddings. ZERO extra encoder passes.
    final report = _selfValidate(motion, encoded, bg, p);
    _lastSelfValidation = report;

    p.totalMs = total.elapsedMilliseconds;
    _lastLearnProfile = p;
    if (kDebugMode) debugPrint(p.toText());

    if (!report.passed) {
      throw MotionV2LearnException(
        'SELF_VALIDATION_FAILED: the model could not recognize its own '
        'demonstrations (perDemo=${report.perDemo}, loo=${report.leaveOneOut})',
        report: report,
      );
    }

    final json = motion.toJson()
      ..['metadata'] = {
        'movementName': movementName,
        'selfValidation': report.toJson(),
        'learnProfile': p.toJson(),
      };
    return TaughtMotionV2Spec.fromJson(json);
  }

  SelfValidationReport? _lastSelfValidation;
  SelfValidationReport? get lastSelfValidation => _lastSelfValidation;

  SelfValidationReport _selfValidate(
    TaughtMotionV2 motion,
    List<MotionEncodedDemo> encoded,
    List<Float32List>? bg,
    LearnProfile p,
  ) {
    final swSv = Stopwatch()..start();
    final perDemo = <bool>[];
    var worstPm = 0.0, worstTm = 0.0;
    for (final e in encoded) {
      final r = motion.matchEncoded(e.rep, e.emb, background: bg);
      perDemo.add(r.isSameFamily);
      if (r.protoMargin > worstPm) worstPm = r.protoMargin;
      final tm = motion.acceptTrajDist <= 0
          ? 0.0
          : (1.0 - r.trajSim) / motion.acceptTrajDist;
      if (tm > worstTm) worstTm = tm;
    }
    p.selfValidateMs = swSv.elapsedMilliseconds;

    final swLoo = Stopwatch()..start();
    final loo = <bool>[];
    for (var i = 0; i < encoded.length; i++) {
      final two = motion.twoRefSubset(i); // cached refs, no encoder
      final r = two.matchEncoded(encoded[i].rep, encoded[i].emb, background: bg);
      loo.add(r.isSameFamily);
    }
    p.looMs = swLoo.elapsedMilliseconds;

    final need = encoded.length - (encoded.length ~/ 3); // majority
    return SelfValidationReport(
      passed: perDemo.where((x) => x).length >= need &&
          loo.where((x) => x).length >= need,
      perDemo: perDemo,
      leaveOneOut: loo,
      worstProtoMargin: worstPm,
      worstTrajMargin: worstTm,
    );
  }

  @override
  Future<void> load(TaughtMotionV2Spec spec) async {
    final enc = await _enc();
    final bg = await _bg();
    _motion = TaughtMotionV2.fromJson(spec.json);
    _session = StreamingMotionV2(_motion!, enc, background: bg);
  }

  @override
  Future<MotionV2RuntimeResult> update(List<NuvoPoseFrame> frames) async {
    final s = _session;
    if (s == null) throw const MotionV2Exception('No V2 session — call load() first.');
    return s.push(frames);
  }

  @override
  Future<void> reset() async => _session?.reset();

  @override
  Future<void> dispose() async {
    _session = null;
    _motion = null;
  }
}
