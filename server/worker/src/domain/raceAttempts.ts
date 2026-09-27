/**
 * Attempt lifecycle for best_attempt / timed_attempt races (docs/agents/
 * 21-race-system-v2-design.md §20, Phase D).
 *
 *   POST /:id/attempts            → authoritative start (open attempt)
 *   next verified /proof submit   → binds to the open attempt (auto-bind —
 *                                   no client contract change needed)
 *   timer end / submit            → score locked, maximum_attempt scoring
 *                                   recomputes best
 *
 * An open attempt that outlives its duration + grace is 'expired' lazily on
 * the next read/write — no sweeper needed.
 */
import type { RaceRow } from '../types';
import { generateId } from '../lib/crypto';
import { effectiveRaceStatus } from './raceLifecycle';

export interface RaceAttemptRow {
  id: string;
  race_id: string;
  user_id: string;
  attempt_index: number;
  client_attempt_id: string | null;
  status: string;
  started_at: string;
  deadline_at: string | null;
  submitted_at: string | null;
  score: number | null;
  move_log_id: string | null;
  created_at: string;
}

/** Submit grace beyond the declared duration — covers upload latency. */
export const ATTEMPT_SUBMIT_GRACE_MS = 15 * 1000;
/** An untimed attempt left open this long is abandoned, not live. */
export const OPEN_ATTEMPT_TTL_MS = 6 * 60 * 60 * 1000;

export function formatUsesAttempts(format: string): boolean {
  return format === 'best_attempt' || format === 'timed_attempt';
}

export type AttemptOpenError =
  | 'not_active'
  | 'wrong_format'
  | 'attempt_in_progress'
  | 'attempt_limit_reached';

export interface AttemptOpenResult {
  ok: boolean;
  error?: AttemptOpenError;
  attempt?: RaceAttemptRow;
  attemptsUsed?: number;
}

export async function openAttempt(
  db: D1Database,
  race: RaceRow,
  userId: string,
  clientAttemptId: string | null,
  now = new Date(),
): Promise<AttemptOpenResult> {
  const format = (race.format ?? race.race_type) as string;
  if (!formatUsesAttempts(format)) return { ok: false, error: 'wrong_format' };
  if (effectiveRaceStatus(race.status, race.start_at, race.end_at, now) !== 'active') {
    return { ok: false, error: 'not_active' };
  }

  // Idempotent: a retried open returns the same attempt.
  if (clientAttemptId) {
    const existing = await db
      .prepare(
        'SELECT * FROM race_attempts WHERE race_id = ? AND user_id = ? AND client_attempt_id = ?',
      )
      .bind(race.id, userId, clientAttemptId)
      .first<RaceAttemptRow>();
    if (existing) return { ok: true, attempt: existing, attemptsUsed: await attemptsUsed(db, race.id, userId) };
  }

  await expireStaleOpenAttempts(db, race.id, userId, race, now);

  const open = await db
    .prepare(
      "SELECT * FROM race_attempts WHERE race_id = ? AND user_id = ? AND status = 'open'",
    )
    .bind(race.id, userId)
    .first<RaceAttemptRow>();
  if (open) return { ok: false, error: 'attempt_in_progress', attempt: open };

  const used = await attemptsUsed(db, race.id, userId);
  if (race.attempt_limit != null && used >= race.attempt_limit) {
    return { ok: false, error: 'attempt_limit_reached', attemptsUsed: used };
  }

  const durationMs = race.attempt_duration_seconds != null ? race.attempt_duration_seconds * 1000 : null;
  const deadline = durationMs != null ? new Date(now.getTime() + durationMs).toISOString() : null;
  const attemptId = generateId();
  await db
    .prepare(
      `INSERT INTO race_attempts
         (id, race_id, user_id, attempt_index, client_attempt_id, status, started_at, deadline_at, created_at)
       VALUES (?, ?, ?, ?, ?, 'open', ?, ?, CURRENT_TIMESTAMP)`,
    )
    .bind(attemptId, race.id, userId, used + 1, clientAttemptId, now.toISOString(), deadline)
    .run();

  const attempt = await db.prepare('SELECT * FROM race_attempts WHERE id = ?').bind(attemptId).first<RaceAttemptRow>();
  return { ok: true, attempt: attempt ?? undefined, attemptsUsed: used };
}

export async function attemptsUsed(db: D1Database, raceId: string, userId: string): Promise<number> {
  const row = await db
    .prepare(
      "SELECT COUNT(*) as n FROM race_attempts WHERE race_id = ? AND user_id = ? AND status IN ('open','submitted','expired')",
    )
    .bind(raceId, userId)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

/**
 * Find the attempt this verified submission belongs to. Auto-bind is the
 * contract: the client never has to thread an attempt id through the proof
 * payload — opening an attempt then submitting proof is enough.
 */
export async function bindableOpenAttempt(
  db: D1Database,
  race: RaceRow,
  userId: string,
  now = new Date(),
): Promise<RaceAttemptRow | null> {
  if (!formatUsesAttempts((race.format ?? race.race_type) as string)) return null;
  const attempt = await db
    .prepare(
      "SELECT * FROM race_attempts WHERE race_id = ? AND user_id = ? AND status = 'open' ORDER BY started_at DESC LIMIT 1",
    )
    .bind(race.id, userId)
    .first<RaceAttemptRow>();
  if (!attempt) return null;

  // Timed attempt past its deadline + grace → expired, no bind.
  if (attempt.deadline_at) {
    const deadlineMs = new Date(attempt.deadline_at).getTime() + ATTEMPT_SUBMIT_GRACE_MS;
    if (now.getTime() > deadlineMs) {
      await expireAttempt(db, attempt.id);
      return null;
    }
  }
  return attempt;
}

export async function closeAttempt(
  db: D1Database,
  attemptId: string,
  score: number,
  moveLogId: string,
): Promise<void> {
  await db
    .prepare(
      "UPDATE race_attempts SET status = 'submitted', submitted_at = CURRENT_TIMESTAMP, score = ?, move_log_id = ? WHERE id = ?",
    )
    .bind(score, moveLogId, attemptId)
    .run();
}

export async function expireAttempt(db: D1Database, attemptId: string): Promise<void> {
  await db
    .prepare("UPDATE race_attempts SET status = 'expired' WHERE id = ? AND status = 'open'")
    .bind(attemptId)
    .run();
}

async function expireStaleOpenAttempts(
  db: D1Database,
  raceId: string,
  userId: string,
  _race: RaceRow,
  now: Date,
): Promise<void> {
  const opens = await db
    .prepare("SELECT * FROM race_attempts WHERE race_id = ? AND user_id = ? AND status = 'open'")
    .bind(raceId, userId)
    .all<RaceAttemptRow>();
  for (const attempt of opens.results) {
    const started = new Date(attempt.started_at).getTime();
    const deadlineMs = attempt.deadline_at
      ? new Date(attempt.deadline_at).getTime() + ATTEMPT_SUBMIT_GRACE_MS
      : started + OPEN_ATTEMPT_TTL_MS;
    if (now.getTime() > deadlineMs) await expireAttempt(db, attempt.id);
  }
}
