import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic vector/sequence math for Motion V2 — a 1:1 port of
/// `tools/motion_v2/experiments/lib_repr.py` + the helpers in
/// `engine/taught_motion.py`. Parity-tested against Python golden fixtures
/// (`test/motion_v2_engine_test.dart`).
///
/// Convention: a "vector" is a `Float32List`; a "sequence" is `List<Float32List>`
/// (T rows). A rep is `List<List<Float32List>>` (T x J x D).

Float32List l2norm(Float32List v) {
  var n = 0.0;
  for (final x in v) {
    if (x.isFinite) n += x * x;
  }
  n = math.sqrt(n) + 1e-8;
  final out = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    final x = v[i];
    out[i] = (x.isFinite ? x : 0.0) / n;
  }
  return out;
}

List<Float32List> l2normSeq(List<Float32List> seq) =>
    [for (final r in seq) l2norm(r)];

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

double l2dist(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = a[i] - b[i];
    s += d * d;
  }
  return math.sqrt(s);
}

/// (T, J, D) -> (D,) : mean over time AND joints.  == np `rep.mean(axis=(0,1))`
Float32List meanPool(List<List<Float32List>> rep) {
  final d = rep.first.first.length;
  final acc = Float64List(d);
  var count = 0;
  for (final frame in rep) {
    for (final joint in frame) {
      for (var k = 0; k < d; k++) {
        acc[k] += joint[k];
      }
      count++;
    }
  }
  final out = Float32List(d);
  for (var k = 0; k < d; k++) {
    out[k] = acc[k] / count;
  }
  return out;
}

/// (T, J, D) -> (T, D) : mean over joints per frame, then L2-normalize each row.
/// == np `_l2n(rep.mean(axis=1))`
List<Float32List> perFrameEmbedding(List<List<Float32List>> rep) {
  final d = rep.first.first.length;
  final out = <Float32List>[];
  for (final frame in rep) {
    final row = Float64List(d);
    for (final joint in frame) {
      for (var k = 0; k < d; k++) {
        row[k] += joint[k];
      }
    }
    final f = Float32List(d);
    for (var k = 0; k < d; k++) {
      f[k] = row[k] / frame.length;
    }
    out.add(l2norm(f));
  }
  return out;
}

/// Linear-interp resample a sequence to [target] rows. == np `resample_seq`.
List<Float32List> resampleSeq(List<Float32List> seq, int target) {
  final t = seq.length;
  if (t == target) return seq;
  final d = seq.first.length;
  final out = <Float32List>[];
  for (var i = 0; i < target; i++) {
    final idx = target == 1 ? 0.0 : i * (t - 1) / (target - 1);
    final lo = idx.floor();
    final hi = math.min(lo + 1, t - 1);
    final w = idx - lo;
    final row = Float32List(d);
    for (var k = 0; k < d; k++) {
      row[k] = seq[lo][k] * (1 - w) + seq[hi][k] * w;
    }
    out.add(row);
  }
  return out;
}

/// Sakoe-Chiba banded DTW, cosine local cost. == np `dtw_distance`.
/// Re-L2-normalizes both inputs (matches Python).
double dtwDistance(List<Float32List> a, List<Float32List> b, {double band = 0.2}) {
  final ta = a.length, tb = b.length;
  if (ta == 0 || tb == 0) return 1.0;
  final an = l2normSeq(a), bn = l2normSeq(b);
  final w = math.max((band * math.max(ta, tb)).toInt(), (ta - tb).abs() + 1);
  final inf = double.infinity;
  final prev = List<double>.filled(tb + 1, inf);
  final cur = List<double>.filled(tb + 1, inf);
  prev[0] = 0.0;
  for (var i = 1; i <= ta; i++) {
    cur.fillRange(0, tb + 1, inf);
    final jlo = math.max(1, i - w);
    final jhi = math.min(tb, i + w);
    for (var j = jlo; j <= jhi; j++) {
      final c = 1.0 - dot(an[i - 1], bn[j - 1]);
      final m = math.min(prev[j], math.min(cur[j - 1], prev[j - 1]));
      cur[j] = c + m;
    }
    for (var j = 0; j <= tb; j++) {
      prev[j] = cur[j];
    }
  }
  return prev[tb] / (ta + tb);
}

/// per-frame speed of an embedding trajectory. == np `embedding_velocity`.
Float32List embeddingVelocity(List<Float32List> emb) {
  final t = emb.length;
  final out = Float32List(t);
  if (t < 2) return out;
  for (var i = 1; i < t; i++) {
    out[i] = l2dist(emb[i], emb[i - 1]);
  }
  out[0] = out[1];
  return out;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return 0.0;
  final s = List<double>.of(xs)..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : 0.5 * (s[n ~/ 2 - 1] + s[n ~/ 2]);
}

double median(Iterable<double> xs) => _median(xs.toList());

/// Trim leading/trailing idle by embedding velocity. == np `segment_action`.
({int start, int end}) segmentAction(List<Float32List> emb, {double idleFrac = 0.30}) {
  final t = emb.length;
  if (t < 4) return (start: 0, end: t);
  final v = embeddingVelocity(emb);
  final active = [for (final x in v) if (x > 1e-5) x];
  if (active.isEmpty) return (start: 0, end: t);
  final thr = idleFrac * _median(active);
  var first = -1, last = -1;
  for (var i = 0; i < t; i++) {
    if (v[i] > thr) {
      if (first < 0) first = i;
      last = i;
    }
  }
  if (first < 0) return (start: 0, end: t);
  return (start: math.max(0, first - 1), end: math.min(t, last + 2));
}

List<Float32List> sliceSeq(List<Float32List> seq, int s, int e) =>
    seq.sublist(s, e);

List<List<Float32List>> sliceRep(List<List<Float32List>> rep, int s, int e) =>
    rep.sublist(s, e);

// ── Body-region diagnostics ──────────────────────────────────────────────────

/// h36m joint indices per understandable body region (see nuvo_to_h36m.dart:
/// 0 root 7 belly 8 neck 9 nose 10 head 11-13 left arm 14-16 right arm
/// 1-3 right leg 4-6 left leg).
const Map<String, List<int>> kH36mRegions = {
  'head': [9, 10],
  'left arm': [11, 12, 13],
  'right arm': [14, 15, 16],
  'torso': [0, 7, 8],
  'left leg': [4, 5, 6],
  'right leg': [1, 2, 3],
};

/// Per-region motion magnitude over an h36m sequence (each row 17*3 joint-major
/// x,y,conf) — mean frame-to-frame joint travel. Generic; no per-exercise rules.
/// Used to tell "your right arm barely moved" from "wrong path".
Map<String, double> regionActivity(List<Float32List> seq) {
  final out = <String, double>{};
  kH36mRegions.forEach((region, joints) {
    var sum = 0.0;
    var cnt = 0;
    for (final j in joints) {
      double? px, py;
      for (var t = 0; t < seq.length; t++) {
        final x = seq[t][j * 3], y = seq[t][j * 3 + 1], c = seq[t][j * 3 + 2];
        if (c == 0) continue;
        final lpx = px, lpy = py;
        if (lpx != null && lpy != null) {
          sum += math.sqrt((x - lpx) * (x - lpx) + (y - lpy) * (y - lpy));
          cnt++;
        }
        px = x;
        py = y;
      }
    }
    out[region] = cnt == 0 ? 0.0 : sum / cnt;
  });
  return out;
}
