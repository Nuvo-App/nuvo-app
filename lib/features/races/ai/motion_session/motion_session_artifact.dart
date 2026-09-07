import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../data/ai_motion_models.dart';
import '../../data/motion_analysis_contract.dart';

/// Schema version for [MotionSessionArtifact]. Bump on any breaking change to
/// the JSON shape; stored sessions must stay readable after the verifier
/// changes, so the analyst / replay tooling keys on this.
const int kMotionSessionSchema = 1;

/// Which verifier produced the session.
enum MotionSessionKind { preset, custom }

/// How the session ended.
enum MotionSessionOutcome { verified, failed, incomplete }

extension MotionSessionOutcomeWire on MotionSessionOutcome {
  String get wire => switch (this) {
        MotionSessionOutcome.verified => 'verified',
        MotionSessionOutcome.failed => 'failed',
        MotionSessionOutcome.incomplete => 'incomplete',
      };
}

/// One meaningful runtime decision during the session — a rep the verifier
/// awarded, a candidate it rejected, a readiness transition, an error. This is
/// the "interpretation" layer: what Nuvo believed was happening, stored next
/// to the raw pose observations so an analyst never has to reconstruct it.
class MotionSessionEvent {
  MotionSessionEvent({
    required this.tMs,
    required this.type,
    this.state,
    this.detail,
    this.count,
    this.metrics = const {},
  });

  /// Milliseconds since session start.
  final int tMs;

  /// 'rep_counted' | 'readiness' | 'validator_state' | 'target_reached' |
  /// 'rejection' | 'error' | 'note'.
  final String type;
  final String? state;
  final String? detail;
  final int? count;

  /// Relevant numbers at this instant (elbow angle, knee stagger, confidence,
  /// similarity scores, thresholds…).
  final Map<String, double> metrics;

  Map<String, dynamic> toJson() => {
        't': tMs,
        'type': type,
        if (state != null) 'state': state,
        if (detail != null) 'detail': detail,
        if (count != null) 'count': count,
        if (metrics.isNotEmpty)
          'metrics': {
            for (final e in metrics.entries) e.key: _round(e.value),
          },
      };
}

/// The complete, self-contained record of one motion verification attempt.
///
/// It carries both the OBSERVATION (the normalized landmark stream the
/// verifier actually evaluated) and the INTERPRETATION (race/goal context,
/// verifier + model versions, the decision events, the final result) so a
/// developer or an AI analyst can understand the attempt from this object
/// alone — no phone log required.
///
/// Serialization mirrors the Motion V2 diagnostic session convention: a
/// schema-versioned JSON document, gzip'd for storage / upload (raw pose data
/// compresses heavily), plus a compact human log. Both the manual "share
/// session" action and the automatic upload consume this same object.
class MotionSessionArtifact {
  MotionSessionArtifact({
    required this.sessionId,
    required this.kind,
    required this.startedAt,
    required this.endedAt,
    required this.activityId,
    required this.activityTitle,
    required this.raceId,
    required this.goalValue,
    required this.goalUnit,
    required this.measurementType,
    required this.outcome,
    required this.detectedValue,
    required this.confidence,
    required this.failedRuleReason,
    required this.verifierVersion,
    required this.modelVersion,
    required this.appVersion,
    required this.gitCommit,
    required this.platform,
    required this.osVersion,
    required this.buildMode,
    required this.framesReceived,
    required this.framesProcessed,
    required this.effectivePoseFps,
    required this.frames,
    required this.events,
    this.serverAnalysis,
    this.extra = const {},
  });

  final String sessionId;
  final MotionSessionKind kind;
  final DateTime startedAt;
  final DateTime endedAt;

  final String activityId;
  final String activityTitle;
  final String? raceId;
  final int? goalValue;
  final String goalUnit;
  final String measurementType;

  final MotionSessionOutcome outcome;
  final int detectedValue;
  final double confidence;
  final String failedRuleReason;

  final String verifierVersion;
  final String modelVersion;
  final String appVersion;
  final String gitCommit;
  final String platform;
  final String osVersion;
  final String buildMode;

  final int framesReceived;
  final int framesProcessed;
  final double effectivePoseFps;

  /// The normalized landmark stream the verifier evaluated (bounded upstream).
  final List<NuvoPoseFrame> frames;

  /// The verifier's decision trace.
  final List<MotionSessionEvent> events;

  /// The server motion-analysis result, if one came back before finish.
  final Map<String, dynamic>? serverAnalysis;

  final Map<String, dynamic> extra;

  int get durationMs => endedAt.difference(startedAt).inMilliseconds;
  int get framesDropped => framesReceived - framesProcessed;

  /// The searchable metadata a client sends alongside the blob so the Worker
  /// can index it without unpacking the whole payload.
  Map<String, dynamic> metadata() => {
        'sessionId': sessionId,
        'kind': kind.name,
        'activityId': activityId,
        'raceId': raceId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'outcome': outcome.wire,
        'detectedValue': detectedValue,
        'goalValue': goalValue,
        'confidence': _round(confidence),
        'failedRuleReason': failedRuleReason,
        'appVersion': appVersion,
        'gitCommit': gitCommit,
        'verifierVersion': verifierVersion,
        'modelVersion': modelVersion,
        'schemaVersion': kMotionSessionSchema,
        'frameCount': frames.length,
        'durationMs': durationMs,
      };

  Map<String, dynamic> toJson() => {
        'schemaVersion': kMotionSessionSchema,
        'sessionId': sessionId,
        'kind': kind.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
        'durationMs': durationMs,
        'context': {
          'activityId': activityId,
          'activityTitle': activityTitle,
          'raceId': raceId,
          'goal': {
            'value': goalValue,
            'unit': goalUnit,
            'measurementType': measurementType,
          },
        },
        'result': {
          'outcome': outcome.wire,
          'detectedValue': detectedValue,
          'goalValue': goalValue,
          'confidence': _round(confidence),
          'failedRuleReason': failedRuleReason,
        },
        'versions': {
          'schema': kMotionSessionSchema,
          'verifier': verifierVersion,
          'model': modelVersion,
          'app': appVersion,
          'gitCommit': gitCommit,
        },
        'device': {
          'platform': platform,
          'osVersion': osVersion,
          'buildMode': buildMode,
        },
        'pipeline': {
          'framesReceived': framesReceived,
          'framesProcessed': framesProcessed,
          'framesDropped': framesDropped,
          'effectivePoseFps': _round(effectivePoseFps),
        },
        'events': [for (final e in events) e.toJson()],
        'frames': [for (final f in frames) f.toJson()],
        if (serverAnalysis != null) 'serverAnalysis': serverAnalysis,
        if (extra.isNotEmpty) 'extra': extra,
      };

  /// gzip'd JSON — the storage / upload form.
  Uint8List toGzipBytes() =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(toJson()))));

  /// Compact human log — the "Copy Log" form. Enough to triage without
  /// unpacking the full artifact.
  String toLogText() {
    final b = StringBuffer()
      ..writeln('NUVO MOTION SESSION  $sessionId')
      ..writeln('activity   : $activityId ($activityTitle)  kind=${kind.name}')
      ..writeln('race       : ${raceId ?? '(none)'}')
      ..writeln('goal       : ${goalValue ?? '-'} $goalUnit  ($measurementType)')
      ..writeln('outcome    : ${outcome.wire}  '
          'detected=$detectedValue/${goalValue ?? '-'}  '
          'confidence=${_round(confidence)}')
      ..writeln('failedRule : ${failedRuleReason.isEmpty ? 'none' : failedRuleReason}')
      ..writeln('duration   : ${durationMs}ms')
      ..writeln('pipeline   : received=$framesReceived processed=$framesProcessed '
          'dropped=$framesDropped  fps=${_round(effectivePoseFps)}')
      ..writeln('versions   : app=$appVersion commit=$gitCommit '
          'verifier=$verifierVersion model=$modelVersion')
      ..writeln('device     : $platform $osVersion ($buildMode)')
      ..writeln('frames     : ${frames.length} captured')
      ..writeln('')
      ..writeln('EVENTS');
    for (final e in events) {
      b.write('  +${e.tMs}ms  ${e.type}');
      if (e.state != null) b.write('  state=${e.state}');
      if (e.count != null) b.write('  count=${e.count}');
      if (e.detail != null) b.write('  ${e.detail}');
      if (e.metrics.isNotEmpty) {
        b.write('  {');
        b.write(e.metrics.entries
            .map((m) => '${m.key}=${_round(m.value)}')
            .join(', '));
        b.write('}');
      }
      b.writeln();
    }
    if (serverAnalysis != null) {
      b
        ..writeln('')
        ..writeln('SERVER ANALYSIS')
        ..writeln('  ${jsonEncode(serverAnalysis)}');
    }
    b.writeln('\nFull session: $sessionId.json.gz (schema $kMotionSessionSchema)');
    return b.toString();
  }

  /// Write the gzip artifact to a local file (shared by manual export and the
  /// upload queue's on-disk staging). Returns the file.
  Future<File> writeGzip(String dirPath) async {
    final file = File('$dirPath/$sessionId.json.gz');
    await file.writeAsBytes(toGzipBytes(), flush: true);
    return file;
  }
}

double _round(double v) => (v * 1000).roundToDouble() / 1000;
