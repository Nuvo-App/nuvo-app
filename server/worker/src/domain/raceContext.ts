/**
 * Competitive context — the canonical, server-derived answer to "how am I
 * doing in this race?" (docs/agents/21-race-system-v2-design.md §25).
 *
 * Structured numbers, not strings: clients (race detail, Crew, notifications)
 * render copy in Nuvo language from these fields. Pure — no I/O.
 */
import { effectiveRaceStatus } from './raceLifecycle';

export interface ViewerContextInput {
  raceId: string;
  format: string;
  targetValue: number | null;
  startAt: string | null;
  endAt: string | null;
  storedStatus: string;
  winnerUserId: string | null;
  scoreDirection: string;
  attemptLimit: number | null;
  attemptDurationSeconds: number | null;
  /** Active members ordered by rank (rank_cache ASC, score DESC, joined ASC). */
  standings: Array<{
    userId: string;
    score: number;
    rank: number | null;
    finishedAt?: string | null;
  }>;
  attemptsUsed: number;
  openAttemptId: string | null;
  viewerUserId: string | undefined;
  now?: Date;
}

export interface RaceViewerContext {
  isMember: boolean;
  isSpectator: boolean;
  status: string;
  score: number;
  rank: number | null;
  participantCount: number;
  leaderUserId: string | null;
  leaderScore: number | null;
  isLeading: boolean;
  isTied: boolean;
  isFinished: boolean;
  /** Units (metric scale) behind the current leader. 0 when leading/tied. */
  gapToLeader: number | null;
  /** Units behind the next rank above the viewer. */
  gapToNextRank: number | null;
  /** Units left to reach the goal (first_to_goal / goal-by-deadline). */
  goalRemaining: number | null;
  timeRemainingSeconds: number | null;
  startsInSeconds: number | null;
  attemptsUsed: number;
  attemptsRemaining: number | null;
  openAttemptId: string | null;
  /** True when the race's win condition is "lowest score" (fastest time). */
  lowerIsBetter: boolean;
}

export function computeViewerContext(input: ViewerContextInput): RaceViewerContext {
  const now = input.now ?? new Date();
  const status = effectiveRaceStatus(input.storedStatus, input.startAt, input.endAt, now);
  const viewerId = input.viewerUserId;
  const standings = input.standings;
  const me = viewerId ? standings.find((s) => s.userId === viewerId) : undefined;
  const isMember = Boolean(me);
  const leader = standings[0] ?? null;
  const leaderScore = leader?.score ?? null;
  const lowerIsBetter = input.scoreDirection === 'lower';

  const myScore = me?.score ?? 0;
  const myRank = me?.rank ?? null;
  const isLeading = Boolean(me && leader && me.userId === leader.userId);
  const isTied = Boolean(
    me && standings.filter((s) => s.score === myScore && s.userId !== viewerId).length > 0,
  );

  let gapToLeader: number | null = null;
  if (leader && !isLeading) {
    gapToLeader = lowerIsBetter ? myScore - leaderScore! : leaderScore! - myScore;
    if (gapToLeader <= 0) gapToLeader = 0;
  }

  let gapToNextRank: number | null = null;
  if (me && myRank !== null) {
    const ahead = standings.filter((s) => (s.rank ?? 9999) < myRank);
    const nearest = ahead.length > 0 ? ahead[ahead.length - 1] : null;
    if (nearest) {
      gapToNextRank = lowerIsBetter ? myScore - nearest.score : nearest.score - myScore;
      if (gapToNextRank < 0) gapToNextRank = 0;
    }
  }

  let goalRemaining: number | null = null;
  if (input.targetValue != null && input.targetValue > 0) {
    goalRemaining = Math.max(0, input.targetValue - myScore);
  }

  let timeRemainingSeconds: number | null = null;
  if (input.endAt) {
    timeRemainingSeconds = Math.max(0, Math.floor((new Date(input.endAt).getTime() - now.getTime()) / 1000));
  }
  let startsInSeconds: number | null = null;
  if (input.startAt) {
    const s = Math.floor((new Date(input.startAt).getTime() - now.getTime()) / 1000);
    startsInSeconds = s > 0 ? s : null;
  }

  const isFinished = Boolean(
    me && (me.finishedAt != null || (input.targetValue != null && input.targetValue > 0 && myScore >= input.targetValue)),
  );

  const attemptsRemaining =
    input.attemptLimit != null ? Math.max(0, input.attemptLimit - input.attemptsUsed) : null;

  return {
    isMember,
    isSpectator: Boolean(viewerId && !isMember),
    status,
    score: myScore,
    rank: myRank,
    participantCount: standings.length,
    leaderUserId: leader?.userId ?? null,
    leaderScore,
    isLeading,
    isTied,
    isFinished,
    gapToLeader,
    gapToNextRank,
    goalRemaining,
    timeRemainingSeconds,
    startsInSeconds,
    attemptsUsed: input.attemptsUsed,
    attemptsRemaining,
    openAttemptId: input.openAttemptId,
    lowerIsBetter,
  };
}
