import 'dart:math' as math;
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';

/// Nuvo pose stream -> MotionBERT 17-joint H36M skeleton.
/// 1:1 port of `tools/motion_v2/adapter/nuvo_to_h36m.py`. Parity-tested against
/// `test/fixtures/motion_v2_golden.json` (`h36m_*`).
///
/// Output: `List<Float32List>` of length T, each row 17*3 = 51 floats laid out
/// joint-major `[j0x, j0y, j0c, j1x, ...]`. Coords sequence-normalized to
/// [-1, 1] via MotionBERT's exact `crop_scale`.

const int kNumJoints = 17;
const double _minLikelihood = 0.30;

// H36M-17 (from MotionBERT dataset_action.coco2h36m):
//  0 root 1 rhip 2 rknee 3 rank 4 lhip 5 lknee 6 lank
//  7 belly 8 neck 9 nose 10 head 11 lsho 12 lelb 13 lwri 14 rsho 15 relb 16 rwri
const List<int> h36mLeft = [4, 5, 6, 11, 12, 13];
const List<int> h36mRight = [1, 2, 3, 14, 15, 16];

// each H36M joint = mean of these Nuvo landmarks (belly & head are derived).
const Map<int, List<String>> _map = {
  0: ['leftHip', 'rightHip'],
  1: ['rightHip'],
  2: ['rightKnee'],
  3: ['rightAnkle'],
  4: ['leftHip'],
  5: ['leftKnee'],
  6: ['leftAnkle'],
  8: ['leftShoulder', 'rightShoulder'],
  9: ['nose'],
  10: ['leftEar', 'rightEar'],
  11: ['leftShoulder'],
  12: ['leftElbow'],
  13: ['leftWrist'],
  14: ['rightShoulder'],
  15: ['rightElbow'],
  16: ['rightWrist'],
};

const List<List<int>> h36mBones = [
  [0, 1], [1, 2], [2, 3], [0, 4], [4, 5], [5, 6],
  [0, 7], [7, 8], [8, 9], [9, 10],
  [8, 11], [11, 12], [12, 13], [8, 14], [14, 15], [15, 16],
];

/// One frame's landmark map -> (17, 3) as a flat Float32List(51).
Float32List _frameToH36m(Map<String, NuvoPosePoint> pts) {
  final out = Float32List(kNumJoints * 3);
  ({double x, double y, double c})? pt(String name) {
    final p = pts[name];
    if (p == null || p.likelihood < _minLikelihood) return null;
    return (x: p.x, y: p.y, c: p.likelihood);
  }

  _map.forEach((j, names) {
    final got = [for (final n in names) pt(n)].whereType<({double x, double y, double c})>().toList();
    if (got.isEmpty) return;
    var sx = 0.0, sy = 0.0, mc = double.infinity;
    for (final g in got) {
      sx += g.x;
      sy += g.y;
      mc = math.min(mc, g.c);
    }
    out[j * 3] = sx / got.length;
    out[j * 3 + 1] = sy / got.length;
    out[j * 3 + 2] = mc;
  });

  // belly = midpoint(root, neck)
  if (out[0 * 3 + 2] > 0 && out[8 * 3 + 2] > 0) {
    out[7 * 3] = 0.5 * (out[0] + out[8 * 3]);
    out[7 * 3 + 1] = 0.5 * (out[1] + out[8 * 3 + 1]);
    out[7 * 3 + 2] = math.min(out[0 * 3 + 2], out[8 * 3 + 2]);
  }
  // head fallback: ears missing -> extrapolate above nose along nose->neck
  if (out[10 * 3 + 2] == 0 && out[9 * 3 + 2] > 0 && out[8 * 3 + 2] > 0) {
    out[10 * 3] = out[9 * 3] + (out[9 * 3] - out[8 * 3]) * 0.5;
    out[10 * 3 + 1] = out[9 * 3 + 1] + (out[9 * 3 + 1] - out[8 * 3 + 1]) * 0.5;
    out[10 * 3 + 2] = out[9 * 3 + 2] * 0.5;
  }
  return out;
}

/// Linearly interpolate short confidence gaps per joint; interpolated frames
/// get a damped confidence. == np `_fill_gaps`.
void _fillGaps(List<Float32List> seq) {
  final t = seq.length;
  for (var j = 0; j < kNumJoints; j++) {
    final valid = <int>[];
    for (var i = 0; i < t; i++) {
      if (seq[i][j * 3 + 2] > 0) valid.add(i);
    }
    if (valid.isEmpty || valid.length == t) continue;
    for (var i = 0; i < t; i++) {
      if (seq[i][j * 3 + 2] > 0) continue;
      // find bracketing valid indices
      int lo = valid.first, hi = valid.last;
      for (final v in valid) {
        if (v <= i) lo = v;
        if (v >= i) {
          hi = v;
          break;
        }
      }
      final span = (hi - lo);
      final w = span == 0 ? 0.0 : (i - lo) / span;
      for (var c = 0; c < 2; c++) {
        seq[i][j * 3 + c] = seq[lo][j * 3 + c] * (1 - w) + seq[hi][j * 3 + c] * w;
      }
      final ci = seq[lo][j * 3 + 2] * (1 - w) + seq[hi][j * 3 + 2] * w;
      seq[i][j * 3 + 2] = ci * 0.5;
    }
  }
}

/// MotionBERT's exact 2D `crop_scale` normalizer (scale_range=[1,1]).
/// Uses only conf!=0 coords for the bbox; leaves the confidence channel alone.
void _cropScale(List<Float32List> seq) {
  double xmin = double.infinity, xmax = -double.infinity;
  double ymin = double.infinity, ymax = -double.infinity;
  var valid = 0;
  for (final f in seq) {
    for (var j = 0; j < kNumJoints; j++) {
      if (f[j * 3 + 2] == 0) continue;
      valid++;
      xmin = math.min(xmin, f[j * 3]);
      xmax = math.max(xmax, f[j * 3]);
      ymin = math.min(ymin, f[j * 3 + 1]);
      ymax = math.max(ymax, f[j * 3 + 1]);
    }
  }
  if (valid < 4) {
    for (final f in seq) {
      f.fillRange(0, f.length, 0);
    }
    return;
  }
  final scale = math.max(xmax - xmin, ymax - ymin);
  if (scale == 0) {
    for (final f in seq) {
      f.fillRange(0, f.length, 0);
    }
    return;
  }
  final xs = (xmin + xmax - scale) / 2;
  final ys = (ymin + ymax - scale) / 2;
  for (final f in seq) {
    for (var j = 0; j < kNumJoints; j++) {
      var x = (f[j * 3] - xs) / scale;
      var y = (f[j * 3 + 1] - ys) / scale;
      x = (x - 0.5) * 2;
      y = (y - 0.5) * 2;
      f[j * 3] = x.clamp(-1.0, 1.0);
      f[j * 3 + 1] = y.clamp(-1.0, 1.0);
    }
  }
}

/// Full pipeline. == np `frames_to_h36m(frames, mirror=mirror)`.
List<Float32List> framesToH36m(List<NuvoPoseFrame> frames, {bool mirror = false}) {
  if (frames.isEmpty) return const [];
  final seq = [for (final f in frames) _frameToH36m(f.points)];
  _fillGaps(seq);
  _cropScale(seq);
  if (mirror) {
    for (final f in seq) {
      for (var j = 0; j < kNumJoints; j++) {
        f[j * 3] = -f[j * 3];
      }
      for (var k = 0; k < h36mLeft.length; k++) {
        final l = h36mLeft[k], r = h36mRight[k];
        for (var c = 0; c < 3; c++) {
          final tmp = f[l * 3 + c];
          f[l * 3 + c] = f[r * 3 + c];
          f[r * 3 + c] = tmp;
        }
      }
    }
  }
  return seq;
}

/// per-joint fraction of frames with confidence > 0.
Map<String, double> h36mCoverage(List<Float32List> seq) {
  const names = ['root', 'rhip', 'rknee', 'rank', 'lhip', 'lknee', 'lank',
    'belly', 'neck', 'nose', 'head', 'lsho', 'lelb', 'lwri', 'rsho', 'relb', 'rwri'];
  final out = <String, double>{};
  if (seq.isEmpty) {
    for (final n in names) {
      out[n] = 0;
    }
    return out;
  }
  for (var j = 0; j < kNumJoints; j++) {
    var c = 0;
    for (final f in seq) {
      if (f[j * 3 + 2] != 0) c++;
    }
    out[names[j]] = c / seq.length;
  }
  return out;
}
