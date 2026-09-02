import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../data/ai_motion_models.dart';

/// Schema version of [NuvoMotionDiagnosticSession]. Bump on any breaking change
/// to the payload shape. Offline tools (`tools/motion_v2/replay_session.py`)
/// pin to this.
const int kMotionDiagSchema = 1;

/// One frame of pose data for offline replay. Compact: joint-major arrays.
class MotionDiagFrame {
  MotionDiagFrame({
    required this.tMs,
    required this.raw,
    this.smoothed,
    this.interpolated = const [],
    this.missing = const [],
    this.readiness,
    this.articulationEnergy,
  });

  /// ms since the session started.
  final int tMs;

  /// name -> [x, y, z, confidence]
  final Map<String, List<double>> raw;
  final Map<String, List<double>>? smoothed;
  final List<String> interpolated;
  final List<String> missing;
  final String? readiness;
  final double? articulationEnergy;

  static Map<String, List<double>> _pts(NuvoPoseFrame f) => {
        for (final e in f.points.entries)
          e.key: [
            _r(e.value.x),
            _r(e.value.y),
            _r(e.value.z),
            _r(e.value.likelihood),
          ],
      };

  factory MotionDiagFrame.fromFrames({
    required int tMs,
    required NuvoPoseFrame raw,
    NuvoPoseFrame? smoothed,
    List<String> interpolated = const [],
    List<String> missing = const [],
    String? readiness,
    double? articulationEnergy,
  }) =>
      MotionDiagFrame(
        tMs: tMs,
        raw: _pts(raw),
        smoothed: smoothed == null ? null : _pts(smoothed),
        interpolated: interpolated,
        missing: missing,
        readiness: readiness,
        articulationEnergy: articulationEnergy,
      );

  Map<String, dynamic> toJson() => {
        't': tMs,
        'raw': raw,
        if (smoothed != null) 'smoothed': smoothed,
        if (interpolated.isNotEmpty) 'interp': interpolated,
        if (missing.isNotEmpty) 'missing': missing,
        if (readiness != null) 'readiness': readiness,
        if (articulationEnergy != null) 'energy': _r(articulationEnergy!),
      };
}

double _r(num v) => double.parse(v.toStringAsFixed(5));

class MotionDiagDemo {
  MotionDiagDemo({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.rawFrameCount,
    required this.trimmedFrameCount,
    required this.estFps,
    required this.frames,
    this.tracking = const {},
    this.segmentation = const {},
  });

  final int index;
  final int startMs;
  final int endMs;
  final int rawFrameCount;
  final int trimmedFrameCount;
  final double estFps;
  final List<MotionDiagFrame> frames;
  final Map<String, dynamic> tracking;
  final Map<String, dynamic> segmentation;

  Map<String, dynamic> toJson() => {
        'index': index,
        'startMs': startMs,
        'endMs': endMs,
        'rawDurationMs': endMs - startMs,
        'rawFrameCount': rawFrameCount,
        'trimmedFrameCount': trimmedFrameCount,
        'estFps': _r(estFps),
        'tracking': tracking,
        'segmentation': segmentation,
        'frames': [for (final f in frames) f.toJson()],
      };
}

class MotionDiagMatchWindow {
  MotionDiagMatchWindow({
    required this.tMs,
    required this.bufferFrames,
    required this.protoDist,
    required this.trajDist,
    required this.votesList,
    this.separation,
    required this.motionProgress,
    required this.decision,
    required this.confidence,
    required this.state,
    required this.newRep,
    required this.count,
    this.inferenceMs = 0,
  });

  final int tMs;
  final int bufferFrames;
  final List<double> protoDist; // per reference
  final List<double> trajDist; // per reference
  final List<bool> votesList;
  final double? separation;
  final double motionProgress;
  final String decision;
  final double confidence;
  final String state;
  final bool newRep;
  final int count;
  final int inferenceMs;

  int get votes => votesList.where((v) => v).length;

  Map<String, dynamic> toJson() => {
        't': tMs,
        'buffer': bufferFrames,
        'proto': [for (final d in protoDist) _r(d)],
        'traj': [for (final d in trajDist) _r(d)],
        'votes': votes,
        'voteList': votesList,
        if (separation != null) 'separation': _r(separation!),
        'progress': _r(motionProgress),
        'decision': decision,
        'confidence': _r(confidence),
        'state': state,
        if (newRep) 'newRep': true,
        'count': count,
        'inferenceMs': inferenceMs,
      };
}

class MotionDiagLiveTest {
  MotionDiagLiveTest({
    required this.startMs,
    required this.endMs,
    required this.frames,
    required this.matchTrace,
    this.finalAttempt,
    this.finalCount = 0,
  });

  final int startMs;
  final int endMs;
  final List<MotionDiagFrame> frames;
  final List<MotionDiagMatchWindow> matchTrace;
  final Map<String, dynamic>? finalAttempt;
  final int finalCount;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'durationMs': endMs - startMs,
        'frameCount': frames.length,
        'finalCount': finalCount,
        if (finalAttempt != null) 'finalAttempt': finalAttempt,
        'matchTrace': [for (final w in matchTrace) w.toJson()],
        'frames': [for (final f in frames) f.toJson()],
      };
}

/// A complete, versioned, offline-replayable record of one Teach Nuvo session
/// (3 demos -> learn -> test). Behind `NUVO_DIAGNOSTICS`.
class NuvoMotionDiagnosticSession {
  NuvoMotionDiagnosticSession({
    required this.sessionId,
    required this.timestamp,
    required this.meta,
    required this.teaching,
    this.selfValidation,
    this.spec,
    this.liveTest,
    this.performance = const {},
  });

  final String sessionId;
  final DateTime timestamp;

  /// app version, git commit, platform, device, OS, build mode, schema
  /// versions, encoder / matcher / normalization identifiers.
  final Map<String, dynamic> meta;
  final List<MotionDiagDemo> teaching;
  final Map<String, dynamic>? selfValidation;

  /// The full learned `TaughtMotionV2Spec` JSON (references, spreads,
  /// thresholds, region activity).
  final Map<String, dynamic>? spec;
  final MotionDiagLiveTest? liveTest;
  final Map<String, dynamic> performance;

  /// `MV2-YYYYMMDD-XXXXXX` from a timestamp + short random token.
  static String newId(DateTime now, String token) {
    final d = now.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'MV2-${d.year}${two(d.month)}${two(d.day)}-'
        '${token.toUpperCase().padRight(6, '0').substring(0, 6)}';
  }

  Map<String, dynamic> toJson() => {
        'schema': kMotionDiagSchema,
        'sessionId': sessionId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'meta': meta,
        'teaching': [for (final d in teaching) d.toJson()],
        if (selfValidation != null) 'selfValidation': selfValidation,
        if (spec != null) 'spec': spec,
        if (liveTest != null) 'liveTest': liveTest!.toJson(),
        'performance': performance,
      };

  /// gzip'd JSON — raw pose data compresses heavily. This is the FULL session
  /// artifact (the one you hand back for offline replay).
  Uint8List toGzipBytes() {
    final json = utf8.encode(jsonEncode(toJson()));
    return Uint8List.fromList(gzip.encode(json));
  }

  // ── Human-readable Copy Log ────────────────────────────────────────────────

  String toLogText() {
    final b = StringBuffer();
    void h(String s) => b.writeln('\n═══ $s ═══');
    void kv(String k, Object? v) => b.writeln('  $k: $v');

    b.writeln('NUVO MOTION V2 DIAGNOSTIC  (schema $kMotionDiagSchema)');
    h('SESSION');
    kv('id', sessionId);
    kv('timestamp', timestamp.toUtc().toIso8601String());
    meta.forEach(kv);

    for (final demo in teaching) {
      h('TEACHING DEMO ${demo.index}');
      kv('duration', '${demo.endMs - demo.startMs} ms  (${demo.rawFrameCount} raw '
          '-> ${demo.trimmedFrameCount} trimmed frames)');
      kv('est fps', demo.estFps.toStringAsFixed(1));
      demo.tracking.forEach((k, v) => kv('track.$k', v));
      demo.segmentation.forEach((k, v) => kv('seg.$k', v));
      // per-region summary of the frames' motion, computed later offline; here
      // just note coverage.
      final withPts = demo.frames.where((f) => f.raw.isNotEmpty).length;
      kv('frames with pose', '$withPts / ${demo.frames.length}');
    }

    if (selfValidation != null) {
      h('SELF VALIDATION');
      selfValidation!.forEach(kv);
    }

    if (spec != null) {
      h('LEARNED SPEC (three-shot)');
      kv('schema', spec!['schema']);
      kv('references', (spec!['references'] as List?)?.length);
      kv('proto_spread', spec!['proto_spread']);
      kv('traj_spread', spec!['traj_spread']);
      kv('proto_spread_max', spec!['proto_spread_max']);
      kv('traj_spread_max', spec!['traj_spread_max']);
      kv('demo_lengths', spec!['demo_lengths']);
      kv('demo_active_vel', spec!['demo_active_vel']);
      kv('region_activity', spec!['region_activity']);
    }

    final lt = liveTest;
    if (lt != null) {
      h('LIVE TEST');
      kv('duration', '${lt.endMs - lt.startMs} ms  (${lt.frames.length} frames)');
      kv('final count', lt.finalCount);

      h('MATCH TRACE');
      for (final w in lt.matchTrace) {
        b.writeln('  t=${(w.tMs / 1000).toStringAsFixed(2)}s  '
            'votes=${w.votes}/${w.protoDist.length}  '
            'progress=${w.motionProgress.toStringAsFixed(2)}  '
            'sep=${w.separation?.toStringAsFixed(2) ?? "-"}  '
            'proto=[${w.protoDist.map((d) => d.toStringAsFixed(3)).join(",")}]  '
            'traj=[${w.trajDist.map((d) => d.toStringAsFixed(3)).join(",")}]  '
            '${w.decision}${w.newRep ? "  +1" : ""}');
      }

      final fa = lt.finalAttempt;
      if (fa != null) {
        h('FINAL ATTEMPT');
        fa.forEach(kv);
      }
    }

    if (performance.isNotEmpty) {
      h('PERFORMANCE');
      performance.forEach(kv);
    }

    b.writeln('\nFull replayable session: $sessionId (.json.gz)');
    return b.toString();
  }
}
