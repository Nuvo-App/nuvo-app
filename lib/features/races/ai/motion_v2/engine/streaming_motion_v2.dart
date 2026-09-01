import 'dart:math' as math;
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';
import '../motion_v2_models.dart';
import 'motion_v2_math.dart';
import 'nuvo_to_h36m.dart';
import 'taught_motion_v2.dart';

/// Incremental recognition for the live test camera. 1:1 port of
/// `tools/motion_v2/engine/streaming.py`.
///
/// Rolling frame buffer. On each [push] it re-encodes the recent window,
/// matches, and emits a rep when the buffer transitions into a confident match
/// after having been *away* from one (so holding the end pose can't re-fire and
/// idle can't fire). No per-movement state machine.
class StreamingMotionV2 {
  StreamingMotionV2(this.motion, this.encoder, {double fpsHint = 15.0})
      : _bufCap = math.max(30, (5.0 * fpsHint).round());

  final TaughtMotionV2 motion;
  final MotionEncoderV2 encoder;
  final int _bufCap;

  static const int _minFrames = 8;
  static const int _reevalEvery = 3;
  static const double _neutralDrop = 0.55;
  static const double _matchScore = 0.5;

  final List<NuvoPoseFrame> _buf = [];
  int _count = 0;
  bool _armed = true;
  bool _inMatch = false;
  int _framesSeen = 0;
  int _sinceEval = 0;
  MotionV2RuntimeResult _last = MotionV2RuntimeResult.empty;

  void reset() {
    _buf.clear();
    _count = 0;
    _armed = true;
    _inMatch = false;
    _framesSeen = 0;
    _sinceEval = 0;
    _last = MotionV2RuntimeResult.empty;
  }

  Future<MotionV2RuntimeResult> push(List<NuvoPoseFrame> frames) async {
    final t0 = DateTime.now();
    _buf.addAll(frames);
    if (_buf.length > _bufCap) {
      _buf.removeRange(0, _buf.length - _bufCap);
    }
    _framesSeen += frames.length;
    _sinceEval += frames.length;

    if (_framesSeen < _minFrames) {
      return _result(false, 0, 0, MotionV2RuntimeState.warmingUp, t0);
    }
    if (_sinceEval < _reevalEvery && _last != MotionV2RuntimeResult.empty) {
      return _last;
    }
    _sinceEval = 0;

    final hDiag = framesToH36mDiag(_buf);
    final h = hDiag.seq;
    final hm = framesToH36m(_buf, mirror: true);
    final rep = await encoder.encode(h);
    final repM = await encoder.encode(hm);
    final emb = perFrameEmbedding(rep);
    final embM = perFrameEmbedding(repM);
    final m = motion.matchEncoded(rep, emb, repM: repM, embM: embM);

    final seg = segmentAction(emb);
    final prog = _progress(
      seg.end - seg.start >= 4 ? sliceSeq(emb, seg.start, seg.end) : emb,
    );

    var newRep = false;
    if (m.isSameFamily && m.score >= _matchScore) {
      if (_armed && !_inMatch) {
        _count++;
        newRep = true;
        _armed = false;
      }
      _inMatch = true;
    } else {
      _inMatch = false;
      if (m.score < _neutralDrop) _armed = true;
      if (_armed && _count > 0 && _buf.length > _minFrames) {
        _buf.removeRange(0, _buf.length - _minFrames);
      }
    }

    final state = _inMatch
        ? MotionV2RuntimeState.matching
        : (_armed ? MotionV2RuntimeState.neutral : MotionV2RuntimeState.returning);

    final r = _result(newRep, m.score, prog, state, t0,
        protoDist: m.protoDist, protoMargin: m.protoMargin, trajSim: m.trajSim,
        rootDrift: hDiag.diag.rootTranslationMagnitude,
        scaleSpread: hDiag.diag.scaleChangeFraction);
    _last = r;
    return r;
  }

  double _progress(List<Float32List> embSeg) {
    if (embSeg.length < 2) return 0.0;
    final q = resampleSeq(l2normSeq(embSeg), motion.canonical.length);
    final c = motion.canonical.length;
    var j = 0;
    for (var t = 0; t < c; t++) {
      final hi = math.min(c - 1, j + 5);
      var best = j;
      var bestS = -2.0;
      for (var k = j; k <= hi; k++) {
        final s = dot(motion.canonical[k], q[t]);
        if (s > bestS) {
          bestS = s;
          best = k;
        }
      }
      j = math.max(j, best);
    }
    return j / (c - 1);
  }

  MotionV2RuntimeResult _result(
    bool newRep,
    double conf,
    double prog,
    MotionV2RuntimeState state,
    DateTime t0, {
    double? protoDist,
    double? protoMargin,
    double? trajSim,
    double? rootDrift,
    double? scaleSpread,
  }) {
    return MotionV2RuntimeResult(
      matched: state == MotionV2RuntimeState.matching,
      newRep: newRep,
      count: _count,
      confidence: conf,
      motionProgress: prog,
      state: state,
      inferenceLatency: DateTime.now().difference(t0),
      bufferFrames: _buf.length,
      protoDist: protoDist,
      protoMargin: protoMargin,
      trajSim: trajSim,
      rootDrift: rootDrift,
      scaleSpread: scaleSpread,
    );
  }
}
