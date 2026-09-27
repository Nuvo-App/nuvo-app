/**
 * Scheduled notification reminders (docs/agents/21-notification-reengagement-
 * plan.md §5). Jobs are written at event time (race created with a start
 * line) and claimed by the minute cron. They are NOT a domain authority:
 * claim-time handlers re-validate the world (race still scheduled? member
 * still active?) and no-op when it moved on. Race correctness never depends
 * on a job firing — lifecycle transitions belong to domain/raceFinalize.ts.
 */
import { generateId } from '../lib/crypto';
import type { RaceRow } from '../types';

export const JOB_KINDS = ['race_starting_soon'] as const;
export type NotificationJobKind = (typeof JOB_KINDS)[number];

export interface NotificationJobRow {
  id: string;
  kind: NotificationJobKind;
  entity_type: string;
  entity_id: string;
  user_id: string | null;
  dedupe_key: string;
  run_at: string;
  payload_json: string | null;
  status: string;
  created_at: string;
}

/** How far before `start_at` the "starts soon" reminder lands. */
export const STARTING_SOON_LEAD_MS = 30 * 60 * 1000;

/**
 * Schedule the pre-start reminder for a scheduled race. No-op when the race
 * has no start line or the reminder window already passed. The dedupe key
 * carries `startAt`, so PATCHing a new start line arms a new job while the
 * stale one self-cancels at claim time (see jobStillRelevant).
 */
export async function scheduleRaceStartingSoon(
  db: D1Database,
  raceId: string,
  startAt: string | null,
  now = new Date(),
): Promise<void> {
  if (!startAt) return;
  const runAt = new Date(new Date(startAt).getTime() - STARTING_SOON_LEAD_MS);
  if (runAt.getTime() <= now.getTime()) return;
  await db
    .prepare(
      `INSERT OR IGNORE INTO notification_jobs
        (id, kind, entity_type, entity_id, dedupe_key, run_at, payload_json)
       VALUES (?, 'race_starting_soon', 'race', ?, ?, ?, NULL)`,
    )
    .bind(
      generateId(),
      raceId,
      `job:race_starting_soon:${raceId}:${startAt}`,
      runAt.toISOString(),
    )
    .run();
}

/**
 * Claim due pending jobs atomically — a row is marked 'claimed' before it is
 * handed out, so a retried sweep or concurrent claim can't deliver twice.
 * The handler marks 'sent' (or back to 'pending' on transient failure).
 */
export async function claimDueJobs(
  db: D1Database,
  now = new Date(),
  limit = 50,
): Promise<NotificationJobRow[]> {
  const due = await db
    .prepare(
      `SELECT * FROM notification_jobs
       WHERE status = 'pending' AND run_at <= ?
       ORDER BY run_at ASC LIMIT ?`,
    )
    .bind(now.toISOString(), limit)
    .all<NotificationJobRow>();
  const claimed: NotificationJobRow[] = [];
  for (const job of due.results) {
    const res = await db
      .prepare(
        `UPDATE notification_jobs SET status = 'claimed'
         WHERE id = ? AND status = 'pending'`,
      )
      .bind(job.id)
      .run();
    if ((res.meta?.changes ?? 0) > 0) claimed.push(job);
  }
  return claimed;
}

export async function markJobDone(
  db: D1Database,
  jobId: string,
  status: 'sent' | 'cancelled' | 'pending',
): Promise<void> {
  await db
    .prepare('UPDATE notification_jobs SET status = ? WHERE id = ?')
    .bind(status, jobId)
    .run();
}

/**
 * Re-validate a race_starting_soon job at claim time: the race must still
 * exist, still be scheduled (start_at in the future, status active — a race
 * that started/finished/cancelled gets nothing), AND the job's run_at must
 * still match the race's actual start line. A PATCH that moved start_at
 * leaves a stale job whose reminder would fire at the wrong moment — this
 * check cancels it.
 */
export function jobStillRelevant(job: NotificationJobRow, race: RaceRow | null, now = new Date()): boolean {
  if (job.kind !== 'race_starting_soon') return true;
  if (!race || race.status !== 'active' || race.deleted_at || !race.start_at) return false;
  const start = new Date(race.start_at).getTime();
  if (start <= now.getTime()) return false;
  const expectedRunAt = start - STARTING_SOON_LEAD_MS;
  const drift = Math.abs(new Date(job.run_at).getTime() - expectedRunAt);
  return drift < 60 * 1000; // scheduled for a start line that has since moved
}
