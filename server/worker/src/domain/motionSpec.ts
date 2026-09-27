const ALLOWED_ENGINES = new Set([
  'native_v1',
  'state_machine_v1',
  'alternating_rep_v1',
  'hold_v1',
  'object_composition_v1',
  'sequence_match_v1',
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
  'model',
  'activity', 'package',
  'phases', 'repTimeoutMs', 'lostPoseMs',
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

function model(value: unknown): void {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new MotionSpecValidationError('model_invalid');
  }
  const item = value as Record<string, unknown>;
  const unknown = Object.keys(item).filter((key) =>
    !['modelVersion', 'inputSchemaVersion', 'artifactSha256', 'inputSize'].includes(key));
  if (unknown.length) throw new MotionSpecValidationError('model_unknown_key');
  stringValue(item.modelVersion, 'model_version', 120);
  boundedInt(item.inputSchemaVersion, 'model_input_schema_version', 1, 1, 1);
  const digest = stringValue(item.artifactSha256, 'model_artifact_sha256', 80).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(digest)) throw new MotionSpecValidationError('model_artifact_sha256_invalid');
  boundedInt(item.inputSize, 'model_input_size', 160, 1280, 800);
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

// sequence_match_v1 — the closed predicate grammar. Exactly four kinds; a
// predicate may only carry the fields its kind owns, so the wire format can
// never smuggle in an expression the engine doesn't interpret.
const SEQUENCE_PREDICATE_KEYS: Record<string, Set<string>> = {
  landmark_axis: new Set(['kind', 'point', 'axis', 'operator', 'threshold', 'minLikelihood']),
  angle: new Set(['kind', 'a', 'b', 'c', 'operator', 'degrees', 'minLikelihood']),
  axis_delta: new Set(['kind', 'a', 'b', 'axis', 'operator', 'delta', 'minLikelihood']),
  segment_ratio: new Set(['kind', 'a', 'b', 'refA', 'refB', 'operator', 'ratio', 'minLikelihood']),
};

function sequenceOperator(value: unknown, field: string): void {
  if (!['gt', 'gte', 'lt', 'lte'].includes(String(value))) {
    throw new MotionSpecValidationError(`${field}_operator_invalid`);
  }
}

function sequenceLikelihood(value: unknown, field: string): void {
  if (value !== undefined &&
      (typeof value !== 'number' || !Number.isFinite(value) || value < 0.2 || value > 1)) {
    throw new MotionSpecValidationError(`${field}_likelihood_invalid`);
  }
}

function sequenceLandmark(entry: Record<string, unknown>, field: string, prefix: string): void {
  const name = stringValue(entry[field], `${prefix}_${field}`);
  if (!ALLOWED_LANDMARKS.has(name)) {
    throw new MotionSpecValidationError(`${prefix}_${field}_landmark_invalid`);
  }
}

function sequencePredicate(entry: unknown, field: string): void {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    throw new MotionSpecValidationError(`${field}_predicate_invalid`);
  }
  const item = entry as Record<string, unknown>;
  const kind = stringValue(item.kind, `${field}_kind`, 40);
  const keys = SEQUENCE_PREDICATE_KEYS[kind];
  if (!keys) throw new MotionSpecValidationError(`${field}_kind_invalid`);
  if (Object.keys(item).some((key) => !keys.has(key))) {
    throw new MotionSpecValidationError(`${field}_unknown_key`);
  }
  sequenceOperator(item.operator, field);
  sequenceLikelihood(item.minLikelihood, field);
  switch (kind) {
    case 'landmark_axis':
      sequenceLandmark(item, 'point', field);
      if (item.axis !== 'x' && item.axis !== 'y') throw new MotionSpecValidationError(`${field}_axis_invalid`);
      boundedNumber(item.threshold, `${field}_threshold`, 0, 1);
      break;
    case 'angle':
      sequenceLandmark(item, 'a', field);
      sequenceLandmark(item, 'b', field);
      sequenceLandmark(item, 'c', field);
      boundedNumber(item.degrees, `${field}_degrees`, 0, 180);
      break;
    case 'axis_delta':
      sequenceLandmark(item, 'a', field);
      sequenceLandmark(item, 'b', field);
      if (item.axis !== 'x' && item.axis !== 'y') throw new MotionSpecValidationError(`${field}_axis_invalid`);
      boundedNumber(item.delta, `${field}_delta`, -1, 1);
      break;
    case 'segment_ratio':
      sequenceLandmark(item, 'a', field);
      sequenceLandmark(item, 'b', field);
      sequenceLandmark(item, 'refA', field);
      sequenceLandmark(item, 'refB', field);
      boundedNumber(item.ratio, `${field}_ratio`, 0, 8);
      break;
  }
}

// V1 enforces a STRICT LINEAR chain — no branches, no cycles: every phase's
// `next` must be exactly the following phase's id, and only the last phase
// may complete. Any deviation fails the spec.
function sequencePhases(value: unknown, stableFrames: number): void {
  if (!Array.isArray(value) || value.length < 2 || value.length > 8) {
    throw new MotionSpecValidationError('sequence_phases_invalid');
  }
  const ids: string[] = [];
  for (const entry of value) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new MotionSpecValidationError('sequence_phase_invalid');
    }
    const phase = entry as Record<string, unknown>;
    const allowed = new Set(['id', 'predicates', 'minDwellFrames', 'breakToleranceFrames', 'maxDwellMs', 'next']);
    if (Object.keys(phase).some((key) => !allowed.has(key))) {
      throw new MotionSpecValidationError('sequence_phase_unknown_key');
    }
    const id = stringValue(phase.id, 'phase_id', 40);
    if (!/^[a-z0-9_]{1,40}$/.test(id)) throw new MotionSpecValidationError('phase_id_invalid');
    ids.push(id);
    const predicates = phase.predicates;
    if (!Array.isArray(predicates) || predicates.length === 0 || predicates.length > 6) {
      throw new MotionSpecValidationError('phase_predicates_invalid');
    }
    predicates.forEach((predicate, index) => sequencePredicate(predicate, `phase_${id}_predicate_${index}`));
    boundedInt(phase.minDwellFrames, 'phase_min_dwell_frames', 1, 30, stableFrames);
    boundedInt(phase.breakToleranceFrames, 'phase_break_tolerance_frames', 0, 8, 1);
    if (phase.maxDwellMs !== undefined) {
      boundedInt(phase.maxDwellMs, 'phase_max_dwell_ms', 50, 60 * 1000, 0);
    }
    stringValue(phase.next, 'phase_next', 40);
  }
  if (new Set(ids).size !== ids.length) throw new MotionSpecValidationError('phase_id_duplicate');
  for (let i = 0; i < ids.length; i++) {
    const expected = i === ids.length - 1 ? 'complete' : ids[i + 1];
    if ((value[i] as Record<string, unknown>).next !== expected) {
      throw new MotionSpecValidationError('sequence_chain_invalid');
    }
  }
}

const ACTIVITY_BLOCK_KEYS = new Set([
  'displayName', 'measurementType', 'defaultTarget', 'preferredCameraView',
  'instructions', 'unit', 'coachingTextActive', 'coachingTextIncomplete',
]);

const ACTIVITY_CAMERA_VIEWS = new Set(['front', 'side', 'front_or_angle']);

function activityBlock(value: unknown) {
  if (value === undefined) return;
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new MotionSpecValidationError('activity_invalid');
  }
  const item = value as Record<string, unknown>;
  if (Object.keys(item).some((key) => !ACTIVITY_BLOCK_KEYS.has(key))) {
    throw new MotionSpecValidationError('activity_unknown_key');
  }
  stringValue(item.displayName, 'activity_display_name');
  if (item.measurementType !== 'repetitions' && item.measurementType !== 'duration') {
    throw new MotionSpecValidationError('activity_measurement_type_invalid');
  }
  if (item.preferredCameraView !== undefined &&
      !ACTIVITY_CAMERA_VIEWS.has(String(item.preferredCameraView))) {
    throw new MotionSpecValidationError('activity_camera_view_invalid');
  }
  if (item.defaultTarget !== undefined) {
    boundedInt(item.defaultTarget, 'activity_default_target', 1, 100000, 1);
  }
  if (item.instructions !== undefined) {
    const lines = strings(item.instructions, 'activity_instructions', 6);
    if (lines.some((line) => line.length > 140)) {
      throw new MotionSpecValidationError('activity_instruction_too_long');
    }
  }
  for (const key of ['unit', 'coachingTextActive', 'coachingTextIncomplete']) {
    if (item[key] !== undefined) stringValue(item[key], `activity_${key}`, 140);
  }
}

const PACKAGE_ASSET_TYPES = new Set([
  'preview_v1', 'motion_v2_spec_v1', 'onnx_model', 'test_vectors_v1',
]);

const PACKAGE_ASSET_MAX_BYTES: Record<string, number> = {
  preview_v1: 256 * 1024,
  motion_v2_spec_v1: 512 * 1024,
  onnx_model: 50 * 1024 * 1024,
  test_vectors_v1: 2 * 1024 * 1024,
};

const PACKAGE_MAX_ASSETS = 8;
const PACKAGE_MAX_TOTAL_BYTES = 64 * 1024 * 1024;

function packageManifest(value: unknown) {
  if (value === undefined) return;
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new MotionSpecValidationError('package_invalid');
  }
  const item = value as Record<string, unknown>;
  if (Object.keys(item).some((key) => key !== 'packageSchemaVersion' && key !== 'assets')) {
    throw new MotionSpecValidationError('package_unknown_key');
  }
  if (item.packageSchemaVersion !== 1) {
    throw new MotionSpecValidationError('package_schema_unsupported');
  }
  const rawAssets = item.assets;
  if (!Array.isArray(rawAssets) || rawAssets.length > PACKAGE_MAX_ASSETS) {
    throw new MotionSpecValidationError('package_assets_invalid');
  }
  const seen = new Set<string>();
  let totalBytes = 0;
  for (const entry of rawAssets) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new MotionSpecValidationError('package_asset_invalid');
    }
    const asset = entry as Record<string, unknown>;
    if (Object.keys(asset).some((key) =>
      !['id', 'type', 'sha256', 'url', 'bytes', 'required'].includes(key))) {
      throw new MotionSpecValidationError('package_asset_unknown_key');
    }
    const id = stringValue(asset.id, 'package_asset_id', 64);
    const type = stringValue(asset.type, 'package_asset_type', 64);
    const sha256 = stringValue(asset.sha256, 'package_asset_sha256', 80).toLowerCase();
    stringValue(asset.url, 'package_asset_url', 512);
    const bytes = asset.bytes;
    if (!PACKAGE_ASSET_TYPES.has(type)) {
      throw new MotionSpecValidationError('package_asset_type_unsupported');
    }
    if (!/^[0-9a-f]{64}$/.test(sha256)) {
      throw new MotionSpecValidationError('package_asset_sha256_invalid');
    }
    if (typeof bytes !== 'number' || !Number.isInteger(bytes) ||
        bytes <= 0 || bytes > PACKAGE_ASSET_MAX_BYTES[type]) {
      throw new MotionSpecValidationError('package_asset_bytes_invalid');
    }
    if (!seen.add(id)) throw new MotionSpecValidationError('package_asset_id_duplicate');
    totalBytes += bytes;
    if (totalBytes > PACKAGE_MAX_TOTAL_BYTES) {
      throw new MotionSpecValidationError('package_too_large');
    }
  }
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
  activityBlock(value.activity);
  packageManifest(value.package);
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
    model(value.model);
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
  // Sequence fields are engine-scoped: carrying them under another engine
  // is an authoring bug and fails closed, never silently ignored.
  const isSequence = engineType === 'sequence_match_v1';
  if (!isSequence &&
      (value.phases !== undefined || value.repTimeoutMs !== undefined || value.lostPoseMs !== undefined)) {
    throw new MotionSpecValidationError('sequence_fields_not_allowed');
  }
  if (isSequence) {
    if (value.measurementType !== undefined && value.measurementType !== 'repetitions') {
      throw new MotionSpecValidationError('sequence_measurement_invalid');
    }
    sequencePhases(value.phases, stableFrames);
    boundedInt(value.repTimeoutMs, 'rep_timeout_ms', 500, 60 * 1000, 8000);
    boundedInt(value.lostPoseMs, 'lost_pose_ms', 100, 10 * 1000, 1500);
  }
  void stableFrames;
  return value;
}
