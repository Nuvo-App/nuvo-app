import 'dart:collection';
import 'dart:math' as math;

import '../../data/ai_motion_models.dart';
import 'pose_quality.dart';

/// A persistent view of the person being tracked — the same body continuing to
/// move, not a fresh pose sample every frame.
///
/// Per raw MLKit frame it produces a **smoothed** [NuvoPoseFrame] (One Euro
/// filter per joint), carries a briefly-missing joint forward, and maintains a
/// *temporal* readiness state with hysteresis (losing READY is deliberately
/// harder than keeping it) plus an articulation-energy signal that says when
/// the person actually started moving (root/scale-normalised, so walking into
/// position does not count).
///
/// Feeds both Teach Nuvo capture and the live verification test.
class PoseTrack {
  PoseTrack({
    this.graceFrames = 4,
    this.readyAcquireFrac = 0.65,
    this.readyWindow = 12,
    this.readyLoseBadFrames = 7,
    this.motionStartFrames = 3,
  });

  /// A joint missing for up to this many frames is carried forward (damped
  /// confidence) instead of dropped.
  final int graceFrames;

  /// Fraction of the recent window that must be trackable to ACQUIRE ready.
  final double readyAcquireFrac;
  final int readyWindow;

  /// Consecutive un-trackable frames required to LOSE ready once acquired.
  final int readyLoseBadFrames;

  /// Sustained frames of raised articulation energy to declare "motion started".
  final int motionStartFrames;

  final Map<String, _OneEuro> _fx = {};
  final Map<String, _OneEuro> _fy = {};
  final Map<String, _Carried> _carried = {};

  final Queue<bool> _trackableHist = Queue<bool>();
  int _consecutiveBad = 0;
  bool _ready = false;

  Map<String, ({double x, double y})>? _prevNorm;
  double? _energyBaseline;
  final Queue<double> _energyHist = Queue<double>();
  int _aboveBaseline = 0;
  bool _motionStarted = false;
  DateTime? _motionStartedAt;

  // rolling diagnostics
  int _framesSeen = 0;
  int _goodFrames = 0;
  int _interpolatedThisFrame = 0;
  int _smoothedThisFrame = 0;
  double _articulationEnergy = 0;
  PoseQuality _lastQuality = PoseQuality.noFrame;

  bool get isReady => _ready;
  bool get motionStarted => _motionStarted;
  DateTime? get motionStartedAt => _motionStartedAt;
  PoseQuality get quality => _lastQuality;
  double get articulationEnergy => _articulationEnergy;

  double get readyConfidence => _trackableHist.isEmpty
      ? 0
      : _trackableHist.where((x) => x).length / _trackableHist.length;

  /// One update. [raw] may be null (detector returned nothing this frame).
  /// Returns the smoothed frame (or null while there is nothing to smooth).
  NuvoPoseFrame? update(NuvoPoseFrame? raw, DateTime now) {
    _framesSeen++;
    _interpolatedThisFrame = 0;
    _smoothedThisFrame = 0;

    if (raw == null) {
      _noteTrackable(false);
      _lastQuality = PoseQuality.noFrame;
      return null;
    }

    final dt = _dtSeconds(now);
    final smoothedPts = <String, NuvoPosePoint>{};

    // union of joints we've ever seen + this frame's joints
    final names = <String>{...raw.points.keys, ..._carried.keys};
    for (final name in names) {
      final p = raw.points[name];
      if (p != null && p.likelihood >= 0.20) {
        final sx = (_fx[name] ??= _OneEuro()).filter(p.x, dt);
        final sy = (_fy[name] ??= _OneEuro()).filter(p.y, dt);
        smoothedPts[name] = NuvoPosePoint(
            x: sx, y: sy, z: p.z, likelihood: p.likelihood);
        _carried[name] = _Carried(sx, sy, p.likelihood, 0);
        _smoothedThisFrame++;
      } else {
        // missing / low-confidence this frame — carry forward within grace
        final c = _carried[name];
        if (c != null && c.missedFrames < graceFrames) {
          final missed = c.missedFrames + 1;
          _carried[name] = _Carried(c.x, c.y, c.likelihood, missed);
          smoothedPts[name] = NuvoPosePoint(
            x: c.x,
            y: c.y,
            z: 0,
            likelihood: c.likelihood * math.pow(0.6, missed).toDouble(),
          );
          _interpolatedThisFrame++;
        } else {
          _carried.remove(name);
          _fx.remove(name);
          _fy.remove(name);
        }
      }
    }

    final smoothed = NuvoPoseFrame(
      points: smoothedPts,
      imageWidth: raw.imageWidth,
      imageHeight: raw.imageHeight,
      createdAt: raw.createdAt,
    );

    // temporal readiness from the SMOOTHED frame
    final q = evaluatePoseQuality(smoothed);
    _lastQuality = q;
    final trackable =
        q.trackable || q.readiness == PoseReadiness.unstable;
    if (trackable) _goodFrames++;
    _noteTrackable(trackable);

    // articulation energy: root-relative, scale-normalised joint travel
    _updateArticulation(smoothed, dt);

    return smoothed;
  }

  void _noteTrackable(bool ok) {
    _trackableHist.addLast(ok);
    while (_trackableHist.length > readyWindow) {
      _trackableHist.removeFirst();
    }
    _consecutiveBad = ok ? 0 : _consecutiveBad + 1;

    if (!_ready) {
      if (_trackableHist.length >= (readyWindow * 0.6).ceil() &&
          readyConfidence >= readyAcquireFrac &&
          _lastQuality.readiness != PoseReadiness.noPerson) {
        _ready = true;
      }
    } else {
      // losing ready is hard — a few bad frames don't matter
      if (_consecutiveBad >= readyLoseBadFrames) {
        _ready = false;
        _motionStarted = false;
        _motionStartedAt = null;
        _energyBaseline = null;
        _aboveBaseline = 0;
      }
    }
  }

  void _updateArticulation(NuvoPoseFrame f, double dt) {
    final norm = _normalizedJoints(f);
    if (norm == null) {
      _articulationEnergy = 0;
      _prevNorm = null;
      return;
    }
    final prev = _prevNorm;
    _prevNorm = norm;
    if (prev == null) {
      _articulationEnergy = 0;
      return;
    }
    var sum = 0.0;
    var n = 0;
    for (final e in norm.entries) {
      final p = prev[e.key];
      if (p == null) continue;
      sum += math.sqrt(
          (e.value.x - p.x) * (e.value.x - p.x) +
              (e.value.y - p.y) * (e.value.y - p.y));
      n++;
    }
    final inst = n == 0 ? 0.0 : sum / n / math.max(dt, 1e-3);
    // light EMA
    _energyHist.addLast(inst);
    while (_energyHist.length > 10) {
      _energyHist.removeFirst();
    }
    _articulationEnergy =
        _energyHist.reduce((a, b) => a + b) / _energyHist.length;

    if (!_ready) return;
    // baseline = the quiet energy while ready and not yet moving
    if (!_motionStarted) {
      _energyBaseline = _energyBaseline == null
          ? _articulationEnergy
          : math.min(_energyBaseline!, _articulationEnergy);
      final base = math.max(_energyBaseline ?? 0, 1e-4);
      if (_articulationEnergy > base * 2.2 && _articulationEnergy > 0.04) {
        _aboveBaseline++;
        if (_aboveBaseline >= motionStartFrames) {
          _motionStarted = true;
          _motionStartedAt = f.createdAt;
        }
      } else {
        _aboveBaseline = math.max(0, _aboveBaseline - 1);
      }
    }
  }

  Map<String, ({double x, double y})>? _normalizedJoints(NuvoPoseFrame f) {
    ({double x, double y})? mid(String a, String b) {
      final pa = f.points[a], pb = f.points[b];
      final va = pa != null && pa.likelihood >= 0.2 ? pa : null;
      final vb = pb != null && pb.likelihood >= 0.2 ? pb : null;
      if (va != null && vb != null) {
        return (x: (va.x + vb.x) / 2, y: (va.y + vb.y) / 2);
      }
      if (va != null) return (x: va.x, y: va.y);
      if (vb != null) return (x: vb.x, y: vb.y);
      return null;
    }

    final root = mid('leftHip', 'rightHip');
    final neck = mid('leftShoulder', 'rightShoulder');
    if (root == null || neck == null) return null;
    final scale = math.sqrt((neck.x - root.x) * (neck.x - root.x) +
        (neck.y - root.y) * (neck.y - root.y));
    if (scale < 1e-4) return null;

    final out = <String, ({double x, double y})>{};
    for (final e in f.points.entries) {
      if (e.value.likelihood < 0.2) continue;
      out[e.key] = (
        x: (e.value.x - root.x) / scale,
        y: (e.value.y - root.y) / scale,
      );
    }
    return out;
  }

  double _dtSeconds(DateTime now) {
    final dt = _lastAt == null
        ? 1 / 30
        : now.difference(_lastAt!).inMicroseconds / 1e6;
    _lastAt = now;
    return dt.clamp(1 / 120, 1 / 5);
  }

  DateTime? _lastAt;

  /// Call when a fresh recording starts — keeps the smoothing filters warm but
  /// resets the motion-start detection.
  void armForCapture() {
    _motionStarted = false;
    _motionStartedAt = null;
    _energyBaseline = null;
    _aboveBaseline = 0;
  }

  void reset() {
    _fx.clear();
    _fy.clear();
    _carried.clear();
    _trackableHist.clear();
    _energyHist.clear();
    _consecutiveBad = 0;
    _ready = false;
    _prevNorm = null;
    _energyBaseline = null;
    _aboveBaseline = 0;
    _motionStarted = false;
    _motionStartedAt = null;
    _framesSeen = 0;
    _goodFrames = 0;
    _lastAt = null;
    _lastQuality = PoseQuality.noFrame;
    _articulationEnergy = 0;
  }

  Map<String, dynamic> toDiagnosticsJson() => {
        'framesSeen': _framesSeen,
        'goodFrameRatio': _framesSeen == 0 ? 0 : _goodFrames / _framesSeen,
        'readyConfidence': double.parse(readyConfidence.toStringAsFixed(3)),
        'ready': _ready,
        'consecutiveBadFrames': _consecutiveBad,
        'interpolatedJointCount': _interpolatedThisFrame,
        'smoothedJointCount': _smoothedThisFrame,
        'articulationEnergy': double.parse(_articulationEnergy.toStringAsFixed(4)),
        'energyBaseline': _energyBaseline == null
            ? null
            : double.parse(_energyBaseline!.toStringAsFixed(4)),
        'motionStarted': _motionStarted,
        'motionStartedAt': _motionStartedAt?.toIso8601String(),
        'readiness': _lastQuality.readiness.name,
        'guidance': _lastQuality.guidance,
      };
}

class _Carried {
  const _Carried(this.x, this.y, this.likelihood, this.missedFrames);
  final double x;
  final double y;
  final double likelihood;
  final int missedFrames;
}

/// One Euro filter (Casiez et al.) — smooths slow jitter, stays responsive as
/// velocity rises. Per scalar signal.
class _OneEuro {
  static const double minCutoff = 1.2; // Hz — jitter floor at rest
  static const double beta = 0.02; // responsiveness as speed rises
  static const double dCutoff = 1.0;

  double? _xPrev;
  double _dxPrev = 0;

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double x, double dt) {
    if (_xPrev == null) {
      _xPrev = x;
      return x;
    }
    final dx = (x - _xPrev!) / dt;
    final aD = _alpha(dCutoff, dt);
    final dxHat = _dxPrev + aD * (dx - _dxPrev);
    final cutoff = minCutoff + beta * dxHat.abs();
    final aX = _alpha(cutoff, dt);
    final xHat = _xPrev! + aX * (x - _xPrev!);
    _xPrev = xHat;
    _dxPrev = dxHat;
    return xHat;
  }
}
