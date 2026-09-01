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
const int kSchema = 4;

// ── matcher constants — measured in tools/motion_v2/experiments/exp_matcher.py,
//    then locked. NOT ad-hoc tuning. 1:1 with engine/taught_motion.py. ──────────
const double kDtwBand = 0.33; // tolerate a slower / faster performance
const double kVoteK = 3.0; // a reference "matches" if pd/spread<=K and td/spread<=K
const double kRescueK = 6.0; // 2*kVoteK — how close a lone reference must be
const double kSepAccept = 0.15; // separation needed for the single-reference rescue
const double kBgGate = 1.15; // a vote also needs pd_ref <= gate * nearest background
const double kProtoFloor = 0.04;
const double kTrajFloor = 0.06;

double _clip(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// One demonstration kept whole — never averaged into a blur.
class MotionReference {
  MotionReference({required this.proto, required this.traj, required this.length});
  final Float32List proto; // (D,)
  final List<Float32List> traj; // (kCanonLen, D) L2n
  final int length;

  Map<String, dynamic> toJson() => {
        'proto': proto.toList(),
        'traj': [for (final r in traj) r.toList()],
        'length': length,
      };

  factory MotionReference.fromJson(Map<String, dynamic> d) => MotionReference(
        proto: Float32List.fromList(
            [for (final x in d['proto'] as List) (x as num).toDouble()]),
        traj: [
          for (final r in d['traj'] as List)
            Float32List.fromList([for (final x in r as List) (x as num).toDouble()])
        ],
        length: (d['length'] as num).toInt(),
      );
}

/// DTW distance of an ordered embedding path to a reference path. Band 0.33.
double trajDistance(List<Float32List> embSeg, List<Float32List> canonical) {
  if (embSeg.length < 2) return 1.0;
  final q = resampleSeq(l2normSeq(embSeg), canonical.length);
  return dtwDistance(q, canonical, band: kDtwBand);
}

class RefScore {
  const RefScore(this.protoDist, this.trajDist, this.protoMargin, this.trajMargin,
      this.matches);
  final double protoDist;
  final double trajDist;
  final double protoMargin;
  final double trajMargin;
  final bool matches;
  Map<String, dynamic> toJson() => {
        'proto': double.parse(protoDist.toStringAsFixed(4)),
        'traj': double.parse(trajDist.toStringAsFixed(4)),
        'proto_margin': double.parse(protoMargin.toStringAsFixed(3)),
        'traj_margin': double.parse(trajMargin.toStringAsFixed(3)),
        'matches': matches,
      };
}

class MatchResultV2 {
  const MatchResultV2({
    required this.isSameFamily,
    required this.score,
    required this.protoDist,
    required this.protoMargin,
    required this.trajSim,
    this.votes = 0,
    this.separation,
    this.decision = 'reject',
    this.perRef = const [],
  });
  final bool isSameFamily;
  final double score;
  final double protoDist;
  final double protoMargin;
  final double trajSim;

  /// How many of the 3 references the attempt agreed with.
  final int votes;

  /// (nearest-background-dist − nearest-reference-dist) / nearest-background-dist.
  /// >= 0.5 ⇒ twice as close to the taught motion as to generic motion. null
  /// when no background bank was supplied.
  final double? separation;

  /// '2of3_consensus' | 'separation_rescue' | 'reject'
  final String decision;
  final List<RefScore> perRef;

  Map<String, dynamic> toJson() => {
        'is_same_family': isSameFamily,
        'score': double.parse(score.toStringAsFixed(3)),
        'votes': votes,
        if (separation != null)
          'separation': double.parse(separation!.toStringAsFixed(3)),
        'decision': decision,
        'per_ref': [for (final r in perRef) r.toJson()],
      };
}

/// Three-shot matcher. Keeps all 3 demonstrations as first-class references; the
/// decision comes from consensus across them plus a separation margin against a
/// generic background of unrelated motion. No averaged canonical.
///
/// 1:1 port of `tools/motion_v2/engine/taught_motion.py` (schema 4).
class TaughtMotionV2 {
  TaughtMotionV2({
    required this.name,
    required this.encoderId,
    required this.references,
    required this.protoSpread,
    required this.trajSpread,
    required this.protoSpreadMax,
    required this.trajSpreadMax,
    required this.restEmb,
    required this.demoActiveVel,
    required this.demoLengths,
    this.demoRegionActivity = const {},
    this.schema = kSchema,
  });

  final String name;
  final String encoderId;
  final List<MotionReference> references;
  final double protoSpread; // median pairwise proto distance among demos
  final double trajSpread; // median pairwise trajectory distance among demos
  final double protoSpreadMax;
  final double trajSpreadMax;
  final Float32List restEmb;
  final double demoActiveVel;
  final List<int> demoLengths;

  /// Per-body-region motion magnitude of the demonstrations. Diagnostics only.
  final Map<String, double> demoRegionActivity;

  final int schema;

  // legacy accessors so existing call sites don't break -----------------------
  /// The first reference's canonical trajectory (progress display / streaming).
  List<Float32List> get canonical =>
      references.isEmpty ? const [] : references.first.traj;

  /// Retained for older diagnostics — approximate accept bounds.
  double get acceptProtoDist => kVoteK * math.max(protoSpread, kProtoFloor);
  double get acceptTrajDist => kVoteK * math.max(trajSpread, kTrajFloor);
  List<Float32List> get prototypes => [for (final r in references) r.proto];

  // ---- learn ----
  static Future<TaughtMotionV2> learn({
    required String name,
    required List<List<NuvoPoseFrame>> demos,
    required MotionEncoderV2 encoder,
    String encoderId = 'onnx',
    bool mirrorAug = true, // kept for API compat; references use the primary view
  }) async {
    assert(demos.length >= 2);
    final refs = <MotionReference>[];
    final rests = <Float32List>[];
    final vels = <double>[];
    final regionAcc = <String, double>{};
    var regionN = 0;

    for (final frames in demos) {
      final h36m = framesToH36m(frames);
      final ra = regionActivity(h36m);
      ra.forEach((k, v) => regionAcc[k] = (regionAcc[k] ?? 0) + v);
      regionN++;

      final rep = await encoder.encode(h36m);
      final emb = perFrameEmbedding(rep);
      var seg = segmentAction(emb);
      var s = seg.start, e = seg.end;
      if (e - s < 4) {
        s = 0;
        e = emb.length;
      }
      refs.add(MotionReference(
        proto: meanPool(sliceRep(rep, s, e)),
        traj: resampleSeq(l2normSeq(sliceSeq(emb, s, e)), kCanonLen),
        length: e - s,
      ));
      final v = embeddingVelocity(emb);
      final mv = [for (var i = s; i < e; i++) v[i]];
      final mvMed = median(mv);
      final movers = [for (final x in mv) if (x > mvMed * 0.3) x];
      vels.add(movers.isEmpty ? 0.0 : median(movers));
      final order = List<int>.generate(v.length, (i) => i)
        ..sort((a, b) => v[a].compareTo(v[b]));
      final k = math.max(2, v.length ~/ 5);
      rests.add(l2norm(_meanRows([for (var i = 0; i < k; i++) emb[order[i]]])));
    }

    final pdPairs = <double>[];
    final tdPairs = <double>[];
    for (var i = 0; i < refs.length; i++) {
      for (var j = i + 1; j < refs.length; j++) {
        pdPairs.add(l2dist(refs[i].proto, refs[j].proto));
        tdPairs.add(dtwDistance(refs[i].traj, refs[j].traj, band: kDtwBand));
      }
    }

    final regionAvg = <String, double>{
      for (final e in regionAcc.entries)
        e.key: regionN == 0 ? 0.0 : e.value / regionN,
    };

    return TaughtMotionV2(
      name: name,
      encoderId: encoderId,
      references: refs,
      protoSpread: pdPairs.isEmpty ? 0.02 : median(pdPairs),
      trajSpread: tdPairs.isEmpty ? 0.01 : median(tdPairs),
      protoSpreadMax: pdPairs.isEmpty ? 0.02 : pdPairs.reduce(math.max),
      trajSpreadMax: tdPairs.isEmpty ? 0.01 : tdPairs.reduce(math.max),
      restEmb: l2norm(_meanRows(rests)),
      demoActiveVel: vels.isEmpty ? 0.0 : median(vels),
      demoLengths: [for (final r in refs) r.length],
      demoRegionActivity: regionAvg,
    );
  }

  // ---- match ----
  ({double pd, double td, Float32List desc}) _distOneOrientation(
      MotionReference ref, List<List<Float32List>> rep, List<Float32List> emb) {
    var seg = segmentAction(emb);
    var s = seg.start, e = seg.end;
    if (e - s < 4) {
      s = 0;
      e = emb.length;
    }
    final desc = meanPool(sliceRep(rep, s, e));
    final pd = l2dist(ref.proto, desc);
    final td = trajDistance(sliceSeq(emb, s, e), ref.traj);
    return (pd: pd, td: td, desc: desc);
  }

  MatchResultV2 matchEncoded(
    List<List<Float32List>> rep,
    List<Float32List> emb, {
    List<List<Float32List>>? repM,
    List<Float32List>? embM,
    List<Float32List>? background,
  }) {
    final oris = <({List<List<Float32List>> rep, List<Float32List> emb})>[
      (rep: rep, emb: emb),
      if (repM != null && embM != null) (rep: repM, emb: embM),
    ];
    final ps = math.max(protoSpread, kProtoFloor);
    final ts = math.max(trajSpread, kTrajFloor);

    final perRefRaw = <({double pd, double td})>[];
    Float32List? bestDesc;
    var bestKey = double.infinity;
    for (final ref in references) {
      var bpd = double.infinity, btd = double.infinity;
      Float32List? bdesc;
      for (final o in oris) {
        final d = _distOneOrientation(ref, o.rep, o.emb);
        if (d.pd / ps + d.td / ts < bpd / ps + btd / ts) {
          bpd = d.pd;
          btd = d.td;
          bdesc = d.desc;
        }
      }
      perRefRaw.add((pd: bpd, td: btd));
      final key = bpd / ps + btd / ts;
      if (key < bestKey) {
        bestKey = key;
        bestDesc = bdesc;
      }
    }

    final pms = [for (final r in perRefRaw) r.pd / ps];
    final tms = [for (final r in perRefRaw) r.td / ts];
    final bestPd = perRefRaw.map((r) => r.pd).reduce(math.min);
    final bestTd = perRefRaw.map((r) => r.td).reduce(math.min);
    final bestPm = pms.reduce(math.min);
    final bestTm = tms.reduce(math.min);

    double? sep;
    double? bgMin;
    if (background != null && background.isNotEmpty && bestDesc != null) {
      var mn = double.infinity;
      for (final b in background) {
        mn = math.min(mn, l2dist(b, bestDesc));
      }
      bgMin = mn;
      sep = (mn - bestPd) / math.max(mn, 1e-6);
    }
    final gate = bgMin;

    bool voteFor(double pdAbs, double pm, double tm) {
      var ok = pm <= kVoteK && tm <= kVoteK;
      if (ok && gate != null) ok = pdAbs <= kBgGate * gate;
      return ok;
    }

    var votes = 0;
    final perRef = <RefScore>[];
    for (var i = 0; i < perRefRaw.length; i++) {
      final m = voteFor(perRefRaw[i].pd, pms[i], tms[i]);
      if (m) votes++;
      perRef.add(RefScore(perRefRaw[i].pd, perRefRaw[i].td, pms[i], tms[i], m));
    }

    final oneOk = () {
      for (var i = 0; i < pms.length; i++) {
        if (pms[i] <= kRescueK && tms[i] <= kRescueK) return true;
      }
      return false;
    }();
    final rescue = oneOk && sep != null && sep >= kSepAccept;
    final isSame = votes >= 2 || rescue;

    final score = _clip(
      0.45 * math.max(0.0, 1 - bestPm / kVoteK) +
          0.30 * math.max(0.0, 1 - bestTm / kVoteK) +
          0.25 * (votes / math.max(references.length, 1)),
      0.0,
      1.0,
    );

    return MatchResultV2(
      isSameFamily: isSame,
      score: score,
      protoDist: bestPd,
      protoMargin: bestPm / kVoteK,
      trajSim: 1.0 - bestTd,
      votes: votes,
      separation: sep,
      decision: votes >= 2
          ? '2of3_consensus'
          : (rescue ? 'separation_rescue' : 'reject'),
      perRef: perRef,
    );
  }

  Future<MatchResultV2> match(
    List<NuvoPoseFrame> frames,
    MotionEncoderV2 encoder, {
    List<Float32List>? background,
  }) async {
    final rep = await encoder.encode(framesToH36m(frames));
    final repM = await encoder.encode(framesToH36m(frames, mirror: true));
    return matchEncoded(
      rep,
      perFrameEmbedding(rep),
      repM: repM,
      embM: perFrameEmbedding(repM),
      background: background,
    );
  }

  // ---- serialize (matches Python to_json, schema 4) ----
  Map<String, dynamic> toJson() => {
        'schema': schema,
        'name': name,
        'verifier': 'motion_v2',
        'version': 1,
        'encoder_id': encoderId,
        'encoder': encoderId,
        'references': [for (final r in references) r.toJson()],
        'proto_spread': protoSpread,
        'traj_spread': trajSpread,
        'proto_spread_max': protoSpreadMax,
        'traj_spread_max': trajSpreadMax,
        'rest_emb': restEmb.toList(),
        'demo_active_vel': demoActiveVel,
        'demo_lengths': demoLengths,
        'region_activity': demoRegionActivity,
      };

  factory TaughtMotionV2.fromJson(Map<String, dynamic> d) {
    Float32List vec(dynamic l) =>
        Float32List.fromList([for (final x in l as List) (x as num).toDouble()]);
    final ps = (d['proto_spread'] as num?)?.toDouble() ?? 0.02;
    final tsr = (d['traj_spread'] as num?)?.toDouble() ?? 0.01;
    return TaughtMotionV2(
      name: (d['name'] ?? 'Custom movement') as String,
      encoderId: (d['encoder_id'] ?? d['encoder'] ?? 'onnx') as String,
      references: [
        for (final r in (d['references'] as List? ?? const []))
          MotionReference.fromJson(r as Map<String, dynamic>)
      ],
      protoSpread: ps,
      trajSpread: tsr,
      protoSpreadMax: (d['proto_spread_max'] as num?)?.toDouble() ?? ps,
      trajSpreadMax: (d['traj_spread_max'] as num?)?.toDouble() ?? tsr,
      restEmb: vec(d['rest_emb']),
      demoActiveVel: (d['demo_active_vel'] as num?)?.toDouble() ?? 0.0,
      demoLengths: [
        for (final x in (d['demo_lengths'] as List? ?? const [])) (x as num).toInt()
      ],
      demoRegionActivity: {
        for (final e in ((d['region_activity'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      schema: (d['schema'] as num?)?.toInt() ?? kSchema,
    );
  }
}

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
