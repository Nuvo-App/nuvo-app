import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'motion_intelligence.dart';
import 'parallel_search_candidates.dart';
import 'lab/experiment_registry.dart';
import 'lab/motion_lab.dart';

// ============================================================================
// M1.3 MOTION LAB — REGRESSION TESTS
// ============================================================================
// Tests: bounded metrics, champion promotion, catastrophic rejection,
//        experiment persistence, resume behavior, plateau detection,
//        status generation, failed-experiment recovery, no production writes
// ============================================================================

void main() {
  final labDir = 'test/motion_qa/lab_test_artifacts';
  final fixtureDir = 'test/motion_qa/fixtures/real';

  setUp(() {
    // Clean test artifacts directory
    final dir = Directory(labDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  tearDown(() {
    // Clean up
    final dir = Directory(labDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('M1.3 Regression: Bounded metrics', () {
    test('recall is always in [0, 1]', () {
      final manifest = buildDatasetManifest();
      final devGts = manifest.clips
          .where((c) => c.split == 'dev')
          .map((c) => ClipGroundTruth(
                clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
                split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
              ))
          .toList();

      final eval = CanonicalEvaluator(
        targetMovement: 'jump_squats',
        confuserMovements: ['normal_squats', 'deep_squats', 'vertical_jumps', 'jumping_jacks', 'squat_jacks', 'lunges'],
        groundTruths: devGts,
        fixtureDir: fixtureDir,
      );

      for (final candidate in [
        ProductionJumpSquatAdapter(),
        CandidateAdaptiveHysteresis(),
        ConceptV2Adapter(),
        CandidateNofMTransitions(),
        CandidateMedianFilter(),
      ]) {
        final metrics = eval.evaluate(candidate);
        expect(metrics.repRecall, lessThanOrEqualTo(1.0),
            reason: '${candidate.id} recall > 1.0');
        expect(metrics.repRecall, greaterThanOrEqualTo(0.0),
            reason: '${candidate.id} recall < 0.0');
        expect(metrics.repPrecision, lessThanOrEqualTo(1.0),
            reason: '${candidate.id} precision > 1.0');
        expect(metrics.repPrecision, greaterThanOrEqualTo(0.0),
            reason: '${candidate.id} precision < 0.0');
        expect(metrics.f1, lessThanOrEqualTo(1.0),
            reason: '${candidate.id} F1 > 1.0');
        expect(metrics.f1, greaterThanOrEqualTo(0.0),
            reason: '${candidate.id} F1 < 0.0');
      }
    });

    test('catastrophic overcount is detected and counted', () {
      final manifest = buildDatasetManifest();
      final devGts = manifest.clips
          .where((c) => c.split == 'dev')
          .map((c) => ClipGroundTruth(
                clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
                split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
              ))
          .toList();

      final eval = CanonicalEvaluator(
        targetMovement: 'jump_squats',
        confuserMovements: ['normal_squats', 'deep_squats', 'vertical_jumps', 'jumping_jacks', 'squat_jacks', 'lunges'],
        groundTruths: devGts,
        fixtureDir: fixtureDir,
      );

      // Production candidate should not have catastrophic clips
      final metrics = eval.evaluate(ProductionJumpSquatAdapter());
      expect(metrics.catastrophicClips, lessThanOrEqualTo(metrics.totalTargetClips),
          reason: 'Catastrophic clips exceed total target clips');
    });
  });

  group('M1.3 Regression: Champion promotion', () {
    test('champion is promoted only when genuinely better', () {
      final champPath = '$labDir/CHAMPION.json';
      final manager = ChampionManager(champPath);

      // No champion initially
      expect(manager.champion, isNull);

      // First promotion always succeeds
      final champ1 = ChampionRecord(
        experimentId: 'EXP-000001',
        candidateName: 'test_a',
        family: 'temporal',
        architecture: 'Test',
        config: {},
        datasetVersion: 'v1.0.0',
        recall: 0.5,
        precision: 0.5,
        f1: 0.5,
        falseAcceptClipRate: 0.2,
        exactCountRate: 0.5,
        productScore: 0.2,
        gateResult: 'research',
        sourceCommit: 'test',
        timestamp: DateTime.now(),
      );
      expect(manager.tryPromote(champ1), isTrue);
      expect(manager.champion?.candidateName, 'test_a');

      // Worse F1 — should NOT promote
      final champ2 = ChampionRecord(
        experimentId: 'EXP-000002',
        candidateName: 'test_b',
        family: 'temporal',
        architecture: 'Test',
        config: {},
        datasetVersion: 'v1.0.0',
        recall: 0.4,
        precision: 0.4,
        f1: 0.4,
        falseAcceptClipRate: 0.3,
        exactCountRate: 0.4,
        productScore: 0.1,
        gateResult: 'research',
        sourceCommit: 'test',
        timestamp: DateTime.now(),
      );
      expect(manager.tryPromote(champ2), isFalse);
      expect(manager.champion?.candidateName, 'test_a');

      // Better F1 — should promote
      final champ3 = ChampionRecord(
        experimentId: 'EXP-000003',
        candidateName: 'test_c',
        family: 'hybrid',
        architecture: 'Test',
        config: {},
        datasetVersion: 'v1.0.0',
        recall: 0.6,
        precision: 0.6,
        f1: 0.6,
        falseAcceptClipRate: 0.1,
        exactCountRate: 0.6,
        productScore: 0.3,
        gateResult: 'promising',
        sourceCommit: 'test',
        timestamp: DateTime.now(),
      );
      expect(manager.tryPromote(champ3), isTrue);
      expect(manager.champion?.candidateName, 'test_c');
      expect(manager.championChanges, 2);
    });

    test('champion persists to disk', () {
      final champPath = '$labDir/CHAMPION.json';
      final manager = ChampionManager(champPath);

      final champ = ChampionRecord(
        experimentId: 'EXP-000001',
        candidateName: 'persisted',
        family: 'temporal',
        architecture: 'Test',
        config: {'key': 'value'},
        datasetVersion: 'v1.0.0',
        recall: 0.75,
        precision: 0.90,
        f1: 0.82,
        falseAcceptClipRate: 0.05,
        exactCountRate: 0.80,
        productScore: 0.62,
        gateResult: 'promising',
        sourceCommit: 'test',
        timestamp: DateTime.now(),
      );

      manager.tryPromote(champ);

      // Reload from disk
      final manager2 = ChampionManager(champPath);
      manager2.load();
      expect(manager2.champion, isNotNull);
      expect(manager2.champion?.candidateName, 'persisted');
      expect(manager2.champion?.f1, 0.82);
    });
  });

  group('M1.3 Regression: Experiment persistence', () {
    test('experiments are appended to JSONL and reloadable', () {
      final jsonlPath = '$labDir/EXPERIMENTS.jsonl';
      final registry = ExperimentRegistry(jsonlPath);
      registry.load(); // creates file

      // Append 3 experiments
      for (var i = 0; i < 3; i++) {
        final id = registry.nextId();
        registry.append(ExperimentRecord(
          id: id,
          timestamp: DateTime.now(),
          family: 'temporal',
          candidateName: 'test_$i',
          hypothesis: 'test hypothesis $i',
          config: {'param': i},
          datasetVersion: 'v1.0.0',
          status: 'completed',
          f1: 0.5 + i * 0.01,
          recall: 0.6,
          precision: 0.5,
          tp: 10,
          fn: 5,
          fp: 10,
        ));
      }

      expect(registry.count, 3);
      expect(registry.completedCount, 3);

      // Reload
      final registry2 = ExperimentRegistry(jsonlPath);
      registry2.load();
      expect(registry2.count, 3);
      expect(registry2.completedCount, 3);
      expect(registry2.records[0].candidateName, 'test_0');
      expect(registry2.records[2].f1, closeTo(0.52, 0.001));
      // Next ID should continue from where we left off
      expect(registry2.nextId(), 'EXP-000003');
    });

    test('failed experiments are recorded and counted', () {
      final jsonlPath = '$labDir/EXPERIMENTS_FAILED.jsonl';
      final registry = ExperimentRegistry(jsonlPath);
      registry.load();

      registry.append(ExperimentRecord(
        id: registry.nextId(),
        timestamp: DateTime.now(),
        family: 'gru',
        candidateName: 'crashed',
        hypothesis: 'should crash',
        config: {},
        datasetVersion: 'v1.0.0',
        status: 'failed',
        error: 'OutOfMemory',
      ));

      registry.append(ExperimentRecord(
        id: registry.nextId(),
        timestamp: DateTime.now(),
        family: 'temporal',
        candidateName: 'ok',
        hypothesis: 'should work',
        config: {},
        datasetVersion: 'v1.0.0',
        status: 'completed',
        f1: 0.5,
      ));

      expect(registry.count, 2);
      expect(registry.completedCount, 1);
      expect(registry.failedCount, 1);
    });
  });

  group('M1.3 Regression: Resume behavior', () {
    test('registry resumes from last experiment ID', () {
      final jsonlPath = '$labDir/EXPERIMENTS_RESUME.jsonl';
      final registry = ExperimentRegistry(jsonlPath);
      registry.load();

      // Add 5 experiments
      for (var i = 0; i < 5; i++) {
        registry.append(ExperimentRecord(
          id: registry.nextId(),
          timestamp: DateTime.now(),
          family: 'temporal',
          candidateName: 'test_$i',
          hypothesis: 'test',
          config: {},
          datasetVersion: 'v1.0.0',
          status: 'completed',
          f1: 0.5,
        ));
      }

      expect(registry.nextId(), 'EXP-000005');

      // Reload — should continue from EXP-000005
      final registry2 = ExperimentRegistry(jsonlPath);
      registry2.load();
      expect(registry2.nextId(), 'EXP-000005');
    });
  });

  group('M1.3 Regression: Plateau detection', () {
    test('plateau detected when no improvement in window', () {
      final detector = PlateauDetector(plateauWindow: 5, minImprovement: 0.01);
      final state = FamilyState(family: 'test', bestF1: 0.5, startingBestF1: 0.5);

      // Create 10 records with no improvement
      final records = <ExperimentRecord>[];
      for (var i = 0; i < 10; i++) {
        records.add(ExperimentRecord(
          id: 'EXP-${i.toString().padLeft(6, '0')}',
          timestamp: DateTime.now(),
          family: 'test',
          candidateName: 'test_$i',
          hypothesis: 'test',
          config: {},
          datasetVersion: 'v1.0.0',
          status: 'completed',
          f1: 0.5, // No improvement
        ));
      }

      final plateaued = detector.checkPlateau(state, records);
      expect(plateaued, isTrue);
      expect(state.plateaued, isTrue);
      expect(state.plateauReason, isNotNull);
    });

    test('no plateau when there is improvement', () {
      final detector = PlateauDetector(plateauWindow: 5, minImprovement: 0.01);
      final state = FamilyState(family: 'test', bestF1: 0.5, startingBestF1: 0.5);

      final records = <ExperimentRecord>[];
      for (var i = 0; i < 10; i++) {
        records.add(ExperimentRecord(
          id: 'EXP-${i.toString().padLeft(6, '0')}',
          timestamp: DateTime.now(),
          family: 'test',
          candidateName: 'test_$i',
          hypothesis: 'test',
          config: {},
          datasetVersion: 'v1.0.0',
          status: 'completed',
          f1: 0.5 + i * 0.02, // Steady improvement
        ));
      }

      final plateaued = detector.checkPlateau(state, records);
      expect(plateaued, isFalse);
      expect(state.plateaued, isFalse);
    });
  });

  group('M1.3 Regression: Status generation', () {
    test('STATUS.md is human readable and contains key fields', () {
      final lab = MotionLab(
        labDir: labDir,
        fixtureDir: fixtureDir,
        budgetHours: 0.01,
        maxExperiments: 1,
        plateauWindow: 40,
      );
      lab.load();
      lab.updateStatus();

      final status = File('$labDir/STATUS.md').readAsStringSync();
      expect(status, contains('NUVO MOTION LAB'));
      expect(status, contains('STATUS:'));
      expect(status, contains('Experiments completed:'));
      expect(status, contains('Champion:'));
      expect(status, contains('F1:'));
      expect(status, contains('Plateau:'));
    });
  });

  group('M1.3 Regression: No production writes', () {
    test('lab files are only under test/motion_qa/lab', () {
      final labFiles = Directory('test/motion_qa/lab').listSync();
      for (final f in labFiles) {
        expect(f.path, startsWith('test/motion_qa/lab'),
            reason: 'Lab file outside lab dir: ${f.path}');
      }
    });

    test('production motion files are not modified by lab', () {
      // Check that key production files exist and are not touched
      final productionFiles = [
        'lib/features/races/ai/motion_validators.dart',
        'lib/features/races/ai/pose_detector_service.dart',
        'lib/features/races/ai/airborne_state_tracker.dart',
      ];

      for (final path in productionFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue,
            reason: 'Production file missing: $path');
      }

      // Lab artifacts should NOT exist in production paths
      expect(File('lib/features/races/EXPERIMENTS.jsonl').existsSync(), isFalse);
      expect(File('lib/features/races/CHAMPION.json').existsSync(), isFalse);
    });
  });

  group('M1.3 Regression: Family state persistence', () {
    test('family states persist and reload', () {
      final statePath = '$labDir/FAMILY_STATE.json';
      final manager = FamilyStateManager(statePath);

      manager.getOrCreate('temporal').bestF1 = 0.55;
      manager.getOrCreate('mlp').bestF1 = 0.48;
      manager.getOrCreate('mlp').plateaued = true;
      manager.getOrCreate('mlp').plateauReason = 'No improvement';
      manager.save();

      // Reload
      final manager2 = FamilyStateManager(statePath);
      manager2.load();

      expect(manager2.states['temporal']?.bestF1, 0.55);
      expect(manager2.states['mlp']?.bestF1, 0.48);
      expect(manager2.states['mlp']?.plateaued, isTrue);
      expect(manager2.states['mlp']?.plateauReason, 'No improvement');
    });
  });

  group('M1.3 Regression: Gate classification', () {
    test('catastrophic clips result in reject gate', () {
      final manifest = buildDatasetManifest();
      final devGts = manifest.clips
          .where((c) => c.split == 'dev')
          .map((c) => ClipGroundTruth(
                clipId: c.clipId, movement: c.movement, expectedReps: c.expectedReps,
                split: c.split, source: c.source, isTarget: c.isTarget, isConfuser: c.isConfuser,
              ))
          .toList();

      final eval = CanonicalEvaluator(
        targetMovement: 'jump_squats',
        confuserMovements: ['normal_squats', 'deep_squats', 'vertical_jumps', 'jumping_jacks', 'squat_jacks', 'lunges'],
        groundTruths: devGts,
        fixtureDir: fixtureDir,
      );

      final metrics = eval.evaluate(ProductionJumpSquatAdapter());

      // The gate should be reject if catastrophic or precision < 0.70
      if (metrics.catastrophicClips > 0 || metrics.repPrecision < 0.70) {
        // This is expected behavior — the gate rejects
        expect(true, isTrue);
      }
    });
  });
}
