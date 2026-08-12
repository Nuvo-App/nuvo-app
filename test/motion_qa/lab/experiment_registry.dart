import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

// ============================================================================
// M1.3 EXPERIMENT REGISTRY
// ============================================================================
// Append-only JSONL experiment log with resumability.
// Each experiment gets a unique immutable ID (EXP-NNNNNN).
// ============================================================================

class ExperimentRecord {
  final String id;
  final DateTime timestamp;
  final String family;
  final String candidateName;
  final String? parentExperimentId;
  final String hypothesis;
  final Map<String, dynamic> config;
  final String datasetVersion;
  final String splitUsed;
  final int? randomSeed;
  final String? featureSet;
  final int? temporalWindow;
  final int? modelParams;
  final double? threshold;
  final Duration? trainDuration;
  final Duration? evalDuration;

  // Metrics (from canonical evaluator)
  final int? tp;
  final int? fn;
  final int? fp;
  final double? recall;
  final double? precision;
  final double? f1;
  final double? exactCountRate;
  final double? falseAcceptClipRate;
  final int? catastrophicClips;
  final double? productScore;
  final String? gateResult;
  final Map<String, dynamic>? perConfuserResults;
  final String? failureSummary;
  final String? championComparison;

  // Status
  final String status; // 'completed', 'failed', 'skipped'
  final String? error;

  ExperimentRecord({
    required this.id,
    required this.timestamp,
    required this.family,
    required this.candidateName,
    this.parentExperimentId,
    required this.hypothesis,
    required this.config,
    required this.datasetVersion,
    this.splitUsed = 'dev',
    this.randomSeed,
    this.featureSet,
    this.temporalWindow,
    this.modelParams,
    this.threshold,
    this.trainDuration,
    this.evalDuration,
    this.tp,
    this.fn,
    this.fp,
    this.recall,
    this.precision,
    this.f1,
    this.exactCountRate,
    this.falseAcceptClipRate,
    this.catastrophicClips,
    this.productScore,
    this.gateResult,
    this.perConfuserResults,
    this.failureSummary,
    this.championComparison,
    required this.status,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'family': family,
    'candidateName': candidateName,
    'parentExperimentId': parentExperimentId,
    'hypothesis': hypothesis,
    'config': config,
    'datasetVersion': datasetVersion,
    'splitUsed': splitUsed,
    'randomSeed': randomSeed,
    'featureSet': featureSet,
    'temporalWindow': temporalWindow,
    'modelParams': modelParams,
    'threshold': threshold,
    'trainDurationMs': trainDuration?.inMilliseconds,
    'evalDurationMs': evalDuration?.inMilliseconds,
    'tp': tp,
    'fn': fn,
    'fp': fp,
    'recall': recall,
    'precision': precision,
    'f1': f1,
    'exactCountRate': exactCountRate,
    'falseAcceptClipRate': falseAcceptClipRate,
    'catastrophicClips': catastrophicClips,
    'productScore': productScore,
    'gateResult': gateResult,
    'perConfuserResults': perConfuserResults,
    'failureSummary': failureSummary,
    'championComparison': championComparison,
    'status': status,
    'error': error,
  };

  factory ExperimentRecord.fromJson(Map<String, dynamic> json) {
    return ExperimentRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      family: json['family'] as String,
      candidateName: json['candidateName'] as String,
      parentExperimentId: json['parentExperimentId'] as String?,
      hypothesis: json['hypothesis'] as String,
      config: json['config'] as Map<String, dynamic>,
      datasetVersion: json['datasetVersion'] as String,
      splitUsed: json['splitUsed'] as String? ?? 'dev',
      randomSeed: json['randomSeed'] as int?,
      featureSet: json['featureSet'] as String?,
      temporalWindow: json['temporalWindow'] as int?,
      modelParams: json['modelParams'] as int?,
      threshold: (json['threshold'] as num?)?.toDouble(),
      trainDuration: json['trainDurationMs'] != null
          ? Duration(milliseconds: json['trainDurationMs'] as int)
          : null,
      evalDuration: json['evalDurationMs'] != null
          ? Duration(milliseconds: json['evalDurationMs'] as int)
          : null,
      tp: json['tp'] as int?,
      fn: json['fn'] as int?,
      fp: json['fp'] as int?,
      recall: (json['recall'] as num?)?.toDouble(),
      precision: (json['precision'] as num?)?.toDouble(),
      f1: (json['f1'] as num?)?.toDouble(),
      exactCountRate: (json['exactCountRate'] as num?)?.toDouble(),
      falseAcceptClipRate: (json['falseAcceptClipRate'] as num?)?.toDouble(),
      catastrophicClips: json['catastrophicClips'] as int?,
      productScore: (json['productScore'] as num?)?.toDouble(),
      gateResult: json['gateResult'] as String?,
      perConfuserResults: json['perConfuserResults'] as Map<String, dynamic>?,
      failureSummary: json['failureSummary'] as String?,
      championComparison: json['championComparison'] as String?,
      status: json['status'] as String,
      error: json['error'] as String?,
    );
  }
}

class ExperimentRegistry {
  final String jsonlPath;
  final List<ExperimentRecord> _records = [];
  int _nextId = 0;

  ExperimentRegistry(this.jsonlPath);

  List<ExperimentRecord> get records => List.unmodifiable(_records);
  int get count => _records.length;
  int get completedCount => _records.where((r) => r.status == 'completed').length;
  int get failedCount => _records.where((r) => r.status == 'failed').length;

  /// Load existing records from JSONL file. Creates file if not exists.
  void load() {
    final file = File(jsonlPath);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      return;
    }

    final lines = file.readAsLinesSync();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final record = ExperimentRecord.fromJson(json);
        _records.add(record);
        // Extract numeric part of ID for next counter
        final idNum = int.tryParse(record.id.replaceAll('EXP-', ''));
        if (idNum != null && idNum >= _nextId) {
          _nextId = idNum + 1;
        }
      } catch (e) {
        // Skip malformed lines but log
        stderr.writeln('WARNING: Skipping malformed experiment line: $e');
      }
    }
  }

  /// Create a new experiment ID.
  String nextId() {
    final id = 'EXP-${_nextId.toString().padLeft(6, '0')}';
    _nextId++;
    return id;
  }

  /// Append a record to the JSONL file and in-memory list.
  void append(ExperimentRecord record) {
    _records.add(record);
    final file = File(jsonlPath);
    file.writeAsStringSync('${jsonEncode(record.toJson())}\n', mode: FileMode.append);
  }

  /// Get all completed experiments for a given family.
  List<ExperimentRecord> familyRecords(String family) {
    return _records.where((r) => r.family == family && r.status == 'completed').toList();
  }

  /// Get all completed experiments sorted by F1 descending.
  List<ExperimentRecord> sortedByF1() {
    final completed = _records.where((r) => r.status == 'completed').toList();
    completed.sort((a, b) => (b.f1 ?? 0).compareTo(a.f1 ?? 0));
    return completed;
  }

  /// Best F1 for a family.
  double bestF1ForFamily(String family) {
    final records = familyRecords(family);
    if (records.isEmpty) return 0.0;
    return records.map((r) => r.f1 ?? 0).reduce(math.max);
  }

  /// Best F1 overall.
  double get bestF1 {
    final completed = _records.where((r) => r.status == 'completed').toList();
    if (completed.isEmpty) return 0.0;
    return completed.map((r) => r.f1 ?? 0).reduce(math.max);
  }

  /// Best record overall.
  ExperimentRecord? get bestRecord {
    final sorted = sortedByF1();
    return sorted.isEmpty ? null : sorted.first;
  }

  /// Recent N experiments for a family.
  List<ExperimentRecord> recentFamilyRecords(String family, int n) {
    final records = familyRecords(family);
    if (records.length <= n) return records;
    return records.sublist(records.length - n);
  }
}

// ============================================================================
// CHAMPION MANAGER
// ============================================================================

class ChampionRecord {
  final String experimentId;
  final String candidateName;
  final String family;
  final String architecture;
  final Map<String, dynamic> config;
  final String datasetVersion;
  final double recall;
  final double precision;
  final double f1;
  final double falseAcceptClipRate;
  final double exactCountRate;
  final double productScore;
  final int? modelParams;
  final String gateResult;
  final String sourceCommit;
  final DateTime timestamp;
  final int? catastrophicClips;
  String? promotionReason;
  int confirmedRuns;
  Map<String, double>? holdoutMetrics;

  ChampionRecord({
    required this.experimentId,
    required this.candidateName,
    required this.family,
    required this.architecture,
    required this.config,
    required this.datasetVersion,
    required this.recall,
    required this.precision,
    required this.f1,
    required this.falseAcceptClipRate,
    required this.exactCountRate,
    required this.productScore,
    this.modelParams,
    required this.gateResult,
    required this.sourceCommit,
    required this.timestamp,
    this.catastrophicClips,
    this.promotionReason,
    this.confirmedRuns = 0,
    this.holdoutMetrics,
  });

  Map<String, dynamic> toJson() => {
    'experimentId': experimentId,
    'candidateName': candidateName,
    'family': family,
    'architecture': architecture,
    'config': config,
    'datasetVersion': datasetVersion,
    'recall': recall,
    'precision': precision,
    'f1': f1,
    'falseAcceptClipRate': falseAcceptClipRate,
    'exactCountRate': exactCountRate,
    'productScore': productScore,
    'modelParams': modelParams,
    'gateResult': gateResult,
    'sourceCommit': sourceCommit,
    'timestamp': timestamp.toIso8601String(),
    'catastrophicClips': catastrophicClips,
    'promotionReason': promotionReason,
    'confirmedRuns': confirmedRuns,
    'holdoutMetrics': holdoutMetrics,
  };

  factory ChampionRecord.fromJson(Map<String, dynamic> json) {
    return ChampionRecord(
      experimentId: json['experimentId'] as String,
      candidateName: json['candidateName'] as String,
      family: json['family'] as String,
      architecture: json['architecture'] as String,
      config: json['config'] as Map<String, dynamic>,
      datasetVersion: json['datasetVersion'] as String,
      recall: (json['recall'] as num).toDouble(),
      precision: (json['precision'] as num).toDouble(),
      f1: (json['f1'] as num).toDouble(),
      falseAcceptClipRate: (json['falseAcceptClipRate'] as num).toDouble(),
      exactCountRate: (json['exactCountRate'] as num).toDouble(),
      productScore: (json['productScore'] as num).toDouble(),
      modelParams: json['modelParams'] as int?,
      gateResult: json['gateResult'] as String,
      sourceCommit: json['sourceCommit'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      catastrophicClips: json['catastrophicClips'] as int?,
      promotionReason: json['promotionReason'] as String?,
      confirmedRuns: json['confirmedRuns'] as int? ?? 0,
      holdoutMetrics: json['holdoutMetrics'] as Map<String, double>?,
    );
  }

  static ChampionRecord? fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ChampionRecord.fromJson(json);
  }

  void save(String path) {
    final file = File(path);
    file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(toJson()));
  }
}

class ChampionManager {
  final String championPath;
  ChampionRecord? _champion;
  final List<ChampionRecord> _history = [];

  ChampionManager(this.championPath);

  ChampionRecord? get champion => _champion;
  List<ChampionRecord> get history => List.unmodifiable(_history);
  int get championChanges => _history.length;

  void load() {
    _champion = ChampionRecord.fromFile(championPath);
    if (_champion != null) {
      _history.add(_champion!);
    }
  }

  /// Save current champion state (for updated fields like holdoutMetrics).
  void save() {
    _champion?.save(championPath);
  }

  /// Try to promote a challenger. Returns true if champion changed.
  /// Conservative promotion: requires meaningful F1 improvement and no regressions.
  bool tryPromote(ChampionRecord challenger) {
    if (_champion == null) {
      _champion = challenger;
      _history.add(challenger);
      challenger.promotionReason = 'Initial champion (no prior champion to compare)';
      challenger.save(championPath);
      return true;
    }

    final currentF1 = _champion!.f1;
    final challengerF1 = challenger.f1;

    // Require meaningful F1 improvement (at least 0.005)
    final f1Delta = challengerF1 - currentF1;
    if (f1Delta < 0.005) return false;

    // Reject if recall drops catastrophically (> 0.10 absolute)
    final recallDelta = challenger.recall - _champion!.recall;
    if (recallDelta < -0.10) return false;

    // Reject if false-accept rate increases significantly (> 0.05 absolute)
    final faDelta = challenger.falseAcceptClipRate - _champion!.falseAcceptClipRate;
    if (faDelta > 0.05) return false;

    // Promote with documented reason
    challenger.promotionReason =
        'F1: ${currentF1.toStringAsFixed(4)} → ${challengerF1.toStringAsFixed(4)} '
        '(+${f1Delta.toStringAsFixed(4)}), '
        'Recall: ${_champion!.recall.toStringAsFixed(4)} → ${challenger.recall.toStringAsFixed(4)}, '
        'Precision: ${_champion!.precision.toStringAsFixed(4)} → ${challenger.precision.toStringAsFixed(4)}, '
        'FA clip rate: ${_champion!.falseAcceptClipRate.toStringAsFixed(3)} → ${challenger.falseAcceptClipRate.toStringAsFixed(3)}';

    _champion = challenger;
    _history.add(challenger);
    challenger.save(championPath);
    return true;
  }
}

// ============================================================================
// PLATEAU DETECTOR
// ============================================================================

class FamilyState {
  final String family;
  int experimentsAttempted;
  double bestF1;
  double startingBestF1;
  bool plateaued;
  DateTime? plateauedAt;
  int? plateauedAtCount;
  String? plateauReason;
  double totalRuntimeMs;
  int consecutiveFailures;

  FamilyState({
    required this.family,
    this.experimentsAttempted = 0,
    this.bestF1 = 0.0,
    this.startingBestF1 = 0.0,
    this.plateaued = false,
    this.plateauedAt,
    this.plateauedAtCount,
    this.plateauReason,
    this.totalRuntimeMs = 0.0,
    this.consecutiveFailures = 0,
  });

  Map<String, dynamic> toJson() => {
    'family': family,
    'experimentsAttempted': experimentsAttempted,
    'bestF1': bestF1,
    'startingBestF1': startingBestF1,
    'plateaued': plateaued,
    'plateauedAt': plateauedAt?.toIso8601String(),
    'plateauedAtCount': plateauedAtCount,
    'plateauReason': plateauReason,
    'totalRuntimeMs': totalRuntimeMs,
    'consecutiveFailures': consecutiveFailures,
  };

  factory FamilyState.fromJson(Map<String, dynamic> json) {
    return FamilyState(
      family: json['family'] as String,
      experimentsAttempted: json['experimentsAttempted'] as int? ?? 0,
      bestF1: (json['bestF1'] as num?)?.toDouble() ?? 0.0,
      startingBestF1: (json['startingBestF1'] as num?)?.toDouble() ?? 0.0,
      plateaued: json['plateaued'] as bool? ?? false,
      plateauedAt: json['plateauedAt'] != null
          ? DateTime.parse(json['plateauedAt'] as String)
          : null,
      plateauedAtCount: json['plateauedAtCount'] as int?,
      plateauReason: json['plateauReason'] as String?,
      totalRuntimeMs: (json['totalRuntimeMs'] as num?)?.toDouble() ?? 0.0,
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
    );
  }
}

class PlateauDetector {
  final int plateauWindow;
  final double minImprovement;

  PlateauDetector({
    this.plateauWindow = 40,
    this.minImprovement = 0.005,
  });

  /// Check if a family has plateaued.
  bool checkPlateau(FamilyState state, List<ExperimentRecord> familyRecords) {
    if (state.plateaued) return true;
    if (familyRecords.length < plateauWindow) return false;

    // Get the best F1 from experiments before the plateau window
    final earlier = familyRecords.length > plateauWindow
        ? familyRecords.sublist(0, familyRecords.length - plateauWindow)
        : <ExperimentRecord>[];
    final recent = familyRecords.sublist(familyRecords.length - plateauWindow);

    final earlierBest = earlier.isEmpty
        ? 0.0
        : earlier.map((r) => r.f1 ?? 0).reduce(math.max);
    final recentBest = recent.map((r) => r.f1 ?? 0).reduce(math.max);

    final improvement = recentBest - earlierBest;

    if (improvement < minImprovement) {
      state.plateaued = true;
      state.plateauedAt = DateTime.now();
      state.plateauedAtCount = state.experimentsAttempted;
      state.plateauReason =
          'No improvement > $minImprovement in last $plateauWindow experiments. '
          'Earlier best: ${earlierBest.toStringAsFixed(4)}, '
          'Recent best: ${recentBest.toStringAsFixed(4)}, '
          'Improvement: ${improvement.toStringAsFixed(4)}';
      return true;
    }

    return false;
  }
}

// ============================================================================
// FAMILY STATE MANAGER
// ============================================================================

class FamilyStateManager {
  final String statePath;
  final Map<String, FamilyState> _states = {};

  FamilyStateManager(this.statePath);

  Map<String, FamilyState> get states => Map.unmodifiable(_states);

  void load() {
    final file = File(statePath);
    if (!file.existsSync()) return;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in json.entries) {
      _states[entry.key] = FamilyState.fromJson(entry.value as Map<String, dynamic>);
    }
  }

  void save() {
    final file = File(statePath);
    final map = <String, dynamic>{};
    for (final entry in _states.entries) {
      map[entry.key] = entry.value.toJson();
    }
    file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(map));
  }

  FamilyState getOrCreate(String family) {
    return _states.putIfAbsent(family, () => FamilyState(family: family));
  }

  void recordExperiment(String family, double f1, double runtimeMs, bool failed) {
    final state = getOrCreate(family);
    state.experimentsAttempted++;
    state.totalRuntimeMs += runtimeMs;
    if (failed) {
      state.consecutiveFailures++;
    } else {
      state.consecutiveFailures = 0;
      if (f1 > state.bestF1) {
        state.bestF1 = f1;
      }
    }
  }

  List<String> activeFamilies() {
    return _states.entries
        .where((e) => !e.value.plateaued)
        .map((e) => e.key)
        .toList();
  }

  List<String> plateauedFamilies() {
    return _states.entries
        .where((e) => e.value.plateaued)
        .map((e) => e.key)
        .toList();
  }
}
