/**
 * Race domain events — the canonical "what happened" log (docs/agents/
 * 21-race-system-v2-design.md §19).
 *
 * `race_events` is append-only and durable; `races`/`race_progress` remain
 * authoritative for current state. Scoring/lifecycle domain functions RETURN
 * transition descriptors; route/cron code persists them here and decides
 * what consumers see (notifications via safeEmit today, Agent 2's policy
 * pipeline later — race code never calls push directly).
 */
import { generateId } from '../lib/crypto';

export const RACE_EVENT_TYPES = [
  'race_created',
  'race_joined',
  'race_started',
  'progress_accepted',
  'rank_changed',
  'lead_changed',
  'attempt_started',
  'attempt_completed',
  'participant_finished',
  'race_finished',
  'winner_determined',
  'personal_best',
  'rematch_requested',
  'proof_vetoed',
] as const;
export type RaceEventType = (typeof RACE_EVENT_TYPES)[number];

export interface RaceEventInput {
  type: RaceEventType;
  actorUserId?: string | null;
  subjectUserId?: string | null;
  payload?: Record<string, unknown>;
  /** The move_log row this event was produced by — lets a proof veto void
   *  exactly the canonical events that proof created. */
  moveLogId?: string | null;
}

export interface RaceEventRow {
  id: string;
  race_id: string;
  event_type: string;
  actor_user_id: string | null;
  subject_user_id: string | null;
  payload_json: string | null;
  created_at: string;
}

/**
 * Persist a batch of domain events for one race inside the caller's D1 batch
 * when possible. Falls back to individual writes for >1 event (D1 batch is
 * used to keep the write atomic with itself).
 */
export async function recordRaceEvents(
  db: D1Database,
  raceId: string,
  events: RaceEventInput[],
): Promise<void> {
  if (events.length === 0) return;
  const stmts = events.map((e) =>
    db
      .prepare(
        `INSERT INTO race_events (id, race_id, event_type, actor_user_id, subject_user_id, payload_json, move_log_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      )
      .bind(
        generateId(),
        raceId,
        e.type,
        e.actorUserId ?? null,
        e.subjectUserId ?? null,
        e.payload ? JSON.stringify(e.payload) : null,
        e.moveLogId ?? null,
      ),
  );
  await db.batch(stmts);
}

export async function recordRaceEvent(
  db: D1Database,
  raceId: string,
  event: RaceEventInput,
): Promise<void> {
  return recordRaceEvents(db, raceId, [event]);
}
