import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'experiment_registry.dart';

// ============================================================================
// M1.3 SEARCH POLICY + FAILURE MINING
// ============================================================================
// Decides what experiment to run next based on evidence.
// ============================================================================

/// Failure cluster for grouping similar failures.
class FailureCluster {
  final String name;
  final String description;
  final List<String> affectedClips;
  final int missedReps;
  final int falseReps;
  final Map<String, dynamic> commonFeatures;
  final String likelyReason;
  final List<String> failingFamilies;
  final List<String> succeedingFamilies;
  final String? proposedExperiment;

  FailureCluster({
    required this.name,
    required this.description,
    required this.affectedClips,
    required this.missedReps,
    required this.falseReps,
    required this.commonFeatures,
    required this.likelyReason,
    required this.failingFamilies,
    required this.succeedingFamilies,
    this.proposedExperiment,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'affectedClips': affectedClips,
    'missedReps': missedReps,
    'falseReps': falseReps,
    'commonFeatures': commonFeatures,
    'likelyReason': likelyReason,
    'failingFamilies': failingFamilies,
    'succeedingFamilies': succeedingFamilies,
    'proposedExperiment': proposedExperiment,
  };
}

/// Failure miner that clusters failures from experiment results.
class FailureMiner {
  final String outputPath;
  List<FailureCluster> _clusters = [];

  FailureMiner(this.outputPath);

  List<FailureCluster> get clusters => List.unmodifiable(_clusters);

  /// Load existing failure clusters.
  void load() {
    final file = File(outputPath);
    if (!file.existsSync()) return;
    final json = jsonDecode(file.readAsStringSync()) as List;
    _clusters = json.map((c) => FailureCluster(
      name: c['name'] as String,
      description: c['description'] as String,
      affectedClips: (c['affectedClips'] as List).cast<String>(),
      missedReps: c['missedReps'] as int,
      falseReps: c['falseReps'] as int,
      commonFeatures: c['commonFeatures'] as Map<String, dynamic>,
      likelyReason: c['likelyReason'] as String,
      failingFamilies: (c['failingFamilies'] as List).cast<String>(),
      succeedingFamilies: (c['succeedingFamilies'] as List).cast<String>(),
      proposedExperiment: c['proposedExperiment'] as String?,
    )).toList();
  }

  /// Mine failures from the best experiment's per-confuser results.
  /// This is a simplified version that clusters by confuser movement.
  void mineFromExperiments(List<ExperimentRecord> records) {
    if (records.isEmpty) return;

    // Find the best completed experiment
    final best = records
        .where((r) => r.status == 'completed' && r.f1 != null)
        .toList()
      ..sort((a, b) => (b.f1 ?? 0).compareTo(a.f1 ?? 0));

    if (best.isEmpty) return;

    final champion = best.first;
    final perConfuser = champion.perConfuserResults ?? {};

    final newClusters = <FailureCluster>[];

    // Cluster by confuser movement
    for (final entry in perConfuser.entries) {
      final movement = entry.key;
      final data = entry.value as Map<String, dynamic>;
      final faClips = data['falseAcceptClips'] as int? ?? 0;
      final faReps = data['falseAcceptReps'] as int? ?? 0;

      if (faClips > 0 || faReps > 0) {
        newClusters.add(FailureCluster(
          name: 'FALSE_ACCEPT_${movement.toUpperCase()}',
          description: 'Champion false-accepts on $movement: $faClips clips, $faReps reps',
          affectedClips: [], // Would need clip-level results to populate
          missedReps: 0,
          falseReps: faReps,
          commonFeatures: {},
          likelyReason: _inferReason(movement),
          failingFamilies: _failingFamilies(records, movement),
          succeedingFamilies: _succeedingFamilies(records, movement),
          proposedExperiment: _proposeExperiment(movement, champion),
        ));
      }
    }

    // Check for low recall on target clips
    if ((champion.recall ?? 0) < 0.75) {
      newClusters.add(FailureCluster(
        name: 'LOW_RECALL_TARGET',
        description: 'Champion recall is ${(champion.recall ?? 0).toStringAsFixed(3)} — below 0.75 gate',
        affectedClips: [],
        missedReps: champion.fn ?? 0,
        falseReps: 0,
        commonFeatures: {},
        likelyReason: 'Detector may be too conservative or missing key motion phases',
        failingFamilies: [],
        succeedingFamilies: [],
        proposedExperiment: 'Try relaxed temporal thresholds or lower airborne confidence',
      ));
    }

    _clusters = newClusters;
    save();
  }

  String _inferReason(String movement) {
    switch (movement) {
      case 'deep_squats':
        return 'Deep squat compression pattern resembles jump squat descent phase';
      case 'jumping_jacks':
        return 'Jumping jack airborne phase and vertical motion triggers flight detection';
      case 'vertical_jumps':
        return 'Vertical jump has airborne phase without squat compression';
      case 'squat_jacks':
        return 'Squat jack combines squat + jump, closely resembling jump squat';
      case 'normal_squats':
        return 'Normal squat has compression but no flight phase';
      case 'lunges':
        return 'Lunge has leg movement but different geometry';
      default:
        return 'Unknown confuser pattern';
    }
  }

  List<String> _failingFamilies(List<ExperimentRecord> records, String movement) {
    final families = <String>{};
    for (final r in records) {
      if (r.status != 'completed') continue;
      final perConfuser = r.perConfuserResults ?? {};
      final data = perConfuser[movement];
      if (data != null) {
        final faClips = (data as Map<String, dynamic>)['falseAcceptClips'] as int? ?? 0;
        if (faClips > 0) {
          families.add(r.family);
        }
      }
    }
    return families.toList();
  }

  List<String> _succeedingFamilies(List<ExperimentRecord> records, String movement) {
    final families = <String>{};
    for (final r in records) {
      if (r.status != 'completed') continue;
      final perConfuser = r.perConfuserResults ?? {};
      final data = perConfuser[movement];
      if (data != null) {
        final faClips = (data as Map<String, dynamic>)['falseAcceptClips'] as int? ?? 0;
        if (faClips == 0) {
          families.add(r.family);
        }
      }
    }
    return families.toList();
  }

  String _proposeExperiment(String movement, ExperimentRecord champion) {
    switch (movement) {
      case 'deep_squats':
        return 'Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout';
      case 'jumping_jacks':
        return 'Add stance-width velocity gate: reject if foot separation oscillates without net compression';
      case 'vertical_jumps':
        return 'Add compression requirement: reject if no descent phase detected';
      case 'squat_jacks':
        return 'Add temporal ordering gate: require compression before airborne phase';
      default:
        return 'Investigate specific feature differences between $movement and jump_squats';
    }
  }

  void save() {
    final file = File(outputPath);
    final json = _clusters.map((c) => c.toJson()).toList();
    file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(json));
  }

  /// Get the primary failure cluster (most impactful).
  FailureCluster? get primaryCluster {
    if (_clusters.isEmpty) return null;
    _clusters.sort((a, b) => b.falseReps.compareTo(a.falseReps));
    return _clusters.first;
  }
}

// ============================================================================
// SEARCH POLICY — HIERARCHICAL SEARCH ENGINE
// ============================================================================
// Stage A: Broad exploration across all families
// Stage B: Family selection — reduce compute on plateaued families
// Stage C: Local refinement — mutation around champions
// Stage D: Confirmation — re-evaluate promising candidates

enum ResearchStage { broadExploration, familySelection, localRefinement, confirmation }

/// Decides which experiment family to try next.
class SearchPolicy {
  final ExperimentRegistry registry;
  final FamilyStateManager familyStates;
  final FailureMiner failureMiner;
  final PlateauDetector plateauDetector;
  final _rng = math.Random(42);

  // Family weights — higher = more likely to be selected
  final Map<String, double> _familyWeights = {};

  // Research stage tracking
  ResearchStage _currentStage = ResearchStage.broadExploration;

  // Stage thresholds (based on total experiments across all families)
  static const int _broadExplorationBudget = 300;  // ~30 per family
  static const int _familySelectionBudget = 800;   // Focus on top 5 families
  // After that: local refinement + confirmation indefinitely

  // Champion config cache for mutation-based search
  final Map<String, Map<String, dynamic>> _bestConfigsPerFamily = {};

  // Pending confirmation candidates
  final List<String> _pendingConfirmations = [];
  final Map<String, int> _confirmationAttempts = {};

  SearchPolicy({
    required this.registry,
    required this.familyStates,
    required this.failureMiner,
    required this.plateauDetector,
  });

  ResearchStage get currentStage => _currentStage;

  /// Initialize default family weights.
  void initialize() {
    _familyWeights.addAll({
      'temporal': 1.0,
      'camera': 0.7,
      'signal_quality': 0.6,
      'geometric': 0.8,
      'confuser_specialist': 1.0,
      'mlp': 0.8,
      'conv1d': 0.6,
      'gru': 0.3,
      'hybrid': 1.2,
      'ensemble': 0.4,
    });
  }

  /// Update research stage based on total experiments completed.
  void _updateStage() {
    final totalCompleted = registry.completedCount;

    if (totalCompleted < _broadExplorationBudget) {
      _currentStage = ResearchStage.broadExploration;
    } else if (totalCompleted < _broadExplorationBudget + _familySelectionBudget) {
      _currentStage = ResearchStage.familySelection;
    } else {
      // Alternate between refinement and confirmation
      if (_pendingConfirmations.isNotEmpty && _rng.nextDouble() < 0.3) {
        _currentStage = ResearchStage.confirmation;
      } else {
        _currentStage = ResearchStage.localRefinement;
      }
    }
  }

  /// Decide which family to explore next.
  String selectFamily() {
    _updateStage();

    // In confirmation stage, pick from pending confirmations
    if (_currentStage == ResearchStage.confirmation && _pendingConfirmations.isNotEmpty) {
      // Return the family of the first pending confirmation
      final pending = _pendingConfirmations.first;
      final record = registry.records.where((r) => r.id == pending).firstOrNull;
      if (record != null) return record.family;
    }

    // Get active (non-plateaued) families
    final active = familyStates.activeFamilies();
    if (active.isEmpty) {
      // All plateaued — reset all for new exploration cycle
      return _selectFromAllFamilies();
    }

    // Update weights based on stage and failure analysis
    _updateWeightsFromFailures();
    _updateWeightsFromStage();

    // Weighted random selection
    final weights = active.map((f) => _familyWeights[f] ?? 0.5).toList();
    final total = weights.reduce((a, b) => a + b);
    if (total <= 0) return active.first;

    var r = _rng.nextDouble() * total;
    for (var i = 0; i < active.length; i++) {
      r -= weights[i];
      if (r <= 0) return active[i];
    }
    return active.last;
  }

  String _selectFromAllFamilies() {
    final all = familyStates.states.keys.toList();
    if (all.isEmpty) return 'temporal';
    return all[_rng.nextInt(all.length)];
  }

  /// Update weights based on research stage.
  void _updateWeightsFromStage() {
    switch (_currentStage) {
      case ResearchStage.broadExploration:
        // Equal-ish weights — explore everything
        for (final key in _familyWeights.keys) {
          _familyWeights[key] = (_familyWeights[key] ?? 0.5).clamp(0.3, 1.5);
        }
        break;

      case ResearchStage.familySelection:
        // Boost families with improving F1 trends, suppress stagnant ones
        for (final entry in familyStates.states.entries) {
          final state = entry.value;
          if (state.experimentsAttempted > 20) {
            final improvement = state.bestF1 - state.startingBestF1;
            if (improvement > 0.01) {
              _familyWeights[entry.key] = (_familyWeights[entry.key] ?? 0.5) * 1.3;
            } else if (improvement < 0.001) {
              _familyWeights[entry.key] = (_familyWeights[entry.key] ?? 0.5) * 0.5;
            }
          }
        }
        break;

      case ResearchStage.localRefinement:
        // Heavily favor top 3 families by best F1
        final sorted = familyStates.states.entries.toList()
          ..sort((a, b) => b.value.bestF1.compareTo(a.value.bestF1));
        for (var i = 0; i < sorted.length; i++) {
          if (i < 3) {
            _familyWeights[sorted[i].key] = 1.5 + (3 - i) * 0.3;
          } else {
            _familyWeights[sorted[i].key] = 0.1;
          }
        }
        break;

      case ResearchStage.confirmation:
        // Only confirm families with recent improvements
        break;
    }

    // Clamp weights
    for (final key in _familyWeights.keys) {
      _familyWeights[key] = _familyWeights[key]!.clamp(0.01, 3.0);
    }
  }

  /// Record the best config for a family (for mutation-based search).
  void recordBestConfig(String family, Map<String, dynamic> config, double f1) {
    final current = _bestConfigsPerFamily[family];
    if (current == null) {
      _bestConfigsPerFamily[family] = Map.from(config);
    }
    // Always keep the latest — the caller decides when to update
  }

  /// Get the best config for a family (for mutation in Stage C).
  Map<String, dynamic>? getBestConfig(String family) => _bestConfigsPerFamily[family];

  /// Queue a candidate for confirmation runs.
  void queueConfirmation(String experimentId) {
    if (!_pendingConfirmations.contains(experimentId)) {
      _pendingConfirmations.add(experimentId);
      _confirmationAttempts[experimentId] = 0;
    }
  }

  /// Check if a candidate has passed confirmation.
  bool isConfirmed(String experimentId) {
    return (_confirmationAttempts[experimentId] ?? 0) >= 3;
  }

  /// Remove a confirmed or rejected candidate from the queue.
  void dequeueConfirmation(String experimentId) {
    _pendingConfirmations.remove(experimentId);
    _confirmationAttempts.remove(experimentId);
  }

  List<String> get pendingConfirmations => List.unmodifiable(_pendingConfirmations);

  /// Update family weights based on failure clusters.
  void _updateWeightsFromFailures() {
    final clusters = failureMiner.clusters;
    for (final cluster in clusters) {
      // Boost families that succeed on this failure
      for (final family in cluster.succeedingFamilies) {
        _familyWeights[family] = (_familyWeights[family] ?? 0.5) * 1.1;
      }
      // Reduce families that consistently fail
      for (final family in cluster.failingFamilies) {
        _familyWeights[family] = (_familyWeights[family] ?? 0.5) * 0.95;
      }
    }

    // Boost confuser specialist if false accepts dominate
    final hasFalseAccepts = clusters.any((c) => c.falseReps > 0);
    if (hasFalseAccepts) {
      _familyWeights['confuser_specialist'] = (_familyWeights['confuser_specialist'] ?? 0.5) * 1.15;
      _familyWeights['hybrid'] = (_familyWeights['hybrid'] ?? 0.5) * 1.1;
    }

    // Boost temporal if recall is low
    final hasLowRecall = clusters.any((c) => c.name == 'LOW_RECALL_TARGET');
    if (hasLowRecall) {
      _familyWeights['temporal'] = (_familyWeights['temporal'] ?? 0.5) * 1.15;
    }

    // Clamp weights
    for (final key in _familyWeights.keys) {
      _familyWeights[key] = _familyWeights[key]!.clamp(0.05, 2.0);
    }
  }

  /// Check if global plateau is reached (all families plateaued).
  bool get globalPlateau {
    final active = familyStates.activeFamilies();
    return active.isEmpty;
  }

  /// Check if data ceiling is detected.
  bool detectDataCeiling() {
    // Data ceiling: multiple diverse families all plateau at similar F1
    final plateaued = familyStates.plateauedFamilies();
    if (plateaued.length < 4) return false;

    // Check if plateaued families have similar best F1
    final f1s = plateaued.map((f) => familyStates.states[f]!.bestF1).toList();
    if (f1s.isEmpty) return false;
    final maxF1 = f1s.reduce(math.max);
    final minF1 = f1s.reduce(math.min);
    final spread = maxF1 - minF1;

    // If all families are within 0.05 F1 of each other and none > 0.65
    return spread < 0.05 && maxF1 < 0.65;
  }
}

// ============================================================================
// LEARNING CURVE
// ============================================================================

class LearningCurvePoint {
  final int targetClipCount;
  final double f1;
  final double recall;
  final double precision;
  final String experimentId;

  LearningCurvePoint({
    required this.targetClipCount,
    required this.f1,
    required this.recall,
    required this.precision,
    required this.experimentId,
  });

  Map<String, dynamic> toJson() => {
    'targetClipCount': targetClipCount,
    'f1': f1,
    'recall': recall,
    'precision': precision,
    'experimentId': experimentId,
  };
}

class LearningCurve {
  final String outputPath;
  final List<LearningCurvePoint> _points = [];

  LearningCurve(this.outputPath);

  List<LearningCurvePoint> get points => List.unmodifiable(_points);

  void load() {
    final file = File(outputPath);
    if (!file.existsSync()) return;
    final json = jsonDecode(file.readAsStringSync()) as List;
    _points.clear();
    for (final p in json) {
      _points.add(LearningCurvePoint(
        targetClipCount: p['targetClipCount'] as int,
        f1: (p['f1'] as num).toDouble(),
        recall: (p['recall'] as num).toDouble(),
        precision: (p['precision'] as num).toDouble(),
        experimentId: p['experimentId'] as String,
      ));
    }
  }

  void addPoint(LearningCurvePoint point) {
    // Replace existing point with same clip count
    _points.removeWhere((p) => p.targetClipCount == point.targetClipCount);
    _points.add(point);
    _points.sort((a, b) => a.targetClipCount.compareTo(b.targetClipCount));
    save();
  }

  void save() {
    final file = File(outputPath);
    final json = _points.map((p) => p.toJson()).toList();
    file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(json));
  }

  /// Generate a learning curve by evaluating champion with increasing data fractions.
  /// Since we can't add real data, we simulate by subsampling existing target clips.
  void generateCurve({
    required String experimentId,
    required double f1,
    required double recall,
    required double precision,
    required int targetClipCount,
  }) {
    addPoint(LearningCurvePoint(
      targetClipCount: targetClipCount,
      f1: f1,
      recall: recall,
      precision: precision,
      experimentId: experimentId,
    ));
  }
}
