const ALLOWED_ENGINES = new Set([
  'native_v1',
  'state_machine_v1',
  'alternating_rep_v1',
  'hold_v1',
]);

const ALLOWED_LANDMARKS = new Set([
  'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow',
  'leftWrist', 'rightWrist', 'leftHip', 'rightHip', 'leftKnee',
  'rightKnee', 'leftAnkle', 'rightAnkle', 'nose',
]);

const ALLOWED_SPEC_KEYS = new Set([
  'specSchemaVersion', 'releaseId', 'activityId', 'engineType',
  'measurementType', 'requiredCapabilities', 'requiredLandmarks',
  'stableFrames', 'startRules', 'activeRules', 'leftRules', 'rightRules',
  'holdRules', 'minHoldMs', 'maxHoldMs', 'nativeValidatorKey',
]);

export class MotionSpecValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MotionSpecValidationError';
  }
}

type Rule = {
  point?: unknown;
  axis?: unknown;
  operator?: unknown;
  threshold?: unknown;
  minLikelihood?: unknown;
};

function stringValue(value: unknown, field: string, max = 160): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) {
    throw new MotionSpecValidationError(`${field}_invalid`);
  }
  return value.trim();
}

function boundedInt(value: unknown, field: string, min: number, max: number, fallback: number): number {
  if (value === undefined) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value) || value < min || value > max) {
    throw new MotionSpecValidationError(`${field}_out_of_range`);
  }
  return value;
}

function strings(value: unknown, field: string, max: number): string[] {
  if (!Array.isArray(value) || value.length > max) throw new MotionSpecValidationError(`${field}_invalid`);
  const entries = value.map((entry) => stringValue(entry, field));
  if (new Set(entries).size !== entries.length) throw new MotionSpecValidationError(`${field}_duplicate`);
  return entries;
}

function rules(value: unknown, field: string): Rule[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 12) throw new MotionSpecValidationError(`${field}_invalid`);
  return value.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new MotionSpecValidationError(`${field}_rule_invalid`);
    }
    const rule = entry as Rule;
    const point = stringValue(rule.point, `${field}_point`);
    if (!ALLOWED_LANDMARKS.has(point)) throw new MotionSpecValidationError(`${field}_landmark_invalid`);
    if (rule.axis !== 'x' && rule.axis !== 'y') throw new MotionSpecValidationError(`${field}_axis_invalid`);
    if (!['gt', 'gte', 'lt', 'lte'].includes(String(rule.operator))) {
      throw new MotionSpecValidationError(`${field}_operator_invalid`);
    }
    if (typeof rule.threshold !== 'number' || !Number.isFinite(rule.threshold) || rule.threshold < 0 || rule.threshold > 1) {
      throw new MotionSpecValidationError(`${field}_threshold_invalid`);
    }
    if (rule.minLikelihood !== undefined &&
        (typeof rule.minLikelihood !== 'number' || !Number.isFinite(rule.minLikelihood) || rule.minLikelihood < 0.2 || rule.minLikelihood > 1)) {
      throw new MotionSpecValidationError(`${field}_likelihood_invalid`);
    }
    const unknown = Object.keys(rule).filter((key) => !['point', 'axis', 'operator', 'threshold', 'minLikelihood'].includes(key));
    if (unknown.length) throw new MotionSpecValidationError(`${field}_unknown_key`);
    return rule;
  });
}

export function validateMotionVerifierSpec(
  spec: unknown,
  expected?: { releaseId?: string; activityId?: string },
): Record<string, unknown> {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
    throw new MotionSpecValidationError('spec_invalid');
  }
  const value = spec as Record<string, unknown>;
  if (JSON.stringify(value).length > 64 * 1024) throw new MotionSpecValidationError('spec_too_large');
  const unknown = Object.keys(value).filter((key) => !ALLOWED_SPEC_KEYS.has(key));
  if (unknown.length) throw new MotionSpecValidationError('unknown_spec_key');
  if (value.specSchemaVersion !== 1) throw new MotionSpecValidationError('schema_unsupported');
  const releaseId = stringValue(value.releaseId, 'release_id');
  const activityId = stringValue(value.activityId, 'activity_id');
  if (expected?.releaseId && releaseId !== expected.releaseId) throw new MotionSpecValidationError('release_id_mismatch');
  if (expected?.activityId && activityId !== expected.activityId) throw new MotionSpecValidationError('activity_id_mismatch');
  const engineType = stringValue(value.engineType, 'engine_type');
  if (!ALLOWED_ENGINES.has(engineType)) throw new MotionSpecValidationError('engine_unsupported');

  if (engineType === 'native_v1') {
    stringValue(value.nativeValidatorKey, 'native_validator_key', 80);
    return value;
  }

  const landmarks = strings(value.requiredLandmarks, 'required_landmarks', 24);
  if (landmarks.some((landmark) => !ALLOWED_LANDMARKS.has(landmark))) {
    throw new MotionSpecValidationError('required_landmark_invalid');
  }
  const start = rules(value.startRules, 'start_rules');
  const active = rules(value.activeRules, 'active_rules');
  const left = rules(value.leftRules, 'left_rules');
  const right = rules(value.rightRules, 'right_rules');
  const hold = rules(value.holdRules, 'hold_rules');
  if (engineType === 'state_machine_v1' && (!start.length || !active.length)) throw new MotionSpecValidationError('state_rules_missing');
  if (engineType === 'alternating_rep_v1' && (!left.length || !right.length)) throw new MotionSpecValidationError('alternating_rules_missing');
  if (engineType === 'hold_v1' && !hold.length) throw new MotionSpecValidationError('hold_rules_missing');
  const stableFrames = boundedInt(value.stableFrames, 'stable_frames', 1, 12, 3);
  const minHoldMs = boundedInt(value.minHoldMs, 'min_hold_ms', 50, 60 * 60 * 1000, 250);
  boundedInt(value.maxHoldMs, 'max_hold_ms', minHoldMs, 60 * 60 * 1000, 60 * 60 * 1000);
  if (engineType !== 'hold_v1' && (value.minHoldMs !== undefined || value.maxHoldMs !== undefined)) {
    throw new MotionSpecValidationError('hold_timing_not_allowed');
  }
  void stableFrames;
  return value;
}
