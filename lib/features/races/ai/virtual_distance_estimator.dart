import 'dart:math' as math;

/// Turns the treadmill-running gait signal into an **estimated virtual
/// distance** — how far the athlete would have travelled if they were moving
/// forward instead of running in place.
///
/// It is deliberately cheap: it runs off signals the gait detector already
/// produces (confirmed alternating steps, the knee-swing amplitude, torso
/// scale) — no per-frame inference, no extra pose passes. One confirmed step
/// adds one smoothed stride length; nothing else adds distance, so standing
/// still and random shifting contribute zero.
///
/// It is also deliberately imprecise. A monocular camera cannot recover true
/// ground speed, so this is a biomechanically-plausible estimate: faster /
/// higher-drive running produces a longer stride and (via more steps per
/// second) more distance per unit time; a shuffle produces less. Everything
/// is rounded and smoothed so the number never jumps on a single frame.
class VirtualDistanceEstimator {
  // Stride model (metres per step). An in-place step "covers" less than a
  // real running stride (~1.4-1.6 m) because we are estimating effort-
  // equivalent forward travel, not measuring it.
  static const double _minStride = 0.45;
  static const double _maxStride = 1.45;
  static const double _baseStride = 0.55;
  static const double _driveSpan = 0.75;
  static const double _strideEmaAlpha = 0.25;

  // Knee-drive normalization: swing/torso below this reads as a shuffle,
  // above the top as a hard drive.
  static const double _driveLo = 0.15;
  static const double _driveHi = 0.55;

  // Cadence + pace are read over a trailing window and go stale when steps
  // stop. A window (not an inter-step interval) keeps both steady through the
  // gait detector's sub-stride jitter.
  static const int _windowMs = 9000;
  static const int _staleMs = 4000;
  static const double _metresPerMile = 1609.344;

  double _metres = 0;
  double _smoothedStride = _baseStride;
  double _lastDriveFactor = 0;
  int? _lastStepMs;
  int _lastFrameMs = 0;

  /// (elapsedMs, cumulative metres) at each confirmed step — the trailing
  /// window for both cadence and pace.
  final List<({int t, double m})> _window = [];

  double get metres => _metres;

  void reset() {
    _metres = 0;
    _smoothedStride = _baseStride;
    _lastDriveFactor = 0;
    _lastStepMs = null;
    _lastFrameMs = 0;
    _window.clear();
  }

  /// Call once per processed frame so cadence / pace age out when the athlete
  /// stops.
  void onFrame(int elapsedMs) {
    _lastFrameMs = elapsedMs;
    _trim(elapsedMs);
  }

  void _trim(int now) {
    while (_window.length > 1 && now - _window.first.t > _windowMs) {
      _window.removeAt(0);
    }
  }

  /// One confirmed alternating step. [swingAmplitude] and [torsoHeight] are the
  /// gait detector's own numbers; [elapsedMs] is the frame time.
  void onStep({
    required double swingAmplitude,
    required double torsoHeight,
    required int elapsedMs,
  }) {
    final scale = torsoHeight <= 0 ? 0.16 : torsoHeight;
    final driveFactor =
        ((swingAmplitude.abs() / scale) - _driveLo) / (_driveHi - _driveLo);
    _lastDriveFactor = driveFactor.clamp(0.0, 1.0);
    _lastStepMs = elapsedMs;

    final hz = _cadenceHz;
    final cadenceStretch = 0.85 + 0.15 * ((hz - 1.5) / 1.5).clamp(0.0, 1.0);
    final targetStride =
        ((_baseStride + _driveSpan * _lastDriveFactor) * cadenceStretch)
            .clamp(_minStride, _maxStride);
    _smoothedStride += _strideEmaAlpha * (targetStride - _smoothedStride);
    _metres += _smoothedStride;

    _window.add((t: elapsedMs, m: _metres));
    _trim(elapsedMs);
  }

  /// Steps per second over the trailing window (0 when stale / too few).
  /// Capped at a sane human ceiling so a burst of gait-detector jitter can't
  /// spike it.
  double get _cadenceHz {
    if (_isStale || _window.length < 2) return 0;
    final span = (_window.last.t - _window.first.t) / 1000.0;
    if (span < 1.0) return 0;
    return math.min((_window.length - 1) / span, 3.5);
  }

  double get cadenceStepsPerMinute => _cadenceHz * 60;

  bool get _isStale =>
      _lastStepMs == null || _lastFrameMs - _lastStepMs! > _staleMs;

  /// Seconds per mile — derived from `cadence × stride` so it stays consistent
  /// with the distance that is accumulating (a trailing-slope estimate drifts
  /// against it). Null when stale / not enough signal.
  double? get paceSecondsPerMile {
    if (_isStale || _window.length < 3) return null;
    final speedMps = _cadenceHz * _smoothedStride;
    if (speedMps < 0.4) return null;
    return _metresPerMile / speedMps;
  }

  /// 0 (idle) · 1 (easy) · 2 (moderate) · 3 (hard) — a coarse effort bucket
  /// from cadence + knee drive, never frame-jittery.
  int get intensityLevel {
    if (_cadenceHz <= 0.2) return 0;
    final cadenceScore = ((_cadenceHz - 1.4) / 1.4).clamp(0.0, 1.0);
    final composite = 0.6 * cadenceScore + 0.4 * _lastDriveFactor;
    if (composite < 0.28) return 1;
    if (composite < 0.62) return 2;
    return 3;
  }

  String get intensityLabel => switch (intensityLevel) {
        0 => 'Ready',
        1 => 'Easy',
        2 => 'Moderate',
        _ => 'Hard',
      };

  /// Snapshot for `debugValues` / telemetry.
  Map<String, double> get metrics => {
        'virtualDistanceM': _round(_metres),
        'cadenceSpm': _round(cadenceStepsPerMinute),
        'strideM': _round(_smoothedStride),
        'paceSecPerMile': _round(paceSecondsPerMile ?? 0),
        'intensity': intensityLevel.toDouble(),
      };

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// Convenience for the completion check / result.
  int get metresRounded => math.max(0, _metres.round());
}
