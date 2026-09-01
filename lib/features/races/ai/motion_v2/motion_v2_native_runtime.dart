import 'dart:async';

import '../../data/ai_motion_models.dart';
import 'engine/motion_v2_onnx_encoder.dart';
import 'engine/streaming_motion_v2.dart';
import 'engine/taught_motion_v2.dart';
import 'motion_v2_models.dart';
import 'motion_verifier_v2.dart';

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
    final json = motion.toJson()
      ..['metadata'] = {'movementName': movementName};
    return TaughtMotionV2Spec.fromJson(json);
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
