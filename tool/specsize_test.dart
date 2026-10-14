import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/motion_v2_onnx_encoder.dart';
import 'package:nuvo/features/races/ai/motion_v2/engine/taught_motion_v2.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

List<NuvoPoseFrame> frames(List<dynamic> wire) => [
  for (final f in wire)
    NuvoPoseFrame(
      points: {
        for (final e in (f['points'] as Map).entries)
          e.key as String: NuvoPosePoint(
            x: (e.value[0] as num).toDouble(), y: (e.value[1] as num).toDouble(),
            z: (e.value[2] as num).toDouble(), likelihood: (e.value[3] as num).toDouble(),
          ),
      },
      imageWidth: (f['w'] as num).toDouble(),
      imageHeight: (f['h'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch((f['t'] as num).toInt()),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('spec size', () async {
    if (!Platform.isLinux ||
        !(Platform.environment['LD_LIBRARY_PATH'] ?? '').contains('onnx')) {
      return;
    }
    final g = jsonDecode(File('test/fixtures/motion_v2_golden.json').readAsStringSync());
    final demos = [for (final d in g['demos'] as List) frames(d as List)];
    final encoder = await MotionV2OnnxEncoder.load();
    final spec = await TaughtMotionV2.learn(name: 'probe', demos: demos, encoder: encoder, encoderId: 'test');
    final j = spec.toJson();
    final bytes = utf8.encode(jsonEncode(j)).length;
    print('SPEC_JSON_BYTES=$bytes');
    print('SPEC_KEYS=${j.keys.toList()}');
    if (j['references'] is List) {
      final r = (j['references'] as List).first as Map;
      print('REF_KEYS=${r.keys.toList()} proto_len=${(r['proto'] as List).length} traj_len=${(r['traj'] as List).length} traj_row=${(r['traj'] as List).first is List ? ((r['traj'] as List).first as List).length : 0}');
    }
  });
}
