import {
  activityForId,
  normalizeActivityId,
  normalizeMetric,
  scoringRuleForFormat,
  type RaceActivityId,
  type RaceFormat,
  type RaceMetric,
  type RaceRecurrence,
  type RaceScoringRule,
  type VerificationMethod,
} from './raceActivities';

export interface RaceConfig {
  activityId: RaceActivityId;
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
export const PRESET_VERIFIER_TYPE = 'preset_pose';
export const CUSTOM_VERIFIER_VERSION = 1;
export const CUSTOM_VERIFIER_SPEC_MAX_BYTES = 128 * 1024;

export interface CustomRaceConfig {
  verifierType: typeof CUSTOM_VERIFIER_TYPE;
  verifierVersion: typeof CUSTOM_VERIFIER_VERSION;
  verifierSpecJson: string;
  customActivityName: string;
  metric: 'reps';
  format: 'first_to_goal';
  scoringRule: 'cumulative_sum';
  targetValue: number;
  attemptDurationSeconds: null;
  attemptLimit: null;
  verificationMethod: 'ai';
  timezone: string;
  startsAt: string | null;
  endsAt: string | null;
  recurrence: RaceRecurrence;
}

const FORMATS = new Set<RaceFormat>(['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);
const RECURRENCES = new Set<RaceRecurrence>(['none', 'daily', 'weekly']);
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

export function customConfigFromBody(body: Record<string, unknown>): CustomRaceConfig | null | { error: string } {
  const verifierType = stringValue(body, 'verifierType', 'verifier_type');
  if (!verifierType) return null;
  if (verifierType !== CUSTOM_VERIFIER_TYPE) return { error: 'Verifier type is not supported.' };

  const verifierVersion = intValue(body, 'verifierVersion', 'verifier_version');
  if (verifierVersion !== CUSTOM_VERIFIER_VERSION) return { error: 'Verifier version is not supported.' };

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
  const specError = validateCustomVerifierSpec(spec, customActivityName);
  if (specError) return { error: specError };
  const verifierSpecJson = JSON.stringify(spec);
  if (new TextEncoder().encode(verifierSpecJson).length > CUSTOM_VERIFIER_SPEC_MAX_BYTES) {
    return { error: 'Custom verifier spec is too large.' };
  }

  const targetValue = intValue(body, 'targetValue', 'target_value');
  if (!targetValue) return { error: 'Target is required.' };
  const recurrenceRaw = stringValue(body, 'recurrence') ?? 'none';
  const recurrence = RECURRENCES.has(recurrenceRaw as RaceRecurrence) ? recurrenceRaw as RaceRecurrence : 'none';

  return {
    verifierType: CUSTOM_VERIFIER_TYPE,
    verifierVersion: CUSTOM_VERIFIER_VERSION,
    verifierSpecJson,
    customActivityName,
    metric: 'reps',
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    targetValue,
    attemptDurationSeconds: null,
    attemptLimit: null,
    verificationMethod: 'ai',
    timezone: stringValue(body, 'timezone') ?? 'America/New_York',
    startsAt: stringValue(body, 'startsAt', 'startLineAt') ?? null,
    endsAt: stringValue(body, 'endsAt', 'finishLineAt') ?? null,
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
  const scoringRule = scoringRuleForFormat(format);

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

export function assertSubmissionCompatible(config: RaceConfig, activityId: string | null, metric: string | null): string | null {
  if (normalizeActivityId(activityId) !== config.activityId) return 'Verified movement does not match this race.';
  if (normalizeMetric(metric, activityForId(config.activityId)) !== config.metric) return 'Verified metric does not match this race.';
  return null;
}
