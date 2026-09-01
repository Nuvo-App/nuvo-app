
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

import '../motion_v2_models.dart';
import 'nuvo_to_h36m.dart';
import 'taught_motion_v2.dart';

/// On-device MotionBERT encoder via ONNX Runtime.
///
///   framesToH36m output (T x 51)  ->  rep (T x 17 x 512)
///
/// The model (`assets/models/motion_v2_encoder.onnx`) is the release_action
/// backbone's `return_rep` output, fp16. Bit-close to PyTorch (see
/// `tools/motion_v2/scripts/export_onnx.py`: fp16 MAE ~1e-4).
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
  static Future<MotionV2OnnxEncoder> load() async {
    if (_shared == null) {
      OrtEnv.instance.init();
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      final opts = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
      _shared = OrtSession.fromBuffer(bytes, opts);
    }
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
  static void resetSharedForTest() => _shared = null;
}
