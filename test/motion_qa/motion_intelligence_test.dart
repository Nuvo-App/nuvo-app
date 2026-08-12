import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'motion_intelligence.dart';
import 'experiment_candidates.dart';

// ============================================================================
// PHASE 10-25: MOTION INTELLIGENCE TEST HARNESS
// Runs all candidates through canonical evaluator, produces leaderboard,
// failure mining, and M1 report.
// ============================================================================

void main() {
  final fixtureDir = 'test/motion_qa/fixtures/real';
  final outputDir = 'test/motion_qa/experiment_results';
  Directory(outputDir).createSync(recursive: true);
  final manifest = buildDatasetManifest();

  // Save dataset manifest
  File('$outputDir/dataset_manifest.json')
      .writeAsStringSync(JsonEncoder.withIndent('  ').convert(manifest.toJson()));

  // Build ground truths from manifest (dev split only for now)
  final devGroundTruths = manifest.clips
      .where((c) => c.split == 'dev')
      .map((c) => ClipGroundTruth(
            clipId: c.clipId,
            movement: c.movement,
            expectedReps: c.expectedReps,
            split: c.split,
            source: c.source,
            isTarget: c.isTarget,
            isConfuser: c.isConfuser,
          ))
      .toList();

  final valGroundTruths = manifest.clips
      .where((c) => c.split == 'validation')
      .map((c) => ClipGroundTruth(
            clipId: c.clipId,
            movement: c.movement,
            expectedReps: c.expectedReps,
            split: c.split,
            source: c.source,
            isTarget: c.isTarget,
            isConfuser: c.isConfuser,
          ))
      .toList();

  final holdoutGroundTruths = manifest.clips
      .where((c) => c.split == 'holdout')
      .map((c) => ClipGroundTruth(
            clipId: c.clipId,
            movement: c.movement,
            expectedReps: c.expectedReps,
            split: c.split,
            source: c.source,
            isTarget: c.isTarget,
            isConfuser: c.isConfuser,
          ))
      .toList();

  final evaluator = CanonicalEvaluator(
    targetMovement: 'jump_squats',
    confuserMovements: [
      'normal_squats', 'deep_squats', 'vertical_jumps',
      'jumping_jacks', 'squat_jacks', 'lunges',
    ],
    groundTruths: devGroundTruths,
    fixtureDir: fixtureDir,
  );

  final valEvaluator = CanonicalEvaluator(
    targetMovement: 'jump_squats',
    confuserMovements: evaluator.confuserMovements,
    groundTruths: valGroundTruths,
    fixtureDir: fixtureDir,
  );

  final holdoutEvaluator = CanonicalEvaluator(
    targetMovement: 'jump_squats',
    confuserMovements: evaluator.confuserMovements,
    groundTruths: holdoutGroundTruths,
    fixtureDir: fixtureDir,
  );

  final leaderboard = Leaderboard();

  // Define all candidates
  final candidates = <MotionCandidate>[
    ProductionJumpSquatAdapter(),
    ConceptV2Adapter(),
    CandidateLoweredAirborne(),
    CandidateFootGuard(),
    CandidateCameraCompensated(),
    CandidateRelaxedTemporal(),
    MLCandidate(
      id: 'ml_heuristic_v1',
      architecture: 'HeuristicScore_v1',
      predictFn: jsqHeuristicScore,
      threshold: 0.5,
    ),
    MLCandidate(
      id: 'ml_heuristic_v2',
      architecture: 'HeuristicScore_v2_low_threshold',
      predictFn: jsqHeuristicScore,
      threshold: 0.35,
    ),
  ];

  test('Motion Intelligence M1: Run all candidates through canonical evaluator', () {
    for (final candidate in candidates) {
      final devMetrics = evaluator.evaluate(candidate);
      final valMetrics = valGroundTruths.isEmpty ? null : valEvaluator.evaluate(candidate);
      final holdoutMetrics = holdoutGroundTruths.isEmpty ? null : holdoutEvaluator.evaluate(candidate);

      final entry = LeaderboardEntry(
        candidateId: candidate.id,
        family: candidate.family,
        architecture: candidate.architecture,
        parameters: {},
        gitSha: '6927d17',
        datasetVersion: manifest.version,
        timestamp: DateTime.now(),
        devMetrics: devMetrics,
        validationMetrics: valMetrics,
        holdoutMetrics: holdoutMetrics,
        notes: '',
      );

      leaderboard.register(entry);

      // Save per-candidate detailed results
      final detailFile = File('$outputDir/${candidate.id}_dev_results.json');
      detailFile.writeAsStringSync(JsonEncoder.withIndent('  ').convert({
        'candidateId': candidate.id,
        'metrics': devMetrics.toJson(),
        'clipResults': devMetrics.clipResults.map((r) => {
          'clipId': r.clipId,
          'movement': r.movement,
          'expectedReps': r.expectedReps,
          'detectedReps': r.detectedReps,
          'isTarget': r.isTarget,
          'isConfuser': r.isConfuser,
          'exactMatch': r.exactMatch,
          'repError': r.repError,
          'isFalseAccept': r.isFalseAccept,
          'processingMs': r.processingTime.inMilliseconds,
          'framesProcessed': r.framesProcessed,
          'failures': r.failures.map((f) => {
            'concept': f.concept,
            'phase': f.phase,
            'confidence': f.confidence,
          }).toList(),
        }).toList(),
      }));
    }

    // Save leaderboard
    File('$outputDir/leaderboard.json')
        .writeAsStringSync(leaderboard.toJsonString());
    File('$outputDir/leaderboard.csv')
        .writeAsStringSync(leaderboard.toCsv());
    File('$outputDir/leaderboard_report.txt')
        .writeAsStringSync(leaderboard.toReport());

    // Failure mining for top candidate
    final topEntry = leaderboard.entries.first;
    if (topEntry.devMetrics != null) {
      final failureReport = FailureMiner.generateReport(topEntry.devMetrics!.clipResults);
      File('$outputDir/failure_mining_${topEntry.candidateId}.txt')
          .writeAsStringSync(failureReport);
    }

    // Print summary
    print('\n${leaderboard.toReport()}');

    // Assertions: ensure system is functional
    expect(leaderboard.entries.length, greaterThanOrEqualTo(5),
        reason: 'Must have at least 5 candidates');
    expect(leaderboard.entries.first.devMetrics, isNotNull,
        reason: 'Top candidate must have dev metrics');
  });

  test('Motion Intelligence M1: Parameter search on ConceptV2 flightThresholdRatio', () {
    final searchSpace = ParameterSearchSpace('flightThresholdRatio', [0.10, 0.15, 0.20, 0.25, 0.30]);
    final search = SearchRunner([searchSpace], (params) {
      final candidate = ConceptV2Adapter();
      candidate.initialize(params);
      final metrics = evaluator.evaluate(candidate);
      // Objective: maximize recall while penalizing false accepts
      return metrics.repRecall - 0.5 * metrics.falseAcceptRate;
    });

    final ranked = search.gridSearch();
    expect(ranked, isNotEmpty);

    print('\n=== PARAMETER SEARCH RESULTS ===');
    for (var i = 0; i < ranked.length; i++) {
      final config = ranked[i];
      final objective = search.objective(config);
      print('${i + 1}. flightThresholdRatio=${config['flightThresholdRatio']} objective=${objective.toStringAsFixed(3)}');
    }

    // Save search results
    File('$outputDir/parameter_search_results.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert({
      'searchSpace': searchSpace.values,
      'results': ranked.map((c) => {
        'config': c,
        'objective': search.objective(c),
      }).toList(),
    }));
  });

  test('Motion Intelligence M1: Generate M1 milestone report', () {
    final report = StringBuffer();
    report.writeln('=== MOTION INTELLIGENCE — MILESTONE 1 REPORT ===');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('Dataset: ${manifest.version} (${manifest.clips.length} clips)');
    report.writeln('Git SHA: 6927d17');
    report.writeln('');
    report.writeln('--- SYSTEM COMPONENTS ---');
    report.writeln('1. Canonical Detector Interface: MotionCandidate');
    report.writeln('   - ${candidates.length} candidates registered');
    report.writeln('   - Families: ${candidates.map((c) => c.family).toSet().join(", ")}');
    report.writeln('   - Architectures: ${candidates.map((c) => c.architecture).toSet().join(", ")}');
    report.writeln('');
    report.writeln('2. Canonical Evaluator: CanonicalEvaluator');
    report.writeln('   - Metrics: recall, precision, count MAE, exact count rate,');
    report.writeln('     overcount/undercount rates, false accept rate, confuser clusters');
    report.writeln('   - Splits: dev (${devGroundTruths.length}), val (${valGroundTruths.length}), holdout (${holdoutGroundTruths.length})');
    report.writeln('');
    report.writeln('3. Dataset Manifest: v${manifest.version}');
    report.writeln('   - Target: jump_squats (${manifest.clips.where((c) => c.isTarget).length} clips)');
    report.writeln('   - Confusers: ${manifest.clips.where((c) => c.isConfuser).length} clips');
    report.writeln('   - Hard negatives: ${manifest.clips.where((c) => c.isHardNegative).length} clips');
    report.writeln('');
    report.writeln('4. Leaderboard: ${leaderboard.entries.length} entries');
    report.writeln('');
    report.writeln('--- LEADERBOARD SUMMARY ---');
    report.writeln(leaderboard.toReport());
    report.writeln('');
    report.writeln('--- BOTTLENECK ANALYSIS ---');
    final topEntry = leaderboard.entries.first;
    if (topEntry.devMetrics != null) {
      final m = topEntry.devMetrics!;
      report.writeln('Top candidate: ${topEntry.candidateId}');
      report.writeln('  Recall: ${m.repRecall.toStringAsFixed(3)}');
      report.writeln('  Precision: ${m.repPrecision.toStringAsFixed(3)}');
      report.writeln('  False accepts: ${m.totalFalseAcceptReps} reps from ${m.falseAcceptClips} clips');
      report.writeln('  Confuser breakdown: ${m.confuserFalseAccepts}');
      report.writeln('');
      final failureReport = FailureMiner.generateReport(m.clipResults);
      report.writeln(failureReport);
    }
    report.writeln('');
    report.writeln('--- RECOMMENDATIONS ---');
    report.writeln('1. Focus on confuser rejection (precision is the bottleneck)');
    report.writeln('2. Add camera motion compensation to all candidates');
    report.writeln('3. Expand holdout set for more robust evaluation');
    report.writeln('4. Train tiny MLP on pose features as ML baseline');
    report.writeln('5. Explore hybrid: deterministic + ML score fusion');
    report.writeln('');
    report.writeln('--- NEXT STEPS (Phase 27+) ---');
    report.writeln('- Subagent orchestration for parallel research');
    report.writeln('- Automated parameter search across more dimensions');
    report.writeln('- Movement expansion beyond jump squats');
    report.writeln('- Production promotion gate: recall > 0.80 AND precision > 0.90');

    final reportPath = '$outputDir/MOTION_INTELLIGENCE_M1_REPORT.md';
    File(reportPath).writeAsStringSync(report.toString());
    print('\n${report.toString()}');
  });
}
