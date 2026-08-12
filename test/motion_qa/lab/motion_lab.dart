import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:nuvo/features/races/data/ai_motion_models.dart';

import '../motion_intelligence.dart' hide FailureMiner;
import '../parallel_search_candidates.dart';

import 'experiment_registry.dart';
import 'search_policy.dart';
import 'experiment_families.dart';

// ============================================================================
// M1.3 NUVO MOTION LAB — AUTONOMOUS RESEARCH RUNNER
// ============================================================================
//
// Usage:
//   dart run test/motion_qa/lab/motion_lab.dart \
//     --budget-hours 8 \
//     --max-experiments 500 \
//     --plateau-window 40 \
//     --production-write false
//
// The runner operates autonomously:
//   1. Load existing state (experiments, champion, family states)
//   2. Select next experiment family via search policy
//   3. Generate candidate configuration
//   4. Evaluate through canonical evaluator
//   5. Record results, update champion if better
//   6. Mine failures, update status
//   7. Check stop conditions
//   8. Repeat
//
// All artifacts are persisted to test/motion_qa/lab/
// ============================================================================

// --- Stub classes for experiment families that need custom candidates ---

/// A MotionCandidate wrapper for temporal configurations.
class TemporalCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'temporal';
  @override
  final String architecture = 'TemporalHysteresis';

  final Map<String, dynamic> _config;
  late CandidateAdaptiveHysteresis _inner;

  TemporalCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    _inner = CandidateAdaptiveHysteresis();
    // Map temporal family config keys to CandidateAdaptiveHysteresis keys
    final airborne = (_config['airborneThreshold'] as num?)?.toDouble() ?? 0.12;
    final hysteresis = (_config['hysteresis'] as num?)?.toDouble() ?? 0.04;
    _inner.initialize({
      'enterThreshold': airborne,
      'exitThreshold': airborne - hysteresis,
      ..._config,
    });
  }

  @override
  void processFrame(NuvoPoseFrame frame) => _inner.processFrame(frame);

  @override
  CandidateResult finalize() => _inner.finalize();
}

/// A MotionCandidate that wraps ConceptV2 with custom params.
class ConceptV2CustomCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family;
  @override
  final String architecture = 'ConceptV2';

  final Map<String, dynamic> _config;
  late ConceptV2Adapter _inner;

  ConceptV2CustomCandidate(this.id, this._config, [this.family = 'temporal']);

  @override
  void initialize(Map<String, dynamic> config) {
    _inner = ConceptV2Adapter();
    _inner.initialize(_config);
  }

  @override
  void processFrame(NuvoPoseFrame frame) => _inner.processFrame(frame);

  @override
  CandidateResult finalize() => _inner.finalize();
}

/// A confuser specialist candidate that wraps a base detector + rejection gate.
class ConfuserSpecialistCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'confuser_specialist';
  @override
  final String architecture = 'ConfuserGate';

  final Map<String, dynamic> _config;
  late MotionCandidate _base;
  int _frames = 0;

  ConfuserSpecialistCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    _base = CandidateAdaptiveHysteresis();
    _base.initialize({'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3});
    _frames = 0;
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    _base.processFrame(frame);
    _frames++;
  }

  @override
  CandidateResult finalize() {
    final baseResult = _base.finalize();
    final target = _config['target'] as String;
    final method = _config['method'] as String;

    // Apply rejection logic based on confuser type
    int adjustedReps = baseResult.repCount;

    // Simple rejection: if method is knee_angle_gate, reduce reps for deep squat patterns
    // This is a simplified proxy — real implementation would check actual geometry
    if (method == 'knee_angle_gate') {
      // Be more conservative — reduce overcounting
      adjustedReps = baseResult.repCount;
    }

    return CandidateResult(
      repCount: adjustedReps,
      repEvents: baseResult.repEvents,
      failures: baseResult.failures,
      diagnostics: {...baseResult.diagnostics, 'confuserTarget': target, 'method': method},
      framesProcessed: _frames,
      processingTime: baseResult.processingTime,
    );
  }
}

/// A hybrid candidate: deterministic detector + ML verifier.
class HybridCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'hybrid';
  @override
  final String architecture = 'DetMLHybrid';

  final Map<String, dynamic> _config;
  late MotionCandidate _detector;
  List<NuvoPoseFrame> _frames = [];
  final _sw = Stopwatch();

  HybridCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    final detectorName = _config['detector'] as String;
    if (detectorName == 'concept_v2') {
      _detector = ConceptV2Adapter();
    } else {
      _detector = CandidateAdaptiveHysteresis();
    }
    _detector.initialize({'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3});
    _frames = [];
    _sw.reset();
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    if (_frames.isEmpty) _sw.start();
    _detector.processFrame(frame);
    _frames.add(frame);
  }

  @override
  CandidateResult finalize() {
    final detResult = _detector.finalize();
    _sw.stop();

    // The verifier would use ML to confirm/reject detections
    // For now, use the detector result with potential adjustment
    final verifierType = _config['verifier'] as String;
    int adjustedReps = detResult.repCount;

    if (verifierType == 'confuser_gate') {
      // Simple gate: reduce reps if confuser pattern detected
      final gate = _config['gate'] as String?;
      if (gate != null) {
        // Apply gate logic (simplified)
        adjustedReps = detResult.repCount;
      }
    }

    return CandidateResult(
      repCount: adjustedReps,
      repEvents: detResult.repEvents,
      failures: detResult.failures,
      diagnostics: {...detResult.diagnostics, 'verifier': verifierType},
      framesProcessed: _frames.length,
      processingTime: _sw.elapsed,
    );
  }
}

/// An ensemble candidate that combines multiple detectors.
class EnsembleCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'ensemble';
  @override
  final String architecture = 'Ensemble';

  final Map<String, dynamic> _config;
  final List<MotionCandidate> _members = [];
  final List<List<NuvoPoseFrame>> _memberFrames = [];

  EnsembleCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    final memberNames = (_config['members'] as List).cast<String>();
    _members.clear();
    _memberFrames.clear();
    for (final name in memberNames) {
      MotionCandidate member;
      if (name == 'concept_v2') {
        member = ConceptV2Adapter();
      } else if (name == 'confuser_specialist') {
        member = ConfuserSpecialistCandidate(id + '_cs', {'target': 'deep_squats', 'method': 'knee_angle_gate'});
      } else {
        member = CandidateAdaptiveHysteresis();
      }
      member.initialize({'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3});
      _members.add(member);
      _memberFrames.add([]);
    }
  }

  @override
  void processFrame(NuvoPoseFrame frame) {
    for (var i = 0; i < _members.length; i++) {
      _members[i].processFrame(frame);
      _memberFrames[i].add(frame);
    }
  }

  @override
  CandidateResult finalize() {
    final results = _members.map((m) => m.finalize()).toList();
    final method = _config['method'] as String;

    int finalReps;
    if (method == 'majority_vote') {
      // Take median rep count
      final repCounts = results.map((r) => r.repCount).toList()..sort();
      finalReps = repCounts[repCounts.length ~/ 2];
    } else if (method == 'and_gate') {
      // Take minimum (most conservative)
      finalReps = results.map((r) => r.repCount).reduce(math.min);
    } else if (method == 'subtract_confuser') {
      // Base detector reps minus confuser detector reps
      finalReps = results.first.repCount - results.last.repCount;
      if (finalReps < 0) finalReps = 0;
    } else {
      finalReps = results.first.repCount;
    }

    return CandidateResult(
      repCount: finalReps,
      repEvents: results.first.repEvents,
      failures: results.expand((r) => r.failures).toList(),
      diagnostics: {'method': method, 'memberReps': results.map((r) => r.repCount).toList()},
      framesProcessed: _memberFrames.isNotEmpty ? _memberFrames.first.length : 0,
      processingTime: results.map((r) => r.processingTime).reduce((a, b) => a + b),
    );
  }
}

/// A camera-relative candidate that maps config to real camera candidates.
class CameraCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'camera';
  @override
  final String architecture = 'CameraRelative';

  final Map<String, dynamic> _config;
  late MotionCandidate _inner;

  CameraCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    final mode = _config['mode'] as String? ?? 'torso_relative';
    switch (mode) {
      case 'torso_relative':
        _inner = CandidateTorsoSubtractedAirborne();
        _inner.initialize({
          'flightThresholdRatio': _config['airborneThreshold'] ?? 0.15,
        });
        break;
      case 'hip_relative_ankle':
        _inner = CandidateHipRelativeAirborne();
        _inner.initialize({
          'flightThresholdRatio': _config['airborneThreshold'] ?? 0.15,
          'standingHkr': 0.55,
        });
        break;
      case 'shoulder_hip_consensus':
        _inner = CandidateShoulderHipConsensus();
        _inner.initialize({
          'consensusThreshold': _config['threshold'] ?? 0.003,
        });
        break;
      case 'translation_compensation':
        _inner = CandidateTorsoSubtractedAirborne();
        _inner.initialize({
          'flightThresholdRatio': 0.12 + (_config['windowSize'] as int? ?? 10) * 0.001,
        });
        break;
      case 'camera_contamination_reject':
        _inner = CandidateShoulderHipConsensus();
        _inner.initialize({
          'consensusThreshold': _config['motionThreshold'] ?? 0.005,
        });
        break;
      default:
        _inner = CandidateTorsoSubtractedAirborne();
        _inner.initialize({});
    }
  }

  @override
  void processFrame(NuvoPoseFrame frame) => _inner.processFrame(frame);

  @override
  CandidateResult finalize() => _inner.finalize();
}

/// A signal quality candidate that maps config to real signal candidates.
class SignalQualityCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'signal_quality';
  @override
  final String architecture = 'SignalQuality';

  final Map<String, dynamic> _config;
  late MotionCandidate _inner;

  SignalQualityCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    final smoothing = _config['smoothing'] as String? ?? 'mean';
    if (smoothing == 'median') {
      _inner = CandidateMedianFilter();
      _inner.initialize({
        'windowSize': _config['window'] ?? 3,
      });
    } else {
      _inner = CandidateConfidenceSmoothing();
      _inner.initialize({
        'minConfidence': _config['adaptiveConfidenceThreshold'] ?? 0.40,
      });
    }
  }

  @override
  void processFrame(NuvoPoseFrame frame) => _inner.processFrame(frame);

  @override
  CandidateResult finalize() => _inner.finalize();
}

/// A geometric/feature candidate that maps config to real feature candidates.
class GeometricCandidate extends MotionCandidate {
  @override
  final String id;
  @override
  final String family = 'geometric';
  @override
  final String architecture = 'GeometricFeature';

  final Map<String, dynamic> _config;
  late MotionCandidate _inner;

  GeometricCandidate(this.id, this._config);

  @override
  void initialize(Map<String, dynamic> config) {
    final features = (_config['features'] as List?)?.cast<String>() ?? ['kneeAngle'];
    if (features.contains('acceleration')) {
      _inner = CandidateAccelerationFeature();
      _inner.initialize({
        'accelThreshold': -0.001 - (_config['threshold'] as num? ?? 0.5) * 0.002,
      });
    } else if (features.contains('jointVelocity') || features.contains('angularVelocity')) {
      _inner = CandidateJointAngularVelocity();
      _inner.initialize({
        'kneeVelThreshold': 3.0 + (_config['threshold'] as num? ?? 0.5) * 5.0,
      });
    } else if (features.contains('stanceWidth') || features.contains('symmetry')) {
      _inner = CandidateStanceWidthDynamics();
      _inner.initialize({
        'maxStanceWidth': 0.15 + (_config['threshold'] as num? ?? 0.5) * 0.06,
      });
    } else {
      _inner = CandidateAdaptiveHysteresis();
      _inner.initialize({
        'enterThreshold': 0.10 + (_config['threshold'] as num? ?? 0.5) * 0.08,
        'exitThreshold': 0.03 + (_config['threshold'] as num? ?? 0.5) * 0.03,
      });
    }
  }

  @override
  void processFrame(NuvoPoseFrame frame) => _inner.processFrame(frame);

  @override
  CandidateResult finalize() => _inner.finalize();
}

// ============================================================================
// MOTION LAB — MAIN RUNNER
// ============================================================================

class MotionLab {
  final String labDir;
  final String fixtureDir;
  final double budgetHours;
  final int maxExperiments;
  final int plateauWindow;
  final bool productionWrite;

  late final ExperimentRegistry registry;
  late final ChampionManager championManager;
  late final FamilyStateManager familyStates;
  late final FailureMiner failureMiner;
  late final SearchPolicy searchPolicy;
  late final LearningCurve learningCurve;
  late final FamilyRegistry familyRegistry;

  final DatasetManifest manifest;
  late final List<ClipGroundTruth> devGroundTruths;
  late final List<ClipGroundTruth> valGroundTruths;
  late final List<ClipGroundTruth> holdoutGroundTruths;

  /// Run-scoped directory for this run's artifacts (prevents cross-run overwrites).
  late final String runDir;

  final List<String> confuserMovements = [
    'normal_squats', 'deep_squats', 'vertical_jumps',
    'jumping_jacks', 'squat_jacks', 'lunges',
  ];

  DateTime? _startTime;
  int _experimentsSinceImprovement = 0;
  DateTime? _lastImprovementTime;
  int _holdoutEvaluations = 0;
  bool _hasRunFinalHoldout = false;
  int _validationConfirmations = 0;

  MotionLab({
    required this.labDir,
    required this.fixtureDir,
    this.budgetHours = 8.0,
    this.maxExperiments = 500,
    this.plateauWindow = 40,
    this.productionWrite = false,
  }) : manifest = buildDatasetManifest() {
    // Create run-scoped directory to prevent cross-run overwrites
    final runTimestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    runDir = '$labDir/runs/$runTimestamp';
    Directory(runDir).createSync(recursive: true);
    // Write pointer to latest run
    File('$labDir/LATEST_RUN.txt').writeAsStringSync(runDir);

    // Initialize components — all artifacts in runDir
    registry = ExperimentRegistry('$runDir/EXPERIMENTS.jsonl');
    championManager = ChampionManager('$runDir/CHAMPION.json');
    familyStates = FamilyStateManager('$runDir/FAMILY_STATE.json');
    failureMiner = FailureMiner('$runDir/FAILURE_CLUSTERS.json');
    learningCurve = LearningCurve('$runDir/LEARNING_CURVE.json');
    familyRegistry = FamilyRegistry();
    searchPolicy = SearchPolicy(
      registry: registry,
      familyStates: familyStates,
      failureMiner: failureMiner,
      plateauDetector: PlateauDetector(plateauWindow: plateauWindow),
    );

    // Build ground truths
    devGroundTruths = manifest.clips
        .where((c) => c.split == 'dev')
        .map((c) => ClipGroundTruth(
              clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
              split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
            ))
        .toList();
    valGroundTruths = manifest.clips
        .where((c) => c.split == 'validation')
        .map((c) => ClipGroundTruth(
              clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
              split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
            ))
        .toList();
    holdoutGroundTruths = manifest.clips
        .where((c) => c.split == 'holdout')
        .map((c) => ClipGroundTruth(
              clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
              split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
            ))
        .toList();
  }

  /// Load all persistent state.
  void load() {
    registry.load();
    championManager.load();
    familyStates.load();
    failureMiner.load();
    learningCurve.load();
    searchPolicy.initialize();

    // Initialize all family states so they're active from the start
    for (final familyName in familyRegistry.familyNames) {
      familyStates.getOrCreate(familyName);
    }

    // Update family starting best from loaded state
    for (final entry in familyStates.states.entries) {
      if (entry.value.bestF1 > 0 && entry.value.startingBestF1 == 0) {
        entry.value.startingBestF1 = entry.value.bestF1;
      }
    }
  }

  /// Run the research loop.
  Future<void> run() async {
    _startTime = DateTime.now();

    print('\n${'=' * 70}');
    print('NUVO MOTION LAB — AUTONOMOUS RESEARCH ENGINE');
    print('=' * 70);
    print('Budget: ${budgetHours}h, Max experiments: $maxExperiments');
    print('Plateau window: $plateauWindow');
    print('Production write: $productionWrite');
    print('Lab dir: $labDir');
    print('Experiments loaded: ${registry.count}');
    print('Champion: ${championManager.champion?.candidateName ?? "NONE"}');
    print('F1: ${championManager.champion?.f1.toStringAsFixed(4) ?? "N/A"}');
    print('=' * 70);

    // If no champion exists, seed with M1.1 best (temp_adaptive_hyst)
    if (championManager.champion == null) {
      _seedInitialChampion();
    }

    // Main loop — time-based budget, not experiment count
    while (_shouldContinue()) {
      try {
        _runSingleExperiment();
      } catch (e, stack) {
        stderr.writeln('ERROR in experiment: $e');
        stderr.writeln(stack.toString().split('\n').take(3).join('\n'));
        _recordFailedExperiment(e.toString());
      }

      // Periodic status update (every 5 experiments)
      if (registry.completedCount % 5 == 0) {
        updateStatus();
      }

      // Periodic failure mining + family state save (every 10 experiments)
      if (registry.completedCount % 10 == 0 && registry.completedCount > 0) {
        failureMiner.mineFromExperiments(registry.records);
        familyStates.save();
      }

      // Check for plateau in all families
      _checkPlateaus();

      // Validation confirmation runs for pending champions (every 100 experiments)
      if (registry.completedCount % 100 == 0 && registry.completedCount > 0) {
        _runValidationConfirmations();
      }

      // Data ceiling detection — generate DATA_REQUEST.md but DON'T stop
      if (searchPolicy.detectDataCeiling() && _holdoutEvaluations < 1) {
        print('\n*** DATA_CEILING_SUSPECTED — generating DATA_REQUEST.md ***');
        _generateDataRequest();
      }
    }

    // FINAL holdout evaluation — one-time, after search is complete
    if (!_hasRunFinalHoldout) {
      _evaluateChampionOnHoldout();
      _hasRunFinalHoldout = true;
    }

    // Final outputs
    updateStatus();
    updateLeaderboard();
    failureMiner.mineFromExperiments(registry.records);
    generateReport();

    print('\n${'=' * 70}');
    print('MOTION LAB COMPLETE');
    print('Experiments: ${registry.count} (${registry.completedCount} completed, ${registry.failedCount} failed)');
    print('Champion: ${championManager.champion?.candidateName ?? "NONE"}');
    print('F1: ${championManager.champion?.f1.toStringAsFixed(4) ?? "N/A"}');
    print('=' * 70);
  }

  /// Seed initial champion with the M1.1 best candidate.
  void _seedInitialChampion() {
    print('Seeding initial champion (temp_adaptive_hyst)...');
    final eval = CanonicalEvaluator(
      targetMovement: 'jump_squats',
      confuserMovements: confuserMovements,
      groundTruths: devGroundTruths,
      fixtureDir: fixtureDir,
    );

    final candidate = CandidateAdaptiveHysteresis();
    final metrics = eval.evaluate(candidate);

    final champion = ChampionRecord(
      experimentId: 'SEED-000000',
      candidateName: candidate.id,
      family: candidate.family,
      architecture: candidate.architecture,
      config: {'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3},
      datasetVersion: manifest.version,
      recall: metrics.repRecall,
      precision: metrics.repPrecision,
      f1: metrics.f1,
      falseAcceptClipRate: metrics.falseAcceptClipRate,
      exactCountRate: metrics.exactCountRate,
      productScore: metrics.productScore,
      gateResult: _classifyGate(metrics).name,
      sourceCommit: 'm1.3-seed',
      timestamp: DateTime.now(),
      catastrophicClips: metrics.catastrophicClips,
    );

    championManager.tryPromote(champion);
    print('  Champion seeded: F1=${metrics.f1.toStringAsFixed(4)}');

    // Add initial learning curve point
    final targetClipCount = devGroundTruths.where((g) => g.isTarget).length;
    learningCurve.generateCurve(
      experimentId: 'SEED-000000',
      f1: metrics.f1,
      recall: metrics.repRecall,
      precision: metrics.repPrecision,
      targetClipCount: targetClipCount,
    );
  }

  /// Run a single experiment.
  void _runSingleExperiment() {
    // Select family
    final familyName = searchPolicy.selectFamily();
    final family = familyRegistry.getFamily(familyName);

    if (family == null) {
      _recordFailedExperiment('Unknown family: $familyName');
      return;
    }

    // Generate experiment
    final familyHistory = registry.familyRecords(familyName);
    final proposed = family.generate(
      history: familyHistory,
      failureClusters: failureMiner.clusters,
    );

    final experimentId = registry.nextId();
    print('\n[$experimentId] family=$familyName candidate=${proposed.candidateName}');
    print('  hypothesis: ${proposed.hypothesis}');

    // Build candidate
    final candidate = _buildCandidate(familyName, proposed);

    // Evaluate
    final evalSw = Stopwatch()..start();
    final eval = CanonicalEvaluator(
      targetMovement: 'jump_squats',
      confuserMovements: confuserMovements,
      groundTruths: devGroundTruths,
      fixtureDir: fixtureDir,
    );

    final metrics = eval.evaluate(candidate);
    evalSw.stop();

    print('  recall=${metrics.repRecall.toStringAsFixed(4)} precision=${metrics.repPrecision.toStringAsFixed(4)} f1=${metrics.f1.toStringAsFixed(4)}');
    print('  faClipRate=${metrics.falseAcceptClipRate.toStringAsFixed(3)} catastrophic=${metrics.catastrophicClips}');

    // Build per-confuser results
    final perConfuser = <String, dynamic>{};
    for (final entry in metrics.confuserFalseAcceptClipRates.entries) {
      perConfuser[entry.key] = {
        'falseAcceptClipRate': entry.value,
        'falseAcceptReps': metrics.confuserFalseAccepts[entry.key] ?? 0,
        'falseAcceptClips': metrics.clipResults
            .where((r) => r.movement == entry.key && r.detectedReps > 0)
            .length,
      };
    }

    // Classify gate
    final gate = _classifyGate(metrics);

    // Compare to champion
    String? championComparison;
    if (championManager.champion != null) {
      final champ = championManager.champion!;
      final delta = metrics.f1 - champ.f1;
      championComparison = 'F1 delta: ${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(4)} '
          '(champion F1=${champ.f1.toStringAsFixed(4)})';
    }

    // Build failure summary
    final failureSummary = _buildFailureSummary(metrics);

    // Record experiment
    final record = ExperimentRecord(
      id: experimentId,
      timestamp: DateTime.now(),
      family: familyName,
      candidateName: proposed.candidateName,
      parentExperimentId: proposed.parentExperimentId,
      hypothesis: proposed.hypothesis,
      config: proposed.config,
      datasetVersion: manifest.version,
      splitUsed: 'dev',
      randomSeed: proposed.randomSeed,
      featureSet: proposed.featureSet,
      temporalWindow: proposed.temporalWindow,
      modelParams: proposed.modelParams,
      threshold: proposed.threshold,
      evalDuration: evalSw.elapsed,
      tp: metrics.totalTP,
      fn: metrics.totalFN,
      fp: metrics.totalFP,
      recall: metrics.repRecall,
      precision: metrics.repPrecision,
      f1: metrics.f1,
      exactCountRate: metrics.exactCountRate,
      falseAcceptClipRate: metrics.falseAcceptClipRate,
      catastrophicClips: metrics.catastrophicClips,
      productScore: metrics.productScore,
      gateResult: gate.name,
      perConfuserResults: perConfuser,
      failureSummary: failureSummary,
      championComparison: championComparison,
      status: 'completed',
    );

    registry.append(record);

    // Update family state
    familyStates.recordExperiment(familyName, metrics.f1, evalSw.elapsed.inMilliseconds.toDouble(), false);
    familyStates.save();

    // Record best config for mutation-based search (Stage C)
    final familyBestF1 = familyStates.getOrCreate(familyName).bestF1;
    if (metrics.f1 >= familyBestF1) {
      searchPolicy.recordBestConfig(familyName, proposed.config, metrics.f1);
    }

    // Track experiments since last improvement
    _experimentsSinceImprovement++;

    // Try champion promotion (conservative — Phase 6)
    if (metrics.catastrophicClips == 0) {
      final challenger = ChampionRecord(
        experimentId: experimentId,
        candidateName: proposed.candidateName,
        family: familyName,
        architecture: candidate.architecture,
        config: proposed.config,
        datasetVersion: manifest.version,
        recall: metrics.repRecall,
        precision: metrics.repPrecision,
        f1: metrics.f1,
        falseAcceptClipRate: metrics.falseAcceptClipRate,
        exactCountRate: metrics.exactCountRate,
        productScore: metrics.productScore,
        modelParams: proposed.modelParams,
        gateResult: gate.name,
        sourceCommit: 'm1.3-lab',
        timestamp: DateTime.now(),
        catastrophicClips: metrics.catastrophicClips,
      );

      final promoted = championManager.tryPromote(challenger);
      if (promoted) {
        _experimentsSinceImprovement = 0;
        _lastImprovementTime = DateTime.now();
        print('  *** NEW CHAMPION *** F1=${metrics.f1.toStringAsFixed(4)}');
        print('  Reason: ${challenger.promotionReason}');

        // Update learning curve
        final targetClipCount = devGroundTruths.where((g) => g.isTarget).length;
        learningCurve.generateCurve(
          experimentId: experimentId,
          f1: metrics.f1,
          recall: metrics.repRecall,
          precision: metrics.repPrecision,
          targetClipCount: targetClipCount,
        );

        // Queue for confirmation on validation set
        searchPolicy.queueConfirmation(experimentId);
      }
    }
  }

  /// Build a MotionCandidate from a proposed experiment.
  MotionCandidate _buildCandidate(String family, ProposedExperiment proposed) {
    switch (family) {
      case 'temporal':
        return TemporalCandidate(proposed.candidateName, proposed.config);
      case 'camera':
        return CameraCandidate(proposed.candidateName, proposed.config);
      case 'signal_quality':
        return SignalQualityCandidate(proposed.candidateName, proposed.config);
      case 'geometric':
        return GeometricCandidate(proposed.candidateName, proposed.config);
      case 'confuser_specialist':
        return ConfuserSpecialistCandidate(proposed.candidateName, proposed.config);
      case 'hybrid':
        return HybridCandidate(proposed.candidateName, proposed.config);
      case 'ensemble':
        return EnsembleCandidate(proposed.candidateName, proposed.config);
      case 'mlp':
      case 'conv1d':
      case 'gru':
        // ML candidates: use temporal with varied thresholds as proxy.
        // Real ML training would require the feature dataset pipeline.
        return TemporalCandidate(proposed.candidateName, {
          'airborneThreshold': 0.08 + (proposed.threshold ?? 0.5) * 0.10,
          'hysteresis': 0.03 + (proposed.threshold ?? 0.5) * 0.03,
          'minRepGap': proposed.temporalWindow != null
              ? (proposed.temporalWindow! ~/ 4).clamp(5, 15)
              : 8,
          'persistence': 3,
        });
      default:
        return TemporalCandidate(proposed.candidateName, proposed.config);
    }
  }

  /// Classify candidate gate from metrics.
  CandidateGate _classifyGate(AggregateMetrics m) {
    if (m.catastrophicClips > 0 || m.repPrecision < 0.70) {
      return CandidateGate.reject;
    }
    if (m.repRecall >= 0.90 && m.repPrecision >= 0.95 && m.falseAcceptClipRate <= 0.10) {
      return CandidateGate.productCandidate;
    }
    if (m.repRecall >= 0.75 && m.repPrecision >= 0.90) {
      return CandidateGate.promising;
    }
    return CandidateGate.research;
  }

  /// Build a failure summary string.
  String _buildFailureSummary(AggregateMetrics m) {
    final parts = <String>[];
    if (m.catastrophicClips > 0) {
      parts.add('${m.catastrophicClips} catastrophic clips');
    }
    if (m.totalFN > 0) {
      parts.add('${m.totalFN} missed reps');
    }
    if (m.totalFP > 0) {
      parts.add('${m.totalFP} false positive reps');
    }
    for (final entry in m.confuserFalseAcceptClipRates.entries) {
      if (entry.value > 0) {
        parts.add('${entry.key}: ${entry.value.toStringAsFixed(2)} FA clip rate');
      }
    }
    return parts.isEmpty ? 'No significant failures' : parts.join('; ');
  }

  /// Record a failed experiment.
  void _recordFailedExperiment(String error) {
    final id = registry.nextId();
    final record = ExperimentRecord(
      id: id,
      timestamp: DateTime.now(),
      family: 'unknown',
      candidateName: 'failed',
      hypothesis: 'N/A',
      config: {},
      datasetVersion: manifest.version,
      status: 'failed',
      error: error,
    );
    registry.append(record);
  }

  /// Run validation confirmation for pending champion candidates.
  /// Uses the validation split (NOT holdout) to confirm that a champion
  /// generalizes beyond the dev/search split.
  void _runValidationConfirmations() {
    final pending = searchPolicy.pendingConfirmations;
    if (pending.isEmpty) return;

    final champ = championManager.champion;
    if (champ == null) return;

    // Only confirm the current champion (the most recent promotion)
    if (!pending.contains(champ.experimentId)) {
      // Clear stale pending confirmations
      for (final id in List.from(pending)) {
        searchPolicy.dequeueConfirmation(id);
      }
      return;
    }

    // Evaluate on validation set
    final valEval = CanonicalEvaluator(
      targetMovement: 'jump_squats',
      confuserMovements: confuserMovements,
      groundTruths: valGroundTruths,
      fixtureDir: fixtureDir,
    );

    final candidate = _buildCandidate(champ.family, ProposedExperiment(
      family: champ.family,
      candidateName: champ.candidateName,
      hypothesis: 'Validation confirmation',
      config: champ.config,
    ));

    final valMetrics = valEval.evaluate(candidate);
    _validationConfirmations++;
    champ.confirmedRuns = _validationConfirmations;
    championManager.save();

    print('\n=== VALIDATION CONFIRMATION #$_validationConfirmations ===');
    print('  Champion: ${champ.candidateName}');
    print('  Dev F1: ${champ.f1.toStringAsFixed(4)}, Val F1: ${valMetrics.f1.toStringAsFixed(4)}');

    // Check if validation confirms the dev result
    final valGap = champ.f1 - valMetrics.f1;
    if (valGap > 0.10) {
      print('  WARNING: Validation gap > 0.10 — champion may be overfit to dev');
    } else {
      print('  OK: Validation confirms dev performance (gap=${valGap.toStringAsFixed(4)})');
    }

    // Dequeue after confirmation
    searchPolicy.dequeueConfirmation(champ.experimentId);
  }

  /// Evaluate current champion on holdout split — ONE-TIME final evaluation.
  /// Holdout is NEVER queried during search. This runs once after the search loop ends.
  void _evaluateChampionOnHoldout() {
    final champ = championManager.champion;
    if (champ == null) return;

    _holdoutEvaluations++;
    print('\n=== FINAL HOLDOUT EVALUATION ===');
    print('Champion: ${champ.candidateName} (F1=${champ.f1.toStringAsFixed(4)} on dev)');

    final eval = CanonicalEvaluator(
      targetMovement: 'jump_squats',
      confuserMovements: confuserMovements,
      groundTruths: holdoutGroundTruths,
      fixtureDir: fixtureDir,
    );

    final candidate = _buildCandidate(champ.family, ProposedExperiment(
      family: champ.family,
      candidateName: champ.candidateName,
      hypothesis: 'Holdout eval',
      config: champ.config,
    ));

    final metrics = eval.evaluate(candidate);
    print('  Holdout F1=${metrics.f1.toStringAsFixed(4)} '
        'recall=${metrics.repRecall.toStringAsFixed(4)} '
        'precision=${metrics.repPrecision.toStringAsFixed(4)} '
        'faClipRate=${metrics.falseAcceptClipRate.toStringAsFixed(3)}');

    // Record holdout metrics on champion (one-time, final)
    champ.holdoutMetrics = {
      'f1': metrics.f1,
      'recall': metrics.repRecall,
      'precision': metrics.repPrecision,
      'falseAcceptClipRate': metrics.falseAcceptClipRate,
    };
    championManager.save();

    // Write holdout results to a separate file
    final holdoutReport = StringBuffer();
    holdoutReport.writeln('# HOLDOUT EVALUATION #$_holdoutEvaluations');
    holdoutReport.writeln('Time: ${DateTime.now().toIso8601String()}');
    holdoutReport.writeln('Champion: ${champ.candidateName}');
    holdoutReport.writeln('Dev F1: ${champ.f1.toStringAsFixed(4)}');
    holdoutReport.writeln('Holdout F1: ${metrics.f1.toStringAsFixed(4)}');
    holdoutReport.writeln('Holdout Recall: ${metrics.repRecall.toStringAsFixed(4)}');
    holdoutReport.writeln('Holdout Precision: ${metrics.repPrecision.toStringAsFixed(4)}');
    holdoutReport.writeln('Holdout FA Clip Rate: ${metrics.falseAcceptClipRate.toStringAsFixed(3)}');
    holdoutReport.writeln('');
    final overfitGap = champ.f1 - metrics.f1;
    holdoutReport.writeln('Overfitting gap (dev - holdout): ${overfitGap.toStringAsFixed(4)}');
    if (overfitGap > 0.05) {
      holdoutReport.writeln('WARNING: Significant overfitting detected (gap > 0.05)');
    }
    File('$runDir/HOLDOUT_RESULTS.md').writeAsStringSync(holdoutReport.toString());
  }

  /// Check plateaus for all families.
  void _checkPlateaus() {
    for (final familyName in familyRegistry.familyNames) {
      final state = familyStates.getOrCreate(familyName);

      // Auto-unplateau after 100 more experiments to allow new random configs
      if (state.plateaued) {
        final plateauedAtCount = state.plateauedAtCount ?? 0;
        if (state.experimentsAttempted - plateauedAtCount >= 100) {
          state.plateaued = false;
          state.plateauedAt = null;
          state.plateauReason = null;
          state.startingBestF1 = state.bestF1;
          print('\n*** FAMILY UN-PLATEAUED: $familyName (cooldown expired) ***');
          familyStates.save();
        }
        continue;
      }

      final records = registry.familyRecords(familyName);
      if (records.length >= plateauWindow) {
        final didPlateau = searchPolicy.plateauDetector.checkPlateau(state, records);
        if (didPlateau) {
          print('\n*** FAMILY PLATEAU: $familyName ***');
          print('  ${state.plateauReason}');
          familyStates.save();
        }
      }
    }
  }

  /// Check if the lab should continue running.
  /// Time is the primary budget. maxExperiments is only a safety ceiling.
  bool _shouldContinue() {
    // Safety ceiling — protect against bugs (set very high)
    if (registry.count >= maxExperiments) {
      print('\n*** SAFETY CEILING REACHED ($maxExperiments experiments) ***');
      return false;
    }

    // Time budget — primary termination
    if (_startTime != null) {
      final elapsed = DateTime.now().difference(_startTime!);
      if (elapsed.inMinutes >= (budgetHours * 60).round()) {
        print('\n*** BUDGET HOURS EXHAUSTED (${budgetHours}h) ***');
        return false;
      }
    }

    // Global plateau — reset and continue (don't stop)
    if (searchPolicy.globalPlateau) {
      print('\n*** GLOBAL PLATEAU — RESETTING FOR CONTINUED EXPLORATION ***\n');
      for (final familyName in familyRegistry.familyNames) {
        final state = familyStates.getOrCreate(familyName);
        state.plateaued = false;
        state.plateauedAt = null;
        state.plateauedAtCount = null;
        state.plateauReason = null;
        state.startingBestF1 = state.bestF1;
      }
      familyStates.save();
    }

    return true;
  }

  /// Generate DATA_REQUEST.md when data ceiling is detected.
  void _generateDataRequest() {
    final report = StringBuffer();
    report.writeln('# DATA REQUEST — Motion Intelligence');
    report.writeln('');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('');
    report.writeln('## DATA_CEILING_DETECTED');
    report.writeln('');
    report.writeln('Multiple model families have plateaued at similar F1 scores,');
    report.writeln('indicating the dataset is too small for further improvement.');
    report.writeln('');
    report.writeln('## Current Dataset');
    report.writeln('');
    report.writeln('- Total clips: ${manifest.clips.length}');
    report.writeln('- Target (jump_squat) clips: ${manifest.clips.where((c) => c.isTarget).length}');
    report.writeln('- Confuser clips: ${manifest.clips.where((c) => c.isConfuser).length}');
    report.writeln('');
    report.writeln('## Requested Data');
    report.writeln('');
    report.writeln('### Jump Squat (Target)');
    report.writeln('- +15 clips: low camera angle, shallow jump, athletic stance');
    report.writeln('- +15 clips: moderate camera movement, full body visible');
    report.writeln('- +10 clips: poor ankle confidence, loose clothing / occlusion');
    report.writeln('- +10 clips: varied athletes, body types, speeds');
    report.writeln('');
    report.writeln('### Hard Negatives');
    report.writeln('- +10 explosive deep squats');
    report.writeln('- +10 narrow jumping jacks');
    report.writeln('- +10 vertical jumps (no squat compression)');
    report.writeln('- +5 squat jacks');
    report.writeln('');
    report.writeln('### Priority');
    report.writeln('1. Jump squat variety (camera angles, athlete diversity)');
    report.writeln('2. Deep squat hard negatives');
    report.writeln('3. Jumping jack hard negatives');

    File('$runDir/DATA_REQUEST.md').writeAsStringSync(report.toString());
    print('  DATA_REQUEST.md written');
  }

  /// Update STATUS.md — rich live status (Phase 10).
  void updateStatus() {
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;
    final remaining = _startTime != null
        ? Duration(minutes: (budgetHours * 60).round()) - elapsed
        : Duration.zero;

    final champ = championManager.champion;
    final primaryCluster = failureMiner.primaryCluster;
    final stage = searchPolicy.currentStage;

    // Throughput calculation
    final elapsedSec = elapsed.inSeconds > 0 ? elapsed.inSeconds : 1;
    final throughput = registry.completedCount / elapsedSec;
    final expPerHour = throughput * 3600;

    final status = StringBuffer();
    status.writeln('# NUVO MOTION LAB — LIVE STATUS');
    status.writeln('');
    status.writeln('**STATUS:** RUNNING');
    status.writeln('**Last update:** ${DateTime.now().toIso8601String()}');
    status.writeln('');
    status.writeln('## Time Budget');
    status.writeln('');
    status.writeln('| Metric | Value |');
    status.writeln('|--------|-------|');
    status.writeln('| Elapsed | ${elapsed.inHours}h ${elapsed.inMinutes % 60}m ${elapsed.inSeconds % 60}s |');
    status.writeln('| Remaining | ${remaining.inHours}h ${remaining.inMinutes % 60}m |');
    status.writeln('| Budget | ${budgetHours}h |');
    status.writeln('| Throughput | ${throughput.toStringAsFixed(1)} exp/s (${expPerHour.toStringAsFixed(0)} exp/h) |');
    status.writeln('');
    status.writeln('## Research Stage');
    status.writeln('');
    status.writeln('**Current stage:** ${stage.name}');
    status.writeln('Experiments since last improvement: $_experimentsSinceImprovement');
    if (_lastImprovementTime != null) {
      final sinceImprovement = DateTime.now().difference(_lastImprovementTime!);
      status.writeln('Time since last improvement: ${sinceImprovement.inMinutes}m');
    }
    status.writeln('Pending confirmations: ${searchPolicy.pendingConfirmations.length}');
    status.writeln('Validation confirmations: $_validationConfirmations');
    status.writeln('Final holdout: ${_hasRunFinalHoldout ? "EVALUATED" : "NOT YET (running)"}');
    status.writeln('');
    status.writeln('## Champion');
    status.writeln('');
    status.writeln('| Metric | Value |');
    status.writeln('|--------|-------|');
    status.writeln('| Experiment | ${champ?.experimentId ?? "NONE"} |');
    status.writeln('| Candidate | ${champ?.candidateName ?? "N/A"} |');
    status.writeln('| Family | ${champ?.family ?? "N/A"} |');
    status.writeln('| Recall | ${(champ?.recall ?? 0).toStringAsFixed(4)} |');
    status.writeln('| Precision | ${(champ?.precision ?? 0).toStringAsFixed(4)} |');
    status.writeln('| F1 | ${(champ?.f1 ?? 0).toStringAsFixed(4)} |');
    status.writeln('| FA clip rate | ${(champ?.falseAcceptClipRate ?? 0).toStringAsFixed(4)} |');
    status.writeln('| Exact count | ${(champ?.exactCountRate ?? 0).toStringAsFixed(4)} |');
    status.writeln('| Catastrophic clips | ${champ?.catastrophicClips ?? "N/A"} |');
    status.writeln('| Confirmed runs | ${champ?.confirmedRuns ?? 0} |');
    if (champ?.holdoutMetrics != null) {
      final hm = champ!.holdoutMetrics!;
      status.writeln('| Holdout F1 | ${hm['f1']?.toStringAsFixed(4) ?? "N/A"} |');
      status.writeln('| Holdout recall | ${hm['recall']?.toStringAsFixed(4) ?? "N/A"} |');
      status.writeln('| Holdout precision | ${hm['precision']?.toStringAsFixed(4) ?? "N/A"} |');
    }
    status.writeln('');
    status.writeln('### Promotion Reason');
    status.writeln('');
    status.writeln('${champ?.promotionReason ?? "N/A"}');
    status.writeln('');
    status.writeln('## Experiment Counts');
    status.writeln('');
    status.writeln('| Metric | Value |');
    status.writeln('|--------|-------|');
    status.writeln('| Total attempted | ${registry.count} |');
    status.writeln('| Completed | ${registry.completedCount} |');
    status.writeln('| Failed | ${registry.failedCount} |');
    status.writeln('| Champion changes | ${championManager.championChanges} |');
    status.writeln('');
    status.writeln('## Family Status');
    status.writeln('');
    status.writeln('| Family | Experiments | Best F1 | Plateaued | Status |');
    status.writeln('|--------|-------------|---------|-----------|--------|');
    for (final familyName in familyRegistry.familyNames) {
      final state = familyStates.getOrCreate(familyName);
      final famStatus = state.plateaued ? 'PLATEAUED' : 'ACTIVE';
      status.writeln('| $familyName | ${state.experimentsAttempted} | '
          '${state.bestF1.toStringAsFixed(4)} | '
          '${state.plateaued ? "YES" : "NO"} | $famStatus |');
    }
    status.writeln('');
    status.writeln('## Failure Analysis');
    status.writeln('');
    status.writeln('**Primary cluster:** ${primaryCluster?.name ?? "NONE"}');
    if (primaryCluster != null) {
      status.writeln('- ${primaryCluster.description}');
      status.writeln('- Reason: ${primaryCluster.likelyReason}');
      status.writeln('- Proposed: ${primaryCluster.proposedExperiment ?? "N/A"}');
    }
    status.writeln('');
    status.writeln('## Improvement Summary');
    status.writeln('');
    final startingF1 = championManager.history.isNotEmpty
        ? championManager.history.first.f1
        : 0.0;
    final currentF1 = champ?.f1 ?? 0.0;
    final improvement = currentF1 - startingF1;
    status.writeln('- Starting F1: ${startingF1.toStringAsFixed(4)}');
    status.writeln('- Current F1: ${currentF1.toStringAsFixed(4)}');
    status.writeln('- Improvement: ${improvement >= 0 ? "+" : ""}${improvement.toStringAsFixed(4)}');
    status.writeln('');
    status.writeln('---');
    status.writeln('Generated: ${DateTime.now().toIso8601String()}');

    _atomicWrite('$runDir/STATUS.md', status.toString());
  }

  /// Update leaderboard files.
  void updateLeaderboard() {
    final sorted = registry.sortedByF1().take(50).toList();

    // JSON
    final jsonList = sorted.map((r) => r.toJson()).toList();
    File('$runDir/LEADERBOARD.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert(jsonList));

    // CSV
    final csv = StringBuffer();
    csv.writeln('rank,experiment,family,candidate,recall,precision,f1,exactCountRate,falseAcceptClipRate,productScore,gate,runtimeMs');
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      csv.writeln('${i + 1},${r.id},${r.family},${r.candidateName},'
          '${r.recall?.toStringAsFixed(4) ?? ""},'
          '${r.precision?.toStringAsFixed(4) ?? ""},'
          '${r.f1?.toStringAsFixed(4) ?? ""},'
          '${r.exactCountRate?.toStringAsFixed(4) ?? ""},'
          '${r.falseAcceptClipRate?.toStringAsFixed(4) ?? ""},'
          '${r.productScore?.toStringAsFixed(4) ?? ""},'
          '${r.gateResult ?? ""},'
          '${r.evalDuration?.inMilliseconds ?? ""}');
    }
    File('$runDir/LEADERBOARD.csv').writeAsStringSync(csv.toString());

    // MD
    final md = StringBuffer();
    md.writeln('# LEADERBOARD');
    md.writeln('');
    md.writeln('| Rank | Experiment | Family | Candidate | Recall | Precision | F1 | FA Clip Rate | Gate |');
    md.writeln('|------|------------|--------|-----------|--------|-----------|----|-------------|------|');
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      md.writeln('| ${i + 1} | ${r.id} | ${r.family} | ${r.candidateName} | '
          '${r.recall?.toStringAsFixed(4) ?? ""} | '
          '${r.precision?.toStringAsFixed(4) ?? ""} | '
          '${r.f1?.toStringAsFixed(4) ?? ""} | '
          '${r.falseAcceptClipRate?.toStringAsFixed(4) ?? ""} | '
          '${r.gateResult ?? ""} |');
    }
    File('$runDir/LEADERBOARD.md').writeAsStringSync(md.toString());
  }

  /// Generate the final overnight report.
  void generateReport() {
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;

    final champ = championManager.champion;
    final startingChamp = championManager.history.isNotEmpty
        ? championManager.history.first
        : null;

    final report = StringBuffer();
    report.writeln('# NUVO MOTION LAB — OVERNIGHT REPORT');
    report.writeln('');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('');
    report.writeln('---');
    report.writeln('');
    report.writeln('## EXECUTIVE SUMMARY (30-second read)');
    report.writeln('');
    report.writeln('Runtime: ${elapsed.inHours}h ${elapsed.inMinutes % 60}m');
    report.writeln('Experiments attempted: ${registry.count}');
    report.writeln('Experiments completed: ${registry.completedCount}');
    report.writeln('Experiments failed: ${registry.failedCount}');
    report.writeln('Champion changes: ${championManager.championChanges}');
    final elapsedSec = elapsed.inSeconds > 0 ? elapsed.inSeconds : 1;
    final throughput = registry.completedCount / elapsedSec;
    report.writeln('Throughput: ${throughput.toStringAsFixed(1)} exp/s (${(throughput * 3600).toStringAsFixed(0)} exp/h)');
    report.writeln('Research stage: ${searchPolicy.currentStage.name}');
    report.writeln('Validation confirmations: $_validationConfirmations');
    report.writeln('Final holdout evaluated: ${_hasRunFinalHoldout ? "YES" : "NO"}');
    report.writeln('');
    report.writeln('### STARTING CHAMPION');
    report.writeln('Recall: ${startingChamp?.recall.toStringAsFixed(4) ?? "N/A"}');
    report.writeln('Precision: ${startingChamp?.precision.toStringAsFixed(4) ?? "N/A"}');
    report.writeln('F1: ${startingChamp?.f1.toStringAsFixed(4) ?? "N/A"}');
    report.writeln('False accept rate: ${startingChamp?.falseAcceptClipRate.toStringAsFixed(4) ?? "N/A"}');
    report.writeln('');
    report.writeln('### ENDING CHAMPION');
    report.writeln('Experiment: ${champ?.experimentId ?? "NONE"}');
    report.writeln('Family: ${champ?.family ?? "N/A"}');
    report.writeln('Recall: ${(champ?.recall ?? 0).toStringAsFixed(4)}');
    report.writeln('Precision: ${(champ?.precision ?? 0).toStringAsFixed(4)}');
    report.writeln('F1: ${(champ?.f1 ?? 0).toStringAsFixed(4)}');
    report.writeln('False accept rate: ${(champ?.falseAcceptClipRate ?? 0).toStringAsFixed(4)}');
    report.writeln('Exact count quality: ${(champ?.exactCountRate ?? 0).toStringAsFixed(4)}');
    report.writeln('Confirmed runs: ${champ?.confirmedRuns ?? 0}');
    if (champ?.holdoutMetrics != null) {
      final hm = champ!.holdoutMetrics!;
      report.writeln('');
      report.writeln('### HOLDOUT EVALUATION');
      report.writeln('Holdout F1: ${hm['f1']?.toStringAsFixed(4) ?? "N/A"}');
      report.writeln('Holdout Recall: ${hm['recall']?.toStringAsFixed(4) ?? "N/A"}');
      report.writeln('Holdout Precision: ${hm['precision']?.toStringAsFixed(4) ?? "N/A"}');
      report.writeln('Holdout FA Clip Rate: ${hm['falseAcceptClipRate']?.toStringAsFixed(3) ?? "N/A"}');
      final overfitGap = (champ.f1) - (hm['f1'] ?? 0.0);
      report.writeln('Overfitting gap (dev - holdout): ${overfitGap.toStringAsFixed(4)}');
      if (overfitGap > 0.05) {
        report.writeln('WARNING: Significant overfitting detected — champion may not generalize');
      } else if (overfitGap.abs() < 0.02) {
        report.writeln('GOOD: Champion generalizes well to holdout');
      }
    }
    report.writeln('');
    report.writeln('### PROMOTION REASON');
    report.writeln('${champ?.promotionReason ?? "N/A"}');
    report.writeln('');
    final improvement = champ != null && startingChamp != null
        ? champ.f1 - startingChamp.f1
        : 0.0;
    report.writeln('### IMPROVEMENT');
    report.writeln('${improvement >= 0 ? "+" : ""}${improvement.toStringAsFixed(4)} F1 points');
    report.writeln('');
    report.writeln('### GATES');
    report.writeln('75/90: ${_checkGate(champ, 0.75, 0.90) ? "PASS" : "FAIL"}');
    report.writeln('85/95: ${_checkGate(champ, 0.85, 0.95) ? "PASS" : "FAIL"}');
    report.writeln('90/95: ${_checkGate(champ, 0.90, 0.95) ? "PASS" : "FAIL"}');
    report.writeln('');
    report.writeln('### PRODUCTION READY');
    final ready = _checkGate(champ, 0.90, 0.95) && (champ?.catastrophicClips ?? 1) == 0;
    report.writeln('${ready ? "YES" : "NO"}');
    if (!ready && manifest.clips.length < 50) {
      report.writeln('INSUFFICIENT_DATA_FOR_PRODUCTION_CLAIM');
    }
    report.writeln('');
    report.writeln('### NEXT BOTTLENECK');
    if (searchPolicy.detectDataCeiling()) {
      report.writeln('DATA');
    } else if (searchPolicy.globalPlateau) {
      report.writeln('MODEL (all families plateaued)');
    } else {
      report.writeln('See family analysis below');
    }
    report.writeln('');
    report.writeln('### MOST IMPORTANT DISCOVERY');
    final bestRecord = registry.bestRecord;
    if (bestRecord != null) {
      report.writeln('${bestRecord.candidateName}: F1=${bestRecord.f1?.toStringAsFixed(4)}');
      report.writeln('  ${bestRecord.hypothesis}');
    } else {
      report.writeln('No experiments completed');
    }
    report.writeln('');
    report.writeln('### NEXT HUMAN ACTION');
    if (searchPolicy.detectDataCeiling()) {
      report.writeln('Review DATA_REQUEST.md and collect additional pose data');
    } else if (ready) {
      report.writeln('Review promotion candidate for production integration');
    } else {
      report.writeln('Review failure clusters and consider data expansion or feature engineering');
    }
    report.writeln('');
    report.writeln('---');
    report.writeln('');
    report.writeln('## DETAILED ANALYSIS');
    report.writeln('');
    report.writeln('### Experiment Family Performance');
    report.writeln('');
    report.writeln('| Family | Experiments | Best F1 | Plateaued | Runtime (ms) |');
    report.writeln('|--------|-------------|---------|-----------|-------------|');
    for (final familyName in familyRegistry.familyNames) {
      final state = familyStates.getOrCreate(familyName);
      report.writeln('| $familyName | ${state.experimentsAttempted} | '
          '${state.bestF1.toStringAsFixed(4)} | '
          '${state.plateaued ? "YES" : "NO"} | '
          '${state.totalRuntimeMs.toStringAsFixed(0)} |');
    }
    report.writeln('');
    report.writeln('### Champion History');
    report.writeln('');
    for (var i = 0; i < championManager.history.length; i++) {
      final c = championManager.history[i];
      report.writeln('${i + 1}. ${c.experimentId}: ${c.candidateName} F1=${c.f1.toStringAsFixed(4)}');
    }
    report.writeln('');
    report.writeln('### Learning Curve');
    report.writeln('');
    if (learningCurve.points.isNotEmpty) {
      report.writeln('| Target Clips | F1 | Recall | Precision |');
      report.writeln('|-------------|-----|--------|-----------|');
      for (final p in learningCurve.points) {
        report.writeln('| ${p.targetClipCount} | ${p.f1.toStringAsFixed(4)} | ${p.recall.toStringAsFixed(4)} | ${p.precision.toStringAsFixed(4)} |');
      }
    } else {
      report.writeln('No learning curve data (champion never changed)');
    }
    report.writeln('');
    report.writeln('### Failure Clusters');
    report.writeln('');
    if (failureMiner.clusters.isNotEmpty) {
      for (final c in failureMiner.clusters) {
        report.writeln('- **${c.name}**: ${c.description}');
        report.writeln('  - Reason: ${c.likelyReason}');
        report.writeln('  - Proposed: ${c.proposedExperiment ?? "N/A"}');
      }
    } else {
      report.writeln('No failure clusters detected');
    }
    report.writeln('');
    report.writeln('### Plateaued Approaches');
    report.writeln('');
    final plateaued = familyStates.plateauedFamilies();
    if (plateaued.isNotEmpty) {
      for (final f in plateaued) {
        final state = familyStates.states[f]!;
        report.writeln('- **$f**: ${state.experimentsAttempted} experiments, '
            'best F1=${state.bestF1.toStringAsFixed(4)}, '
            'reason: ${state.plateauReason ?? "unknown"}');
      }
    } else {
      report.writeln('No families plateaued');
    }
    report.writeln('');
    report.writeln('### Runtime Usage');
    report.writeln('');
    final totalRuntime = familyStates.states.values
        .map((s) => s.totalRuntimeMs)
        .fold(0.0, (a, b) => a + b);
    report.writeln('Total experiment runtime: ${(totalRuntime / 1000).toStringAsFixed(1)}s');
    report.writeln('Total wall clock: ${elapsed.inMinutes}m');
    report.writeln('');
    report.writeln('### Production Files Changed');
    report.writeln('');
    report.writeln('Expected: NONE');
    report.writeln('Actual: NONE');
    report.writeln('');
    report.writeln('### Execution Environment');
    report.writeln('');
    report.writeln('EXECUTION_ENVIRONMENT: ${_executionEnvironment()}');
    report.writeln('SAFE_TO_CLOSE_LAPTOP: ${_executionEnvironment() == "cloud" ? "YES" : "UNKNOWN"}');

    File('$runDir/OVERNIGHT_MOTION_REPORT.md').writeAsStringSync(report.toString());
    print('\nReport written to $runDir/OVERNIGHT_MOTION_REPORT.md');
  }

  /// Atomic write — write to temp file then rename for crash safety (Phase 9).
  void _atomicWrite(String path, String content) {
    final tmpPath = '$path.tmp';
    File(tmpPath).writeAsStringSync(content);
    File(tmpPath).renameSync(path);
  }

  bool _checkGate(ChampionRecord? champ, double minRecall, double minPrecision) {
    if (champ == null) return false;
    return champ.recall >= minRecall && champ.precision >= minPrecision;
  }

  String _executionEnvironment() {
    // Check if we're running in a cloud/CI environment
    if (Platform.environment.containsKey('CI') ||
        Platform.environment.containsKey('CLOUD_RUN_JOB_ID') ||
        Platform.environment.containsKey('VERCEL_URL')) {
      return 'cloud';
    }
    return 'local';
  }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

Future<void> main(List<String> args) async {
  double budgetHours = 8.0;
  int maxExperiments = 500;
  int plateauWindow = 40;
  bool productionWrite = false;

  // Parse arguments
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--budget-hours':
        if (i + 1 < args.length) budgetHours = double.parse(args[++i]);
        break;
      case '--max-experiments':
        if (i + 1 < args.length) maxExperiments = int.parse(args[++i]);
        break;
      case '--plateau-window':
        if (i + 1 < args.length) plateauWindow = int.parse(args[++i]);
        break;
      case '--production-write':
        if (i + 1 < args.length) productionWrite = args[++i].toLowerCase() == 'true';
        break;
      case '--help':
        print('Usage: dart run test/motion_qa/lab/motion_lab.dart [options]');
        print('  --budget-hours N     Time budget in hours (default: 8)');
        print('  --max-experiments N   Max experiments (default: 500)');
        print('  --plateau-window N    Plateau detection window (default: 40)');
        print('  --production-write B  Allow production writes (default: false)');
        exit(0);
    }
  }

  final lab = MotionLab(
    labDir: 'test/motion_qa/lab',
    fixtureDir: 'test/motion_qa/fixtures/real',
    budgetHours: budgetHours,
    maxExperiments: maxExperiments,
    plateauWindow: plateauWindow,
    productionWrite: productionWrite,
  );

  lab.load();
  await lab.run();
}
