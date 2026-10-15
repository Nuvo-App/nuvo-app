import {
  activityForId,
  normalizeActivityId,
  normalizeActivityIdLoose,
  normalizeMetric,
  scoringRuleForFormat,
  type RaceFormat,
  type RaceMetric,
  type RaceRecurrence,
  type RaceScoringRule,
  type VerificationMethod,
} from './raceActivities';
import type { RegistryActivity } from './motionRegistry';

export interface RaceConfig {
  /// The server-owned activity identity — a static-catalog ID for compiled
  /// motions, or a registry-published ID for remote-only motions. Stored and
  /// compared verbatim; never coerced to another activity.
  activityId: string;
  metric: RaceMetric;
  format: RaceFormat;
  scoringRule: RaceScoringRule;
  targetValue: number | null;
  attemptDurationSeconds: number | null;
  attemptLimit: number | null;
  verificationMethod: VerificationMethod;
  timezone: string;
  startsAt: string | null;
  endsAt: string | null;
  recurrence: RaceRecurrence;
}

export const CUSTOM_VERIFIER_TYPE = 'custom_pose_sequence';
export const MOTION_V2_VERIFIER_TYPE = 'motion_v2';
export const PRESET_VERIFIER_TYPE = 'preset_pose';
export const CUSTOM_VERIFIER_VERSION = 1;
export const MOTION_V2_VERIFIER_VERSION = 1;
export const CUSTOM_VERIFIER_SPEC_MAX_BYTES = 128 * 1024;
// V2 learned specs carry per-demo encoder embeddings (3 refs × proto+trajectory,
// ~1MB as JSON) — an order of magnitude larger than V1 pose templates.
export const MOTION_V2_SPEC_MAX_BYTES = 1536 * 1024;

/** Custom taught-movement races: V1 pose templates AND V2 learned specs. */
export function isCustomVerifierType(t: string | null | undefined): boolean {
  return t === CUSTOM_VERIFIER_TYPE || t === MOTION_V2_VERIFIER_TYPE;
}

export interface CustomRaceConfig {
  verifierType: string;
  verifierVersion: typeof CUSTOM_VERIFIER_VERSION;
  verifierSpecJson: string;
  customActivityName: string;
  metric: 'reps';
  format: RaceFormat;
  scoringRule: RaceScoringRule;
  /** Required for first_to_goal only; null for window / attempt formats. */
  targetValue: number | null;
  attemptDurationSeconds: number | null;
  attemptLimit: number | null;
  verificationMethod: 'ai';
  timezone: string;
  startsAt: string | null;
  endsAt: string | null;
  recurrence: RaceRecurrence;
}

const FORMATS = new Set<RaceFormat>(['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);
const RECURRENCES = new Set<RaceRecurrence>(['none', 'daily', 'weekly']);

/**
 * Non-physical / honor-logged goals (pages read, hours studied, tasks done…).
 * No AI Motion Proof — progress is user-logged. Stored with
 * `verifier_type = MANUAL_VERIFIER_TYPE`. The wire `metric` is always `reps`
 * (the score is an opaque cumulative integer); the human unit lives in
 * `target_unit` for display.
 */
export const MANUAL_VERIFIER_TYPE = 'manual_log';

/** 'lower' = fastest/lowest verified value wins (time-attack, golf score). */
export function scoreDirectionFromBody(
  body: Record<string, unknown>,
): 'higher' | 'lower' {
  return stringValue(body, 'scoreDirection', 'score_direction') === 'lower'
    ? 'lower'
    : 'higher';
}

const MANUAL_PROOF_REQUIREMENTS = new Set([
  'manual',
  'note',
  'link',
  'photo',
  'photo_video',
  'daily_check',
  'habit_check',
]);

export interface ManualRaceConfig {
  verifierType: typeof MANUAL_VERIFIER_TYPE;
  metric: 'reps';
  unit: string; // free-text display unit ("pages", "minutes", "days")
  format: RaceFormat;
  scoringRule: RaceScoringRule;
  targetValue: number;
  recurrence: RaceRecurrence;
  timezone: string;
  startsAt: string | null;
  endsAt: string | null;
}

/**
 * Returns a manual config when the body is an honor-logged goal:
 *  - no supported preset activityId and no custom verifierType, and
 *  - a manual-style proofRequirement / proofMode.
 * Returns null when it's not a manual race, or an error string when it is but
 * is malformed.
 */
export function manualConfigFromBody(
  body: Record<string, unknown>,
): ManualRaceConfig | null | { error: string } {
  if (stringValue(body, 'verifierType', 'verifier_type')) return null;

  const activityId = normalizeActivityId(stringValue(body, 'activityId', 'activity_id', 'aiActivityType'));
  if (activityId && activityForId(activityId)?.availability === 'supported') return null;

  const proof = (
    stringValue(body, 'proofMode', 'proofRequirement', 'proof_requirement') ?? 'manual'
  ).toLowerCase();
  if (!MANUAL_PROOF_REQUIREMENTS.has(proof)) return null;

  const targetValue = intValue(body, 'targetValue', 'target_value');
  if (!targetValue) return { error: 'A goal amount is required.' };

  const unitRaw = stringValue(body, 'unit', 'targetUnit', 'target_unit') ?? 'done';
  const unit = unitRaw.slice(0, 24);

  const rawFormat = stringValue(body, 'format') ?? 'first_to_goal';
  const format = FORMATS.has(rawFormat as RaceFormat) ? (rawFormat as RaceFormat) : 'first_to_goal';

  const recurrenceRaw = stringValue(body, 'recurrence') ?? 'none';
  const recurrence = RECURRENCES.has(recurrenceRaw as RaceRecurrence)
    ? (recurrenceRaw as RaceRecurrence)
    : 'none';

  return {
    verifierType: MANUAL_VERIFIER_TYPE,
    metric: 'reps',
    unit,
    format,
    scoringRule: scoringRuleForFormat(format, scoreDirectionFromBody(body)),
    targetValue,
    recurrence,
    timezone: stringValue(body, 'timezone') ?? 'America/New_York',
    startsAt: stringValue(body, 'startsAt', 'startLineAt') ?? null,
    endsAt: stringValue(body, 'endsAt', 'finishLineAt') ?? null,
  };
}
const COMPLETION_STRATEGIES = new Set(['completionAtTerminalPose', 'completionAfterSequenceReturn']);

function stringValue(body: Record<string, unknown>, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const value = body[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return undefined;
}

function intValue(body: Record<string, unknown>, ...keys: string[]): number | null {
  for (const key of keys) {
    const value = body[key];
    if (value === null) return null;
    if (typeof value === 'number' && value > 0) return Math.floor(value);
  }
  return null;
}

function recordValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function finiteNumber(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value);
}

function ratio(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
}

function stringList(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const strings = value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0);
  return strings.length === value.length ? strings : null;
}

function hasOnlyFiniteNumbers(value: unknown): boolean {
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(hasOnlyFiniteNumbers);
  if (value && typeof value === 'object') {
    return Object.values(value as Record<string, unknown>).every(hasOnlyFiniteNumbers);
  }
  return true;
}

function validatePoseFeatureVector(value: unknown): boolean {
  const vector = recordValue(value);
  const values = recordValue(vector?.values);
  if (!values || Object.keys(values).length === 0) return false;
  return Object.values(values).every((raw) => {
    const feature = recordValue(raw);
    return Boolean(
      feature &&
      finiteNumber(feature.value) &&
      ratio(feature.confidence) &&
      typeof feature.valid === 'boolean' &&
      typeof feature.kind === 'string' &&
      feature.kind.length > 0,
    );
  });
}

function validatePoseObject(value: unknown): boolean {
  const pose = recordValue(value);
  if (!pose) return false;
  const landmarks = recordValue(pose.landmarks);
  if (landmarks && Object.keys(landmarks).length > 0) return true;
  return validatePoseFeatureVector(pose.features);
}

function validateTemplateFrame(value: unknown): boolean {
  const frame = recordValue(value);
  if (!frame || !ratio(frame.position)) return false;
  const features = recordValue(frame.features);
  if (!features || Object.keys(features).length === 0) return false;
  return Object.values(features).every((raw) => {
    const feature = recordValue(raw);
    return Boolean(
      feature &&
      finiteNumber(feature.value) &&
      ratio(feature.confidence) &&
      ratio(feature.reliability) &&
      finiteNumber(feature.allowedVariation) &&
      Number(feature.allowedVariation) >= 0 &&
      typeof feature.contributingDemonstrationCount === 'number' &&
      feature.contributingDemonstrationCount > 0 &&
      typeof feature.kind === 'string' &&
      feature.kind.length > 0,
    );
  });
}

function validateCustomVerifierSpec(spec: Record<string, unknown>, customActivityName: string): string | null {
  if (!hasOnlyFiniteNumbers(spec)) return 'Custom verifier spec contains invalid numeric values.';
  if (spec.version !== CUSTOM_VERIFIER_VERSION) return 'Custom verifier version is not supported.';
  if (spec.verifierType !== CUSTOM_VERIFIER_TYPE) return 'Custom verifier type is not supported.';
  if (spec.measurementType !== 'count') return 'Custom verifier must count reps.';
  if (typeof spec.movementName !== 'string' || spec.movementName.trim() !== customActivityName) {
    return 'Custom movement name does not match the verifier spec.';
  }
  if (!validatePoseObject(spec.startPose) || !validatePoseObject(spec.completionPose)) {
    return 'Custom verifier is missing pose templates.';
  }
  if (typeof spec.completionStrategy !== 'string' || !COMPLETION_STRATEGIES.has(spec.completionStrategy)) {
    return 'Custom verifier has an unsupported completion strategy.';
  }
  const sequence = Array.isArray(spec.canonicalSequence) ? spec.canonicalSequence : null;
  if (!sequence || sequence.length === 0 || sequence.length > 180 || !sequence.every(validateTemplateFrame)) {
    return 'Custom verifier sequence is invalid.';
  }
  if (spec.expectedSequenceFrameCount !== sequence.length) {
    return 'Custom verifier frame count does not match the sequence.';
  }
  const required = stringList(spec.requiredFeatureIds);
  const active = stringList(spec.activeFeatureIds);
  if (!required || required.length === 0 || !active || active.length === 0) {
    return 'Custom verifier must include active and required features.';
  }
  if (new Set(active).size !== active.length || new Set(required).size !== required.length) {
    return 'Custom verifier contains duplicate feature ids.';
  }
  const activeSet = new Set(active);
  if (!required.every((id) => activeSet.has(id))) {
    return 'Custom verifier required features must also be active.';
  }
  let previousPosition = -1;
  for (const rawFrame of sequence) {
    const frame = recordValue(rawFrame);
    const position = typeof frame?.position === 'number' ? frame.position : -1;
    if (position <= previousPosition) return 'Custom verifier sequence positions must increase.';
    previousPosition = position;
    const features = recordValue(frame?.features);
    if (!features) return 'Custom verifier sequence is invalid.';
    if (!Object.keys(features).every((id) => activeSet.has(id))) {
      return 'Custom verifier sequence uses inactive features.';
    }
  }
  if (sequence.length > 1) {
    const first = recordValue(sequence[0]);
    const last = recordValue(sequence[sequence.length - 1]);
    if (first?.position !== 0 || last?.position !== 1) {
      return 'Custom verifier sequence must include start and finish frames.';
    }
  }
  const thresholds = [
    spec.sequenceSimilarityThreshold,
    spec.completionSimilarityThreshold,
    spec.resetSimilarityThreshold,
    spec.minimumValidFeatureRatio,
    spec.minimumVisibility,
  ];
  if (!thresholds.every(ratio)) return 'Custom verifier thresholds are invalid.';
  if (typeof spec.cooldownMs !== 'number' || spec.cooldownMs <= 0 || spec.cooldownMs > 10000) {
    return 'Custom verifier cooldown is invalid.';
  }
  return null;
}

/**
 * Motion-V2 learned specs are opaque to the worker — the trained encoder owns
 * their semantics. Structural check only: the spec's own verifier marker, the
 * movement name, and the reference demos it was learned from.
 */
function validateMotionV2Spec(spec: Record<string, unknown>, customActivityName: string): string | null {
  if (!hasOnlyFiniteNumbers(spec)) return 'Custom verifier spec contains invalid numeric values.';
  if (spec.verifier !== MOTION_V2_VERIFIER_TYPE) return 'Custom verifier type is not supported.';
  if (typeof spec.schema !== 'number' || !Number.isFinite(spec.schema)) {
    return 'Custom verifier spec is invalid.';
  }
  const name = typeof spec.name === 'string' ? spec.name.trim() : '';
  if (name.toLowerCase() !== customActivityName.trim().toLowerCase()) {
    return 'Custom movement name does not match the verifier spec.';
  }
  const refs = spec.references;
  if (!Array.isArray(refs) || refs.length === 0 || refs.length > 4) {
    return 'Custom verifier spec has no reference demos.';
  }
  for (const rawRef of refs) {
    const ref = recordValue(rawRef);
    if (!Array.isArray(ref?.proto) || ref.proto.length === 0 ||
        !Array.isArray(ref?.traj) || ref.traj.length === 0) {
      return 'Custom verifier spec references are invalid.';
    }
  }
  return null;
}

export function customConfigFromBody(body: Record<string, unknown>): CustomRaceConfig | null | { error: string } {
  const verifierType = stringValue(body, 'verifierType', 'verifier_type');
  if (!verifierType) return null;
  if (!isCustomVerifierType(verifierType)) return { error: 'Verifier type is not supported.' };
  const isV2 = verifierType === MOTION_V2_VERIFIER_TYPE;

  const verifierVersion = intValue(body, 'verifierVersion', 'verifier_version');
  const expectedVersion = isV2 ? MOTION_V2_VERIFIER_VERSION : CUSTOM_VERIFIER_VERSION;
  if (verifierVersion !== expectedVersion) return { error: 'Verifier version is not supported.' };

  const customActivityName = stringValue(body, 'customActivityName', 'custom_activity_name');
  if (!customActivityName || customActivityName.length > 40) {
    return { error: 'Custom movement name is required.' };
  }

  const presetActivity = normalizeActivityId(stringValue(body, 'activityId', 'activity_id', 'aiActivityType'));
  if (presetActivity && activityForId(presetActivity)?.availability === 'supported') {
    return { error: 'Custom races cannot use a preset activity.' };
  }

  const spec = recordValue(body.verifierSpec ?? body.verifier_spec);
  if (!spec) return { error: 'Custom verifier spec is required.' };
  const specError = isV2
    ? validateMotionV2Spec(spec, customActivityName)
    : validateCustomVerifierSpec(spec, customActivityName);
  if (specError) return { error: specError };
  const verifierSpecJson = JSON.stringify(spec);
  const maxSpecBytes = isV2 ? MOTION_V2_SPEC_MAX_BYTES : CUSTOM_VERIFIER_SPEC_MAX_BYTES;
  if (new TextEncoder().encode(verifierSpecJson).length > maxSpecBytes) {
    return { error: 'Custom verifier spec is too large.' };
  }

  // Win condition. Absent / unknown keeps the original contract: a race to a
  // target (older clients never sent a format for custom races).
  const rawFormat = stringValue(body, 'format') ?? 'first_to_goal';
  if (!FORMATS.has(rawFormat as RaceFormat)) return { error: 'Race format is not supported.' };
  const format = rawFormat as RaceFormat;

  const targetValue = intValue(body, 'targetValue', 'target_value');
  if (format === 'first_to_goal' && !targetValue) return { error: 'Target is required.' };

  const endsAt = stringValue(body, 'endsAt', 'finishLineAt') ?? null;
  const attemptDurationSeconds =
    format === 'first_to_goal' ? null : intValue(body, 'attemptDurationSeconds', 'attempt_duration_seconds');
  const attemptLimit =
    format === 'first_to_goal' ? null : intValue(body, 'attemptLimit', 'attempt_limit');
  if (format === 'most_in_window' && !endsAt) return { error: 'A finish line is required.' };
  if (format === 'timed_attempt' && !attemptDurationSeconds) {
    return { error: 'Attempt duration is required.' };
  }

  const recurrenceRaw = stringValue(body, 'recurrence') ?? 'none';
  const recurrence = RECURRENCES.has(recurrenceRaw as RaceRecurrence) ? recurrenceRaw as RaceRecurrence : 'none';

  return {
    verifierType,
    verifierVersion: expectedVersion,
    verifierSpecJson,
    customActivityName,
    metric: 'reps',
    format,
    scoringRule: scoringRuleForFormat(format, scoreDirectionFromBody(body)),
    // A window / attempt race has nothing to reach — never store a made-up target.
    targetValue: format === 'first_to_goal' ? targetValue : null,
    attemptDurationSeconds,
    attemptLimit,
    verificationMethod: 'ai',
    timezone: stringValue(body, 'timezone') ?? 'America/New_York',
    startsAt: stringValue(body, 'startsAt', 'startLineAt') ?? null,
    endsAt,
    recurrence,
  };
}

export function configFromBody(body: Record<string, unknown>): RaceConfig | { error: string } {
  const activityId = normalizeActivityId(stringValue(body, 'activityId', 'activity_id', 'aiActivityType'));
  if (!activityId) return { error: 'Choose a supported activity.' };

  const activity = activityForId(activityId);
  if (!activity || activity.availability !== 'supported') return { error: 'Nuvo cannot verify this movement yet.' };

  const metric = normalizeMetric(stringValue(body, 'metric', 'targetUnit', 'unit'), activity);
  if (!metric || !activity.supportedMetrics.includes(metric)) {
    return { error: `${activity.displayName} cannot use that metric.` };
  }

  const rawFormat = stringValue(body, 'format') ?? 'first_to_goal';
  const format = FORMATS.has(rawFormat as RaceFormat) ? rawFormat as RaceFormat : undefined;
  if (!format || !activity.supportedFormats.includes(format)) {
    return { error: `${activity.displayName} does not support that win condition yet.` };
  }

  const targetValue = intValue(body, 'targetValue', 'target_value');
  if (format === 'first_to_goal' && !targetValue) return { error: 'Target is required.' };

  const recurrenceRaw = stringValue(body, 'recurrence') ?? 'none';
  const recurrence = RECURRENCES.has(recurrenceRaw as RaceRecurrence) ? recurrenceRaw as RaceRecurrence : 'none';
  const scoringRule = scoringRuleForFormat(format, scoreDirectionFromBody(body));

  return {
    activityId,
    metric,
    format,
    scoringRule,
    targetValue,
    attemptDurationSeconds: intValue(body, 'attemptDurationSeconds', 'attempt_duration_seconds'),
    attemptLimit: intValue(body, 'attemptLimit', 'attempt_limit'),
    verificationMethod: 'camera_pose',
    timezone: stringValue(body, 'timezone') ?? 'America/New_York',
    startsAt: stringValue(body, 'startsAt', 'startLineAt') ?? null,
    endsAt: stringValue(body, 'endsAt', 'finishLineAt') ?? null,
    recurrence,
  };
}

/**
 * Builds a race config for a control-plane activity that has no static
 * catalog entry (a motion published after this Worker build). The registry
 * row supplies metric/format bounds; everything else mirrors configFromBody.
 */
export function registryConfigFromBody(
  body: Record<string, unknown>,
  activity: RegistryActivity,
): RaceConfig | { error: string } {
  const expectedMetric = normalizeMetric(activity.metric) ?? 'reps';
  const requested = normalizeMetric(
    stringValue(body, 'metric', 'targetUnit', 'unit'),
  );
  if (requested && requested !== expectedMetric) {
    return { error: `${activity.displayName} cannot use that metric.` };
  }

  const rawFormat = stringValue(body, 'format') ?? 'first_to_goal';
  const format = FORMATS.has(rawFormat as RaceFormat) ? rawFormat as RaceFormat : undefined;
  if (!format ||
      (activity.supportedFormats.length > 0 &&
       !activity.supportedFormats.includes(format))) {
    return { error: `${activity.displayName} does not support that win condition yet.` };
  }

  const targetValue = intValue(body, 'targetValue', 'target_value');
  if (format === 'first_to_goal' && !targetValue) return { error: 'Target is required.' };

  const recurrenceRaw = stringValue(body, 'recurrence') ?? 'none';
  const recurrence = RECURRENCES.has(recurrenceRaw as RaceRecurrence) ? recurrenceRaw as RaceRecurrence : 'none';

  return {
    activityId: activity.id,
    metric: expectedMetric,
    format,
    scoringRule: scoringRuleForFormat(format, scoreDirectionFromBody(body)),
    targetValue,
    attemptDurationSeconds: intValue(body, 'attemptDurationSeconds', 'attempt_duration_seconds'),
    attemptLimit: intValue(body, 'attemptLimit', 'attempt_limit'),
    verificationMethod: 'camera_pose',
    timezone: stringValue(body, 'timezone') ?? 'America/New_York',
    startsAt: stringValue(body, 'startsAt', 'startLineAt') ?? null,
    endsAt: stringValue(body, 'endsAt', 'finishLineAt') ?? null,
    recurrence,
  };
}

export function assertSubmissionCompatible(config: RaceConfig, activityId: string | null, metric: string | null): string | null {
  if (normalizeActivityIdLoose(activityId) !== config.activityId) return 'Verified movement does not match this race.';
  if (normalizeMetric(metric, activityForId(config.activityId)) !== config.metric) return 'Verified metric does not match this race.';
  return null;
}
