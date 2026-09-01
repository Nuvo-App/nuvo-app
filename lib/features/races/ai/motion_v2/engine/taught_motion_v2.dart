import 'dart:math' as math;
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';
import 'motion_v2_math.dart';
import 'nuvo_to_h36m.dart';

/// The pretrained motion encoder. `encode(h36mSeq)` -> rep `(T, 17, 512)`.
/// Implemented on-device by the ONNX runtime (`motion_v2_onnx_encoder.dart`);
/// a mock backs the parity tests.
abstract interface class MotionEncoderV2 {
  /// [h36mSeq]: T rows of 51 floats (17 joints x [x,y,c]), from `framesToH36m`.
  Future<List<List<Float32List>>> encode(List<Float32List> h36mSeq);
  int get dimRep;
}

const int kCanonLen = 32;
const int kSchema = 3;

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Normalized DTW distance of an ordered embedding path to the canonical path.
/// == np `traj_distance`.
double trajDistance(List<Float32List> embSeg, List<Float32List> canonical) {
  if (embSeg.length < 2) return 1.0;
  final q = resampleSeq(l2normSeq(embSeg), canonical.length);
  return dtwDistance(q, canonical);
}

class MatchResultV2 {
  const MatchResultV2({
    required this.isSameFamily,
    required this.score,
    required this.protoDist,
    required this.protoMargin,
    required this.trajSim,
  });
  final bool isSameFamily;
  final double score;
  final double protoDist;
  final double protoMargin;
  final double trajSim;
}

/// A movement learned from a few demonstrations. 1:1 port of
/// `tools/motion_v2/engine/taught_motion.py`. Serialization is byte-compatible
/// with the Python `to_json()` so specs are interchangeable with the service.
class TaughtMotionV2 {
  TaughtMotionV2({
    required this.name,
    required this.encoderId,
    required this.prototypes,
    required this.canonical,
    required this.restEmb,
    required this.acceptProtoDist,
    required this.acceptTrajDist,
    required this.demoActiveVel,
    required this.demoLengths,
    this.schema = kSchema,
  });

  final String name;
  final String encoderId;
  final List<Float32List> prototypes; // (n, D)
  final List<Float32List> canonical; // (CANON_LEN, D) L2n
  final Float32List restEmb; // (D,) L2n
  final double acceptProtoDist;
  final double acceptTrajDist;
  final double demoActiveVel;
  final List<int> demoLengths;
  final int schema;

  // ---- learn ----
  static Future<TaughtMotionV2> learn({
    required String name,
    required List<List<NuvoPoseFrame>> demos,
    required MotionEncoderV2 encoder,
    String encoderId = 'onnx',
    bool mirrorAug = true,
  }) async {
    assert(demos.length >= 2);
    final protos = <Float32List>[];
    final trajs = <List<Float32List>>[];
    final rests = <Float32List>[];
    final lens = <int>[];
    final vels = <double>[];

    for (final frames in demos) {
      final variants = <bool>[false, if (mirrorAug) true];
      for (final mir in variants) {
        final rep = await encoder.encode(framesToH36m(frames, mirror: mir));
        final emb = perFrameEmbedding(rep);
        var seg = segmentAction(emb);
        var s = seg.start, e = seg.end;
        if (e - s < 4) {
          s = 0;
          e = emb.length;
        }
        lens.add(e - s);
        protos.add(meanPool(sliceRep(rep, s, e)));
        trajs.add(resampleSeq(l2normSeq(sliceSeq(emb, s, e)), kCanonLen));
        final v = embeddingVelocity(emb);
        final mv = [for (var i = s; i < e; i++) v[i]];
        final mvMed = median(mv);
        final movers = [for (final x in mv) if (x > mvMed * 0.3) x];
        vels.add(movers.isEmpty ? 0.0 : median(movers));
        // rest = mean of the lowest-velocity 20% of frames, L2-normed
        final order = List<int>.generate(v.length, (i) => i)
          ..sort((a, b) => v[a].compareTo(v[b]));
        final k = math.max(2, v.length ~/ 5);
        rests.add(l2norm(_meanRows([for (var i = 0; i < k; i++) emb[order[i]]])));
      }
    }

    final canonical = l2normSeq(_meanSeq(trajs));
    final restEmb = l2norm(_meanRows(rests));

    // proto threshold: k x intra-demo spread, floored/capped by descriptor mag.
    final spread = <double>[];
    for (var i = 0; i < protos.length; i++) {
      for (var j = i + 1; j < protos.length; j++) {
        spread.add(l2dist(protos[i], protos[j]));
      }
    }
    final mag = median([for (final p in protos) _norm(p)]);
    final apd = _clip(4.0 * (spread.isEmpty ? 0.02 : _mean(spread)), 0.04 * mag, 0.15 * mag);

    final tdOwn = [for (final t in trajs) trajDistance(t, canonical)];
    final atd = _clip(median(tdOwn) * 3.0 + 5e-4, 1e-3, 0.05);

    return TaughtMotionV2(
      name: name,
      encoderId: encoderId,
      prototypes: protos,
      canonical: canonical,
      restEmb: restEmb,
      acceptProtoDist: apd,
      acceptTrajDist: atd,
      demoActiveVel: vels.isEmpty ? 0.0 : median(vels),
      demoLengths: lens,
    );
  }

  // ---- match ----
  MatchResultV2 matchEncoded(
    List<List<Float32List>> rep,
    List<Float32List> emb, {
    List<List<Float32List>>? repM,
    List<Float32List>? embM,
  }) {
    double bestKey = double.infinity, bestPd = 0, bestTd = 1;
    void consider(List<List<Float32List>> r, List<Float32List> e) {
      var seg = segmentAction(e);
      var s = seg.start, en = seg.end;
      if (en - s < 4) {
        s = 0;
        en = e.length;
      }
      final desc = meanPool(sliceRep(r, s, en));
      var pd = double.infinity;
      for (final p in prototypes) {
        pd = math.min(pd, l2dist(p, desc));
      }
      final td = trajDistance(sliceSeq(e, s, en), canonical);
      final key = pd / acceptProtoDist + td / acceptTrajDist;
      if (key < bestKey) {
        bestKey = key;
        bestPd = pd;
        bestTd = td;
      }
    }

    consider(rep, emb);
    if (repM != null && embM != null) consider(repM, embM);

    final pm = bestPd / acceptProtoDist;
    final tm = bestTd / acceptTrajDist;
    final same = pm <= 1.0 && tm <= 1.0;
    final score = _clip(
      0.55 * math.max(0.0, 1 - pm) + 0.45 * math.max(0.0, 1 - tm),
      0,
      1,
    );
    return MatchResultV2(
      isSameFamily: same,
      score: score,
      protoDist: bestPd,
      protoMargin: pm,
      trajSim: 1.0 - bestTd,
    );
  }

  Future<MatchResultV2> match(
    List<NuvoPoseFrame> frames,
    MotionEncoderV2 encoder,
  ) async {
    final rep = await encoder.encode(framesToH36m(frames));
    final repM = await encoder.encode(framesToH36m(frames, mirror: true));
    return matchEncoded(
      rep,
      perFrameEmbedding(rep),
      repM: repM,
      embM: perFrameEmbedding(repM),
    );
  }

  // ---- serialize (matches Python to_json) ----
  Map<String, dynamic> toJson() => {
        'schema': schema,
        'name': name,
        'verifier': 'motion_v2',
        'version': 1,
        'encoder_id': encoderId,
        'encoder': encoderId,
        'prototypes': [for (final p in prototypes) p.toList()],
        'canonical': [for (final c in canonical) c.toList()],
        'rest_emb': restEmb.toList(),
        'accept_proto_dist': acceptProtoDist,
        'accept_traj_dist': acceptTrajDist,
        'demo_active_vel': demoActiveVel,
        'demo_lengths': demoLengths,
      };

  factory TaughtMotionV2.fromJson(Map<String, dynamic> d) {
    Float32List vec(dynamic l) =>
        Float32List.fromList([for (final x in l as List) (x as num).toDouble()]);
    return TaughtMotionV2(
      name: (d['name'] ?? 'Custom movement') as String,
      encoderId: (d['encoder_id'] ?? d['encoder'] ?? 'onnx') as String,
      prototypes: [for (final p in d['prototypes'] as List) vec(p)],
      canonical: [for (final c in d['canonical'] as List) vec(c)],
      restEmb: vec(d['rest_emb']),
      acceptProtoDist: (d['accept_proto_dist'] as num).toDouble(),
      acceptTrajDist: (d['accept_traj_dist'] as num).toDouble(),
      demoActiveVel: (d['demo_active_vel'] as num?)?.toDouble() ?? 0.0,
      demoLengths: [for (final x in (d['demo_lengths'] as List? ?? const [])) (x as num).toInt()],
      schema: (d['schema'] as num?)?.toInt() ?? kSchema,
    );
  }
}

double _norm(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  return math.sqrt(s);
}

double _mean(List<double> xs) =>
    xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

Float32List _meanRows(List<Float32List> rows) {
  final d = rows.first.length;
  final acc = Float64List(d);
  for (final r in rows) {
    for (var k = 0; k < d; k++) {
      acc[k] += r[k];
    }
  }
  final out = Float32List(d);
  for (var k = 0; k < d; k++) {
    out[k] = acc[k] / rows.length;
  }
  return out;
}

List<Float32List> _meanSeq(List<List<Float32List>> seqs) {
  final t = seqs.first.length, d = seqs.first.first.length;
  final out = <Float32List>[];
  for (var i = 0; i < t; i++) {
    final acc = Float64List(d);
    for (final s in seqs) {
      for (var k = 0; k < d; k++) {
        acc[k] += s[i][k];
      }
    }
    final row = Float32List(d);
    for (var k = 0; k < d; k++) {
      row[k] = acc[k] / seqs.length;
    }
    out.add(row);
  }
  return out;
}
