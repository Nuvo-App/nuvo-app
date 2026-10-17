import 'dart:math' as math;
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';
import '../motion_v2_models.dart';
import '../pose_quality.dart';
import 'demo_clip.dart' show shoulderWidth;
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
  StreamingMotionV2(
    this.motion,
    this.encoder, {
    double fpsHint = 15.0,
    this.background,
  }) : _bufCap = math.max(30, (5.0 * fpsHint).round());

  final TaughtMotionV2 motion;
  final MotionEncoderV2 encoder;

  /// Generic-motion anchors for the separation margin (see MotionV2Background).
  final List<Float32List>? background;

  final int _bufCap;

  static const int _minFrames = 8;
  static const int _reevalEvery = 3;
  // Defaults — overridable per-spec via spec.tuning (server-patchable, no app
  // update). Keys: matchScore, neutralDrop, repMinProgress.
  static const double _defaultNeutralDrop = 0.55;
  static const double _defaultMatchScore = 0.5;
  // A rep requires an attempt that actually traversed the movement — a
  // transient same-family window (e.g. walking back to the start position,
  // which can share the demos' approach shape) must not count. The attempt
  // must have covered most of the canonical trajectory AND lasted at least
  // half the shortest demo.
  static const double _defaultRepMinProgress = 0.55;
  // Progress position at which the next rep re-arms — "back at the start of
  // the movement". Tunable via spec.tuning['repRearmProgress'].
  static const double _defaultRepRearmProgress = 0.30;

  final List<NuvoPoseFrame> _buf = [];

  double get _matchScore => motion.tuning['matchScore'] ?? _defaultMatchScore;
  double get _neutralDrop =>
      motion.tuning['neutralDrop'] ?? _defaultNeutralDrop;
  double get _repMinProgress =>
      motion.tuning['repMinProgress'] ?? _defaultRepMinProgress;
  double get _repRearmProgress =>
      motion.tuning['repRearmProgress'] ?? _defaultRepRearmProgress;
  // Rep search inside the window (spec.tuning['subwindow'] = 0 turns it off and
  // restores whole-window matching — server-patchable, no app update).
  bool get _subwindow => (motion.tuning['subwindow'] ?? 1.0) >= 0.5;
  // Absolute frame index where the last counted rep ended (-1 = none yet).
  int _lastCountedEnd = -1;
  // How much bigger than the working-spot size means "at the phone".
  double get _phoneFactor => motion.tuning['phoneFactor'] ?? 1.8;
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
    _lastCountedEnd = -1;
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
    final pq = evaluatePoseQuality(
      _buf.isEmpty ? null : _buf.last,
      recent: recent,
    );

    if (_framesSeen < _minFrames) {
      return _result(false, 0, 0, MotionV2RuntimeState.warmingUp, t0, pq: pq);
    }
    if (_sinceEval < _reevalEvery && _last != MotionV2RuntimeResult.empty) {
      return _last;
    }
    // Nothing is moving (waiting, standing at the phone): the last verdict
    // stands, so don't spend a model pass (~2-6s on a phone) on it. One eval
    // still runs after the movement stops, so a rep finishing right as the
    // person freezes is counted.
    if (_isStill()) {
      if (_stillEvaled) {
        _sinceEval = 0;
        return _last;
      }
      _stillEvaled = true;
    } else {
      _stillEvaled = false;
    }
    _sinceEval = 0;

    final hDiag = framesToH36mDiag(_buf);
    final h = hDiag.seq;
    final rep = await encoder.encode(h);
    final emb = perFrameEmbedding(rep);
    var m = motion.matchEncoded(rep, emb, background: background);
    List<List<Float32List>>? repM;
    List<Float32List>? embM;
    // Reps found INSIDE the window (several per eval); empty in whole-window mode.
    var found = _subwindow
        ? _findReps(rep, emb, null, null)
        : const <_RepHit>[];
    // The mirrored encoder pass (left/right-handed invariance) doubles the
    // cost of every eval, and on a phone each pass is ~1s — enough to lag the
    // camera and miss reps. Run it only when nothing matched on the direct
    // pass: during a rep (the evals that count) one pass is enough.
    final directMatched = _subwindow
        ? found.isNotEmpty || (m.isSameFamily && m.score >= _matchScore)
        : (m.isSameFamily && m.score >= _matchScore);
    if (!directMatched) {
      final hm = framesToH36m(_buf, mirror: true);
      repM = await encoder.encode(hm);
      embM = perFrameEmbedding(repM);
      m = motion.matchEncoded(
        rep,
        emb,
        repM: repM,
        embM: embM,
        background: background,
      );
      if (_subwindow) found = _findReps(rep, emb, repM, embM);
    }
    if (_subwindow && found.isNotEmpty) {
      final best = found.reduce((a, b) => a.m.score >= b.m.score ? a : b);
      if (best.m.score > m.score) m = best.m;
    }

    final seg = segmentAction(emb);
    final activeLen = seg.end - seg.start;
    final embSeg = activeLen >= 4 ? sliceSeq(emb, seg.start, seg.end) : emb;
    final prog = _progress(embSeg);

    // ── Attempt lifecycle ────────────────────────────────────────────────
    final v = embeddingVelocity(emb);
    final vSeg = activeLen >= 4
        ? [for (var i = seg.start; i < seg.end; i++) v[i]]
        : v;
    final movementNow =
        activeLen >= 4 &&
        (motion.demoActiveVel <= 0 ||
            median(vSeg) > motion.demoActiveVel * 0.35);

    if (!_attemptActive && movementNow && pq.trackable) {
      _resetAttempt();
      _attemptActive = true;
      // Frame time, not wall clock — a fast encoder must not let a
      // short motion pass the duration gate by feeding frames quickly.
      _attemptStart = _buf.last.createdAt;
    }
    if (_attemptActive) {
      _maxProgress = math.max(_maxProgress, prog);
      _bestProtoMargin = math.min(_bestProtoMargin, m.protoMargin);
      _bestTrajMargin = math.min(
        _bestTrajMargin,
        1.0 - m.trajSim <= 0 ? 0 : (1.0 - m.trajSim) / motion.acceptTrajDist,
      );
      _worstScale = math.max(_worstScale, hDiag.diag.scaleChangeFraction);
      _worstRoot = math.max(_worstRoot, hDiag.diag.rootTranslationMagnitude);
      if (!pq.trackable) _sawUntrackableMidAttempt = true;
      _missingMidAttempt.addAll(pq.missingRegions.map(bodyRegionLabel));
    }

    var newRep = false;
    if (m.isSameFamily && m.score >= _matchScore) {
      _inMatch = true;
      // Count when the match comes with a real attempt behind it — progress
      // through the canonical path + plausible duration — not merely a single
      // high-scoring window.
      if (!_subwindow && _armed && _repEligible()) {
        _count++;
        newRep = true;
        _armed = false;
        _lastAttempt = _successAttempt(h, hDiag.diag, t0);
        _resetAttempt();
      }
      // Re-arm on return-to-start, not only on match-break: for movements
      // whose rest pose is INSIDE the family (hanging on the bar between
      // pull-ups), the score never drops below the match line, so without
      // this the count freezes at 1 forever — exactly what session
      // ms_c39db497 showed (one rep across 17s of continuous matching).
      if (!_armed && prog <= _repRearmProgress) _armed = true;
    } else {
      _inMatch = false;
      if (m.score < _neutralDrop) _armed = true;
      // Attempt ended without a match → explain why.
      if (_attemptActive && !movementNow) {
        _lastAttempt = _failAttempt(h, hDiag.diag, m, embSeg, t0);
        _resetAttempt();
      }
      if (!_subwindow && _armed && _count > 0 && _buf.length > _minFrames) {
        _buf.removeRange(0, _buf.length - _minFrames);
      }
    }

    if (_subwindow) {
      for (final hit in found) {
        // A rep counts once: it must not overlap the previous counted rep.
        final len = hit.end - hit.start;
        if (_lastCountedEnd >= 0 &&
            hit.start < _lastCountedEnd - (0.3 * len).round()) {
          continue;
        }
        _count++;
        newRep = true;
        _lastCountedEnd = hit.end;
        _inMatch = true;
        _lastAttempt = _successAttempt(h, hDiag.diag, t0);
        _resetAttempt();
      }
      if (found.isNotEmpty) _inMatch = true;
    }

    final state = _inMatch
        ? MotionV2RuntimeState.matching
        : (_armed
              ? MotionV2RuntimeState.neutral
              : MotionV2RuntimeState.returning);

    final r = _result(
      newRep,
      m.score,
      prog,
      state,
      t0,
      protoDist: m.protoDist,
      protoMargin: m.protoMargin,
      trajSim: m.trajSim,
      rootDrift: hDiag.diag.rootTranslationMagnitude,
      scaleSpread: hDiag.diag.scaleChangeFraction,
      pq: pq,
      match: m,
    );
    _last = r;
    return r;
  }

  /// Look for the taught rep INSIDE the current window: slide candidate
  /// lengths around the taught rep length over the embeddings, score each
  /// slice with the same matcher, and keep the best non-overlapping matches.
  /// This is what lets several reps count per eval, and keeps the mount /
  /// walk-up / walk-off around a rep out of the match.
  List<_RepHit> _findReps(
    List<List<Float32List>> rep,
    List<Float32List> emb,
    List<List<Float32List>>? repM,
    List<Float32List>? embM,
  ) {
    final w = emb.length;
    final lens = [...motion.demoLengths]..sort();
    if (w < 8 || lens.isEmpty) return const [];
    final refLen = lens[lens.length ~/ 2];
    final v = embeddingVelocity(emb);
    final minVel = motion.demoActiveVel > 0 ? motion.demoActiveVel * 0.35 : 0.0;
    final base = _framesSeen - w;
    final cands = <_RepHit>[];
    final seen = <int>{};
    for (final f in const [0.8, 1.0, 1.25]) {
      // A slice much shorter than the taught rep would be time-stretched to
      // fit it (a mount or a few warm-up frames then "matches") — a candidate
      // must cover at least 70% of the taught rep, and the window must be
      // able to hold it.
      var len = (refLen * f).round();
      if (len > w) len = w;
      if (len < (refLen * 0.7).round()) continue;
      if (!seen.add(len)) continue;
      final stride = math.max(2, len ~/ 8);
      for (var e = w; e - len >= 0; e -= stride) {
        final s = e - len;
        // A rep needs real movement inside it — stillness never counts.
        if (minVel > 0 && median(v.sublist(s, e)) <= minVel) continue;
        // Standing at the phone (walking up to stop, or just arrived) is not
        // a rep: the taught reps were done at the working spot, far smaller
        // in frame.
        if (_atPhone(s, e)) continue;
        final mm = motion.matchEncoded(
          rep,
          emb,
          repM: repM,
          embM: embM,
          background: background,
          window: (start: s, end: e),
        );
        if (mm.isSameFamily && mm.score >= _matchScore) {
          cands.add(_RepHit(base + s, base + e, mm));
        }
      }
    }
    cands.sort((a, b) => b.m.score.compareTo(a.m.score));
    final picked = <_RepHit>[];
    for (final c in cands) {
      final free = picked.every((p) {
        final overlap = math.min(p.end, c.end) - math.max(p.start, c.start);
        final shorter = math.min(p.end - p.start, c.end - c.start);
        return overlap <= 0.3 * shorter;
      });
      if (free) picked.add(c);
    }
    picked.sort((a, b) => a.start.compareTo(b.start));
    return picked;
  }

  bool _stillEvaled = false;
  static const int _stillFrames = 15;
  static const double _stillSpread = 0.025;
  static const List<String> _stillJoints = [
    'nose',
    'leftWrist',
    'rightWrist',
    'leftElbow',
    'rightElbow',
    'leftAnkle',
    'rightAnkle',
    'leftHip',
    'rightHip',
  ];

  /// True when the key joints stayed within ~2.5% of the frame over the last
  /// half-second. Missing joints never count as still (stay safe: evaluate).
  bool _isStill() {
    if ((motion.tuning['idleSkip'] ?? 1.0) < 0.5) return false;
    if (_buf.length < _stillFrames) return false;
    final recent = _buf.sublist(_buf.length - _stillFrames);
    for (final j in _stillJoints) {
      var minX = 2.0, maxX = -1.0, minY = 2.0, maxY = -1.0;
      for (final f in recent) {
        final p = f.points[j];
        if (p == null || p.likelihood < 0.3) return false;
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      if (maxX - minX > _stillSpread || maxY - minY > _stillSpread) {
        return false;
      }
    }
    return true;
  }

  /// True when the person fills the frame far more than they did while
  /// teaching (spec.tuning['workingSize'] = shoulder width at the working
  /// spot): they are at the phone, not at the working spot.
  bool _atPhone(int s, int e) {
    final ws = motion.tuning['workingSize'];
    if (ws == null || ws <= 0 || e > _buf.length) return false;
    final sizes = <double>[for (var i = s; i < e; i++) ?shoulderWidth(_buf[i])]
      ..sort();
    if (sizes.length < 3) return false;
    return sizes[sizes.length ~/ 2] > ws * _phoneFactor;
  }

  /// A match counts as a rep only inside an attempt that has traversed most
  /// of the taught canonical path and lasted at least half the shortest demo.
  /// Without this, the very first same-family window — e.g. the user still
  /// walking back into position, whose pose stream can resemble the demos'
  /// approach shape — registers as a rep before the movement even starts.
  bool _repEligible() {
    if (!_attemptActive) return false;
    if (_maxProgress < _repMinProgress) return false;
    if (motion.demoLengths.isEmpty) return true;
    final expMinMs =
        motion.demoLengths.reduce(math.min) * _framePeriodMs() * 0.5;
    final durMs = _attemptStart == null
        ? 0
        : _buf.last.createdAt.difference(_attemptStart!).inMilliseconds;
    return durMs >= expMinMs;
  }

  // ── Attempt result builders ──────────────────────────────────────────────

  MotionAttemptResult _successAttempt(
    List<Float32List> h,
    MotionInputDiagnostics diag,
    DateTime t0,
  ) {
    final durMs = _attemptStart == null
        ? 0
        : _buf.last.createdAt.difference(_attemptStart!).inMilliseconds;
    return MotionAttemptResult(
      outcome: MotionAttemptOutcome.success,
      poseReadiness: PoseReadiness.ready.name,
      maxProgress: 1.0,
      durationMs: durMs,
      encoderLatencyMs: DateTime.now().difference(t0).inMilliseconds.toDouble(),
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
        : _buf.last.createdAt.difference(_attemptStart!).inMilliseconds;
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
      regionErr[region] = taught <= 1e-6
          ? 0.0
          : math.max(0.0, (taught - live) / taught);
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
      encoderLatencyMs: DateTime.now().difference(t0).inMilliseconds.toDouble(),
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
    MatchResultV2? match,
  }) {
    // The message the user should see: pose problem first (can't recognise a
    // movement you can't track), then the last attempt's feedback, then status.
    final attempt = _attemptActive
        ? const MotionAttemptResult(outcome: MotionAttemptOutcome.inProgress)
        : _lastAttempt;
    return MotionV2RuntimeResult(
      votes: match?.votes ?? 0,
      separation: match?.separation,
      decision: match?.decision ?? 'reject',
      perReference: [for (final p in match?.perRef ?? const []) p.toJson()],
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

/// A rep found inside the live window, in absolute frame indices.
class _RepHit {
  _RepHit(this.start, this.end, this.m);
  final int start;
  final int end;
  final MatchResultV2 m;
}
