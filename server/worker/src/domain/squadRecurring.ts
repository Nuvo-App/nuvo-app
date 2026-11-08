/**
 * v13 crew races — recurring race definitions, per-member auto-join opt-outs,
 * and the cron sweep that materializes each week's race.
 *
 * Crew language note: "squad" is the API/storage noun; the app calls these
 * groups crews. A `squad_recurring_races` row is a template ("Pushup
 * Monday"); every UTC day the sweep spawns a real race for rows whose
 * `weekday` matches and `last_spawned_at` is still earlier than today, then
 * auto-joins every active member who has not opted out (and while the row's
 * `auto_join` flag is on).
 *
 * Everything here tolerates a schema that predates 0049: a missing
 * recurring/opt-out/mute column means "nothing configured", never a 500 —
 * same tolerance the mutes module uses for user_mutes.
 */
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { isBlocked } from '../lib/privacy';
import { bestEffort } from '../lib/safe';
import { RACE_LAUNCH_VISIBILITY } from '../lib/raceAccess';
import {
  ensureMember,
  ensurePersonId,
  ensureProgress,
  getProfileName,
  recomputeRanks,
} from './raceMembership';
import { notifyEvent } from './notificationPolicy';
import { recordRaceEvents } from './raceEvents';

type Env = AppEnv['Bindings'];
type WaitUntil = ((p: Promise<unknown>) => void) | undefined;

export interface RecurringRow {
  id: string;
  squad_id: string;
  title: string;
  activity_id: string | null;
  race_type: string | null;
  target_value: number | null;
  target_unit: string | null;
  weekday: number;
  auto_join: number;
  active: number;
  last_spawned_at: string | null;
  created_by: string;
  created_at: string;
}

/** 'YYYY-MM-DD' in UTC — the day key every spawn decision is made on. */
export function utcToday(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/**
 * Monday 00:00 UTC of the current week as a SQLite datetime ('YYYY-MM-DD
 * HH:MM:SS'). The weekly standings window starts here — documented on
 * GET /squads/:id/standings.
 */
export function weekStartUtc(now = new Date()): string {
  const day = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7));
  return day.toISOString().slice(0, 19).replace('T', ' ');
}

/** Next UTC occurrence of `weekday` (0=Sunday..6=Saturday) — today counts. */
export function nextOccurrenceUtc(weekday: number, now = new Date()): { nextAt: string; isToday: boolean } {
  const daysUntil = (weekday - now.getUTCDay() + 7) % 7;
  const day = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + daysUntil));
  return { nextAt: `${day.toISOString().slice(0, 10)}T00:00:00.000Z`, isToday: daysUntil === 0 };
}

/**
 * Members whose crew notifications are suppressed — the new
 * squad_members.muted_at flag plus the older user_mutes 'crew' rows (both
 * mute surfaces mute the same crew). Tolerant of either schema piece being
 * absent; a missing table means "nobody muted".
 */
export async function squadMutedSet(db: D1Database, squadId: string): Promise<Set<string>> {
  const muted = new Set<string>();
  try {
    const rows = await db
      .prepare(
        "SELECT user_id FROM squad_members WHERE squad_id = ? AND status = 'active' AND muted_at IS NOT NULL",
      )
      .bind(squadId)
      .all<{ user_id: string }>();
    for (const r of rows.results) muted.add(r.user_id);
  } catch {
    // squad_members.muted_at predates 0049 — no mutes exist
  }
  try {
    const rows = await db
      .prepare("SELECT user_id FROM user_mutes WHERE target_type = 'crew' AND target_id = ?")
      .bind(squadId)
      .all<{ user_id: string }>();
    for (const r of rows.results) muted.add(r.user_id);
  } catch {
    // user_mutes predates 0048 — no mutes exist
  }
  return muted;
}

/** Whether one member muted this crew — same union as squadMutedSet. */
export async function isSquadMuted(db: D1Database, squadId: string, userId: string): Promise<boolean> {
  return (await squadMutedSet(db, squadId)).has(userId);
}

/**
 * Puts a user into a crew-linked race. The same mechanics code-join uses:
 * blocks are honored, a creator-removed member is never re-added, ranks are
 * recomputed, and a fresh membership emits race_invited (skipped when the
 * member muted the crew — the seat still lands, the ping does not).
 */
export async function addMemberToSquadRace(
  env: Env,
  waitUntil: WaitUntil,
  race: { id: string; title: string; creator_id: string; score_direction?: string | null },
  userId: string,
  inviterName: string | null,
  opts: { muted?: boolean } = {},
): Promise<boolean> {
  const db = env.DB;
  if (userId !== race.creator_id) {
    if ((await isBlocked(db, userId, race.creator_id)) || (await isBlocked(db, race.creator_id, userId))) {
      return false;
    }
  }
  const { created, reactivated, blocked } = await ensureMember(db, race.id, userId);
  // Someone the race creator removed stays out; adding the crew never overrides that.
  if (blocked) return false;
  await ensureProgress(db, race.id, userId);
  if (created || reactivated) {
    await recomputeRanks(db, race.id, race.score_direction === 'lower' ? 'lower' : 'higher');
  }
  if (created && userId !== race.creator_id && !opts.muted) {
    await bestEffort('squad_race_invited', () =>
      notifyEvent(env, waitUntil, {
        type: 'race_invited',
        userId,
        actorUserId: race.creator_id,
        actorName: inviterName,
        raceId: race.id,
        raceTitle: race.title,
      }),
    );
  }
  return created;
}

/** Verified proof value per active member inside this crew's linked races. */
export async function squadProofPoints(
  db: D1Database,
  squadId: string,
  since: string | null,
): Promise<Map<string, number> | null> {
  try {
    const rows = await db
      .prepare(
        `SELECT sm.user_id, COALESCE(SUM(ml.value), 0) AS points
         FROM squad_members sm
         LEFT JOIN move_logs ml ON ml.user_id = sm.user_id AND ml.status = 'verified'
           AND ml.race_id IN (SELECT race_id FROM squad_races WHERE squad_id = ?)
           ${since ? 'AND ml.created_at >= ?' : ''}
         WHERE sm.squad_id = ? AND sm.status = 'active'
         GROUP BY sm.user_id`,
      )
      .bind(...(since ? [squadId, since, squadId] : [squadId, squadId]))
      .all<{ user_id: string; points: number }>();
    return new Map(rows.results.map((r) => [r.user_id, r.points ?? 0]));
  } catch {
    return null; // move_logs predates the schema — no points yet
  }
}

/**
 * The same points read across several crews at once — one grouped query for
 * the GET /squads list's myRankWeek.
 */
export async function squadProofPointsMany(
  db: D1Database,
  squadIds: string[],
  since: string,
): Promise<Map<string, Map<string, number>> | null> {
  if (squadIds.length === 0) return new Map();
  try {
    const marks = squadIds.map(() => '?').join(',');
    const rows = await db
      .prepare(
        `SELECT sm.squad_id, sm.user_id, COALESCE(SUM(ml.value), 0) AS points
         FROM squad_members sm
         LEFT JOIN move_logs ml ON ml.user_id = sm.user_id AND ml.status = 'verified'
           AND ml.created_at >= ?
           AND ml.race_id IN (SELECT race_id FROM squad_races WHERE squad_id = sm.squad_id)
         WHERE sm.squad_id IN (${marks}) AND sm.status = 'active'
         GROUP BY sm.squad_id, sm.user_id`,
      )
      .bind(since, ...squadIds)
      .all<{ squad_id: string; user_id: string; points: number }>();
    const out = new Map<string, Map<string, number>>();
    for (const r of rows.results) {
      const inner = out.get(r.squad_id) ?? new Map<string, number>();
      inner.set(r.user_id, r.points ?? 0);
      out.set(r.squad_id, inner);
    }
    return out;
  } catch {
    return null; // move_logs predates the schema
  }
}

/** Competition rank: 1 + the number of people with strictly more points. */
export function competitionRank(points: Map<string, number>, userId: string): number {
  const mine = points.get(userId) ?? 0;
  let rank = 1;
  for (const [id, p] of points) if (id !== userId && p > mine) rank += 1;
  return rank;
}

interface RecurringTiming {
  nextAt: string;
  isLive: boolean;
}

/** Next run of a recurring row: today's spawn (live) or the coming weekday. */
export function recurringTiming(
  row: Pick<RecurringRow, 'weekday' | 'last_spawned_at'>,
  now = new Date(),
): RecurringTiming {
  const today = utcToday(now);
  const spawnedToday = row.last_spawned_at != null && row.last_spawned_at.slice(0, 10) === today;
  const { nextAt } = nextOccurrenceUtc(row.weekday, now);
  // Already spawned today → the live race is the current instance; otherwise
  // the next weekday boundary is when it goes live.
  return { nextAt, isLive: spawnedToday };
}

/**
 * Crew stats on GET /squads/:id — wins (linked races whose winner is an
 * active member) and the crew streak: consecutive UTC days, ending today or
 * yesterday, with at least one verified proof by an active member inside a
 * crew-linked race. Tolerant of schemas without move_logs/winner columns.
 */
export async function squadCrewStats(
  db: D1Database,
  squadId: string,
  raceCount: number,
): Promise<{ wins: number; races: number; streakDays: number }> {
  let wins = 0;
  try {
    const row = await db
      .prepare(
        `SELECT COUNT(*) AS n FROM squad_races sr
         JOIN races r ON r.id = sr.race_id
         WHERE sr.squad_id = ? AND r.winner_user_id IS NOT NULL
           AND r.winner_user_id IN (
             SELECT user_id FROM squad_members WHERE squad_id = ? AND status = 'active')`,
      )
      .bind(squadId, squadId)
      .first<{ n: number }>();
    wins = row?.n ?? 0;
  } catch {
    wins = 0;
  }
  let streakDays = 0;
  try {
    const days = await db
      .prepare(
        `SELECT DISTINCT date(ml.created_at) AS day
         FROM move_logs ml
         JOIN squad_races sr ON sr.race_id = ml.race_id
         JOIN squad_members sm ON sm.squad_id = sr.squad_id AND sm.user_id = ml.user_id AND sm.status = 'active'
         WHERE sr.squad_id = ? AND ml.status = 'verified'
         ORDER BY day`,
      )
      .bind(squadId)
      .all<{ day: string }>();
    streakDays = consecutiveDaysEndingToday((days.results ?? []).map((d) => d.day).filter(Boolean));
  } catch {
    streakDays = 0;
  }
  return { wins, races: raceCount, streakDays };
}

/** Consecutive 'YYYY-MM-DD' run ending today or yesterday (UTC). */
function consecutiveDaysEndingToday(days: string[], now = new Date()): number {
  if (days.length === 0) return 0;
  const epoch = (d: string) => Math.floor(Date.parse(`${d}T00:00:00Z`) / 86_400_000);
  const today = epoch(utcToday(now));
  let run = 1;
  for (let i = days.length - 1; i > 0; i--) {
    if (epoch(days[i]) - epoch(days[i - 1]) === 1) run += 1;
    else break;
  }
  return today - epoch(days[days.length - 1]) <= 1 ? run : 0;
}

// ── Cron sweep ───────────────────────────────────────────────────────────────

/**
 * Spawn today's recurring races. For every active recurring row whose UTC
 * weekday is today and that has not spawned today, claim it (the guarded
 * UPDATE makes a second sweep in the same UTC day a no-op), create the race
 * exactly like a crew race link does, then auto-join members.
 *
 * A spawned race runs until 00:00 UTC on the next occurrence (7 days out),
 * so a "Pushup Monday" race stays open all week and finalizes as the next
 * one spawns. Returns the number of races created — for the cron log.
 */
export async function sweepRecurringSquadRaces(
  env: Env,
  waitUntil: WaitUntil,
): Promise<number> {
  const db = env.DB;
  let due: Array<RecurringRow & { owner_id: string }>;
  try {
    const res = await db
      .prepare(
        `SELECT rr.*, s.owner_id
         FROM squad_recurring_races rr
         JOIN squads s ON s.id = rr.squad_id
         WHERE rr.active = 1 AND s.deleted_at IS NULL
           AND rr.weekday = CAST(strftime('%w', 'now') AS INTEGER)
           AND (rr.last_spawned_at IS NULL OR date(rr.last_spawned_at) < date('now'))
         LIMIT 50`,
      )
      .all<RecurringRow & { owner_id: string }>();
    due = res.results;
  } catch {
    return 0; // squad_recurring_races predates 0049 — nothing to spawn
  }

  let spawned = 0;
  for (const rr of due) {
    try {
      if (await spawnRecurringRace(env, waitUntil, rr)) spawned += 1;
    } catch (err) {
      console.error('[cron] recurring race spawn failed:', (err as Error).message, rr.id);
      // Un-claim so the next sweep retries instead of skipping the week.
      await bestEffort('recurring_unclaim', () =>
        db
          .prepare('UPDATE squad_recurring_races SET last_spawned_at = NULL WHERE id = ?')
          .bind(rr.id)
          .run(),
      );
    }
  }
  return spawned;
}

async function spawnRecurringRace(
  env: Env,
  waitUntil: WaitUntil,
  rr: RecurringRow & { owner_id: string },
): Promise<boolean> {
  const db = env.DB;
  // Idempotency: only the first claimer of this UTC day proceeds. A second
  // sweep sees last_spawned_at already stamped and changes 0 rows.
  const claim = await db
    .prepare(
      `UPDATE squad_recurring_races SET last_spawned_at = CURRENT_TIMESTAMP
       WHERE id = ? AND active = 1
         AND (last_spawned_at IS NULL OR date(last_spawned_at) < date('now'))`,
    )
    .bind(rr.id)
    .run();
  if ((claim.meta?.changes ?? 0) === 0) return false;

  // The template's creator keeps race ownership while still in the crew;
  // otherwise the crew owner stands in so the race never loses its creator.
  const creatorStillMember = await db
    .prepare(
      "SELECT id FROM squad_members WHERE squad_id = ? AND user_id = ? AND status = 'active'",
    )
    .bind(rr.squad_id, rr.created_by)
    .first<{ id: string }>();
  const creatorId = creatorStillMember ? rr.created_by : rr.owner_id;

  const raceId = generateId();
  const format = rr.race_type ?? 'most_in_window';
  const metric = rr.target_unit ?? 'reps';
  const endAt = nextOccurrenceUtc(rr.weekday, new Date(Date.now() + 7 * 86_400_000)).nextAt;
  const personId = await ensurePersonId(db, creatorId);
  await db.batch([
    db
      .prepare(
        `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
           target_value, target_unit, activity_id, metric, format, scoring_rule, attempt_duration_seconds,
           attempt_limit, verification_method, timezone, recurrence, status, visibility,
           start_at, end_at, score_direction, proof_review_mode, created_at, updated_at)
         VALUES (?, ?, ?, NULL, ?, NULL, 'manual', ?, ?, ?, ?, ?, 'cumulative_sum', NULL, NULL, 'manual',
           'UTC', 'weekly', 'active', ?, NULL, ?, 'higher', 'auto_accept',
           CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      )
      .bind(
        raceId,
        creatorId,
        rr.title,
        format,
        rr.target_value,
        rr.target_unit,
        rr.activity_id,
        metric,
        format,
        RACE_LAUNCH_VISIBILITY,
        endAt,
      ),
    db
      .prepare(
        `INSERT INTO squad_races (id, squad_id, race_id, created_by, created_at)
         VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), rr.squad_id, raceId, rr.created_by),
    db
      .prepare(
        `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at)
         VALUES (?, ?, ?, ?, 'creator', 'active', CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), raceId, creatorId, personId),
    db
      .prepare(
        `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
         VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), raceId, creatorId),
  ]);
  await recordRaceEvents(db, raceId, [
    {
      type: 'race_created',
      actorUserId: creatorId,
      payload: { title: rr.title, format, metric, endAt, scoreDirection: 'higher', source: 'recurring' },
    },
  ]);

  const race = { id: raceId, title: rr.title, creator_id: creatorId, score_direction: 'higher' };
  const inviterName = await getProfileName(db, creatorId);
  let members: Array<{ user_id: string }> = [];
  try {
    members = (
      await db
        .prepare("SELECT user_id FROM squad_members WHERE squad_id = ? AND status = 'active'")
        .bind(rr.squad_id)
        .all<{ user_id: string }>()
    ).results;
  } catch {
    members = [];
  }
  let optouts = new Set<string>();
  if (rr.auto_join === 1) {
    try {
      optouts = new Set(
        (
          await db
            .prepare('SELECT user_id FROM squad_recurring_optouts WHERE recurring_id = ?')
            .bind(rr.id)
            .all<{ user_id: string }>()
        ).results.map((o) => o.user_id),
      );
    } catch {
      optouts = new Set();
    }
  }
  const muted = await squadMutedSet(db, rr.squad_id);
  for (const m of members) {
    if (m.user_id === creatorId) continue;
    if (rr.auto_join !== 1 || optouts.has(m.user_id)) continue;
    await bestEffort('recurring_add_member', () =>
      addMemberToSquadRace(env, waitUntil, race, m.user_id, inviterName, {
        muted: muted.has(m.user_id),
      }),
    );
  }
  return true;
}
