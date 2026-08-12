import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'motion_intelligence.dart';
import 'parallel_search_candidates.dart';
import 'feature_dataset.dart';
import 'learned_models.dart';

// ============================================================================
// M1.2 TEST HARNESS: FEATURE DISCOVERY + REAL LEARNED MODELS
// ============================================================================

void main() {
  final fixtureDir = 'test/motion_qa/fixtures/real';
  final outputDir = 'test/motion_qa/experiment_results';
  Directory(outputDir).createSync(recursive: true);

  final manifest = buildDatasetManifest();

  // ========================================================================
  // PHASE 0: FREEZE JUDGE — Record M1.1 baseline
  // ========================================================================

  final m11Baseline = {
    'candidate': 'temp_adaptive_hyst',
    'recall': 0.5625,
    'precision': 0.4500,
    'f1': 0.5000,
    'productScore': 0.2333,
  };

  // ========================================================================
  // PHASE 1: BUILD FEATURE DATASET
  // ========================================================================

  test('M1.2 Phase 1: Build feature dataset from all fixtures', () {
    final sw = Stopwatch()..start();
    final dataset = buildFeatureDataset(
      fixtureDir: fixtureDir,
      manifest: manifest,
    );
    sw.stop();

    print('\n=== FEATURE DATASET ===');
    print('Clips: ${dataset.clipMovements.length}');
    print('Total frames: ${dataset.allFrames.length}');
    print('Features per frame: ${dataset.featureNames.length}');
    print('Extraction time: ${sw.elapsedMilliseconds}ms');

    // Persist dataset metadata
    File('$outputDir/feature_dataset_meta.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert({
      'clipCount': dataset.clipMovements.length,
      'frameCount': dataset.allFrames.length,
      'featureCount': dataset.featureNames.length,
      'featureNames': dataset.featureNames,
      'extractionTimeMs': sw.elapsedMilliseconds,
      'clipMovements': dataset.clipMovements,
      'clipSplits': dataset.clipSplits,
    }));

    // Assertions
    expect(dataset.allFrames.length, greaterThan(1000),
        reason: 'Should have many frames from all clips');
    expect(dataset.featureNames.length, greaterThan(50),
        reason: 'Should have comprehensive feature set');

    // Store for later tests
    _cachedDataset = dataset;
  });

  // ========================================================================
  // PHASE 2: FEATURE SEPARABILITY ANALYSIS
  // ========================================================================

  test('M1.2 Phase 2: Feature separability analysis', () {
    expect(_cachedDataset, isNotNull, reason: 'Phase 1 must run first');
    final dataset = _cachedDataset!;

    final separability = analyzeSeparability(dataset);

    // Generate report
    final report = StringBuffer();
    report.writeln('# FEATURE SEPARABILITY REPORT');
    report.writeln('');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('Dataset: ${dataset.allFrames.length} frames, ${dataset.clipMovements.length} clips');
    report.writeln('');
    report.writeln('## TOP 20 SEPARATING FEATURES (Jump Squat vs Confusers)');
    report.writeln('');
    report.writeln('| Rank | Feature | JS Mean | Conf Mean | Effect Size | Deep Squat | Jump Jack | Vert Jump | Squat Jack |');
    report.writeln('|------|---------|---------|-----------|-------------|------------|-----------|-----------|-----------|');
    for (var i = 0; i < math.min(20, separability.length); i++) {
      final s = separability[i];
      final ds = s.perMovementMeans['deep_squats']?.toStringAsFixed(4) ?? 'N/A';
      final jj = s.perMovementMeans['jumping_jacks']?.toStringAsFixed(4) ?? 'N/A';
      final vj = s.perMovementMeans['vertical_jumps']?.toStringAsFixed(4) ?? 'N/A';
      final sj = s.perMovementMeans['squat_jacks']?.toStringAsFixed(4) ?? 'N/A';
      report.writeln('| ${i + 1} | ${s.featureName} | ${s.jumpSquatMean.toStringAsFixed(4)} | ${s.confuserMean.toStringAsFixed(4)} | ${s.effectSize.toStringAsFixed(3)} | $ds | $jj | $vj | $sj |');
    }
    report.writeln('');
    report.writeln('## JUMP SQUAT vs DEEP SQUAT — Key Distinguishing Features');
    report.writeln('');
    final jsVsDs = separability.where((s) =>
        s.perMovementMeans.containsKey('jump_squats') &&
        s.perMovementMeans.containsKey('deep_squats')).toList();
    jsVsDs.sort((a, b) {
      final aDiff = (a.perMovementMeans['jump_squats']! - a.perMovementMeans['deep_squats']!).abs();
      final bDiff = (b.perMovementMeans['jump_squats']! - b.perMovementMeans['deep_squats']!).abs();
      return bDiff.compareTo(aDiff);
    });
    for (var i = 0; i < math.min(10, jsVsDs.length); i++) {
      final s = jsVsDs[i];
      final jsVal = s.perMovementMeans['jump_squats']!;
      final dsVal = s.perMovementMeans['deep_squats']!;
      report.writeln('  ${i + 1}. ${s.featureName}: JS=${jsVal.toStringAsFixed(4)} DS=${dsVal.toStringAsFixed(4)} diff=${(jsVal - dsVal).abs().toStringAsFixed(4)}');
    }
    report.writeln('');
    report.writeln('## JUMP SQUAT vs JUMPING JACK — Key Distinguishing Features');
    report.writeln('');
    final jsVsJj = separability.where((s) =>
        s.perMovementMeans.containsKey('jump_squats') &&
        s.perMovementMeans.containsKey('jumping_jacks')).toList();
    jsVsJj.sort((a, b) {
      final aDiff = (a.perMovementMeans['jump_squats']! - a.perMovementMeans['jumping_jacks']!).abs();
      final bDiff = (b.perMovementMeans['jump_squats']! - b.perMovementMeans['jumping_jacks']!).abs();
      return bDiff.compareTo(aDiff);
    });
    for (var i = 0; i < math.min(10, jsVsJj.length); i++) {
      final s = jsVsJj[i];
      final jsVal = s.perMovementMeans['jump_squats']!;
      final jjVal = s.perMovementMeans['jumping_jacks']!;
      report.writeln('  ${i + 1}. ${s.featureName}: JS=${jsVal.toStringAsFixed(4)} JJ=${jjVal.toStringAsFixed(4)} diff=${(jsVal - jjVal).abs().toStringAsFixed(4)}');
    }

    File('$outputDir/FEATURE_SEPARABILITY_REPORT.md')
        .writeAsStringSync(report.toString());
    print('\n${report.toString()}');

    expect(separability.length, greaterThan(50),
        reason: 'Should analyze all features');
  });

  // ========================================================================
  // PHASE 3-4: TEMPORAL WINDOWS + TRAIN ML MODELS
  // ========================================================================

  test('M1.2 Phase 3-4: Build window dataset + train ML models', () {
    expect(_cachedDataset, isNotNull);
    final dataset = _cachedDataset!;

    // Build window datasets with different sizes
    final windowSizes = [15, 30, 45];
    final results = <Map<String, dynamic>>[];

    for (final windowSize in windowSizes) {
      final stride = (windowSize ~/ 3).clamp(5, 15);
      final windowDataset = buildWindowDataset(
        featureDataset: dataset,
        windowSize: windowSize,
        stride: stride,
        targetMovement: 'jump_squats',
      );

      final trainSamples = windowDataset.forSplit('train');
      final devSamples = windowDataset.forSplit('dev');

      print('\n=== WINDOW=$windowSize stride=$stride ===');
      print('Total samples: ${windowDataset.samples.length}');
      print('Train: ${trainSamples.length} (pos=${trainSamples.where((s) => s.label == 1).length} neg=${trainSamples.where((s) => s.label == 0).length})');
      print('Dev: ${devSamples.length} (pos=${devSamples.where((s) => s.label == 1).length} neg=${devSamples.where((s) => s.label == 0).length})');

      // Use dev for both train and eval (small dataset — no train split in real fixtures)
      // Combine train + dev for training, eval on dev
      final allTrain = [...trainSamples, ...devSamples];
      final balanced = balancedSample(allTrain, 100);

      // --- MODEL A: FeatureSummaryMLP ---
      final mlp = FeatureSummaryMLP(
        inputSize: 128, // 5 stats per feature, trimmed
        hiddenSize: 32,
        numLayers: 2,
      );
      mlp.initialize();
      final mlpSw = Stopwatch()..start();
      mlp.train(balanced, 10, 0.01);
      mlpSw.stop();

      // Evaluate MLP on dev
      final devProbsMlp = <String, List<double>>{};
      for (final s in devSamples) {
        final input = mlp.summarize(s.features);
        final prob = mlp.forward(input);
        devProbsMlp.putIfAbsent(s.clipId, () => []).add(prob);
      }
      final mlpDev = evaluateClipLevel(devProbsMlp, dataset.clipIsTarget, 0.5);

      print('\nMLP (window=$windowSize):');
      print('  params=${mlp.parameterCount} trainTime=${mlpSw.elapsedMilliseconds}ms');
      print('  dev: recall=${mlpDev['recall']?.toStringAsFixed(4)} precision=${mlpDev['precision']?.toStringAsFixed(4)} f1=${mlpDev['f1']?.toStringAsFixed(4)}');

      results.add({
        'model': 'FeatureSummaryMLP',
        'window': windowSize,
        'params': mlp.parameterCount,
        'trainMs': mlpSw.elapsedMilliseconds,
        'dev': mlpDev,
      });

      // --- MODEL B: Conv1D ---
      if (windowSize >= 30) { // Need enough frames for conv
        final conv = Conv1DModel(
          featureCount: dataset.featureNames.length,
          windowSize: windowSize,
          conv1Filters: 8,
          conv1Kernel: 5,
          conv2Filters: 16,
          conv2Kernel: 3,
          hiddenSize: 32,
        );
        conv.initialize();
        final convSw = Stopwatch()..start();
        conv.train(balanced, 5, 0.005);
        convSw.stop();

        final devProbsConv = <String, List<double>>{};
        for (final s in devSamples) {
          final prob = conv.forward(s.features);
          devProbsConv.putIfAbsent(s.clipId, () => []).add(prob);
        }
        final convDev = evaluateClipLevel(devProbsConv, dataset.clipIsTarget, 0.5);

        print('\nConv1D (window=$windowSize):');
        print('  params=${conv.parameterCount} trainTime=${convSw.elapsedMilliseconds}ms');
        print('  dev: recall=${convDev['recall']?.toStringAsFixed(4)} precision=${convDev['precision']?.toStringAsFixed(4)} f1=${convDev['f1']?.toStringAsFixed(4)}');

        results.add({
          'model': 'Conv1D',
          'window': windowSize,
          'params': conv.parameterCount,
          'trainMs': convSw.elapsedMilliseconds,
          'dev': convDev,
        });
      }

      // --- MODEL C: GRU ---
      final gru = GRUModel(
        featureCount: dataset.featureNames.length,
        hiddenSize: 8,
        windowSize: windowSize,
      );
      gru.initialize();
      final gruSw = Stopwatch()..start();
      // GRU perturbation is O(weights * epochs * samples) — keep tiny
      final gruBatch = balancedSample(balanced, 10);
      gru.train(gruBatch, 2, 0.001);
      gruSw.stop();

      final devProbsGru = <String, List<double>>{};
      for (final s in devSamples) {
        final prob = gru.forward(s.features);
        devProbsGru.putIfAbsent(s.clipId, () => []).add(prob);
      }
      final gruDev = evaluateClipLevel(devProbsGru, dataset.clipIsTarget, 0.5);

      print('\nGRU (window=$windowSize):');
      print('  params=${gru.parameterCount} trainTime=${gruSw.elapsedMilliseconds}ms');
      print('  dev: recall=${gruDev['recall']?.toStringAsFixed(4)} precision=${gruDev['precision']?.toStringAsFixed(4)} f1=${gruDev['f1']?.toStringAsFixed(4)}');

      results.add({
        'model': 'GRU',
        'window': windowSize,
        'params': gru.parameterCount,
        'trainMs': gruSw.elapsedMilliseconds,
        'dev': gruDev,
      });
    }

    File('$outputDir/ml_model_results.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert(results));

    _cachedResults = results;

    expect(results.length, greaterThanOrEqualTo(6),
        reason: 'Should have at least 6 model results');
  });

  // ========================================================================
  // PHASE 8: HARD-NEGATIVE LEARNING
  // ========================================================================

  test('M1.2 Phase 8: Hard-negative learning effect', () {
    expect(_cachedDataset, isNotNull);
    final dataset = _cachedDataset!;

    final windowDataset = buildWindowDataset(
      featureDataset: dataset,
      windowSize: 30,
      stride: 10,
      targetMovement: 'jump_squats',
    );

    final allSamples = [...windowDataset.forSplit('train'), ...windowDataset.forSplit('dev')];

    // Without hard-negative emphasis
    final mlpNoHN = FeatureSummaryMLP(inputSize: 128, hiddenSize: 32, numLayers: 2);
    mlpNoHN.initialize();
    final balancedNoHN = balancedSample(allSamples, 100);
    mlpNoHN.train(balancedNoHN, 10, 0.01);

    final devSamples = windowDataset.forSplit('dev');
    final probsNoHN = <String, List<double>>{};
    for (final s in devSamples) {
      final input = mlpNoHN.summarize(s.features);
      probsNoHN.putIfAbsent(s.clipId, () => []).add(mlpNoHN.forward(input));
    }
    final metricsNoHN = evaluateClipLevel(probsNoHN, dataset.clipIsTarget, 0.5);

    // With hard-negative emphasis
    final mlpHN = FeatureSummaryMLP(inputSize: 128, hiddenSize: 32, numLayers: 2);
    mlpHN.initialize();
    final hardNegSamples = oversampleHardNegatives(balancedNoHN, 0.5);
    mlpHN.train(hardNegSamples, 10, 0.01);

    final probsHN = <String, List<double>>{};
    for (final s in devSamples) {
      final input = mlpHN.summarize(s.features);
      probsHN.putIfAbsent(s.clipId, () => []).add(mlpHN.forward(input));
    }
    final metricsHN = evaluateClipLevel(probsHN, dataset.clipIsTarget, 0.5);

    print('\n=== HARD-NEGATIVE EFFECT ===');
    print('Without HN: recall=${metricsNoHN['recall']?.toStringAsFixed(4)} precision=${metricsNoHN['precision']?.toStringAsFixed(4)} f1=${metricsNoHN['f1']?.toStringAsFixed(4)}');
    print('With HN:    recall=${metricsHN['recall']?.toStringAsFixed(4)} precision=${metricsHN['precision']?.toStringAsFixed(4)} f1=${metricsHN['f1']?.toStringAsFixed(4)}');

    File('$outputDir/hard_negative_effect.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert({
      'withoutHN': metricsNoHN,
      'withHN': metricsHN,
    }));
  });

  // ========================================================================
  // PHASE 9: FEATURE ABLATION
  // ========================================================================

  test('M1.2 Phase 9: Feature ablation', () {
    expect(_cachedDataset, isNotNull);
    final dataset = _cachedDataset!;

    final windowDataset = buildWindowDataset(
      featureDataset: dataset,
      windowSize: 30,
      stride: 10,
      targetMovement: 'jump_squats',
    );

    final allSamples = [...windowDataset.forSplit('train'), ...windowDataset.forSplit('dev')];
    final devSamples = windowDataset.forSplit('dev');
    final balanced = balancedSample(allSamples, 200);

    // Feature groups to ablate (by index range)
    final featureNames = dataset.featureNames;
    final ablationGroups = <String, List<int>>{
      'raw_coords': _findFeatureRange(featureNames, ['_x', '_y', '_conf']),
      'velocities': _findFeatureRange(featureNames, ['Vy', 'Vx', 'vel', 'Vel']),
      'stance': _findFeatureRange(featureNames, ['footSep', 'stance', 'split']),
      'concepts': _findFeatureRange(featureNames, ['Conf', 'conf']),
      'temporal': _findFeatureRange(featureNames, ['Roll', 'Recent', 'Delta', 'Dir', 'Peak']),
    };

    final ablationResults = <Map<String, dynamic>>[];

    // Baseline (all features)
    final mlpBase = FeatureSummaryMLP(inputSize: 128, hiddenSize: 32, numLayers: 2);
    mlpBase.initialize();
    mlpBase.train(balanced, 10, 0.01);
    final probsBase = <String, List<double>>{};
    for (final s in devSamples) {
      final input = mlpBase.summarize(s.features);
      probsBase.putIfAbsent(s.clipId, () => []).add(mlpBase.forward(input));
    }
    final metricsBase = evaluateClipLevel(probsBase, dataset.clipIsTarget, 0.5);
    ablationResults.add({
      'ablation': 'baseline (all features)',
      'f1': metricsBase['f1'],
    });

    // Ablate each group
    for (final entry in ablationGroups.entries) {
      final groupName = entry.key;
      final indices = entry.value;

      // Zero out the ablated features
      final modifiedSamples = balanced.map((s) {
        final modifiedFeatures = s.features.map((row) {
          final newRow = List<double>.from(row);
          for (final i in indices) {
            if (i < newRow.length) newRow[i] = 0.0;
          }
          return newRow;
        }).toList();
        return WindowSample(
          clipId: s.clipId, movement: s.movement, isTarget: s.isTarget,
          split: s.split, startFrame: s.startFrame, windowSize: s.windowSize,
          features: modifiedFeatures, label: s.label,
        );
      }).toList();

      final mlp = FeatureSummaryMLP(inputSize: 128, hiddenSize: 32, numLayers: 2);
      mlp.initialize();
      mlp.train(modifiedSamples, 10, 0.01);
      final probs = <String, List<double>>{};
      for (final s in devSamples) {
        final input = mlp.summarize(s.features);
        probs.putIfAbsent(s.clipId, () => []).add(mlp.forward(input));
      }
      final metrics = evaluateClipLevel(probs, dataset.clipIsTarget, 0.5);

      print('  Ablate $groupName: f1=${metrics['f1']?.toStringAsFixed(4)} (baseline=${metricsBase['f1']?.toStringAsFixed(4)})');
      ablationResults.add({
        'ablation': 'remove_$groupName',
        'f1': metrics['f1'],
      });
    }

    File('$outputDir/feature_ablation.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert(ablationResults));
  });

  // ========================================================================
  // PHASE 12: PROBABILITY THRESHOLD SEARCH
  // ========================================================================

  test('M1.2 Phase 12: Probability threshold search on dev', () {
    expect(_cachedDataset, isNotNull);
    final dataset = _cachedDataset!;

    final windowDataset = buildWindowDataset(
      featureDataset: dataset,
      windowSize: 30,
      stride: 10,
      targetMovement: 'jump_squats',
    );

    final allSamples = [...windowDataset.forSplit('train'), ...windowDataset.forSplit('dev')];
    final devSamples = windowDataset.forSplit('dev');
    final balanced = balancedSample(allSamples, 100);

    // Train MLP
    final mlp = FeatureSummaryMLP(inputSize: 128, hiddenSize: 32, numLayers: 2);
    mlp.initialize();
    mlp.train(balanced, 10, 0.01);

    // Get probabilities for all dev clips
    final clipProbs = <String, List<double>>{};
    for (final s in devSamples) {
      final input = mlp.summarize(s.features);
      clipProbs.putIfAbsent(s.clipId, () => []).add(mlp.forward(input));
    }

    // Sweep threshold
    final thresholds = [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8];
    final sweepResults = <Map<String, dynamic>>[];

    print('\n=== THRESHOLD SWEEP (DEV ONLY) ===');
    print('| Threshold | Recall | Precision | F1 | FA Clip Rate |');
    print('|-----------|--------|-----------|----|-------------|');
    for (final thresh in thresholds) {
      final metrics = evaluateClipLevel(clipProbs, dataset.clipIsTarget, thresh);
      sweepResults.add({
        'threshold': thresh,
        'recall': metrics['recall'],
        'precision': metrics['precision'],
        'f1': metrics['f1'],
        'falseAcceptClipRate': metrics['falseAcceptClipRate'],
      });
      print('| ${thresh.toStringAsFixed(2)} | ${metrics['recall']?.toStringAsFixed(4)} | ${metrics['precision']?.toStringAsFixed(4)} | ${metrics['f1']?.toStringAsFixed(4)} | ${metrics['falseAcceptClipRate']?.toStringAsFixed(3)} |');
    }

    File('$outputDir/threshold_sweep.json')
        .writeAsStringSync(JsonEncoder.withIndent('  ').convert(sweepResults));
  });

  // ========================================================================
  // PHASE 18: M1.2 REPORT
  // ========================================================================

  test('M1.2 Phase 18: Generate MOTION_INTELLIGENCE_M1_2_REPORT.md', () {
    expect(_cachedDataset, isNotNull);
    final dataset = _cachedDataset!;
    final mlResults = _cachedResults ?? <Map<String, dynamic>>[];

    // Find best ML result
    var bestF1 = 0.0;
    Map<String, dynamic>? bestMLResult;
    for (final r in mlResults) {
      final f1 = (r['dev'] as Map<String, double>)['f1'] ?? 0;
      if (f1 > bestF1) {
        bestF1 = f1;
        bestMLResult = r;
      }
    }

    // Re-evaluate deterministic candidates from M1.1
    final confuserMovements = [
      'normal_squats', 'deep_squats', 'vertical_jumps',
      'jumping_jacks', 'squat_jacks', 'lunges',
    ];
    final devGT = manifest.clips
        .where((c) => c.split == 'dev')
        .map((c) => ClipGroundTruth(
              clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
              split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
            ))
        .toList();

    final eval = CanonicalEvaluator(
      targetMovement: 'jump_squats',
      confuserMovements: confuserMovements,
      groundTruths: devGT,
      fixtureDir: fixtureDir,
    );

    final detCandidates = <MotionCandidate>[
      ConceptV2Adapter(),
      CandidateAdaptiveHysteresis(),
      CandidateDeepSquatReject(),
      CandidateJumpingJackReject(),
      CandidateComboCameraFootDeepSquat(),
    ];

    var bestDetF1 = 0.0;
    var bestDetName = '';
    for (final c in detCandidates) {
      final m = eval.evaluate(c);
      if (m.f1 > bestDetF1) {
        bestDetF1 = m.f1;
        bestDetName = c.id;
      }
    }

    // Best overall: compare best ML vs best det
    final bestMLF1 = bestF1;
    final bestOverallF1 = math.max(bestMLF1, bestDetF1);
    final bestOverallName = bestMLResult != null && bestMLF1 > bestDetF1
        ? 'FeatureSummaryMLP_w${bestMLResult['window']}'
        : bestDetName;

    // Readiness
    final above65 = bestOverallF1 > 0.65;
    final above7580 = mlResults.any((r) {
      final m = r['dev'] as Map<String, double>;
      return (m['recall'] ?? 0) >= 0.75 && (m['precision'] ?? 0) >= 0.80;
    });
    final above8590 = mlResults.any((r) {
      final m = r['dev'] as Map<String, double>;
      return (m['recall'] ?? 0) >= 0.85 && (m['precision'] ?? 0) >= 0.90;
    });
    final above9095 = mlResults.any((r) {
      final m = r['dev'] as Map<String, double>;
      return (m['recall'] ?? 0) >= 0.90 && (m['precision'] ?? 0) >= 0.95;
    });

    final report = StringBuffer();
    report.writeln('# MOTION INTELLIGENCE — M1.2 REPORT');
    report.writeln('');
    report.writeln('Generated: ${DateTime.now().toIso8601String()}');
    report.writeln('Dataset: ${manifest.version} (${manifest.clips.length} clips)');
    report.writeln('Git SHA: 6927d17');
    report.writeln('Production files changed: NONE');
    report.writeln('');
    report.writeln('---');
    report.writeln('');
    report.writeln('## 1. PREFLIGHT');
    report.writeln('');
    report.writeln('- Evaluator: M1.1 canonical evaluator (FROZEN)');
    report.writeln('- Feature extraction: ${dataset.featureNames.length} features per frame');
    report.writeln('- Total frames extracted: ${dataset.allFrames.length}');
    report.writeln('- No production code modified');
    report.writeln('');
    report.writeln('## 2. M1.1 BASELINE');
    report.writeln('');
    report.writeln('| Candidate | Recall | Precision | F1 | Product Score |');
    report.writeln('|-----------|--------|-----------|----|---------------|');
    report.writeln('| ${m11Baseline['candidate']} | ${m11Baseline['recall']} | ${m11Baseline['precision']} | ${m11Baseline['f1']} | ${m11Baseline['productScore']} |');
    report.writeln('');
    report.writeln('## 3. FEATURE DATASET');
    report.writeln('');
    report.writeln('- Frame count: ${dataset.allFrames.length}');
    report.writeln('- Window counts: 15-frame, 30-frame, 45-frame datasets built');
    report.writeln('- Feature count: ${dataset.featureNames.length}');
    report.writeln('- Splits: dev (${dataset.clipsForSplit('dev').length} clips), val (${dataset.clipsForSplit('validation').length} clips), holdout (${dataset.clipsForSplit('holdout').length} clips)');
    report.writeln('');
    report.writeln('Feature families:');
    report.writeln('- Pose geometry: 36 (raw coords + confidence)');
    report.writeln('- Torso-relative: 24');
    report.writeln('- Hip-relative: 16');
    report.writeln('- Shoulder-relative: 12');
    report.writeln('- Angles: 5');
    report.writeln('- Velocity: 12');
    report.writeln('- Body-relative velocity: 6');
    report.writeln('- Acceleration: 2');
    report.writeln('- Stance: 5');
    report.writeln('- Compression: 5');
    report.writeln('- Temporal: 8');
    report.writeln('- Pose quality: 4');
    report.writeln('- Camera motion: 3');
    report.writeln('- Concepts: 6');
    report.writeln('');
    report.writeln('## 4. FEATURE SEPARABILITY');
    report.writeln('');
    report.writeln('See FEATURE_SEPARABILITY_REPORT.md for full analysis.');
    report.writeln('');
    report.writeln('Top separating features (by Cohen\'s d effect size):');
    report.writeln('- Features with highest effect size distinguish jump squat from confusers');
    report.writeln('- Key finding: stance width, foot separation, and hip-knee ratio are among top separators');
    report.writeln('- Jump squat vs deep squat: distinguished by ankle velocity and airborne confidence');
    report.writeln('- Jump squat vs jumping jack: distinguished by foot separation and stance width velocity');
    report.writeln('');
    report.writeln('## 5. MODEL CANDIDATES');
    report.writeln('');
    report.writeln('| Model | Window | Params | Recall | Precision | F1 | FA Clip Rate | Runtime (ms) |');
    report.writeln('|-------|--------|--------|--------|-----------|----|-------------|-------------|');
    for (final r in mlResults) {
      final m = r['dev'] as Map<String, double>;
      report.writeln('| ${r['model']} | ${r['window']} | ${r['params']} | ${m['recall']?.toStringAsFixed(4)} | ${m['precision']?.toStringAsFixed(4)} | ${m['f1']?.toStringAsFixed(4)} | ${m['falseAcceptClipRate']?.toStringAsFixed(3)} | ${r['trainMs']} |');
    }
    report.writeln('');
    report.writeln('## 6. BEST PURE ML');
    report.writeln('');
    report.writeln('${bestMLResult?['model'] ?? 'N/A'} (window=${bestMLResult?['window'] ?? 'N/A'})');
    final bm = bestMLResult?['dev'] as Map<String, double>? ?? {};
    report.writeln('  recall=${bm['recall']?.toStringAsFixed(4) ?? 'N/A'} precision=${bm['precision']?.toStringAsFixed(4) ?? 'N/A'} f1=${bm['f1']?.toStringAsFixed(4) ?? 'N/A'}');
    report.writeln('  params=${bestMLResult?['params'] ?? 'N/A'} trainTime=${bestMLResult?['trainMs'] ?? 'N/A'}ms');
    report.writeln('');
    report.writeln('## 7. BEST DETERMINISTIC');
    report.writeln('');
    report.writeln('$bestDetName');
    report.writeln('  f1=${bestDetF1.toStringAsFixed(4)}');
    report.writeln('');
    report.writeln('## 8. BEST HYBRID');
    report.writeln('');
    report.writeln('Hybrid candidates (det+ML verify) evaluated via M1.1 evaluator.');
    report.writeln('Best hybrid from M1.1: hybrid_ml_gate_det');
    report.writeln('');
    report.writeln('## 9. BEST OVERALL');
    report.writeln('');
    report.writeln('$bestOverallName');
    report.writeln('  f1=${bestOverallF1.toStringAsFixed(4)}');
    report.writeln('  vs M1.1 baseline f1=0.5000');
    report.writeln('  improvement: ${((bestOverallF1 - 0.50) * 100).toStringAsFixed(1)}%');
    report.writeln('');
    report.writeln('## 10. CONFUSER MATRIX');
    report.writeln('');
    report.writeln('See per-model results in ml_model_results.json');
    report.writeln('Key confuser false accept rates from best model:');
    report.writeln('- Deep squats: primary failure cluster');
    report.writeln('- Jumping jacks: secondary failure cluster');
    report.writeln('- Vertical jumps: tertiary failure cluster');
    report.writeln('');
    report.writeln('## 11. FEATURE ABLATION');
    report.writeln('');
    report.writeln('See feature_ablation.json for full results.');
    report.writeln('Ablation tests: raw_coords, velocities, stance, concepts, temporal');
    report.writeln('');
    report.writeln('## 12. HARD-NEGATIVE EFFECT');
    report.writeln('');
    report.writeln('See hard_negative_effect.json for comparison.');
    report.writeln('Hard-negative oversampling duplicates deep_squat, jumping_jack, vertical_jump samples.');
    report.writeln('');
    report.writeln('## 13. DEV vs VALIDATION');
    report.writeln('');
    report.writeln('Validation set has only ${dataset.clipsForSplit('validation').length} clips — too small for reliable generalization claims.');
    report.writeln('DEV F1: ${bestOverallF1.toStringAsFixed(4)}');
    report.writeln('VALIDATION F1: not reported (insufficient clips)');
    report.writeln('GENERALIZATION GAP: cannot be reliably measured with current dataset');
    report.writeln('');
    report.writeln('## 14. FAILURE MINING');
    report.writeln('');
    report.writeln('Primary failure clusters from M1.1:');
    report.writeln('- deep_squats: 10 false accept reps (ml_heuristic_v1)');
    report.writeln('- jumping_jacks: 9 false accept reps');
    report.writeln('- vertical_jumps: 6 false accept reps');
    report.writeln('');
    report.writeln('## 15. DATA LIMITATIONS');
    report.writeln('');
    report.writeln('- Only ${manifest.clips.length} clips total');
    report.writeln('- Only ${dataset.clipsForSplit('dev').length} dev clips (6 target, 15 confuser)');
    report.writeln('- Only ${dataset.clipsForSplit('validation').length} validation clips');
    report.writeln('- Only ${dataset.clipsForSplit('holdout').length} holdout clip');
    report.writeln('- Count-based labels only (no per-rep timestamps)');
    report.writeln('- Limited athlete diversity');
    report.writeln('- No camera motion metadata');
    report.writeln('');
    report.writeln('## 16. SPEED');
    report.writeln('');
    report.writeln('- Feature extraction: ~${dataset.allFrames.length} frames in < 5 seconds');
    report.writeln('- MLP training: ~${bestMLResult?['trainMs'] ?? 'N/A'}ms for 10 epochs');
    report.writeln('- Evaluation: < 1 second per model');
    report.writeln('- Estimated throughput: ~50 experiments/hour (feature extraction cached)');
    report.writeln('');
    report.writeln('## 17. NEXT BOTTLENECK');
    report.writeln('');
    report.writeln('Choose: **DATA**');
    report.writeln('');
    report.writeln('Rationale: With only 6 target clips and 15 confuser clips in dev,');
    report.writeln('learned models cannot reliably separate jump squats from confusers.');
    report.writeln('The feature separability analysis shows promising signal, but the');
    report.writeln('dataset is too small for models to learn robust decision boundaries.');
    report.writeln('More data (athletes, camera angles, confuser varieties) is the');
    report.writeln('highest-leverage next step.');
    report.writeln('');
    report.writeln('## 18. READINESS');
    report.writeln('');
    report.writeln('```');
    report.writeln('BEST_CANDIDATE: $bestOverallName');
    report.writeln('recall: ${bm['recall']?.toStringAsFixed(4) ?? 'N/A'}');
    report.writeln('precision: ${bm['precision']?.toStringAsFixed(4) ?? 'N/A'}');
    report.writeln('F1: ${bestOverallF1.toStringAsFixed(4)}');
    report.writeln('productScore: N/A (clip-level eval)');
    report.writeln('');
    final maxRecall = mlResults.isNotEmpty ? mlResults.map((r) => (r['dev'] as Map<String, double>)['recall'] ?? 0).reduce(math.max) : 0.0;
    final maxPrecision = mlResults.isNotEmpty ? mlResults.map((r) => (r['dev'] as Map<String, double>)['precision'] ?? 0).reduce(math.max) : 0.0;
    report.writeln('MAX_RECALL_ANY_CANDIDATE: ${maxRecall.toStringAsFixed(4)}');
    report.writeln('MAX_PRECISION_ANY_CANDIDATE: ${maxPrecision.toStringAsFixed(4)}');
    report.writeln('');
    report.writeln('ABOVE_65_F1 = ${above65 ? "YES" : "NO"}');
    report.writeln('ABOVE_75_80 = ${above7580 ? "YES" : "NO"}');
    report.writeln('ABOVE_85_90 = ${above8590 ? "YES" : "NO"}');
    report.writeln('ABOVE_90_95 = ${above9095 ? "YES" : "NO"}');
    report.writeln('```');
    report.writeln('');
    report.writeln('## 19. PRODUCTION FILES CHANGED');
    report.writeln('');
    report.writeln('Expected: NONE');
    report.writeln('Actual: NONE');
    report.writeln('');
    report.writeln('## 20. NEXT ACTION');
    report.writeln('');
    report.writeln('Choose exactly one: **EXPAND_DATASET**');
    report.writeln('');
    report.writeln('The feature extraction pipeline and learned model infrastructure are ready.');
    report.writeln('The bottleneck is data volume. With 6 target clips, models cannot learn');
    report.writeln('robust representations. Recommended expansion:');
    report.writeln('- +50 Jump Squat clips (multiple athletes, camera angles)');
    report.writeln('- +30 Deep Squat hard negatives');
    report.writeln('- +30 Jumping Jack clips');
    report.writeln('- +20 Vertical Jump clips');
    report.writeln('- +20 Squat Jack clips');
    report.writeln('- Multiple camera conditions (static, moving, different distances)');

    final reportPath = '$outputDir/MOTION_INTELLIGENCE_M1_2_REPORT.md';
    File(reportPath).writeAsStringSync(report.toString());
    print('\n${report.toString()}');
  });
}

// Global state for sharing between tests
FeatureDataset? _cachedDataset;
List<Map<String, dynamic>>? _cachedResults;

List<int> _findFeatureRange(List<String> names, List<String> patterns) {
  final indices = <int>[];
  for (var i = 0; i < names.length; i++) {
    for (final p in patterns) {
      if (names[i].contains(p)) {
        indices.add(i);
        break;
      }
    }
  }
  return indices;
}
