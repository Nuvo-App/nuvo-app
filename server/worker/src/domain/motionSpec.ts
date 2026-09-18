const ALLOWED_ENGINES = new Set([
  'native_v1',
  'state_machine_v1',
  'alternating_rep_v1',
  'hold_v1',
  'object_composition_v1',
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
  'requiredObjects', 'composition',
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

const ALLOWED_OBJECT_KINDS = new Set(['ball', 'hoop']);
const ALLOWED_COMPOSITION_EVENTS = new Set([
  'ball_controlled', 'ball_released', 'ball_ascending', 'ball_descending',
  'ball_through_hoop', 'shot_timeout',
]);

function boundedNumber(value: unknown, field: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new MotionSpecValidationError(`${field}_out_of_range`);
  }
  return value;
}

function requiredObjects(value: unknown): Array<{ id: string; kind: string; minLikelihood: number }> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 8) {
    throw new MotionSpecValidationError('required_objects_invalid');
  }
  const objects = value.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new MotionSpecValidationError('object_requirement_invalid');
    }
    const item = entry as Record<string, unknown>;
    const unknown = Object.keys(item).filter((key) => !['id', 'kind', 'minLikelihood'].includes(key));
    if (unknown.length) throw new MotionSpecValidationError('object_requirement_unknown_key');
    const id = stringValue(item.id, 'object_id', 80);
    const kind = stringValue(item.kind, 'object_kind', 40);
    if (!ALLOWED_OBJECT_KINDS.has(kind)) throw new MotionSpecValidationError('object_kind_unsupported');
    const minLikelihood = boundedNumber(item.minLikelihood ?? 0.35, 'object_likelihood', 0.2, 1);
    return { id, kind, minLikelihood };
  });
  if (new Set(objects.map((entry) => entry.id)).size !== objects.length) {
    throw new MotionSpecValidationError('object_id_duplicate');
  }
  return objects;
}

function composition(value: unknown, objectIds: Set<string>) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new MotionSpecValidationError('composition_invalid');
  }
  const item = value as Record<string, unknown>;
  const allowed = new Set([
    'states', 'transitions', 'startState', 'terminalStates', 'ballObjectId',
    'hoopObjectId', 'stableFrames', 'maxShotMs', 'controlDistance',
    'releaseDistance', 'minUpwardVelocity', 'minDownwardVelocity',
    'hoopPlaneTolerance', 'madeRadius',
  ]);
  if (Object.keys(item).some((key) => !allowed.has(key))) throw new MotionSpecValidationError('composition_unknown_key');
  const states = strings(item.states, 'composition_states', 16);
  const transitions = item.transitions;
  if (!Array.isArray(transitions) || transitions.length === 0 || transitions.length > 24) {
    throw new MotionSpecValidationError('composition_transitions_invalid');
  }
  for (const entry of transitions) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new MotionSpecValidationError('composition_transition_invalid');
    const transition = entry as Record<string, unknown>;
    if (Object.keys(transition).some((key) => !['from', 'to', 'event'].includes(key))) throw new MotionSpecValidationError('composition_transition_unknown_key');
    const from = stringValue(transition.from, 'transition_from', 80);
    const to = stringValue(transition.to, 'transition_to', 80);
    const event = stringValue(transition.event, 'transition_event', 80);
    if (!states.includes(from) || !states.includes(to) || !ALLOWED_COMPOSITION_EVENTS.has(event)) {
      throw new MotionSpecValidationError('composition_transition_reference_invalid');
    }
  }
  const startState = stringValue(item.startState, 'composition_start_state', 80);
  if (!states.includes(startState)) throw new MotionSpecValidationError('composition_start_state_invalid');
  const terminalStates = strings(item.terminalStates, 'composition_terminal_states', 8);
  if (terminalStates.some((state) => !states.includes(state))) throw new MotionSpecValidationError('composition_terminal_state_invalid');
  const ballObjectId = stringValue(item.ballObjectId, 'ball_object_id', 80);
  const hoopObjectId = stringValue(item.hoopObjectId, 'hoop_object_id', 80);
  if (!objectIds.has(ballObjectId) || !objectIds.has(hoopObjectId)) throw new MotionSpecValidationError('composition_object_reference_invalid');
  boundedInt(item.stableFrames, 'composition_stable_frames', 1, 12, 2);
  boundedInt(item.maxShotMs, 'composition_max_shot_ms', 1000, 60 * 1000, 8000);
  boundedNumber(item.controlDistance, 'composition_control_distance', 0.01, 1);
  boundedNumber(item.releaseDistance, 'composition_release_distance', 0.01, 1);
  boundedNumber(item.minUpwardVelocity, 'composition_upward_velocity', 0.001, 10);
  boundedNumber(item.minDownwardVelocity, 'composition_downward_velocity', 0.001, 10);
  boundedNumber(item.hoopPlaneTolerance, 'composition_hoop_tolerance', 0.001, 1);
  boundedNumber(item.madeRadius, 'composition_made_radius', 0.001, 1);
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
  if (engineType === 'object_composition_v1') {
    const objects = requiredObjects(value.requiredObjects);
    composition(value.composition, new Set(objects.map((entry) => entry.id)));
    return value;
  }
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
