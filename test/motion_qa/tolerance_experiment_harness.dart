import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/airborne_state_tracker.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/multi_phase_sequence_tracker.dart';
import 'package:nuvo/features/races/ai/preset_motion/multi_phase_definitions.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

import 'replay_fixture.dart';

/// Experiment harness for controlled tolerance experiments.
///
/// Creates validators with experimental parameters, runs them against
/// all real video fixtures and synthetic fixtures, and records results
/// in a machine-readable format for comparison.
///
/// This is TEST-ONLY tooling. It does not change production behavior.

/// Parameters that can be experimentally varied.
class ExperimentParams {
  const ExperimentParams({
    this.noiseGraceFrames,
    this.standingThreshold,
    this.squatThreshold,
    this.standingStableFrames,
    this.squatStableFrames,
    this.airborneStableFrames,
    this.landingStableFrames,
    this.flightThresholdRatio,
    this.groundedToleranceRatio,
    this.cooldownFrames,
    this.lungeStableFrames,
    this.lungeStandingThreshold,
  });

  /// Override for noiseGraceFrames in definition. null = use production value.
  final int? noiseGraceFrames;

  /// Override for STANDING hipToKneeRatio threshold.
  final double? standingThreshold;

  /// Override for SQUAT hipToKneeRatio threshold.
  final double? squatThreshold;

  /// Override for STANDING stableFrames.
  final int? standingStableFrames;

  /// Override for SQUAT stableFrames.
  final int? squatStableFrames;

  /// Override for AIRBORNE stableFrames.
  final int? airborneStableFrames;

  /// Override for LANDING stableFrames.
  final int? landingStableFrames;

  /// Override for AirborneStateTracker.flightThresholdRatio.
  final double? flightThresholdRatio;

  /// Override for AirborneStateTracker.groundedToleranceRatio.
  final double? groundedToleranceRatio;

  /// Override for cooldownFrames.
  final int? cooldownFrames;

  /// Override for lunge jump phase stableFrames.
  final int? lungeStableFrames;

  /// Override for lunge jump standing (reset) threshold.
  final double? lungeStandingThreshold;

  bool get hasOverrides =>
      noiseGraceFrames != null ||
      standingThreshold != null ||
      squatThreshold != null ||
      standingStableFrames != null ||
      squatStableFrames != null ||
      airborneStableFrames != null ||
      landingStableFrames != null ||
      flightThresholdRatio != null ||
      groundedToleranceRatio != null ||
      cooldownFrames != null ||
      lungeStableFrames != null ||
      lungeStandingThreshold != null;

  String get label {
    final parts = <String>[];
    if (noiseGraceFrames != null) parts.add('ngf=$noiseGraceFrames');
    if (standingThreshold != null) parts.add('std=$standingThreshold');
    if (squatThreshold != null) parts.add('sq=$squatThreshold');
    if (standingStableFrames != null) parts.add('ssf=$standingStableFrames');
    if (squatStableFrames != null) parts.add('sqsf=$squatStableFrames');
    if (airborneStableFrames != null) parts.add('asf=$airborneStableFrames');
    if (landingStableFrames != null) parts.add('lsf=$landingStableFrames');
    if (flightThresholdRatio != null) parts.add('ftr=$flightThresholdRatio');
    if (groundedToleranceRatio != null) parts.add('gtr=$groundedToleranceRatio');
    if (cooldownFrames != null) parts.add('cd=$cooldownFrames');
    if (lungeStableFrames != null) parts.add('lsf=$lungeStableFrames');
    if (lungeStandingThreshold != null) parts.add('lstd=$lungeStandingThreshold');
    return parts.isEmpty ? 'production' : parts.join(',');
  }
}

/// Builds an experimental jump squat definition with overridden parameters.
MultiPhaseSequenceDefinition buildExperimentalJumpSquat(
  AirborneStateTracker airborne,
  ExperimentParams params,
) {
  final standingThreshold = params.standingThreshold ?? 0.70;
  final squatThreshold = params.squatThreshold ?? 0.58;
  final standingStable = params.standingStableFrames ?? 2;
  final squatStable = params.squatStableFrames ?? 1;
  final airborneStable = params.airborneStableFrames ?? 1;
  final landingStable = params.landingStableFrames ?? 2;
  final cooldown = params.cooldownFrames ?? 3;
  final noiseGrace = params.noiseGraceFrames ?? 1;

  final standingCondition = ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    standingThreshold,
    greaterThan: true,
  );

  final groundedStandingCondition = AndCondition([
    standingCondition,
    GroundedCondition(airborne),
  ]);

  final squatCondition = ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    squatThreshold,
    greaterThan: false,
  );

  final airborneCondition = AirborneCondition(airborne);

  final landingCondition = AndCondition([
    standingCondition,
    GroundedCondition(airborne),
  ]);

  const coreLandmarks = [
    'leftShoulder', 'rightShoulder',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
  ];

  return MultiPhaseSequenceDefinition(
    phases: [
      SequencePhaseDefinition(
        id: 'STANDING',
        condition: groundedStandingCondition,
        stableFrames: standingStable,
      ),
      SequencePhaseDefinition(
        id: 'SQUAT',
        condition: squatCondition,
        stableFrames: squatStable,
      ),
      SequencePhaseDefinition(
        id: 'AIRBORNE',
        condition: airborneCondition,
        stableFrames: airborneStable,
      ),
      SequencePhaseDefinition(
        id: 'LANDING',
        condition: landingCondition,
        stableFrames: landingStable,
      ),
    ],
    resetCondition: groundedStandingCondition,
    requiredLandmarks: coreLandmarks,
    cooldownFrames: cooldown,
    noiseGraceFrames: noiseGrace,
  );
}

/// Builds experimental lunge jump definitions with overridden parameters.
List<MultiPhaseSequenceDefinition> buildExperimentalLungeJump(
  AirborneStateTracker airborne,
  ExperimentParams params,
) {
  final lungeStable = params.lungeStableFrames ?? 3;
  final airborneStable = params.airborneStableFrames ?? 1;
  final standingThreshold = params.lungeStandingThreshold ?? 0.86;
  final cooldown = params.cooldownFrames ?? 3;
  final noiseGrace = params.noiseGraceFrames ?? 1;

  final rightLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.rightKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.leftKneeAngle, 160, greaterThan: true),
  ]);

  final leftLungeCondition = const AndCondition([
    ComparisonCondition(PoseSignal.leftKneeAngle, 120, greaterThan: false),
    ComparisonCondition(PoseSignal.rightKneeAngle, 160, greaterThan: true),
  ]);

  final airborneCondition = AirborneCondition(airborne);

  final standingCondition = ComparisonCondition(
    PoseSignal.hipToKneeRatio,
    standingThreshold,
    greaterThan: true,
  );

  const coreLandmarks = [
    'leftShoulder', 'rightShoulder',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
  ];

  return [
    MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(
          id: 'RIGHT_LUNGE',
          condition: rightLungeCondition,
          stableFrames: lungeStable,
        ),
        SequencePhaseDefinition(
          id: 'AIRBORNE',
          condition: airborneCondition,
          stableFrames: airborneStable,
        ),
        SequencePhaseDefinition(
          id: 'LEFT_LUNGE',
          condition: leftLungeCondition,
          stableFrames: lungeStable,
        ),
      ],
      resetCondition: standingCondition,
      requiredLandmarks: coreLandmarks,
      cooldownFrames: cooldown,
      noiseGraceFrames: noiseGrace,
    ),
    MultiPhaseSequenceDefinition(
      phases: [
        SequencePhaseDefinition(
          id: 'LEFT_LUNGE',
          condition: leftLungeCondition,
          stableFrames: lungeStable,
        ),
        SequencePhaseDefinition(
          id: 'AIRBORNE',
          condition: airborneCondition,
          stableFrames: airborneStable,
        ),
        SequencePhaseDefinition(
          id: 'RIGHT_LUNGE',
          condition: rightLungeCondition,
          stableFrames: lungeStable,
        ),
      ],
      resetCondition: standingCondition,
      requiredLandmarks: coreLandmarks,
      cooldownFrames: cooldown,
      noiseGraceFrames: noiseGrace,
    ),
  ];
}

/// Creates an experimental MultiPhaseSequenceValidator for jump squats.
MultiPhaseSequenceValidator createExperimentalJumpSquatValidator(
  ExperimentParams params,
  int target,
) {
  return MultiPhaseSequenceValidator(
    activity: AiMotionActivity.jumpSquats,
    targetValue: target,
    definitions: (airborne) {
      return [buildExperimentalJumpSquat(airborne, params)];
    },
    statusText: 'Experimental JSQ',
    coachingTextActive: '',
    coachingTextIncomplete: '',
  );
}

/// Creates an experimental MultiPhaseSequenceValidator for lunge jumps.
MultiPhaseSequenceValidator createExperimentalLungeJumpValidator(
  ExperimentParams params,
  int target,
) {
  return MultiPhaseSequenceValidator(
    activity: AiMotionActivity.lungeJumps,
    targetValue: target,
    definitions: (airborne) => buildExperimentalLungeJump(airborne, params),
    statusText: 'Experimental LJ',
    coachingTextActive: '',
    coachingTextIncomplete: '',
  );
}

/// Test-only validator wrapper that allows overriding AirborneStateTracker
/// parameters. The production MultiPhaseSequenceValidator creates its own
/// tracker internally with fixed defaults. This wrapper replicates the
/// essential behavior with custom tracker params.
class ExperimentalValidator {
  ExperimentalValidator({
    required this.params,
    required this.isLungeJump,
    this.target = 99,
  }) {
    _airborne = AirborneStateTracker(
      flightThresholdRatio: params.flightThresholdRatio ?? 0.25,
      groundedToleranceRatio: params.groundedToleranceRatio ?? 0.10,
    );
    if (isLungeJump) {
      final defs = buildExperimentalLungeJump(_airborne, params);
      _trackers = defs
          .map((def) => MultiPhaseSequenceTracker(definition: def))
          .toList(growable: false);
    } else {
      final def = buildExperimentalJumpSquat(_airborne, params);
      _trackers = [MultiPhaseSequenceTracker(definition: def)];
    }
  }

  final ExperimentParams params;
  final bool isLungeJump;
  final int target;
  late AirborneStateTracker _airborne;
  late List<MultiPhaseSequenceTracker> _trackers;

  static const _coreLandmarks = [
    'leftShoulder', 'rightShoulder',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
  ];

  int get currentValue {
    final total = _trackers.fold(0, (sum, t) => sum + t.completionCount);
    return total < target ? total : target;
  }

  void start() {
    _airborne.reset();
    for (final t in _trackers) {
      t.reset();
    }
  }

  void update(NuvoPoseFrame frame) {
    _airborne.update(frame);
    if (!frame.hasPoints(_coreLandmarks)) return;
    for (final tracker in _trackers) {
      tracker.update(frame);
    }
  }
}

/// Result of running a single fixture through a validator.
class FixtureResult {
  const FixtureResult({
    required this.fixtureId,
    required this.movement,
    required this.expectedReps,
    required this.detectedReps,
    required this.totalFrames,
    required this.missingLandmarkFrames,
  });

  final String fixtureId;
  final String movement;
  final int expectedReps;
  final int detectedReps;
  final int totalFrames;
  final int missingLandmarkFrames;

  bool get detected => detectedReps > 0;
  bool get matched => detectedReps == expectedReps;
}

/// Runs a fixture through an experimental validator and records results.
FixtureResult runFixtureThroughValidator(
  ReplayFixture fixture,
  dynamic validator,
) {
  validator.start();
  for (final frame in fixture.frames) {
    validator.update(frame.toPoseFrame());
  }
  return FixtureResult(
    fixtureId: fixture.id,
    movement: fixture.movement,
    expectedReps: fixture.expected.reps,
    detectedReps: validator.currentValue,
    totalFrames: fixture.frames.length,
    missingLandmarkFrames: 0,
  );
}

/// Aggregated results for a movement across all fixtures.
class MovementResult {
  MovementResult(this.movement, this.results);

  final String movement;
  final List<FixtureResult> results;

  int get totalExpected => results.fold(0, (s, r) => s + r.expectedReps);
  int get totalDetected => results.fold(0, (s, r) => s + r.detectedReps);
  int get clipsDetected => results.where((r) => r.detected).length;
  int get clipsMatched => results.where((r) => r.matched).length;
  int get clipCount => results.length;

  double get recall =>
      totalExpected > 0 ? totalDetected / totalExpected : 0.0;
  double get clipAcceptance =>
      clipCount > 0 ? clipsDetected / clipCount : 0.0;

  Map<String, dynamic> toJson() => {
        'movement': movement,
        'clips': clipCount,
        'expected_reps': totalExpected,
        'detected_reps': totalDetected,
        'recall_pct': (recall * 100).toStringAsFixed(1),
        'clip_acceptance_pct': (clipAcceptance * 100).toStringAsFixed(1),
        'clips_detected': clipsDetected,
        'clips_matched': clipsMatched,
        'per_clip': results
            .map((r) => {
                  'id': r.fixtureId,
                  'expected': r.expectedReps,
                  'detected': r.detectedReps,
                })
            .toList(),
      };
}

/// Full experiment result.
class ExperimentResult {
  ExperimentResult({
    required this.label,
    required this.params,
    required this.jumpSquat,
    required this.lungeJump,
    required this.confuserResults,
    required this.syntheticPassRate,
    required this.identityPassRate,
  });

  final String label;
  final ExperimentParams params;
  final MovementResult jumpSquat;
  final MovementResult lungeJump;
  final Map<String, MovementResult> confuserResults;
  final double syntheticPassRate;
  final double identityPassRate;

  Map<String, dynamic> toJson() => {
        'label': label,
        'params': label,
        'jump_squat': jumpSquat.toJson(),
        'lunge_jump': lungeJump.toJson(),
        'confusers': confuserResults.map((k, v) => MapEntry(k, v.toJson())),
        'synthetic_pass_rate': syntheticPassRate.toStringAsFixed(1),
        'identity_pass_rate': identityPassRate.toStringAsFixed(1),
      };
}

/// Loads all real video fixtures.
List<ReplayFixture> loadRealFixtures() {
  final realDir = Directory('test/motion_qa/fixtures/real');
  if (!realDir.existsSync()) return [];

  return realDir
      .listSync()
      .where((f) => f.path.endsWith('.json') && !f.path.endsWith('import_log.json'))
      .map((f) => File(f.path))
      .where((f) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return json['frames'] != null;
  })
      .map((f) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return ReplayFixture.fromJsonString(jsonEncode(json));
  }).toList();
}

/// Loads synthetic fixtures from manifest.
List<ReplayFixture> loadSyntheticFixtures() {
  final manifestFile = File('test/motion_qa/fixtures/manifest.json');
  if (!manifestFile.existsSync()) return [];

  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final entries = manifest['fixtures'] as List<dynamic>;

  final fixtures = <ReplayFixture>[];
  for (final entry in entries) {
    final m = entry as Map<String, dynamic>;
    final fid = m['id'] as String;
    if (m['movement'] != 'jump_squats') continue;
    if (!(m['shouldMatch'] as bool)) continue;
    if (fid.contains('__')) continue; // skip augmented
    final fpath = 'test/motion_qa/fixtures/$fid.json';
    final file = File(fpath);
    if (!file.existsSync()) continue;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    fixtures.add(ReplayFixture.fromJsonString(jsonEncode(json)));
  }
  return fixtures;
}

/// Runs all fixtures through an experimental validator and returns results.
MovementResult runMovement(
  List<ReplayFixture> fixtures,
  String movement,
  dynamic validator,
) {
  final mvFixtures = fixtures.where((f) => f.movement == movement).toList();
  final results = mvFixtures
      .map((f) => runFixtureThroughValidator(f, validator))
      .toList();
  return MovementResult(movement, results);
}

/// Runs confuser fixtures through the jump squat validator.
/// Returns per-movement false accept counts.
Map<String, MovementResult> runConfusers(
  List<ReplayFixture> fixtures,
  dynamic validator,
  String validatorName,
) {
  final confuserMovements = <String>[
    'normal_squats', 'deep_squats', 'vertical_jumps',
    'jumping_jacks', 'squat_jacks', 'lunges',
  ];

  final results = <String, MovementResult>{};
  for (final mv in confuserMovements) {
    final mvFixtures = fixtures.where((f) => f.movement == mv).toList();
    if (mvFixtures.isEmpty) continue;
    final fr = mvFixtures
        .map((f) => runFixtureThroughValidator(f, validator))
        .toList();
    results[mv] = MovementResult(mv, fr);
  }
  return results;
}

/// Runs synthetic fixtures through a validator and returns pass rate.
double runSynthetic(
  List<ReplayFixture> syntheticFixtures,
  dynamic validator,
) {
  if (syntheticFixtures.isEmpty) return -1;
  var passed = 0;
  for (final fixture in syntheticFixtures) {
    validator.start();
    for (final frame in fixture.frames) {
      validator.update(frame.toPoseFrame());
    }
    if (validator.currentValue == fixture.expected.reps) passed++;
  }
  return passed / syntheticFixtures.length * 100;
}

/// Full experiment runner.
ExperimentResult runExperiment(
  String label,
  ExperimentParams params,
  List<ReplayFixture> realFixtures,
  List<ReplayFixture> syntheticFixtures,
) {
  // Create experimental validators using the wrapper.
  final jsqValidator = ExperimentalValidator(params: params, isLungeJump: false);
  final ljValidator = ExperimentalValidator(params: params, isLungeJump: true);

  // Run jump squat.
  final jsqResult = runMovement(realFixtures, 'jump_squats', jsqValidator);

  // Run lunge jump.
  final ljResult = runMovement(realFixtures, 'lunge_jumps', ljValidator);

  // Run confusers through jump squat validator.
  final confusers = runConfusers(realFixtures, jsqValidator, 'jump_squats');

  // Run synthetic.
  final synthRate = runSynthetic(syntheticFixtures, jsqValidator);

  // Identity pass rate (placeholder — run separately).
  final identityRate = -1.0;

  return ExperimentResult(
    label: label,
    params: params,
    jumpSquat: jsqResult,
    lungeJump: ljResult,
    confuserResults: confusers,
    syntheticPassRate: synthRate,
    identityPassRate: identityRate,
  );
}

/// Main experiment test entry point.
void main() {
  final realFixtures = loadRealFixtures();
  final syntheticFixtures = loadSyntheticFixtures();

  if (realFixtures.isEmpty) {
    test('experiment harness — fixtures available', () {
      print('No real fixtures found. Run motion_qa_import.py first.');
      expect(true, isTrue);
    });
    return;
  }

  // Save all results to a JSON file for the report.
  final allResults = <ExperimentResult>[];

  group('Tolerance Experiments', () {
    // Baseline: current production parameters.
    test('BASELINE — current production', () {
      final result = runExperiment(
        'BASELINE',
        const ExperimentParams(),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== BASELINE (production) ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%), ${result.jumpSquat.clipsDetected}/${result.jumpSquat.clipCount} clips');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%), ${result.lungeJump.clipsDetected}/${result.lungeJump.clipCount} clips');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
      for (final entry in result.confuserResults.entries) {
        print('  Confuser ${entry.key}: ${entry.value.totalDetected} reps false-accepted');
      }
    });

    // Experiment A: Temporal stability — noiseGraceFrames=0 (strict consecutive)
    test('EXP A1 — noiseGraceFrames=0 (strict consecutive)', () {
      final result = runExperiment(
        'A1_ngf0',
        const ExperimentParams(noiseGraceFrames: 0),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP A1: noiseGraceFrames=0 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment A2: noiseGraceFrames=2 (more grace)
    test('EXP A2 — noiseGraceFrames=2', () {
      final result = runExperiment(
        'A2_ngf2',
        const ExperimentParams(noiseGraceFrames: 2),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP A2: noiseGraceFrames=2 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment B: Athletic stance — lower standing threshold to 0.60
    test('EXP B1 — standingThreshold=0.60', () {
      final result = runExperiment(
        'B1_std060',
        const ExperimentParams(standingThreshold: 0.60),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP B1: standing=0.60 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
      for (final entry in result.confuserResults.entries) {
        final baseline = allResults[0].confuserResults[entry.key];
        final delta = entry.value.totalDetected - (baseline?.totalDetected ?? 0);
        if (delta != 0) {
          print('  Confuser ${entry.key}: ${entry.value.totalDetected} reps (delta=$delta)');
        }
      }
    });

    // Experiment B2: standingThreshold=0.55
    test('EXP B2 — standingThreshold=0.55', () {
      final result = runExperiment(
        'B2_std055',
        const ExperimentParams(standingThreshold: 0.55),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP B2: standing=0.55 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment C: Squat threshold relaxed to 0.65
    test('EXP C1 — squatThreshold=0.65', () {
      final result = runExperiment(
        'C1_sq065',
        const ExperimentParams(squatThreshold: 0.65),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP C1: squat=0.65 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment E: Camera sway — higher flight threshold
    test('EXP E1 — flightThresholdRatio=0.35', () {
      final result = runExperiment(
        'E1_ftr035',
        const ExperimentParams(flightThresholdRatio: 0.35),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP E1: ftr=0.35 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment E2: flightThresholdRatio=0.30
    test('EXP E2 — flightThresholdRatio=0.30', () {
      final result = runExperiment(
        'E2_ftr030',
        const ExperimentParams(flightThresholdRatio: 0.30),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP E2: ftr=0.30 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment F: Lunge stable frames reduced
    test('EXP F1 — lungeStableFrames=2', () {
      final result = runExperiment(
        'F1_lsf2',
        const ExperimentParams(lungeStableFrames: 2),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP F1: lungeStable=2 ===');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment B3: standingThreshold=0.50 (aggressive)
    test('EXP B3 — standingThreshold=0.50', () {
      final result = runExperiment(
        'B3_std050',
        const ExperimentParams(standingThreshold: 0.50),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP B3: standing=0.50 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
      for (final entry in result.confuserResults.entries) {
        final baseline = allResults[0].confuserResults[entry.key];
        final delta = entry.value.totalDetected - (baseline?.totalDetected ?? 0);
        if (delta != 0) {
          print('  Confuser ${entry.key}: ${entry.value.totalDetected} reps (delta=$delta)');
        }
      }
    });

    // Experiment D1: standing stableFrames=1 (faster rearm)
    test('EXP D1 — standingStableFrames=1', () {
      final result = runExperiment(
        'D1_ssf1',
        const ExperimentParams(standingStableFrames: 1),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP D1: standingStable=1 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
    });

    // Experiment COMBO1: B2 + E2 (standing=0.55 + ftr=0.30)
    test('EXP COMBO1 — standing=0.55 + ftr=0.30', () {
      final result = runExperiment(
        'COMBO1_std055_ftr030',
        const ExperimentParams(standingThreshold: 0.55, flightThresholdRatio: 0.30),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP COMBO1: standing=0.55 + ftr=0.30 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  LJ: ${result.lungeJump.totalDetected}/${result.lungeJump.totalExpected} reps (${(result.lungeJump.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
      for (final entry in result.confuserResults.entries) {
        final baseline = allResults[0].confuserResults[entry.key];
        final delta = entry.value.totalDetected - (baseline?.totalDetected ?? 0);
        if (delta != 0) {
          print('  Confuser ${entry.key}: ${entry.value.totalDetected} reps (delta=$delta)');
        }
      }
    });

    // Experiment COMBO2: B2 + D1 (standing=0.55 + standingStable=1)
    test('EXP COMBO2 — standing=0.55 + standingStable=1', () {
      final result = runExperiment(
        'COMBO2_std055_ssf1',
        const ExperimentParams(standingThreshold: 0.55, standingStableFrames: 1),
        realFixtures,
        syntheticFixtures,
      );
      allResults.add(result);
      print('\n=== EXP COMBO2: standing=0.55 + standingStable=1 ===');
      print('  JSQ: ${result.jumpSquat.totalDetected}/${result.jumpSquat.totalExpected} reps (${(result.jumpSquat.recall * 100).toStringAsFixed(1)}%)');
      print('  Synthetic: ${result.syntheticPassRate.toStringAsFixed(1)}%');
      for (final entry in result.confuserResults.entries) {
        final baseline = allResults[0].confuserResults[entry.key];
        final delta = entry.value.totalDetected - (baseline?.totalDetected ?? 0);
        if (delta != 0) {
          print('  Confuser ${entry.key}: ${entry.value.totalDetected} reps (delta=$delta)');
        }
      }
    });

    // Save all results after all tests.
    test('save experiment results', () {
      final json = allResults.map((r) => r.toJson()).toList();
      final outputPath = 'test/motion_qa/experiment_results.json';
      File(outputPath).writeAsStringSync(jsonEncode(json));
      print('\n=== ALL EXPERIMENT RESULTS SAVED ===');
      print('  File: $outputPath');
      print('  Experiments: ${allResults.length}');
      for (final r in allResults) {
        print('  ${r.label.padRight(20)} JSQ=${(r.jumpSquat.recall * 100).toStringAsFixed(1)}% LJ=${(r.lungeJump.recall * 100).toStringAsFixed(1)}% synth=${r.syntheticPassRate.toStringAsFixed(1)}%');
      }
    });
  });
}
