import 'dart:math' as math;
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';
import '../motion_v2_models.dart';
import '../pose_quality.dart';
import 'motion_v2_math.dart';
import 'nuvo_to_h36m.dart';
import 'taught_motion_v2.dart';

/// Incremental recognition + live guidance + failure explanation for the test
/// camera. Rolling frame buffer; on each [push] it re-encodes the recent
/// window, matches, and emits a rep on a confident match after being *away*
/// from one.
///
/// On top of matching it runs:
///  - a shared [PoseQuality] readiness check (Move back / Step closer / Ready)
///  - a generic attempt lifecycle (idle -> in progress -> success / failed)
///  - a structured [MotionAttemptResult] for every failed attempt, so a
///    failure at 5% ("never started") is distinguishable from 85% ("almost").
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

  // Attempt lifecycle.
  bool _attemptActive = false;
  DateTime? _attemptStart;
  double _maxProgress = 0;
  double _bestProtoMargin = double.infinity;
  double _bestTrajMargin = double.infinity;
  double _worstScale = 0;
  double _worstRoot = 0;
  bool _sawUntrackableMidAttempt = false;
  Set<String> _missingMidAttempt = {};
  MotionAttemptResult _lastAttempt = MotionAttemptResult.empty;

  void reset() {
    _buf.clear();
    _count = 0;
    _armed = true;
    _inMatch = false;
    _framesSeen = 0;
    _sinceEval = 0;
    _last = MotionV2RuntimeResult.empty;
    _resetAttempt();
    _lastAttempt = MotionAttemptResult.empty;
  }

  void _resetAttempt() {
    _attemptActive = false;
    _attemptStart = null;
    _maxProgress = 0;
    _bestProtoMargin = double.infinity;
    _bestTrajMargin = double.infinity;
    _worstScale = 0;
    _worstRoot = 0;
    _sawUntrackableMidAttempt = false;
    _missingMidAttempt = {};
  }

  double _framePeriodMs() {
    if (_buf.length < 3) return 66;
    final span = _buf.last.createdAt
        .difference(_buf.first.createdAt)
        .inMilliseconds;
    if (span <= 0) return 66;
    return (span / (_buf.length - 1)).clamp(20, 200).toDouble();
  }

  Future<MotionV2RuntimeResult> push(List<NuvoPoseFrame> frames) async {
    final t0 = DateTime.now();
    _buf.addAll(frames);
    if (_buf.length > _bufCap) {
      _buf.removeRange(0, _buf.length - _bufCap);
    }
    _framesSeen += frames.length;
    _sinceEval += frames.length;

    // Camera readiness — computed every push, cheap, needed for the big message.
    final recent = _buf.length <= 6 ? _buf : _buf.sublist(_buf.length - 6);
    final pq = evaluatePoseQuality(_buf.isEmpty ? null : _buf.last, recent: recent);

    if (_framesSeen < _minFrames) {
      return _result(false, 0, 0, MotionV2RuntimeState.warmingUp, t0, pq: pq);
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
    final activeLen = seg.end - seg.start;
    final embSeg = activeLen >= 4 ? sliceSeq(emb, seg.start, seg.end) : emb;
    final prog = _progress(embSeg);

    // ── Attempt lifecycle ────────────────────────────────────────────────
    final v = embeddingVelocity(emb);
    final vSeg = activeLen >= 4
        ? [for (var i = seg.start; i < seg.end; i++) v[i]]
        : v;
    final movementNow = activeLen >= 4 &&
        (motion.demoActiveVel <= 0 || median(vSeg) > motion.demoActiveVel * 0.35);

    if (!_attemptActive && movementNow && pq.trackable) {
      _resetAttempt();
      _attemptActive = true;
      _attemptStart = DateTime.now();
    }
    if (_attemptActive) {
      _maxProgress = math.max(_maxProgress, prog);
      _bestProtoMargin = math.min(_bestProtoMargin, m.protoMargin);
      _bestTrajMargin = math.min(_bestTrajMargin, 1.0 - m.trajSim <= 0
          ? 0
          : (1.0 - m.trajSim) / motion.acceptTrajDist);
      _worstScale = math.max(_worstScale, hDiag.diag.scaleChangeFraction);
      _worstRoot = math.max(_worstRoot, hDiag.diag.rootTranslationMagnitude);
      if (!pq.trackable) _sawUntrackableMidAttempt = true;
      _missingMidAttempt.addAll(pq.missingRegions.map(bodyRegionLabel));
    }

    var newRep = false;
    if (m.isSameFamily && m.score >= _matchScore) {
      if (_armed && !_inMatch) {
        _count++;
        newRep = true;
        _armed = false;
      }
      _inMatch = true;
      if (_attemptActive) {
        _lastAttempt = _successAttempt(h, hDiag.diag, t0);
        _resetAttempt();
      }
    } else {
      _inMatch = false;
      if (m.score < _neutralDrop) _armed = true;
      // Attempt ended without a match → explain why.
      if (_attemptActive && !movementNow) {
        _lastAttempt = _failAttempt(h, hDiag.diag, m, embSeg, t0);
        _resetAttempt();
      }
      if (_armed && _count > 0 && _buf.length > _minFrames) {
        _buf.removeRange(0, _buf.length - _minFrames);
      }
    }

    final state = _inMatch
        ? MotionV2RuntimeState.matching
        : (_armed ? MotionV2RuntimeState.neutral : MotionV2RuntimeState.returning);

    final r = _result(newRep, m.score, prog, state, t0,
        protoDist: m.protoDist,
        protoMargin: m.protoMargin,
        trajSim: m.trajSim,
        rootDrift: hDiag.diag.rootTranslationMagnitude,
        scaleSpread: hDiag.diag.scaleChangeFraction,
        pq: pq);
    _last = r;
    return r;
  }

  // ── Attempt result builders ──────────────────────────────────────────────

  MotionAttemptResult _successAttempt(
    List<Float32List> h,
    MotionInputDiagnostics diag,
    DateTime t0,
  ) {
    final durMs = _attemptStart == null
        ? 0
        : DateTime.now().difference(_attemptStart!).inMilliseconds;
    return MotionAttemptResult(
      outcome: MotionAttemptOutcome.success,
      poseReadiness: PoseReadiness.ready.name,
      maxProgress: 1.0,
      durationMs: durMs,
      encoderLatencyMs:
          DateTime.now().difference(t0).inMilliseconds.toDouble(),
      userFeedback: '',
    );
  }

  MotionAttemptResult _failAttempt(
    List<Float32List> h,
    MotionInputDiagnostics diag,
    MatchResultV2 m,
    List<Float32List> embSeg,
    DateTime t0,
  ) {
    final period = _framePeriodMs();
    final durMs = _attemptStart == null
        ? 0
        : DateTime.now().difference(_attemptStart!).inMilliseconds;
    final expMin = motion.demoLengths.isEmpty
        ? 0
        : (motion.demoLengths.reduce(math.min) * period * 0.5).round();
    final expMax = motion.demoLengths.isEmpty
        ? 0
        : (motion.demoLengths.reduce(math.max) * period * 2.0).round();

    // Per-region under-movement vs the demonstrations.
    final liveRegion = regionActivity(h);
    final regionErr = <String, double>{};
    motion.demoRegionActivity.forEach((region, taught) {
      final live = liveRegion[region] ?? 0;
      // How much this region fell short of the taught motion (0 = met it).
      regionErr[region] = taught <= 1e-6 ? 0.0 : math.max(0.0, (taught - live) / taught);
    });
    String? primary;
    var worst = 0.0;
    regionErr.forEach((region, err) {
      if (err > worst && (motion.demoRegionActivity[region] ?? 0) > 1e-4) {
        worst = err;
        primary = region;
      }
    });

    final pm = m.protoMargin; // <=1 means "looks like the right movement"
    final tm = motion.acceptTrajDist <= 0
        ? 0.0
        : (1.0 - m.trajSim) / motion.acceptTrajDist;

    MotionFailureCategory cat;
    String feedback;
    if (_sawUntrackableMidAttempt) {
      cat = MotionFailureCategory.lostTrackingMidMotion;
      feedback = 'Camera lost track of you';
    } else if (_worstScale > 0.35 || _worstRoot > 0.35) {
      cat = MotionFailureCategory.cameraDistanceChangedTooMuch;
      feedback = 'Stay at the same distance from the camera';
    } else if (_maxProgress < 0.15) {
      cat = MotionFailureCategory.motionNeverStarted;
      feedback = 'Try the full movement';
    } else if (durMs > 0 && expMax > 0 && durMs > expMax * 1.5) {
      cat = MotionFailureCategory.motionStalled;
      feedback = 'Try that again without pausing';
    } else if (durMs > 0 && expMin > 0 && durMs < expMin) {
      cat = MotionFailureCategory.motionTooFast;
      feedback = 'Try that again a little slower';
    } else if (pm <= 1.2 && _maxProgress >= 0.7 && tm > 1.0) {
      // Right movement, right shape, just not completed / slightly off path.
      cat = MotionFailureCategory.motionIncomplete;
      feedback = primary != null && worst > 0.35
          ? 'Almost — move your $primary a bit more'
          : 'Almost — finish the movement';
    } else if (pm <= 1.0) {
      cat = MotionFailureCategory.trajectoryMismatch;
      feedback = primary != null && worst > 0.3
          ? 'Move your $primary more'
          : 'Try to match the movement more closely';
    } else if (_maxProgress >= 0.15 && _maxProgress < 0.8) {
      cat = MotionFailureCategory.motionIncomplete;
      feedback = 'You stopped before finishing';
    } else {
      cat = MotionFailureCategory.wrongMotion;
      feedback = 'Try the full movement';
    }

    return MotionAttemptResult(
      outcome: MotionAttemptOutcome.failed,
      failureCategory: cat,
      poseReadiness: _sawUntrackableMidAttempt
          ? PoseReadiness.lowVisibility.name
          : PoseReadiness.ready.name,
      maxProgress: _maxProgress,
      prototypeDistance: m.protoDist,
      prototypeThreshold: motion.acceptProtoDist,
      trajectoryDistance: 1.0 - m.trajSim,
      trajectoryThreshold: motion.acceptTrajDist,
      durationMs: durMs,
      expectedDurationMinMs: expMin,
      expectedDurationMaxMs: expMax,
      missingRegions: _missingMidAttempt.toList()..sort(),
      regionErrors: regionErr,
      primaryMismatchRegion: primary,
      cameraDistanceChange: _worstScale,
      rootTranslation: _worstRoot,
      encoderLatencyMs:
          DateTime.now().difference(t0).inMilliseconds.toDouble(),
      userFeedback: feedback,
    );
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
    required PoseQuality pq,
  }) {
    // The message the user should see: pose problem first (can't recognise a
    // movement you can't track), then the last attempt's feedback, then status.
    final attempt = _attemptActive
        ? const MotionAttemptResult(outcome: MotionAttemptOutcome.inProgress)
        : _lastAttempt;
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
      poseGuidance: pq.guidance,
      poseReadiness: pq.readiness.name,
      attempt: attempt,
    );
  }
}
