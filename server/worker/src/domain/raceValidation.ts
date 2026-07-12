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

const FORMATS = new Set<RaceFormat>(['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);
const RECURRENCES = new Set<RaceRecurrence>(['none', 'daily', 'weekly']);

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
