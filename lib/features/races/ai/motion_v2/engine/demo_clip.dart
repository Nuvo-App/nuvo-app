import '../../../data/ai_motion_models.dart';

/// Drops the walk-in / walk-out from a taught demo.
///
/// A person starts a demo standing at the phone (huge in frame), walks back to
/// the spot where they move (small in frame), moves, then walks back to stop
/// it. Shoulder width is a cheap distance gauge: large at the phone, steady at
/// the working spot. The clip keeps the longest settled stretch at working
/// distance and drops the rest.
///
/// Returns [frames] unchanged when there is no clear phone <-> working-spot
/// size difference (the person never came from/went to the phone), when the
/// pose is too sparse to judge, or when the clip would be too short.
const double kClipMinSizeRatio = 1.6;
const double kClipSettleFactor = 1.35;
const int kClipMinFrames = 24;
const int kClipGapFrames = 5;

class DemoClip {
  const DemoClip(this.frames, this.start, this.end, this.workingSize);
  final List<NuvoPoseFrame> frames;
  final int start;
  final int end; // exclusive
  final double? workingSize; // typical shoulder width at the working spot
  bool get clipped => start > 0 || end < frames.length;
}

double? shoulderWidth(NuvoPoseFrame f) {
  final l = f.points['leftShoulder'], r = f.points['rightShoulder'];
  if (l == null || r == null || l.likelihood < 0.3 || r.likelihood < 0.3) {
    return null;
  }
  final dx = l.x - r.x, dy = l.y - r.y;
  return (dx * dx + dy * dy) == 0 ? null : _sqrt(dx * dx + dy * dy);
}

double _sqrt(double v) {
  var x = v > 1 ? v : 1.0;
  for (var i = 0; i < 40; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

double _pct(List<double> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

DemoClip clipDemoToWorkingSpot(List<NuvoPoseFrame> frames) {
  DemoClip whole() => DemoClip(frames, 0, frames.length, null);
  final raw = [for (final f in frames) shoulderWidth(f)];
  final valid = <double>[...raw.nonNulls]..sort();
  if (valid.length < kClipMinFrames) return whole();
  final far = _pct(valid, 0.2), near = _pct(valid, 0.9);
  if (far <= 0 || near / far < kClipMinSizeRatio) return whole();

  // 5-frame median so one noisy shoulder doesn't break the run.
  final size = List<double?>.filled(raw.length, null);
  for (var i = 0; i < raw.length; i++) {
    final w = <double>[
      for (var j = i - 2; j <= i + 2; j++)
        if (j >= 0 && j < raw.length && raw[j] != null) raw[j]!,
    ]..sort();
    if (w.length >= 3) size[i] = w[w.length ~/ 2];
  }
  final limit = far * kClipSettleFactor;

  // Longest run of settled-at-working-distance frames, bridging short gaps.
  var bestS = -1, bestE = -1, runS = -1, lastIn = -1;
  void close() {
    if (runS >= 0 && lastIn - runS > bestE - bestS) {
      bestS = runS;
      bestE = lastIn;
    }
  }

  for (var i = 0; i < size.length; i++) {
    final s = size[i];
    if (s != null && s <= limit) {
      if (runS < 0) runS = i;
      lastIn = i;
    } else if (runS >= 0 && i - lastIn > kClipGapFrames) {
      close();
      runS = -1;
    }
  }
  close();
  if (bestS < 0) return whole();
  final s = (bestS - 3).clamp(0, frames.length);
  final e = (bestE + 4).clamp(0, frames.length);
  if (e - s < kClipMinFrames) return whole();
  return DemoClip(frames.sublist(s, e), s, e, far);
}
