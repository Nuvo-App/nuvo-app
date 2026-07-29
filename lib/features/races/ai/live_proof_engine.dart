import '../data/ai_motion_models.dart';
import 'live_proof_models.dart';

class LiveProofEngine {
  LiveProofEngine({
    required LiveProofActivityDefinition activity,
    required int targetValue,
  }) : _activity = activity,
       _validator = activity.createValidator(
         LiveProofValidatorConfig(
           activityId: activity.activityId,
           targetValue: targetValue,
           metric: activity.metric,
           unit: activity.unit,
           validatorVersion: activity.validatorVersion,
           minimumConfidence: activity.minimumConfidence,
           isHold: activity.isHold,
         ),
       );

  LiveProofActivityDefinition _activity;
  LiveProofValidator _validator;
  LiveProofUpdate? _lastUpdate;

  LiveProofActivityDefinition get activity => _activity;
  int get targetValue => _validator.targetValue;
  int get currentValue => _validator.currentValue;
  double get confidence => _validator.confidence;
  bool get primarySignalVisible => _validator.primarySignalVisible;
  String get validatorState => _validator.validatorState;
  String get failedRuleReason => _validator.failedRuleReason;
  LiveProofUpdate? get lastUpdate => _lastUpdate;

  void selectActivity(LiveProofActivityDefinition activity, int targetValue) {
    _activity = activity;
    _validator = activity.createValidator(
      LiveProofValidatorConfig(
        activityId: activity.activityId,
        targetValue: targetValue,
        metric: activity.metric,
        unit: activity.unit,
        validatorVersion: activity.validatorVersion,
        minimumConfidence: activity.minimumConfidence,
        isHold: activity.isHold,
      ),
    );
    _lastUpdate = null;
  }

  void start() {
    _validator.start();
    _lastUpdate = null;
  }

  LiveProofUpdate updatePose(NuvoPoseFrame frame) {
    final update = _validator.update(
      LiveProofSignalBatch(signals: [PoseLiveProofSignal(frame: frame)]),
    );
    _lastUpdate = update;
    return update;
  }

  LiveProofUpdate updateSignals(LiveProofSignalBatch signals) {
    final update = _validator.update(signals);
    _lastUpdate = update;
    return update;
  }

  LiveProofResult finish() => _validator.finish();

  AiMotionResult finishAiMotion() => finish().toAiMotionResult();
}
