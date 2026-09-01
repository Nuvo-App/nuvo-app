import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/ai_motion_models.dart';
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
    required this.worstProtoMargin,
    required this.worstTrajMargin,
  });
  final bool passed;
  final List<bool> perDemo;
  final double worstProtoMargin;
  final double worstTrajMargin;

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'perDemo': perDemo,
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

  Future<MotionEncoderV2> _enc() async =>
      _encoder ??= _injected ?? await MotionV2OnnxEncoder.load();

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
    final motion = await TaughtMotionV2.learn(
      name: movementName,
      demos: demos,
      encoder: enc,
      encoderId: 'release_action',
    );

    // Self-validation: replay each demo through the fresh verifier. If it can't
    // recognize its own demonstrations, the learn produced junk — don't ship it.
    final report = await _selfValidate(motion, demos, enc);
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

  Future<SelfValidationReport> _selfValidate(
    TaughtMotionV2 motion,
    List<List<NuvoPoseFrame>> demos,
    MotionEncoderV2 enc,
  ) async {
    final perDemo = <bool>[];
    var worstPm = 0.0, worstTm = 0.0;
    for (final demo in demos) {
      try {
        final rep = await enc.encode(framesToH36m(demo));
        final repM = await enc.encode(framesToH36m(demo, mirror: true));
        final r = motion.matchEncoded(
          rep,
          perFrameEmbedding(rep),
          repM: repM,
          embM: perFrameEmbedding(repM),
        );
        perDemo.add(r.isSameFamily);
        worstPm = worstPm < r.protoMargin ? r.protoMargin : worstPm;
        final tm = motion.acceptTrajDist <= 0
            ? 0.0
            : (1.0 - r.trajSim) / motion.acceptTrajDist;
        worstTm = worstTm < tm ? tm : worstTm;
      } catch (e) {
        if (kDebugMode) debugPrint('self-validate demo error: $e');
        perDemo.add(false);
      }
    }
    // Permissive: pass if a clear majority of demos are recognized.
    final ok = perDemo.where((x) => x).length >= (demos.length - (demos.length ~/ 3));
    return SelfValidationReport(
      passed: ok,
      perDemo: perDemo,
      worstProtoMargin: worstPm,
      worstTrajMargin: worstTm,
    );
  }

  @override
  Future<void> load(TaughtMotionV2Spec spec) async {
    final enc = await _enc();
    _motion = TaughtMotionV2.fromJson(spec.json);
    _session = StreamingMotionV2(_motion!, enc);
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
