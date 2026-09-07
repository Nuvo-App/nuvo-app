import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/ai_motion_models.dart';
import '../../domain/motion_activity.dart';
import 'motion_session_artifact.dart';

/// Accumulates one motion verification attempt into a [MotionSessionArtifact].
///
/// Lifecycle mirrors the verification camera:
/// ```
/// start()           // camera opens / recording begins
/// recordFrame(...)  // every PROCESSED pose frame
/// recordCount(...)  // every rep the verifier awards
/// recordState(...)  // validator-state / readiness changes worth keeping
/// finish(...)       // verifier completes, user submits, or the screen exits
/// ```
/// [build] is safe to call after [finish]; an unfinished session still builds
/// (marked `incomplete`) — a session that never reached `finish` is often the
/// most useful diagnostic.
class MotionSessionRecorder {
  MotionSessionRecorder({
    required this.kind,
    required this.activityId,
    required this.activityTitle,
    required this.measurementType,
    this.raceId,
    this.goalValue,
    this.goalUnit = 'reps',
  }) : sessionId = 'ms_${const Uuid().v4().replaceAll('-', '')}';

  final String sessionId;
  final MotionSessionKind kind;
  final String activityId;
  final String activityTitle;
  final String measurementType;
  final String? raceId;
  final int? goalValue;
  final String goalUnit;

  DateTime? _startedAt;
  DateTime? _endedAt;
  final List<NuvoPoseFrame> _frames = [];
  final List<MotionSessionEvent> _events = [];

  // Result (filled by finish()).
  MotionSessionOutcome _outcome = MotionSessionOutcome.incomplete;
  int _detectedValue = 0;
  double _confidence = 0;
  String _failedRuleReason = '';

  // Pipeline counters (fed from PoseDetectorService diagnostics).
  int _framesReceived = 0;
  int _framesProcessed = 0;
  double _effectiveFps = 0;

  String _lastState = '';
  int _lastCount = 0;

  /// Cap so a very long attempt can't grow memory unbounded. ~30s at 20fps
  /// of processed frames; the verifier itself keeps a similar bound.
  static const _maxFrames = 900;

  bool get isRecording => _startedAt != null && _endedAt == null;

  void start() {
    _startedAt = DateTime.now();
    _events.add(MotionSessionEvent(tMs: 0, type: 'note', detail: 'session start'));
  }

  int get _elapsedMs =>
      _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds;

  /// One processed pose frame plus the verifier's read of it. Call once per
  /// frame that actually reached the validator.
  void recordFrame(
    NuvoPoseFrame frame, {
    required String validatorState,
    required int count,
    required double confidence,
    required String failedRuleReason,
    Map<String, double> debugValues = const {},
    String? readiness,
  }) {
    if (!isRecording) return;
    if (_frames.length < _maxFrames) _frames.add(frame);
    _confidence = confidence;

    if (count > _lastCount) {
      _events.add(MotionSessionEvent(
        tMs: _elapsedMs,
        type: 'rep_counted',
        state: validatorState,
        count: count,
        metrics: debugValues,
      ));
      _lastCount = count;
    }
    if (validatorState != _lastState && validatorState.isNotEmpty) {
      _events.add(MotionSessionEvent(
        tMs: _elapsedMs,
        type: 'validator_state',
        state: validatorState,
        detail: failedRuleReason.isEmpty ? null : 'rejected: $failedRuleReason',
        metrics: debugValues,
      ));
      _lastState = validatorState;
    }
    if (readiness != null) {
      _events.add(MotionSessionEvent(
        tMs: _elapsedMs,
        type: 'readiness',
        state: readiness,
      ));
    }
  }

  void recordEvent(String type, {String? detail, Map<String, double> metrics = const {}}) {
    if (_startedAt == null) return;
    _events.add(MotionSessionEvent(
      tMs: _elapsedMs,
      type: type,
      detail: detail,
      metrics: metrics,
    ));
  }

  void updatePipeline({
    required int framesReceived,
    required int framesProcessed,
    required double effectiveFps,
  }) {
    _framesReceived = framesReceived;
    _framesProcessed = framesProcessed;
    _effectiveFps = effectiveFps;
  }

  /// The verifier reached a terminal state. [outcome] `null` → the screen
  /// exited without a result (`incomplete`).
  void finish({
    MotionSessionOutcome? outcome,
    int detectedValue = 0,
    double? confidence,
    String failedRuleReason = '',
  }) {
    if (_endedAt != null) return;
    _endedAt = DateTime.now();
    _outcome = outcome ?? MotionSessionOutcome.incomplete;
    _detectedValue = detectedValue;
    if (confidence != null) _confidence = confidence;
    _failedRuleReason = failedRuleReason;
    _events.add(MotionSessionEvent(
      tMs: _elapsedMs,
      type: 'note',
      detail: 'session end (${_outcome.wire})',
    ));
  }

  MotionSessionArtifact build({Map<String, dynamic>? serverAnalysis}) {
    final start = _startedAt ?? DateTime.now();
    return MotionSessionArtifact(
      sessionId: sessionId,
      kind: kind,
      startedAt: start,
      endedAt: _endedAt ?? DateTime.now(),
      activityId: activityId,
      activityTitle: activityTitle,
      raceId: raceId,
      goalValue: goalValue,
      goalUnit: goalUnit,
      measurementType: measurementType,
      outcome: _outcome,
      detectedValue: _detectedValue,
      confidence: _confidence,
      failedRuleReason: _failedRuleReason,
      verifierVersion: _BaseValidatorVersion.value,
      modelVersion: 'mlkit-pose-base',
      appVersion: const String.fromEnvironment('NUVO_APP_VERSION',
          defaultValue: 'dev'),
      gitCommit: const String.fromEnvironment('NUVO_GIT_COMMIT',
          defaultValue: 'unknown'),
      platform: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      buildMode: kReleaseMode
          ? 'release'
          : kProfileMode
              ? 'profile'
              : 'debug',
      framesReceived: _framesReceived,
      framesProcessed: _framesProcessed,
      effectivePoseFps: _effectiveFps,
      frames: List.unmodifiable(_frames),
      events: List.unmodifiable(_events),
      serverAnalysis: serverAnalysis,
    );
  }
}

/// The one place the preset verifier version string lives (matches
/// `_BaseValidator.validatorVersion`).
abstract final class _BaseValidatorVersion {
  static const value = 'nuvo-ai-motion-v2';
}

/// Helper so a screen can derive the measurement type without importing the
/// catalog directly in more than one place.
String motionMeasurementLabelFor(MotionMeasurementType t) => t.name;
