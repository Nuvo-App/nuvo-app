/**
 * Profile record strip (racing now, wins, win rate), computed server-side so
 * the Profile screen does not need the full races list. Mirrors the client's
 * raceIsActive / raceIsCompleted and win logic exactly.
 */
import { effectiveRaceStatus } from './raceLifecycle';

export interface ProfileRecordRow {
  /** Effective race status (stored status resolved against start/end times). */
  status: string;
  winnerUserId: string | null;
  /** The user has a rank_position = 1 row in race_final_standings. */
  hasRankOne: boolean;
}

export interface ProfileRecord {
  active: number;
  finished: number;
  wins: number;
  winRatePercent: number | null;
}

// Same set as the client's _completedRaceStatuses (race_display.dart).
const COMPLETED_STATUSES = new Set(['completed', 'complete', 'finished', 'archived', 'cancelled']);

export function computeRecord(rows: ProfileRecordRow[], userId?: string): ProfileRecord {
  let active = 0;
  let finished = 0;
  let wins = 0;
  for (const r of rows) {
    if (COMPLETED_STATUSES.has(r.status)) {
      finished += 1;
      // A cancelled race's positional rank never counts as a win.
      if (r.status !== 'cancelled') {
        const recordedWinner = userId !== undefined ? r.winnerUserId === userId : false;
        if (recordedWinner || r.hasRankOne) wins += 1;
      }
    } else if (r.status === 'active') {
      active += 1;
    }
  }
  return {
    active,
    finished,
    wins,
    winRatePercent: finished === 0 ? null : Math.round((wins / finished) * 100),
  };
}

/** One query: every non-deleted race the user is an active member of. */
export async function readProfileRecord(db: D1Database, userId: string): Promise<ProfileRecord> {
  const result = await db
    .prepare(
      `SELECT r.status AS status, r.start_at AS start_at, r.end_at AS end_at,
              r.winner_user_id AS winner_user_id,
              EXISTS (SELECT 1 FROM race_final_standings fs
                       WHERE fs.race_id = r.id AND fs.user_id = ? AND fs.rank_position = 1) AS rank_one
         FROM race_members m
         JOIN races r ON r.id = m.race_id
        WHERE m.user_id = ? AND m.status = 'active' AND r.deleted_at IS NULL`,
    )
    .bind(userId, userId)
    .all<{
      status: string;
      start_at: string | null;
      end_at: string | null;
      winner_user_id: string | null;
      rank_one: number;
    }>();
  const rows: ProfileRecordRow[] = (result.results ?? []).map((r) => ({
    status: effectiveRaceStatus(r.status, r.start_at, r.end_at),
    winnerUserId: r.winner_user_id ?? null,
    hasRankOne: Number(r.rank_one) === 1,
  }));
  return computeRecord(rows, userId);
}
