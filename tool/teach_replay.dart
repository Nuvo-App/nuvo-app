// Teach Nuvo replay + V1-vs-V2 scorecard.
//
//   tool/teach-replay.sh <session.json[.gz] | directory> [--no-v2] [--target N]
//
// Replays a pulled teach artifact (`nuvo-motion.mjs teach-get <id>`) through
// the SAME matcher code the phone runs:
//
//   V1  CustomPoseSequenceRuntime — the spec a created race actually verifies
//       with (`v1.spec` in the artifact), fed the recorded live-test frames.
//   V2  MotionV2NativeRuntime — the learned spec (`spec` in the artifact),
//       fed the same frames in the app's batch size. Needs the ONNX Runtime
//       shared lib on Linux:
//         LD_LIBRARY_PATH=/home/server1/ort/onnxruntime-linux-x64-1.15.1/lib
//
// For every session it prints what each matcher decided on the frames the
// user actually performed, next to what the phone recorded — including the
// counterfactual (the engine the phone's live test did NOT run). A directory
// of sessions produces the aggregate scorecard: same-motion recall per engine,
// disagreements in both directions, per movement.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nuvo/features/races/ai/custom_pose/custom_pose_sequence_runtime.dart';
import 'package:nuvo/features/races/ai/custom_pose/custom_pose_verifier_spec.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_models.dart';
import 'package:nuvo/features/races/ai/motion_v2/motion_v2_native_runtime.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

const _v2BatchSize = 4;

Map<String, dynamic> _load(String path) {
  var raw = File(path).readAsBytesSync();
  if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
    raw = Uint8List.fromList(gzip.decode(raw));
  }
  return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
}

/// Diag frame ({t, raw|smoothed: {name: [x,y,z,conf]}}) -> NuvoPoseFrame.
/// The teach screen feeds the matcher the tracker's smoothed stream, so
/// replay prefers `smoothed` and falls back to `raw`.
List<NuvoPoseFrame> _frames(List<dynamic>? diagFrames, {DateTime? epoch}) {
  final base = epoch ?? DateTime.utc(2026);
  final out = <NuvoPoseFrame>[];
  for (final f in diagFrames ?? const []) {
    final m = f as Map<String, dynamic>;
    final pts = (m['smoothed'] as Map?) ?? (m['raw'] as Map?) ?? const {};
    out.add(
      NuvoPoseFrame(
        points: {
          for (final e in pts.entries)
            e.key as String: NuvoPosePoint(
              x: (e.value[0] as num).toDouble(),
              y: (e.value[1] as num).toDouble(),
              z: (e.value[2] as num?)?.toDouble() ?? 0,
              likelihood: (e.value[3] as num?)?.toDouble() ?? 0,
            ),
        },
        imageWidth: 720,
        imageHeight: 1280,
        createdAt: base.add(Duration(milliseconds: (m['t'] as num).toInt())),
      ),
    );
  }
  return out;
}

class EngineVerdict {
  EngineVerdict({this.matched, this.count = 0, this.detail = ''});
  bool? matched; // null = engine didn't run
  int count;
  String detail;
}

class SessionReport {
  String id = '?';
  String movement = '?';
  String outcome = '?';
  String engine = '?';
  bool hasLiveTest = false;
  EngineVerdict? recordedV1; // what the phone recorded
  EngineVerdict? recordedV2;
  EngineVerdict? replayV1; // replayed here
  EngineVerdict? replayV2;
  int demosV1Recognized = 0;
  int demosV2Recognized = 0;
  int demoCount = 0;
  String? error;
}

Future<EngineVerdict?> replayV1Engine(
  Map<String, dynamic>? v1,
  List<NuvoPoseFrame> frames,
  int target,
) async {
  final specJson = v1?['spec'];
  if (specJson is! Map<String, dynamic> || frames.isEmpty) return null;
  final spec = CustomPoseVerifierSpec.fromJson(specJson);
  final runtime = CustomPoseSequenceRuntime(spec: spec, target: target)..start();
  for (final f in frames) {
    runtime.update(f);
  }
  final r = runtime.customResult();
  return EngineVerdict(
    matched: r.isVerified,
    count: r.count,
    detail: 'count ${r.count}/$target '
        'valid ${r.validFrames}/${r.framesAnalyzed} '
        'conf ${r.confidence.toStringAsFixed(2)}'
        '${r.finalFailureReason == null ? '' : ' fail=${r.finalFailureReason}'}',
  );
}

Future<EngineVerdict?> replayV2Engine(
  Map<String, dynamic>? specJson,
  List<NuvoPoseFrame> frames,
) async {
  if (specJson == null || frames.isEmpty) return null;
  final runtime = MotionV2NativeRuntime();
  try {
    await runtime.load(TaughtMotionV2Spec.fromJson(specJson));
    MotionV2RuntimeResult last = MotionV2RuntimeResult.empty;
    // `matched` is the CURRENT window's decision, not cumulative — a rep that
    // fired earlier and a final window mid-attempt would misreport the stream
    // as unrecognized. Recognition = any rep counted or any matching window.
    var everMatched = false;
    var maxCount = 0;
    for (var i = 0; i < frames.length; i += _v2BatchSize) {
      final end = (i + _v2BatchSize).clamp(0, frames.length);
      last = await runtime.update(frames.sublist(i, end));
      if (last.matched || last.newRep) everMatched = true;
      if (last.count > maxCount) maxCount = last.count;
    }
    return EngineVerdict(
      matched: everMatched || maxCount > 0,
      count: maxCount,
      detail: 'count $maxCount votes ${last.votes}/3 '
          'decision ${last.decision} attempt ${last.attempt.outcome.name}'
          '${last.separation == null ? '' : ' sep ${last.separation!.toStringAsFixed(2)}'}',
    );
  } finally {
    await runtime.dispose();
  }
}

Future<SessionReport> report(
  String path,
  Map<String, dynamic> s, {
  required bool v2,
  required int target,
  bool demos = false,
}) async {
  final r = SessionReport()
    ..id = s['sessionId'] as String? ?? '?'
    ..movement = (s['movementName'] ?? s['meta']?['movementName'] ?? '?') as String
    ..outcome = s['outcome'] as String? ?? '?'
    ..engine = s['engine'] as String? ?? '?';

  final v1 = s['v1'] as Map<String, dynamic>?;
  final live = s['liveTest'] as Map<String, dynamic>?;
  final liveFrames = _frames(live?['frames'] as List?);
  r.hasLiveTest = liveFrames.isNotEmpty;

  // What the phone recorded.
  final v1Test = v1?['testResult'] as Map<String, dynamic>?;
  if (v1Test != null) {
    r.recordedV1 = EngineVerdict(
      matched: v1Test['isVerified'] == true,
      count: (v1Test['count'] as num?)?.toInt() ?? 0,
      detail: 'recorded count ${v1Test['count']} '
          'status ${v1Test['verificationStatus']}',
    );
  }
  final finalAttempt = live?['finalAttempt'] as Map<String, dynamic>?;
  if (finalAttempt != null) {
    r.recordedV2 = EngineVerdict(
      matched: finalAttempt['outcome'] == 'success',
      count: (live?['finalCount'] as num?)?.toInt() ?? 0,
      detail: 'recorded outcome ${finalAttempt['outcome']} '
          'count ${live?['finalCount']}',
    );
  }

  try {
    r.replayV1 = await replayV1Engine(v1, liveFrames, target);
    if (v2) r.replayV2 = await replayV2Engine(s['spec'] as Map<String, dynamic>?, liveFrames);

    if (demos) {
      // Same-motion recall: every teaching demo should be recognized by the
      // matcher it trained. A demo its own matcher rejects points at the
      // encoder/spec, not the user.
      final teaching = s['teaching'] as List? ?? const [];
      r.demoCount = teaching.length;
      for (final d in teaching) {
        final dFrames = _frames((d as Map)['frames'] as List?);
        final v1r = await replayV1Engine(v1, dFrames, 1);
        if (v1r?.matched == true || (v1r?.count ?? 0) > 0) r.demosV1Recognized++;
        if (v2) {
          final v2r = await replayV2Engine(s['spec'] as Map<String, dynamic>?, dFrames);
          if (v2r?.matched == true || (v2r?.count ?? 0) > 0) r.demosV2Recognized++;
        }
      }
    }
  } catch (e) {
    r.error = e.toString();
  }
  return r;
}

String fmtVerdict(EngineVerdict? v) =>
    v == null ? '—' : '${v.matched == true ? 'MATCH' : 'no match'}  (${v.detail})';

Future<void> main(List<String> args) async {
  var v2 = true;
  var target = 5;
  var demos = false;
  final paths = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--no-v2':
        v2 = false;
      case '--target':
        target = int.parse(args[++i]);
      case '--demos':
        demos = true;
      default:
        paths.add(args[i]);
    }
  }
  if (paths.isEmpty) {
    stderr.writeln(
      'usage: teach-replay <session.json[.gz] | dir> [--no-v2] [--target N] [--demos]',
    );
    exit(2);
  }
  final files = <File>[];
  for (final p in paths) {
    final t = FileSystemEntity.typeSync(p);
    if (t == FileSystemEntityType.directory) {
      files.addAll(
        Directory(p)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json') || f.path.endsWith('.json.gz')),
      );
    } else {
      files.add(File(p));
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));

  final reports = <SessionReport>[];
  for (final f in files) {
    Map<String, dynamic> s;
    try {
      s = _load(f.path);
    } catch (e) {
      stderr.writeln('${f.path}: unreadable ($e)');
      continue;
    }
    if (s['teaching'] == null && s['v1'] == null) {
      stderr.writeln('${f.path}: not a teach session artifact');
      continue;
    }
    final r = await report(f.path, s, v2: v2, target: target, demos: demos);
    reports.add(r);
    stdout.writeln('${r.id}  ${r.movement}  (outcome=${r.outcome} engine=${r.engine})');
    if (r.error != null) stdout.writeln('  replay error: ${r.error}');
    if (!r.hasLiveTest) stdout.writeln('  no live test recorded');
    if (r.recordedV1 != null) stdout.writeln('  phone V1 : ${fmtVerdict(r.recordedV1)}');
    if (r.recordedV2 != null) stdout.writeln('  phone V2 : ${fmtVerdict(r.recordedV2)}');
    stdout.writeln('  replay V1: ${fmtVerdict(r.replayV1)}');
    if (v2) stdout.writeln('  replay V2: ${fmtVerdict(r.replayV2)}');
    if (demos && r.demoCount > 0) {
      stdout.writeln(
        '  demo recall: V1 ${r.demosV1Recognized}/${r.demoCount}'
        '${v2 ? '  V2 ${r.demosV2Recognized}/${r.demoCount}' : ''}',
      );
    }
    stdout.writeln('');
  }

  // ── Scorecard ────────────────────────────────────────────────────────────
  final withLive = reports.where((r) => r.hasLiveTest).toList();
  stdout.writeln('═══ SCORECARD ═══');
  stdout.writeln(
    'sessions: ${reports.length}   with live test: ${withLive.length}',
  );
  int tally(bool? Function(SessionReport) pick) =>
      withLive.where((r) => pick(r) == true).length;
  int ran(bool Function(SessionReport) pick) =>
      withLive.where(pick).length;

  final v1Ran = ran((r) => r.replayV1 != null);
  final v2Ran = ran((r) => r.replayV2 != null);
  stdout.writeln('V1 replay : matched ${tally((r) => r.replayV1?.matched)} / $v1Ran');
  if (v2) {
    stdout.writeln('V2 replay : matched ${tally((r) => r.replayV2?.matched)} / $v2Ran');
    final v1YesV2No = withLive
        .where((r) => r.replayV1?.matched == true && r.replayV2?.matched == false)
        .toList();
    final v2YesV1No = withLive
        .where((r) => r.replayV2?.matched == true && r.replayV1?.matched == false)
        .toList();
    stdout.writeln('disagreement V1-match/V2-miss: ${v1YesV2No.length}'
        '${v1YesV2No.isEmpty ? '' : '  (${v1YesV2No.map((r) => r.id).join(', ')})'}');
    stdout.writeln('disagreement V2-match/V1-miss: ${v2YesV1No.length}'
        '${v2YesV1No.isEmpty ? '' : '  (${v2YesV1No.map((r) => r.id).join(', ')})'}');
  }

  // Phone-recorded vs replay agreement — sanity check that replay is faithful.
  var agreeV2 = 0, comparedV2 = 0;
  for (final r in withLive) {
    if (r.recordedV2?.matched != null && r.replayV2?.matched != null) {
      comparedV2++;
      if (r.recordedV2!.matched == r.replayV2!.matched) agreeV2++;
    }
  }
  if (comparedV2 > 0) {
    stdout.writeln('phone-vs-replay V2 agreement: $agreeV2 / $comparedV2');
  }

  final byMovement = <String, List<SessionReport>>{};
  for (final r in withLive) {
    byMovement.putIfAbsent(r.movement, () => []).add(r);
  }
  if (byMovement.length > 1) {
    stdout.writeln('\nby movement:');
    for (final e in byMovement.entries) {
      final n = e.value.length;
      final v1m = e.value.where((r) => r.replayV1?.matched == true).length;
      final v2m = e.value.where((r) => r.replayV2?.matched == true).length;
      stdout.writeln('  ${e.key.padRight(24)} n=$n  V1 $v1m  V2 $v2m');
    }
  }
}
