/// Motion Engine V2 — app-side contract.
///
/// Flutter talks to [MotionVerifierV2], never to MotionBERT / the Python engine
/// directly. See `tools/motion_v2/` and `docs/agents/13-motion-engine-v2.md`.
library;

/// Motion V2 is the **default** custom‑motion engine and runs fully on‑device
/// (`MotionV2NativeRuntime` → bundled ONNX MotionBERT). No flag, no service.
///
/// `--dart-define=NUVO_FORCE_V1=true` forces the legacy geometric verifier
/// (`CustomPoseSequenceRuntime`) — internal troubleshooting / comparison only.
const bool kMotionV1Forced = bool.fromEnvironment('NUVO_FORCE_V1');

/// The dev HTTP service (`tools/motion_v2/service/`) — reachable **only** from
/// the diagnostics panel for native‑vs‑Python comparison. Never on the normal
/// runtime path.
const String kMotionV2ServiceUrl = String.fromEnvironment(
  'NUVO_MOTION_V2_URL',
  defaultValue: 'http://localhost:8799',
);

enum MotionV2RuntimeState { warmingUp, neutral, matching, returning, error }

/// Lifecycle of one detected attempt at the taught movement — so a failure at
/// 5% ("never started") is distinguishable from a failure at 85% ("almost").
enum MotionAttemptOutcome { idle, inProgress, success, failed }

/// Internal diagnostic categories — NEVER shown to users verbatim (see
/// [MotionAttemptResult.userFeedback] for the message the user sees).
enum MotionFailureCategory {
  none,
  poseNotTrackable,
  partialBodyMissing,
  cameraDistanceChangedTooMuch,
  motionNeverStarted,
  motionIncomplete,
  trajectoryMismatch,
  wrongMotion,
  motionTooFast,
  motionStalled,
  lostTrackingMidMotion,
}

/// Structured explanation of one attempt — the "why" behind a rep that did or
/// did not count. Carried on [MotionV2RuntimeResult.attempt].
class MotionAttemptResult {
  const MotionAttemptResult({
    this.outcome = MotionAttemptOutcome.idle,
    this.failureCategory = MotionFailureCategory.none,
    this.poseReadiness = 'no_person',
    this.maxProgress = 0,
    this.prototypeDistance,
    this.prototypeThreshold,
    this.trajectoryDistance,
    this.trajectoryThreshold,
    this.durationMs = 0,
    this.expectedDurationMinMs = 0,
    this.expectedDurationMaxMs = 0,
    this.missingRegions = const [],
    this.regionErrors = const {},
    this.primaryMismatchRegion,
    this.cameraDistanceChange = 0,
    this.rootTranslation = 0,
    this.encoderLatencyMs = 0,
    this.userFeedback = '',
  });

  final MotionAttemptOutcome outcome;
  final MotionFailureCategory failureCategory;
  final String poseReadiness;
  final double maxProgress;
  final double? prototypeDistance;
  final double? prototypeThreshold;
  final double? trajectoryDistance;
  final double? trajectoryThreshold;
  final int durationMs;
  final int expectedDurationMinMs;
  final int expectedDurationMaxMs;
  final List<String> missingRegions;
  final Map<String, double> regionErrors;
  final String? primaryMismatchRegion;
  final double cameraDistanceChange;
  final double rootTranslation;
  final double encoderLatencyMs;

  /// The short, high-confidence instruction to show the user. Empty when there
  /// is nothing worth saying yet.
  final String userFeedback;

  static const empty = MotionAttemptResult();

  Map<String, dynamic> toJson() => {
        'outcome': outcome.name,
        'failureCategory': failureCategory.name,
        'poseReadiness': poseReadiness,
        'maxProgress': double.parse(maxProgress.toStringAsFixed(3)),
        if (prototypeDistance != null) 'prototypeDistance': prototypeDistance,
        if (prototypeThreshold != null) 'prototypeThreshold': prototypeThreshold,
        if (trajectoryDistance != null) 'trajectoryDistance': trajectoryDistance,
        if (trajectoryThreshold != null)
          'trajectoryThreshold': trajectoryThreshold,
        'durationMs': durationMs,
        'expectedDurationMs': [expectedDurationMinMs, expectedDurationMaxMs],
        'missingRegions': missingRegions,
        'regionErrors': regionErrors
            .map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(3)))),
        if (primaryMismatchRegion != null)
          'primaryMismatchRegion': primaryMismatchRegion,
        'cameraDistanceChange':
            double.parse(cameraDistanceChange.toStringAsFixed(4)),
        'rootTranslation': double.parse(rootTranslation.toStringAsFixed(4)),
        'encoderLatencyMs': double.parse(encoderLatencyMs.toStringAsFixed(1)),
        'userFeedback': userFeedback,
      };
}

MotionV2RuntimeState _stateFromRaw(String? raw) => switch (raw) {
  'warming_up' => MotionV2RuntimeState.warmingUp,
  'matched' => MotionV2RuntimeState.matching,
  'returning' => MotionV2RuntimeState.returning,
  'neutral' => MotionV2RuntimeState.neutral,
  _ => MotionV2RuntimeState.neutral,
};

/// A movement learned by Motion V2 — the versioned, serializable spec that
/// travels through the existing custom-verifier storage path.
/// The [movementName] is display metadata only; it never affects recognition.
class TaughtMotionV2Spec {
  const TaughtMotionV2Spec({required this.json, required this.movementName});

  /// Opaque payload produced by the engine. The app does not interpret it —
  /// it stores it and hands it back on `MotionVerifierV2.load`.
  final Map<String, dynamic> json;
  final String movementName;

  String get verifierType => json['verifier'] as String? ?? 'motion_v2';
  int get version => (json['version'] as num?)?.toInt() ?? 1;
  String get encoder => json['encoder'] as String? ?? 'unknown';

  factory TaughtMotionV2Spec.fromJson(Map<String, dynamic> j) => TaughtMotionV2Spec(
    json: j,
    movementName: (j['name'] ?? j['metadata']?['movementName'] ?? 'Custom movement') as String,
  );

  Map<String, dynamic> toJson() => json;
}

/// One recognition update from the live runtime.
class MotionV2RuntimeResult {
  const MotionV2RuntimeResult({
    required this.matched,
    required this.newRep,
    required this.count,
    required this.confidence,
    required this.motionProgress,
    required this.state,
    required this.inferenceLatency,
    this.bufferFrames = 0,
    this.protoDist,
    this.protoMargin,
    this.trajSim,
    this.rootDrift,
    this.scaleSpread,
    this.poseGuidance = '',
    this.poseReadiness = 'ready',
    this.attempt = MotionAttemptResult.empty,
    this.votes = 0,
    this.separation,
    this.decision = 'reject',
    this.perReference = const [],
  });

  final bool matched;
  final bool newRep;
  final int count;
  final double confidence;
  final double motionProgress;
  final MotionV2RuntimeState state;
  final Duration inferenceLatency;
  final int bufferFrames;
  final double? protoDist;
  final double? protoMargin;
  final double? trajSim;

  /// Camera-quality diagnostics from [MotionInputDiagnostics] — the
  /// within-window root drift / anatomical-scale spread the normalizer
  /// removed before the encoder saw the frames. Never affects recognition.
  final double? rootDrift;
  final double? scaleSpread;

  /// Live camera-readiness guidance for the big on-screen message ('Move back',
  /// 'Step closer', 'Ready', …) and its [PoseReadiness] name.
  final String poseGuidance;
  final String poseReadiness;

  /// The current attempt lifecycle + failure explanation (see
  /// [MotionAttemptResult]). `userFeedback` here is what the user should see
  /// when a rep does not land.
  final MotionAttemptResult attempt;

  /// Multi-reference matcher diagnostics for the last window: how many of the 3
  /// taught references agreed, the separation margin against generic motion,
  /// the decision path, and the per-reference proto/traj scores.
  final int votes;
  final double? separation;
  final String decision; // '2of3_consensus' | 'separation_rescue' | 'reject'
  final List<Map<String, dynamic>> perReference;

  static const empty = MotionV2RuntimeResult(
    matched: false, newRep: false, count: 0, confidence: 0, motionProgress: 0,
    state: MotionV2RuntimeState.warmingUp, inferenceLatency: Duration.zero,
  );

  factory MotionV2RuntimeResult.fromJson(Map<String, dynamic> j) => MotionV2RuntimeResult(
    matched: j['matched'] as bool? ?? false,
    newRep: j['newRep'] as bool? ?? false,
    count: (j['count'] as num?)?.toInt() ?? 0,
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
    motionProgress: (j['progress'] as num?)?.toDouble() ?? 0,
    state: _stateFromRaw(j['state'] as String?),
    inferenceLatency: Duration(
      microseconds: (((j['latencyMs'] as num?)?.toDouble() ?? 0) * 1000).round(),
    ),
    bufferFrames: (j['bufferFrames'] as num?)?.toInt() ?? 0,
    protoDist: (j['proto_dist'] as num?)?.toDouble(),
    protoMargin: (j['proto_margin'] as num?)?.toDouble(),
    trajSim: (j['traj_sim'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toDiagnosticsJson() => {
    'matched': matched, 'newRep': newRep, 'count': count,
    'confidence': confidence, 'progress': motionProgress, 'state': state.name,
    'latencyMs': inferenceLatency.inMicroseconds / 1000,
    'bufferFrames': bufferFrames,
    if (protoDist != null) 'protoDist': protoDist,
    if (protoMargin != null) 'protoMargin': protoMargin,
    if (trajSim != null) 'trajSim': trajSim,
    if (rootDrift != null) 'rootDrift': rootDrift,
    if (scaleSpread != null) 'scaleSpread': scaleSpread,
    'poseReadiness': poseReadiness,
    if (poseGuidance.isNotEmpty) 'poseGuidance': poseGuidance,
    'attempt': attempt.toJson(),
    'matcher': {
      'votes': votes,
      if (separation != null) 'separation': separation,
      'decision': decision,
      'perReference': perReference,
    },
  };
}

class MotionV2Exception implements Exception {
  const MotionV2Exception(this.message);
  final String message;
  @override
  String toString() => 'MotionV2Exception: $message';
}
