import 'dart:math' as math;

import 'experiment_registry.dart';
import 'search_policy.dart';

// ============================================================================
// M1.3 EXPERIMENT FAMILIES
// ============================================================================
// Each family generates candidate configurations for the search policy.
// ============================================================================

/// A proposed experiment with its candidate and metadata.
class ProposedExperiment {
  final String family;
  final String candidateName;
  final String hypothesis;
  final Map<String, dynamic> config;
  final String? parentExperimentId;
  final int? randomSeed;
  final String? featureSet;
  final int? temporalWindow;
  final int? modelParams;
  final double? threshold;

  ProposedExperiment({
    required this.family,
    required this.candidateName,
    required this.hypothesis,
    required this.config,
    this.parentExperimentId,
    this.randomSeed,
    this.featureSet,
    this.temporalWindow,
    this.modelParams,
    this.threshold,
  });
}

/// Base class for experiment family generators.
abstract class ExperimentFamily {
  final String name;
  final _rng = math.Random();

  ExperimentFamily(this.name);

  /// Generate the next experiment configuration.
  /// [history] is the list of previous experiments in this family.
  /// [failureClusters] provides failure context.
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  });

  /// Whether this family has more configurations to explore.
  bool hasMoreConfigurations(List<ExperimentRecord> history);
}

// ---------------------------------------------------------------------------
// A. TEMPORAL FAMILY
// ---------------------------------------------------------------------------

class TemporalFamily extends ExperimentFamily {
  TemporalFamily() : super('temporal');

  final _configs = <Map<String, dynamic>>[
    {'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3},
    {'airborneThreshold': 0.10, 'hysteresis': 0.06, 'minRepGap': 10, 'persistence': 4},
    {'airborneThreshold': 0.15, 'hysteresis': 0.03, 'minRepGap': 6, 'persistence': 2},
    {'airborneThreshold': 0.08, 'hysteresis': 0.05, 'minRepGap': 12, 'persistence': 5},
    {'airborneThreshold': 0.20, 'hysteresis': 0.08, 'minRepGap': 8, 'persistence': 3},
    {'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3, 'nOfM': 3},
    {'airborneThreshold': 0.10, 'hysteresis': 0.04, 'minRepGap': 10, 'persistence': 3, 'nOfM': 5},
    {'airborneThreshold': 0.15, 'hysteresis': 0.05, 'minRepGap': 6, 'persistence': 2, 'adaptiveThreshold': true},
    {'airborneThreshold': 0.12, 'hysteresis': 0.06, 'minRepGap': 8, 'persistence': 4, 'phaseTransitionStrict': true},
    {'airborneThreshold': 0.10, 'hysteresis': 0.03, 'minRepGap': 8, 'persistence': 3, 'velocityGate': true},
    {'airborneThreshold': 0.12, 'hysteresis': 0.04, 'minRepGap': 8, 'persistence': 3, 'accelGate': true},
    {'airborneThreshold': 0.08, 'hysteresis': 0.02, 'minRepGap': 15, 'persistence': 5, 'dropoutTolerance': 3},
    {'airborneThreshold': 0.14, 'hysteresis': 0.05, 'minRepGap': 7, 'persistence': 3, 'rearmDelay': 5},
    {'airborneThreshold': 0.11, 'hysteresis': 0.04, 'minRepGap': 9, 'persistence': 4, 'compressionAscentTiming': true},
    {'airborneThreshold': 0.13, 'hysteresis': 0.05, 'minRepGap': 8, 'persistence': 3, 'landingConfirm': true},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      // Generate randomized novel configs after grid exhaustion
      final airborne = 0.06 + _rng.nextDouble() * 0.16; // 0.06–0.22
      final hyst = 0.02 + _rng.nextDouble() * 0.08; // 0.02–0.10
      final gap = 5 + _rng.nextInt(12); // 5–16
      final persist = 1 + _rng.nextInt(6); // 1–6
      config = {
        'airborneThreshold': double.parse(airborne.toStringAsFixed(4)),
        'hysteresis': double.parse(hyst.toStringAsFixed(4)),
        'minRepGap': gap,
        'persistence': persist,
      };
      // Randomly add gates
      if (_rng.nextBool()) config['nOfM'] = 2 + _rng.nextInt(5);
      if (_rng.nextBool()) config['velocityGate'] = true;
      if (_rng.nextBool()) config['accelGate'] = true;
      if (_rng.nextBool()) config['adaptiveThreshold'] = true;
      version = _index + 1;
      _index++;
    }

    // If failure clusters suggest low recall, try lower thresholds
    if (failureClusters.any((c) => c.name == 'LOW_RECALL_TARGET')) {
      config['airborneThreshold'] = (config['airborneThreshold'] as double) * 0.8;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'temporal_v$version',
      hypothesis: 'Temporal config: airborne=${config['airborneThreshold']}, '
          'hyst=${config['hysteresis']}, gap=${config['minRepGap']}, persist=${config['persistence']}',
      config: config,
      temporalWindow: null,
    );
  }
}

// ---------------------------------------------------------------------------
// B. CAMERA-RELATIVE FAMILY
// ---------------------------------------------------------------------------

class CameraFamily extends ExperimentFamily {
  CameraFamily() : super('camera');

  final _configs = <Map<String, dynamic>>[
    {'mode': 'torso_relative', 'referencePoint': 'midHip'},
    {'mode': 'torso_relative', 'referencePoint': 'midShoulder'},
    {'mode': 'hip_relative_ankle', 'smoothing': 3},
    {'mode': 'hip_relative_ankle', 'smoothing': 5},
    {'mode': 'shoulder_hip_consensus', 'threshold': 0.7},
    {'mode': 'shoulder_hip_consensus', 'threshold': 0.5},
    {'mode': 'translation_compensation', 'windowSize': 10},
    {'mode': 'translation_compensation', 'windowSize': 20},
    {'mode': 'camera_contamination_reject', 'motionThreshold': 0.05},
    {'mode': 'camera_contamination_reject', 'motionThreshold': 0.10},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final modes = ['torso_relative', 'hip_relative_ankle', 'shoulder_hip_consensus',
                     'translation_compensation', 'camera_contamination_reject'];
      final mode = modes[_rng.nextInt(modes.length)];
      config = {
        'mode': mode,
        'airborneThreshold': double.parse((0.08 + _rng.nextDouble() * 0.12).toStringAsFixed(4)),
      };
      if (mode == 'hip_relative_ankle') config['smoothing'] = 1 + _rng.nextInt(8);
      if (mode == 'shoulder_hip_consensus') config['threshold'] = double.parse((0.3 + _rng.nextDouble() * 0.5).toStringAsFixed(4));
      if (mode == 'translation_compensation') config['windowSize'] = 5 + _rng.nextInt(25);
      if (mode == 'camera_contamination_reject') config['motionThreshold'] = double.parse((0.02 + _rng.nextDouble() * 0.10).toStringAsFixed(4));
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'camera_${config['mode']}_v$version',
      hypothesis: 'Camera-relative: ${config['mode']} with ${config.toString()}',
      config: config,
    );
  }
}

// ---------------------------------------------------------------------------
// C. SIGNAL QUALITY FAMILY
// ---------------------------------------------------------------------------

class SignalQualityFamily extends ExperimentFamily {
  SignalQualityFamily() : super('signal_quality');

  final _configs = <Map<String, dynamic>>[
    {'smoothing': 'mean', 'window': 3, 'confidenceWeight': true},
    {'smoothing': 'mean', 'window': 5, 'confidenceWeight': true},
    {'smoothing': 'median', 'window': 3, 'confidenceWeight': false},
    {'smoothing': 'median', 'window': 5, 'confidenceWeight': true},
    {'outlierRejection': true, 'threshold': 2.0, 'smoothing': 'mean', 'window': 3},
    {'outlierRejection': true, 'threshold': 3.0, 'smoothing': 'median', 'window': 5},
    {'missingLandmarkTolerance': 2, 'interpolation': true},
    {'missingLandmarkTolerance': 3, 'interpolation': false},
    {'adaptiveConfidenceThreshold': 0.5},
    {'adaptiveConfidenceThreshold': 0.7},
    {'adaptiveConfidenceThreshold': 0.3, 'smoothing': 'mean', 'window': 3},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final smoothings = ['mean', 'median'];
      final smoothing = smoothings[_rng.nextInt(smoothings.length)];
      config = {
        'smoothing': smoothing,
        'window': 2 + _rng.nextInt(8),
        'confidenceWeight': _rng.nextBool(),
      };
      if (_rng.nextBool()) config['outlierRejection'] = true;
      if (_rng.nextBool()) config['threshold'] = 1.0 + _rng.nextDouble() * 3.0;
      if (_rng.nextBool()) config['adaptiveConfidenceThreshold'] = double.parse((0.2 + _rng.nextDouble() * 0.5).toStringAsFixed(4));
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'signal_${config.keys.first}_v$version',
      hypothesis: 'Signal quality: ${config.toString()}',
      config: config,
    );
  }
}

// ---------------------------------------------------------------------------
// D. GEOMETRIC / FEATURE FAMILY
// ---------------------------------------------------------------------------

class GeometricFamily extends ExperimentFamily {
  GeometricFamily() : super('geometric');

  final _configs = <Map<String, dynamic>>[
    {'features': ['kneeAngle', 'hipAngle'], 'threshold': 0.5},
    {'features': ['kneeAngle', 'stanceWidth'], 'threshold': 0.6},
    {'features': ['kneeAngle', 'hipAngle', 'stanceWidth'], 'threshold': 0.5},
    {'features': ['kneeAngle', 'torsoRatio'], 'threshold': 0.7},
    {'features': ['jointVelocity', 'kneeAngle'], 'threshold': 0.5},
    {'features': ['angularVelocity', 'hipAngle'], 'threshold': 0.6},
    {'features': ['acceleration', 'kneeAngle', 'stanceWidth'], 'threshold': 0.5},
    {'features': ['relativeVerticalDisplacement'], 'threshold': 0.08},
    {'features': ['symmetry', 'kneeAngle'], 'threshold': 0.7},
    {'features': ['landingGeometry', 'compressionGeometry'], 'threshold': 0.5},
    {'features': ['kneeAngle', 'hipAngle', 'stanceWidth', 'jointVelocity'], 'threshold': 0.4},
    {'features': ['kneeAngle', 'hipAngle', 'stanceWidth', 'acceleration'], 'threshold': 0.4},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final allFeatures = ['kneeAngle', 'hipAngle', 'stanceWidth', 'jointVelocity',
                           'angularVelocity', 'acceleration', 'symmetry', 'torsoRatio'];
      final numFeatures = 1 + _rng.nextInt(4);
      final features = List.generate(numFeatures, (_) => allFeatures[_rng.nextInt(allFeatures.length)]);
      final uniqueFeatures = features.toSet().toList();
      config = {
        'features': uniqueFeatures,
        'threshold': double.parse((0.3 + _rng.nextDouble() * 0.5).toStringAsFixed(4)),
      };
      version = _index + 1;
      _index++;
    }

    final featureStr = (config['features'] as List).join(',');
    return ProposedExperiment(
      family: name,
      candidateName: 'geom_${featureStr}_v$version',
      hypothesis: 'Geometric features: $featureStr at threshold ${config['threshold']}',
      config: config,
      featureSet: featureStr,
    );
  }
}

// ---------------------------------------------------------------------------
// E. CONFUSER SPECIALIST FAMILY
// ---------------------------------------------------------------------------

class ConfuserSpecialistFamily extends ExperimentFamily {
  ConfuserSpecialistFamily() : super('confuser_specialist');

  final _configs = <Map<String, dynamic>>[
    {'target': 'deep_squats', 'method': 'knee_angle_gate', 'threshold': 60},
    {'target': 'deep_squats', 'method': 'knee_angle_gate', 'threshold': 70},
    {'target': 'deep_squats', 'method': 'compression_depth_gate', 'threshold': 0.15},
    {'target': 'deep_squats', 'method': 'no_flight_phase_gate', 'airborneThreshold': 0.25},
    {'target': 'jumping_jacks', 'method': 'stance_width_gate', 'threshold': 0.5},
    {'target': 'jumping_jacks', 'method': 'stance_width_velocity_gate', 'threshold': 0.1},
    {'target': 'jumping_jacks', 'method': 'arm_motion_gate', 'threshold': 0.3},
    {'target': 'vertical_jumps', 'method': 'no_compression_gate', 'threshold': 0.05},
    {'target': 'vertical_jumps', 'method': 'knee_angle_range_gate', 'threshold': 20},
    {'target': 'squat_jacks', 'method': 'temporal_order_gate', 'compressionBeforeAirborne': true},
    {'target': 'squat_jacks', 'method': 'knee_angle_gate', 'threshold': 65},
    {'target': 'normal_squats', 'method': 'no_flight_gate', 'airborneThreshold': 0.20},
    {'target': 'lunges', 'method': 'asymmetry_gate', 'threshold': 0.3},
    {'target': 'deep_squats', 'method': 'combined_knee_compression', 'kneeThreshold': 65, 'compressionThreshold': 0.12},
    {'target': 'jumping_jacks', 'method': 'combined_stance_arm', 'stanceThreshold': 0.45, 'armThreshold': 0.25},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    // If failure clusters suggest a specific confuser, prioritize that
    final falseAcceptClusters = failureClusters.where((c) => c.name.startsWith('FALSE_ACCEPT_'));
    for (final cluster in falseAcceptClusters) {
      final movement = cluster.name.replaceAll('FALSE_ACCEPT_', '').toLowerCase();
      final matching = _configs.where((c) => c['target'] == movement).toList();
      if (matching.isNotEmpty) {
        final base = matching[_rng.nextInt(matching.length)];
        config = Map<String, dynamic>.from(base);
        // Jitter threshold for novel exploration
        if (config.containsKey('threshold')) {
          config['threshold'] = (config['threshold'] as num).toDouble() * (0.7 + _rng.nextDouble() * 0.6);
        }
        version = _index + 1;
        _index++;
        return ProposedExperiment(
          family: name,
          candidateName: 'confuser_${config['target']}_${config['method']}_v$version',
          hypothesis: 'Reject ${config['target']} using ${config['method']}: ${config.toString()}',
          config: config,
        );
      }
    }

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      // Generate randomized confuser configs
      final targets = ['deep_squats', 'jumping_jacks', 'vertical_jumps', 'squat_jacks', 'normal_squats', 'lunges'];
      final methods = ['knee_angle_gate', 'compression_depth_gate', 'no_flight_phase_gate',
                       'stance_width_gate', 'asymmetry_gate', 'temporal_order_gate'];
      final target = targets[_rng.nextInt(targets.length)];
      final method = methods[_rng.nextInt(methods.length)];
      config = {
        'target': target,
        'method': method,
        'threshold': double.parse((0.1 + _rng.nextDouble() * 0.5).toStringAsFixed(4)),
      };
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'confuser_${config['target']}_${config['method']}_v$version',
      hypothesis: 'Reject ${config['target']} using ${config['method']}: ${config.toString()}',
      config: config,
    );
  }
}

// ---------------------------------------------------------------------------
// F. MLP FAMILY
// ---------------------------------------------------------------------------

class MLPFamily extends ExperimentFamily {
  MLPFamily() : super('mlp');

  final _configs = <Map<String, dynamic>>[
    {'windowSize': 15, 'hiddenSize': 16, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5},
    {'windowSize': 15, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5},
    {'windowSize': 15, 'hiddenSize': 32, 'numLayers': 3, 'lr': 0.005, 'epochs': 15, 'threshold': 0.5},
    {'windowSize': 30, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5},
    {'windowSize': 30, 'hiddenSize': 16, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5},
    {'windowSize': 30, 'hiddenSize': 64, 'numLayers': 2, 'lr': 0.005, 'epochs': 15, 'threshold': 0.5},
    {'windowSize': 45, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5},
    {'windowSize': 15, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 20, 'threshold': 0.4},
    {'windowSize': 15, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.3},
    {'windowSize': 30, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.3},
    {'windowSize': 15, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.02, 'epochs': 15, 'threshold': 0.5, 'hardNegRatio': 2.0},
    {'windowSize': 30, 'hiddenSize': 32, 'numLayers': 2, 'lr': 0.01, 'epochs': 10, 'threshold': 0.5, 'classWeight': 2.0},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final windows = [10, 15, 20, 30, 45, 60];
      final hiddens = [8, 16, 24, 32, 48, 64];
      final layers = [1, 2, 3, 4];
      final lrs = [0.001, 0.005, 0.01, 0.02];
      final epochs = [5, 10, 15, 20];
      final thresholds = [0.3, 0.4, 0.5, 0.6, 0.7];
      config = {
        'windowSize': windows[_rng.nextInt(windows.length)],
        'hiddenSize': hiddens[_rng.nextInt(hiddens.length)],
        'numLayers': layers[_rng.nextInt(layers.length)],
        'lr': lrs[_rng.nextInt(lrs.length)],
        'epochs': epochs[_rng.nextInt(epochs.length)],
        'threshold': thresholds[_rng.nextInt(thresholds.length)],
      };
      if (_rng.nextBool()) config['hardNegRatio'] = 1.0 + _rng.nextDouble() * 3.0;
      if (_rng.nextBool()) config['classWeight'] = 1.0 + _rng.nextDouble() * 3.0;
      version = _index + 1;
      _index++;
    }

    final params = (config['hiddenSize'] as int) * 128 + (config['hiddenSize'] as int) + 1;

    return ProposedExperiment(
      family: name,
      candidateName: 'mlp_w${config['windowSize']}_h${config['hiddenSize']}_l${config['numLayers']}_v$version',
      hypothesis: 'MLP: window=${config['windowSize']}, hidden=${config['hiddenSize']}, '
          'layers=${config['numLayers']}, lr=${config['lr']}, epochs=${config['epochs']}, thresh=${config['threshold']}',
      config: config,
      temporalWindow: config['windowSize'] as int,
      modelParams: params,
      threshold: (config['threshold'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// G. CONV1D FAMILY
// ---------------------------------------------------------------------------

class Conv1DFamily extends ExperimentFamily {
  Conv1DFamily() : super('conv1d');

  final _configs = <Map<String, dynamic>>[
    {'windowSize': 30, 'conv1Filters': 4, 'conv1Kernel': 3, 'conv2Filters': 8, 'conv2Kernel': 3, 'hiddenSize': 16, 'lr': 0.005, 'epochs': 5, 'threshold': 0.5},
    {'windowSize': 30, 'conv1Filters': 8, 'conv1Kernel': 5, 'conv2Filters': 16, 'conv2Kernel': 3, 'hiddenSize': 32, 'lr': 0.005, 'epochs': 5, 'threshold': 0.5},
    {'windowSize': 45, 'conv1Filters': 8, 'conv1Kernel': 5, 'conv2Filters': 16, 'conv2Kernel': 3, 'hiddenSize': 32, 'lr': 0.005, 'epochs': 5, 'threshold': 0.5},
    {'windowSize': 30, 'conv1Filters': 4, 'conv1Kernel': 7, 'conv2Filters': 8, 'conv2Kernel': 3, 'hiddenSize': 16, 'lr': 0.005, 'epochs': 5, 'threshold': 0.3},
    {'windowSize': 30, 'conv1Filters': 8, 'conv1Kernel': 5, 'conv2Filters': 16, 'conv2Kernel': 3, 'hiddenSize': 32, 'lr': 0.005, 'epochs': 5, 'threshold': 0.3},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final windows = [15, 20, 30, 45, 60];
      final filters = [4, 8, 16, 32];
      final kernels = [3, 5, 7];
      final hiddens = [8, 16, 32, 64];
      final lrs = [0.001, 0.005, 0.01];
      final epochs = [3, 5, 10];
      final thresholds = [0.3, 0.4, 0.5, 0.6];
      config = {
        'windowSize': windows[_rng.nextInt(windows.length)],
        'conv1Filters': filters[_rng.nextInt(filters.length)],
        'conv1Kernel': kernels[_rng.nextInt(kernels.length)],
        'conv2Filters': filters[_rng.nextInt(filters.length)],
        'conv2Kernel': kernels[_rng.nextInt(kernels.length)],
        'hiddenSize': hiddens[_rng.nextInt(hiddens.length)],
        'lr': lrs[_rng.nextInt(lrs.length)],
        'epochs': epochs[_rng.nextInt(epochs.length)],
        'threshold': thresholds[_rng.nextInt(thresholds.length)],
      };
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'conv1d_w${config['windowSize']}_f${config['conv1Filters']}_v$version',
      hypothesis: 'Conv1D: window=${config['windowSize']}, filters=${config['conv1Filters']}, '
          'kernel=${config['conv1Kernel']}, thresh=${config['threshold']}',
      config: config,
      temporalWindow: config['windowSize'] as int,
      threshold: (config['threshold'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// H. GRU FAMILY (minimal — GRU is slow)
// ---------------------------------------------------------------------------

class GRUFamily extends ExperimentFamily {
  GRUFamily() : super('gru');

  final _configs = <Map<String, dynamic>>[
    {'windowSize': 15, 'hiddenSize': 8, 'lr': 0.001, 'epochs': 2, 'batchSize': 10, 'threshold': 0.5},
    {'windowSize': 15, 'hiddenSize': 16, 'lr': 0.001, 'epochs': 2, 'batchSize': 10, 'threshold': 0.5},
    {'windowSize': 30, 'hiddenSize': 8, 'lr': 0.001, 'epochs': 2, 'batchSize': 10, 'threshold': 0.5},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final windows = [10, 15, 20, 30];
      final hiddens = [4, 8, 16, 24];
      final lrs = [0.0005, 0.001, 0.005];
      final epochs = [1, 2, 3, 5];
      final thresholds = [0.3, 0.4, 0.5, 0.6];
      config = {
        'windowSize': windows[_rng.nextInt(windows.length)],
        'hiddenSize': hiddens[_rng.nextInt(hiddens.length)],
        'lr': lrs[_rng.nextInt(lrs.length)],
        'epochs': epochs[_rng.nextInt(epochs.length)],
        'batchSize': 5 + _rng.nextInt(15),
        'threshold': thresholds[_rng.nextInt(thresholds.length)],
      };
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'gru_w${config['windowSize']}_h${config['hiddenSize']}_v$version',
      hypothesis: 'GRU: window=${config['windowSize']}, hidden=${config['hiddenSize']}, '
          'epochs=${config['epochs']}, thresh=${config['threshold']}',
      config: config,
      temporalWindow: config['windowSize'] as int,
      threshold: (config['threshold'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// I. HYBRID FAMILY
// ---------------------------------------------------------------------------

class HybridFamily extends ExperimentFamily {
  HybridFamily() : super('hybrid');

  final _configs = <Map<String, dynamic>>[
    {'detector': 'temp_adaptive_hyst', 'verifier': 'mlp', 'verifierWindow': 15, 'verifierThreshold': 0.5},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'mlp', 'verifierWindow': 30, 'verifierThreshold': 0.5},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'mlp', 'verifierWindow': 15, 'verifierThreshold': 0.3},
    {'detector': 'concept_v2', 'verifier': 'mlp', 'verifierWindow': 15, 'verifierThreshold': 0.5},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'confuser_gate', 'gate': 'deep_squat_knee_angle', 'kneeThreshold': 65},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'confuser_gate', 'gate': 'jumping_jack_stance_width', 'stanceThreshold': 0.5},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'confuser_gate', 'gate': 'vertical_jump_no_compression', 'compressionThreshold': 0.05},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'combined_gates', 'gates': ['deep_squat_knee_angle', 'jumping_jack_stance_width']},
    {'detector': 'high_recall_temporal', 'verifier': 'high_precision_geometric', 'recallThreshold': 0.08, 'precisionThreshold': 0.6},
    {'detector': 'temp_adaptive_hyst', 'verifier': 'mlp', 'verifierWindow': 15, 'verifierThreshold': 0.5, 'confuserGate': 'deep_squat_knee_angle'},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final detectors = ['temp_adaptive_hyst', 'concept_v2', 'high_recall_temporal'];
      final verifiers = ['mlp', 'confuser_gate', 'combined_gates', 'high_precision_geometric'];
      final windows = [10, 15, 20, 30, 45];
      final thresholds = [0.3, 0.4, 0.5, 0.6, 0.7];
      config = {
        'detector': detectors[_rng.nextInt(detectors.length)],
        'verifier': verifiers[_rng.nextInt(verifiers.length)],
        'verifierWindow': windows[_rng.nextInt(windows.length)],
        'verifierThreshold': thresholds[_rng.nextInt(thresholds.length)],
      };
      if (_rng.nextBool()) config['confuserGate'] = 'deep_squat_knee_angle';
      version = _index + 1;
      _index++;
    }

    // Adapt based on failure clusters
    final falseAcceptClusters = failureClusters.where((c) => c.name.startsWith('FALSE_ACCEPT_'));
    if (falseAcceptClusters.isNotEmpty) {
      final worstConfuser = falseAcceptClusters.first.name.replaceAll('FALSE_ACCEPT_', '').toLowerCase();
      config['targetConfuser'] = worstConfuser;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'hybrid_${config['detector']}_${config['verifier']}_v$version',
      hypothesis: 'Hybrid: ${config['detector']} proposes → ${config['verifier']} verifies. Config: ${config.toString()}',
      config: config,
      temporalWindow: config['verifierWindow'] as int?,
    );
  }
}

// ---------------------------------------------------------------------------
// J. ENSEMBLE FAMILY
// ---------------------------------------------------------------------------

class EnsembleFamily extends ExperimentFamily {
  EnsembleFamily() : super('ensemble');

  final _configs = <Map<String, dynamic>>[
    {'members': ['temp_adaptive_hyst', 'concept_v2'], 'method': 'majority_vote'},
    {'members': ['temp_adaptive_hyst', 'mlp_w15'], 'method': 'and_gate'},
    {'members': ['temp_adaptive_hyst', 'concept_v2', 'mlp_w15'], 'method': 'majority_vote'},
    {'members': ['temp_adaptive_hyst', 'confuser_specialist'], 'method': 'subtract_confuser'},
    {'members': ['concept_v2', 'confuser_specialist'], 'method': 'and_gate'},
  ];

  int _index = 0;

  @override
  bool hasMoreConfigurations(List<ExperimentRecord> history) => true;

  @override
  ProposedExperiment generate({
    required List<ExperimentRecord> history,
    required List<FailureCluster> failureClusters,
  }) {
    Map<String, dynamic> config;
    int version;

    if (_index < _configs.length) {
      config = Map<String, dynamic>.from(_configs[_index]);
      version = _index + 1;
      _index++;
    } else {
      final allMembers = ['temp_adaptive_hyst', 'concept_v2', 'mlp_w15', 'confuser_specialist'];
      final methods = ['majority_vote', 'and_gate', 'subtract_confuser', 'weighted_avg'];
      final numMembers = 2 + _rng.nextInt(3);
      final members = List.generate(numMembers, (_) => allMembers[_rng.nextInt(allMembers.length)]).toSet().toList();
      if (members.length < 2) members.add(allMembers[_rng.nextInt(allMembers.length)]);
      config = {
        'members': members,
        'method': methods[_rng.nextInt(methods.length)],
      };
      version = _index + 1;
      _index++;
    }

    return ProposedExperiment(
      family: name,
      candidateName: 'ensemble_${config['method']}_v$version',
      hypothesis: 'Ensemble: ${config['members']} using ${config['method']}',
      config: config,
    );
  }
}

// ---------------------------------------------------------------------------
// FAMILY REGISTRY
// ---------------------------------------------------------------------------

class FamilyRegistry {
  final Map<String, ExperimentFamily> _families = {};

  FamilyRegistry() {
    register(TemporalFamily());
    register(CameraFamily());
    register(SignalQualityFamily());
    register(GeometricFamily());
    register(ConfuserSpecialistFamily());
    register(MLPFamily());
    register(Conv1DFamily());
    register(GRUFamily());
    register(HybridFamily());
    register(EnsembleFamily());
  }

  void register(ExperimentFamily family) {
    _families[family.name] = family;
  }

  ExperimentFamily? getFamily(String name) => _families[name];
  List<String> get familyNames => _families.keys.toList();
}
