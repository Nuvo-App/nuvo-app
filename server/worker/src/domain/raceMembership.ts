/**
 * Shared race-membership primitives. The invite-acceptance path
 * (routes/invites.ts) and the legacy join-code path (routes/races.ts) must
 * produce IDENTICAL membership state, so the "add a person to a race" steps
 * live here rather than being reimplemented per entry point.
 *
 * routes/races.ts, routes/invites.ts and routes/squads.ts all use these.
 */
import type { RaceRow } from '../types';
import { generateId } from '../lib/crypto';
import { effectiveRaceStatus } from './raceLifecycle';
import { computeCompetitionRanks, type RankedScore } from './raceRanking';

/**
 * Whether new people may still enter. Uses the DERIVED status so a race whose
 * end_at has passed (stored status not yet finalized) is closed, while a
 * not-yet-started race (derived 'scheduled') stays joinable before the start
 * line.
 */
export function raceIsOpenToJoin(
  race: Pick<RaceRow, 'status' | 'start_at' | 'end_at'>,
  now = new Date(),
): boolean {
  if (race.status !== 'active') return false;
  return effectiveRaceStatus(race.status, race.start_at ?? null, race.end_at ?? null, now) !== 'completed';
}

export async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db
    .prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL')
    .bind(raceId)
    .first<RaceRow>();
}

export async function getProfileName(db: D1Database, userId: string): Promise<string | null> {
  const row = await db
    .prepare('SELECT full_name FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<{ full_name: string | null }>();
  return row?.full_name ?? null;
}

/**
 * race_members.person_id is a legacy NOT NULL FK to people(id); every member
 * row must resolve to a people row first.
 */
export async function ensurePersonId(db: D1Database, userId: string): Promise<string> {
  const existing = await db
    .prepare('SELECT id FROM people WHERE user_id = ?')
    .bind(userId)
    .first<{ id: string }>();
  if (existing) return existing.id;
  const personId = generateId();
  const displayName = await getProfileName(db, userId);
  // A concurrent double-tap may have created the row between the read and
  // this insert — ignore the conflict and read the winner back.
  await db
    .prepare(
      `INSERT INTO people (id, person_key, user_id, display_name, created_at, updated_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT DO NOTHING`,
    )
    .bind(personId, `user-${userId}`, userId, displayName ?? 'Racer')
    .run();
  const winner = await db
    .prepare('SELECT id FROM people WHERE user_id = ?')
    .bind(userId)
    .first<{ id: string }>();
  return winner?.id ?? personId;
}

/**
 * Rows changed by a write. A runner that reports no `meta` (a bare test shim)
 * is treated as "the write happened" so callers keep working.
 */
function changesOf(result: { meta?: { changes?: number } } | null | undefined): number {
  const changes = result?.meta?.changes;
  return typeof changes === 'number' ? changes : 1;
}

export interface EnsureMemberResult {
  /** A brand-new membership row was inserted. */
  created: boolean;
  /** A 'left' (or explicitly re-added 'removed') row was made active again. */
  reactivated: boolean;
  /**
   * The creator removed this person from the race. Self-service entry points
   * (invite link, join code, crew link) must refuse with 403 and nothing was
   * written. Only an explicit creator add (`allowRemoved`) can override.
   */
  blocked: boolean;
}

export interface EnsureMemberOptions {
  /** Creator-initiated add: lets a previously removed member back in. */
  allowRemoved?: boolean;
}

export const REMOVED_FROM_RACE_ERROR = 'You were removed from this race';

/**
 * Idempotent and double-tap safe: a repeated call for an existing member is a
 * no-op; two concurrent calls never throw (the loser sees `created: false`).
 */
export async function ensureMember(
  db: D1Database,
  raceId: string,
  userId: string,
  role = 'racer',
  options: EnsureMemberOptions = {},
): Promise<EnsureMemberResult> {
  const allowRemoved = options.allowRemoved === true;
  // Two passes: the second only runs when a concurrent insert beat ours.
  for (let attempt = 0; attempt < 2; attempt++) {
    const existing = await db
      .prepare('SELECT id, status FROM race_members WHERE race_id = ? AND user_id = ?')
      .bind(raceId, userId)
      .first<{ id: string; status: string }>();
    if (existing) {
      if (existing.status === 'active') return { created: false, reactivated: false, blocked: false };
      if (existing.status === 'removed' && !allowRemoved) {
        return { created: false, reactivated: false, blocked: true };
      }
      // A stale 'left' row must not lock the user out — rejoining reactivates
      // the same membership rather than inserting a duplicate. The status
      // guard makes a racing double-tap reactivate (and notify) only once.
      const res = await db
        .prepare(
          `UPDATE race_members SET status = 'active', role = ?, joined_at = CURRENT_TIMESTAMP
           WHERE id = ? AND status != 'active' AND (status != 'removed' OR ? = 1)`,
        )
        .bind(role, existing.id, allowRemoved ? 1 : 0)
        .run();
      return { created: false, reactivated: changesOf(res) > 0, blocked: false };
    }
    const displayName = await getProfileName(db, userId);
    const personId = await ensurePersonId(db, userId);
    const res = await db
      .prepare(
        `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at, cached_display_name)
         VALUES (?, ?, ?, ?, ?, 'active', CURRENT_TIMESTAMP, ?)
         ON CONFLICT DO NOTHING`,
      )
      .bind(generateId(), raceId, userId, personId, role, displayName)
      .run();
    if (changesOf(res) > 0) return { created: true, reactivated: false, blocked: false };
    // Lost the race to a concurrent insert: re-read and apply the same rules.
  }
  return { created: false, reactivated: false, blocked: false };
}

/** Idempotent and double-tap safe. */
export async function ensureProgress(db: D1Database, raceId: string, userId: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
       VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)
       ON CONFLICT DO NOTHING`,
    )
    .bind(generateId(), raceId, userId)
    .run();
}

export async function isRaceMember(db: D1Database, raceId: string, userId: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'")
    .bind(raceId, userId)
    .first<{ id: string }>();
  return Boolean(row);
}

export async function rankedScores(
  db: D1Database,
  raceId: string,
  direction: 'higher' | 'lower' = 'higher',
): Promise<RankedScore[]> {
  const rows = await db
    .prepare(
      `SELECT rm.user_id, rm.joined_at, rp.progress_value, rp.completed_at
       FROM race_members rm
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'`,
    )
    .bind(raceId)
    .all<{ user_id: string; joined_at: string; progress_value: number | null; completed_at: string | null }>();
  return computeCompetitionRanks(
    rows.results.map((row) => ({
      user_id: row.user_id,
      joined_at: row.joined_at,
      progress_value: row.progress_value ?? 0,
      completed_at: row.completed_at,
    })),
    { direction: direction === 'lower' ? 'asc' : 'desc' },
  );
}

/**
 * Rewrites race_progress.rank_cache from the live roster. Must run after any
 * membership change (join, leave, remove, rejoin) as well as after proofs, so
 * a cached rank never reflects a roster that no longer exists.
 */
export async function recomputeRanks(
  db: D1Database,
  raceId: string,
  direction: 'higher' | 'lower' = 'higher',
): Promise<RankedScore[]> {
  const ranked = await rankedScores(db, raceId, direction);
  const stmts = ranked.map((r) =>
    db
      .prepare('UPDATE race_progress SET rank_cache = ? WHERE race_id = ? AND user_id = ?')
      .bind(r.rank, raceId, r.user_id),
  );
  if (stmts.length) await db.batch(stmts);
  return ranked;
}
