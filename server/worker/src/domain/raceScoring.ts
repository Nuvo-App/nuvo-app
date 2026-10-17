import type { RaceFormat, RaceScoringRule } from './raceActivities';

import { effectiveTargetValue } from './raceTarget';

export interface ScoreInput {
  format: RaceFormat;
  scoringRule: RaceScoringRule;
  previousScore: number;
  submissionValue: number;
  targetValue: number | null;
}

export interface ScoreOutput {
  newScore: number;
  progressPercent: number;
  completed: boolean;
}

export function applyVerifiedSubmission(input: ScoreInput): ScoreOutput {
  const value = Math.max(0, Math.floor(input.submissionValue));
  // minimum_attempt: the stored score is the lowest real submitted value;
  // previousScore 0 means "no score yet", never "score of zero".
  const newScore = input.scoringRule === 'maximum_attempt'
    ? Math.max(input.previousScore, value)
    : input.scoringRule === 'minimum_attempt'
      ? (input.previousScore > 0 ? Math.min(input.previousScore, value) : value)
      : input.previousScore + value;
  const target = effectiveTargetValue(input.format, input.targetValue);
  const progressPercent = target ? Math.min(100, Math.round((newScore / target) * 100)) : 0;
  const completed = input.format === 'first_to_goal' && Boolean(target && newScore >= target);
  return { newScore, progressPercent, completed };
}

/** Largest value one proof may carry, per metric. Real work never gets near
 *  these; they only stop an absurd claim from deciding a race in one write. */
export const MAX_REPS_PER_SUBMISSION = 3000;
export const MAX_SECONDS_PER_SUBMISSION = 8 * 60 * 60;
/** Honor-logged units ("pages", "minutes", "steps") are free-form. */
export const MAX_MANUAL_VALUE_PER_SUBMISSION = 100_000;

export function maxSubmissionValue(metric: string | null | undefined, manual: boolean): number {
  if (manual) return MAX_MANUAL_VALUE_PER_SUBMISSION;
  return metric === 'seconds' ? MAX_SECONDS_PER_SUBMISSION : MAX_REPS_PER_SUBMISSION;
}
