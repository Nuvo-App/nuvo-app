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

  @override
  Future<TaughtMotionV2Spec> learn({
    required String movementName,
    required List<List<NuvoPoseFrame>> demos,
  }) async {
    if (demos.length < 2) {
      throw const MotionV2Exception('Need at least 2 demonstrations.');
    }
    final enc = await _enc();
    final bg = await _bg();
    final motion = await TaughtMotionV2.learn(
      name: movementName,
      demos: demos,
      encoder: enc,
      encoderId: 'release_action',
    );

    // Self-validation: every demo must be recognized from the fresh verifier
    // AND recoverable from the other two (leave-one-out). If not, the three
    // examples don't define one stable movement — don't ship a blur.
    final report = await _selfValidate(motion, demos, enc, bg);
    _lastSelfValidation = report;
    if (!report.passed) {
      throw MotionV2LearnException(
        'SELF_VALIDATION_FAILED: the model could not recognize its own '
        'demonstrations (perDemo=${report.perDemo}, '
        'worstProtoMargin=${report.worstProtoMargin.toStringAsFixed(2)}, '
        'worstTrajMargin=${report.worstTrajMargin.toStringAsFixed(2)})',
        report: report,
      );
    }

    final json = motion.toJson()
      ..['metadata'] = {
        'movementName': movementName,
        'selfValidation': report.toJson(),
      };
    return TaughtMotionV2Spec.fromJson(json);
  }

  SelfValidationReport? _lastSelfValidation;
  SelfValidationReport? get lastSelfValidation => _lastSelfValidation;

  Future<({List<List<Float32List>> rep, List<List<Float32List>> repM,
          List<Float32List> emb, List<Float32List> embM})>
      _encodeBoth(MotionEncoderV2 enc, List<NuvoPoseFrame> demo) async {
    final rep = await enc.encode(framesToH36m(demo));
    final repM = await enc.encode(framesToH36m(demo, mirror: true));
    return (
      rep: rep,
      repM: repM,
      emb: perFrameEmbedding(rep),
      embM: perFrameEmbedding(repM)
    );
  }

  Future<SelfValidationReport> _selfValidate(
    TaughtMotionV2 motion,
    List<List<NuvoPoseFrame>> demos,
    MotionEncoderV2 enc,
    List<Float32List>? bg,
  ) async {
    final encoded = <
        ({List<List<Float32List>> rep, List<List<Float32List>> repM,
          List<Float32List> emb, List<Float32List> embM})>[];
    for (final d in demos) {
      encoded.add(await _encodeBoth(enc, d));
    }

    final perDemo = <bool>[];
    var worstPm = 0.0, worstTm = 0.0;
    for (final e in encoded) {
      final r = motion.matchEncoded(e.rep, e.emb,
          repM: e.repM, embM: e.embM, background: bg);
      perDemo.add(r.isSameFamily);
      if (r.protoMargin > worstPm) worstPm = r.protoMargin;
      final tm = motion.acceptTrajDist <= 0
          ? 0.0
          : (1.0 - r.trajSim) / motion.acceptTrajDist;
      if (tm > worstTm) worstTm = tm;
    }

    // Leave-one-out: each demo must be recognizable from the other two.
    final loo = <bool>[];
    for (var i = 0; i < demos.length; i++) {
      final others = [for (var j = 0; j < demos.length; j++) if (j != i) demos[j]];
      try {
        final two = await TaughtMotionV2.learn(
          name: '_loo', demos: [others[0], others[1], others[0]], encoder: enc,
          encoderId: 'release_action');
        final r = two.matchEncoded(encoded[i].rep, encoded[i].emb,
            repM: encoded[i].repM, embM: encoded[i].embM, background: bg);
        loo.add(r.isSameFamily);
      } catch (e) {
        if (kDebugMode) debugPrint('LOO demo $i error: $e');
        loo.add(false);
      }
    }

    final need = demos.length - (demos.length ~/ 3); // majority
    final passed = perDemo.where((x) => x).length >= need &&
        loo.where((x) => x).length >= need;
    return SelfValidationReport(
      passed: passed,
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
