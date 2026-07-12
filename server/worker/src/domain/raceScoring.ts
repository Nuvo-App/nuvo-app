import type { RaceFormat, RaceScoringRule } from './raceActivities';

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
  const newScore = input.scoringRule === 'maximum_attempt'
    ? Math.max(input.previousScore, value)
    : input.previousScore + value;
  const target = input.targetValue && input.targetValue > 0 ? input.targetValue : null;
  const progressPercent = target ? Math.min(100, Math.round((newScore / target) * 100)) : 0;
  const completed = input.format === 'first_to_goal' && Boolean(target && newScore >= target);
  return { newScore, progressPercent, completed };
}
