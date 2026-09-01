import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/ai_motion_models.dart';
import 'motion_v2_models.dart';
import 'motion_verifier_v2.dart';

/// Talks to the Motion V2 dev inference service (`tools/motion_v2/service/`)
/// over LAN. MVP integration milestone — on-device inference replaces this.
class MotionV2ServiceClient implements MotionVerifierV2, MotionLearnerV2 {
  MotionV2ServiceClient({String? baseUrl, http.Client? client})
      : _base = (baseUrl ?? kMotionV2ServiceUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String _base;
  final http.Client _client;
  String? _sessionId;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_base$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final json = res.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw MotionV2Exception(json['error'] as String? ?? 'HTTP ${res.statusCode}');
      }
      return json;
    } on TimeoutException {
      throw const MotionV2Exception('Motion V2 service timed out.');
    } on SocketException {
      throw MotionV2Exception(
        'Cannot reach the Motion V2 service at $_base. Is '
        'tools/motion_v2/service/app.py running on the same network?',
      );
    } on http.ClientException catch (e) {
      throw MotionV2Exception('Motion V2 service error: ${e.message}');
    }
  }

  static List<Map<String, dynamic>> _wire(List<NuvoPoseFrame> frames) => [
        for (final f in frames)
          {
            't': f.createdAt.millisecondsSinceEpoch,
            'w': f.imageWidth,
            'h': f.imageHeight,
            'points': {
              for (final e in f.points.entries)
                e.key: [e.value.x, e.value.y, e.value.z, e.value.likelihood],
            },
          },
      ];

  @override
  Future<TaughtMotionV2Spec> learn({
    required String movementName,
    required List<List<NuvoPoseFrame>> demos,
  }) async {
    final res = await _post('/motion-v2/learn', {
      'movementName': movementName,
      'demos': [for (final d in demos) _wire(d)],
    });
    return TaughtMotionV2Spec.fromJson(res['spec'] as Map<String, dynamic>);
  }

  @override
  Future<void> load(TaughtMotionV2Spec spec) async {
    final res = await _post('/motion-v2/session', {'spec': spec.json, 'fps': 15});
    _sessionId = res['sessionId'] as String;
  }

  @override
  Future<MotionV2RuntimeResult> update(List<NuvoPoseFrame> frames) async {
    final sid = _sessionId;
    if (sid == null) throw const MotionV2Exception('No V2 session — call load() first.');
    final res = await _post('/motion-v2/session/$sid/frames', {'frames': _wire(frames)});
    return MotionV2RuntimeResult.fromJson(res);
  }

  @override
  Future<void> reset() async {
    final sid = _sessionId;
    if (sid == null) return;
    await _post('/motion-v2/session/$sid/reset', const {});
  }

  @override
  Future<void> dispose() async {
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try {
        await _client
            .delete(Uri.parse('$_base/motion-v2/session/$sid'))
            .timeout(const Duration(seconds: 5));
      } catch (_) {/* best effort */}
    }
    _client.close();
  }
}
