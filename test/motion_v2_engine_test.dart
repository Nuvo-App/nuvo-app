import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_math.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/nuvo_to_h36m.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/taught_motion_v2.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

List<NuvoPoseFrame> _frames(List<dynamic> wire) => [
      for (final f in wire)
        NuvoPoseFrame(
          points: {
            for (final e in (f['points'] as Map).entries)
              e.key as String: NuvoPosePoint(
                x: (e.value[0] as num).toDouble(),
                y: (e.value[1] as num).toDouble(),
                z: (e.value[2] as num).toDouble(),
                likelihood: (e.value[3] as num).toDouble(),
              ),
          },
          imageWidth: (f['w'] as num).toDouble(),
          imageHeight: (f['h'] as num).toDouble(),
          createdAt: DateTime.fromMillisecondsSinceEpoch((f['t'] as num).toInt()),
        ),
    ];

List<Float32List> _seq(List<dynamic> rows) =>
    [for (final r in rows) Float32List.fromList([for (final x in r as List) (x as num).toDouble()])];

List<List<Float32List>> _rep(List<dynamic> t) => [
      for (final frame in t)
        [for (final joint in frame as List) Float32List.fromList([for (final x in joint as List) (x as num).toDouble()])],
    ];

void _expectSeqClose(List<Float32List> got, List<dynamic> want, double tol, String label) {
  expect(got.length, want.length, reason: '$label length');
  for (var i = 0; i < got.length; i++) {
    final w = want[i] as List;
    expect(got[i].length, w.length, reason: '$label row $i length');
    for (var k = 0; k < w.length; k++) {
      expect(got[i][k], closeTo((w[k] as num).toDouble(), tol),
          reason: '$label [$i][$k]');
    }
  }
}

List<T> _clip16<T>(List<T> l) => l.sublist(0, l.length < 16 ? l.length : 16);

void main() {
  group('adapter parity (framesToH36m vs Python golden)', () {
    final g = _load('motion_v2_golden.json');

    test('demo0 h36m matches', () {
      final h = framesToH36m(_frames(g['demos'][0] as List));
      _expectSeqClose(h, g['h36m_demo0'] as List, 2e-3, 'demo0');
    });

    test('demo0 mirrored h36m matches', () {
      final h = framesToH36m(_frames(g['demos'][0] as List), mirror: true);
      _expectSeqClose(h, g['h36m_demo0_mirror'] as List, 2e-3, 'demo0_mirror');
    });

    test('test clip h36m matches', () {
      final h = framesToH36m(_frames(g['test'] as List));
      _expectSeqClose(h, g['h36m_test'] as List, 2e-3, 'test');
    });
  });

  group('math parity (vs Python golden)', () {
    final m = _load('motion_v2_math_golden.json');
    final demos = [for (final r in m['demosA_reps'] as List) _rep(r as List)];

    test('meanPool', () {
      final got = meanPool(demos[0]);
      final want = m['meanPool'] as List;
      for (var k = 0; k < want.length; k++) {
        expect(got[k], closeTo((want[k] as num).toDouble(), 1e-5), reason: 'meanPool[$k]');
      }
    });

    test('perFrameEmbedding row 0', () {
      final got = perFrameEmbedding(demos[0])[0];
      final want = m['perFrameEmbedding_0'] as List;
      for (var k = 0; k < want.length; k++) {
        expect(got[k], closeTo((want[k] as num).toDouble(), 1e-5));
      }
    });

    test('resampleSeq first row', () {
      final e = l2normSeq(perFrameEmbedding(demos[0]));
      final got = resampleSeq(e, m['resample_len'] as int)[0];
      final want = m['resample_first'] as List;
      for (var k = 0; k < want.length; k++) {
        expect(got[k], closeTo((want[k] as num).toDouble(), 1e-5));
      }
    });

    test('dtwDistance self ~ golden', () {
      final e = _clip16(l2normSeq(perFrameEmbedding(demos[0])));
      expect(dtwDistance(e, e), closeTo((m['dtw_self'] as num).toDouble(), 1e-5));
    });

    test('dtwDistance cross ~ golden', () {
      final a = _clip16(l2normSeq(perFrameEmbedding(demos[0])));
      final b = _clip16(l2normSeq(perFrameEmbedding(_rep(m['testB_rep'] as List))));
      expect(dtwDistance(a, b), closeTo((m['dtw_cross'] as num).toDouble(), 1e-5));
    });

    test('segmentAction', () {
      final seg = segmentAction(perFrameEmbedding(demos[0]));
      final want = m['segment_full'] as List;
      expect(seg.start, want[0]);
      expect(seg.end, want[1]);
    });
  });

  group('matchEncoded decision parity (Python golden spec + reps)', () {
    final m = _load('motion_v2_math_golden.json');
    final learn = m['learn'] as Map<String, dynamic>;
    final motion = TaughtMotionV2(
      name: 'golden',
      encoderId: 'test',
      prototypes: _seq(learn['prototypes'] as List),
      canonical: _seq(learn['canonical'] as List),
      restEmb: Float32List.fromList(
          [for (final x in learn['rest_emb'] as List) (x as num).toDouble()]),
      acceptProtoDist: (learn['accept_proto_dist'] as num).toDouble(),
      acceptTrajDist: (learn['accept_traj_dist'] as num).toDouble(),
      demoActiveVel: 0,
      demoLengths: [for (final x in learn['demo_lengths'] as List) x as int],
    );

    void check(String key, List<dynamic> repJson) {
      final rep = _rep(repJson);
      final r = motion.matchEncoded(rep, perFrameEmbedding(rep));
      final want = m[key] as Map<String, dynamic>;
      expect(r.isSameFamily, want['is_same'], reason: '$key is_same');
      expect(r.protoMargin, closeTo((want['proto_margin'] as num).toDouble(), 1e-3),
          reason: '$key proto_margin');
      expect(r.trajSim, closeTo(1.0 - (want['traj_margin'] as num).toDouble() * motion.acceptTrajDist, 3e-3),
          reason: '$key traj');
    }

    test('match_A', () => check('match_A', m['testA_rep'] as List));
    test('match_B', () => check('match_B', m['testB_rep'] as List));
  });

  group('spec round-trip is byte-compatible with Python', () {
    test('fromJson/toJson stable + decisions loadable', () {
      final g = _load('motion_v2_golden.json');
      final spec = TaughtMotionV2.fromJson(g['spec'] as Map<String, dynamic>);
      expect(spec.canonical.length, kCanonLen);
      expect(spec.prototypes.length, 6); // 3 demos x mirror
      final j = spec.toJson();
      final again = TaughtMotionV2.fromJson(j);
      expect(again.acceptProtoDist, spec.acceptProtoDist);
      expect(again.acceptTrajDist, spec.acceptTrajDist);
    });
  });
}
