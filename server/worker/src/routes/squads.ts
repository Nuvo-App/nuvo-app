import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';
import { conditional, stalenessBucket, weakEtag } from '../lib/etag';
import { hasAcceptedTerms } from '../lib/terms';
import { isBlocked } from '../lib/privacy';
import { getProfileName, getRace } from '../domain/raceMembership';
import { effectiveTargetValue } from '../domain/raceTarget';
import { notifyEvent } from '../domain/notificationPolicy';
import { bestEffort } from '../lib/safe';
import { computeSquadStandings, type SquadRaceInput } from '../domain/squadStandings';
import {
  addMemberToSquadRace,
  competitionRank,
  isSquadMuted,
  recurringTiming,
  squadCrewStats,
  squadMutedSet,
  squadProofPoints,
  squadProofPointsMany,
  weekStartUtc,
  type RecurringRow,
} from '../domain/squadRecurring';

/**
 * Crew groups. "Squad" in the API, "crew" in the app's copy.
 *
 *   POST /squads                       create (caller becomes owner)
 *   GET  /squads                       my crews (+ v13 card fields)
 *   POST /squads/join                  join by code
 *   GET  /squads/discover              friends' crews I could ask to join
 *   GET  /squads/:id                   detail: members, races, standings, stats
 *   GET  /squads/:id/preview           non-member card (name/faces/count)
 *   GET  /squads/:id/standings         points = verified proof in crew races
 *   POST /squads/:id/races             link a race I created -> members added
 *   POST /squads/:id/join-request      ask to join a discovered crew
 *   POST /squads/:id/join-requests/:userId/approve|decline   owner/admin
 *   POST /squads/:id/mute              mute crew notifications for me
 *   POST|PATCH|DELETE /squads/:id/recurring[...]             recurring races
 *   POST /squads/:id/leave
 */
export const squadsRouter = new Hono<AppEnv>();

squadsRouter.use('*', requireAuth);

const MAX_MEMBERS = 100;
const MAX_SQUADS_PER_USER = 10;
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CREW_COLORS = new Set(['coral', 'sun', 'lilac', 'mint', 'sky']);
const BIO_MAX = 120;
const ICON_MAX = 32;

type Ctx = Context<AppEnv>;

interface SquadRow {
  id: string;
  name: string;
  join_code: string;
  owner_id: string;
  created_at: string;
  bio?: string | null;
  color_key?: string | null;
  icon_key?: string | null;
}

const badRequest = (error: string) => ({ ok: false, error });

function generateJoinCode(): string {
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((b) => CODE_CHARS[b % CODE_CHARS.length])
    .join('');
}

/** Run a read that may touch 0049-era columns/tables; failure means "unset". */
async function tolerant<T>(fallback: T, fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch {
    return fallback;
  }
}

async function getSquad(db: D1Database, squadId: string): Promise<SquadRow | null> {
  return db
    .prepare('SELECT * FROM squads WHERE id = ? AND deleted_at IS NULL')
    .bind(squadId)
    .first<SquadRow>();
}

type CrewRole = 'owner' | 'admin' | 'member';

/** Small stable hash so a role change always changes the ETag. */
function hashString(value: string): string {
  let h = 5381;
  for (let i = 0; i < value.length; i++) h = ((h << 5) + h + value.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36);
}

/**
 * Ownership is authoritative on squads.owner_id: a stored 'owner' role on
 * anyone else (for example a stale row) counts as a plain member.
 */
function effectiveRole(ownerId: string, userId: string, storedRole: string): CrewRole {
  if (ownerId === userId) return 'owner';
  return storedRole === 'admin' ? 'admin' : 'member';
}

async function roleOf(db: D1Database, squadId: string, userId: string): Promise<CrewRole | null> {
  const row = await db
    .prepare(
      `SELECT sm.role, s.owner_id
       FROM squad_members sm JOIN squads s ON s.id = sm.squad_id
       WHERE sm.squad_id = ? AND sm.user_id = ? AND sm.status = 'active'`,
    )
    .bind(squadId, userId)
    .first<{ role: string; owner_id: string }>();
  if (!row) return null;
  return effectiveRole(row.owner_id, userId, row.role);
}

/** Crews the user is currently an active member of, optionally excluding one. */
async function activeMembershipCount(db: D1Database, userId: string, excludeSquadId?: string): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) as count FROM squad_members WHERE user_id = ? AND status = 'active' AND squad_id != ?")
    .bind(userId, excludeSquadId ?? '')
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function isActiveMember(db: D1Database, squadId: string, userId: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT id FROM squad_members WHERE squad_id = ? AND user_id = ? AND status = 'active'")
    .bind(squadId, userId)
    .first<{ id: string }>();
  return Boolean(row);
}

async function memberCount(db: D1Database, squadId: string): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) as count FROM squad_members WHERE squad_id = ? AND status = 'active'")
    .bind(squadId)
    .first<{ count: number }>();
  return row?.count ?? 0;
}

async function readJson(c: Ctx): Promise<Record<string, unknown> | null> {
  try {
    const body = await c.req.json();
    return body && typeof body === 'object' ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** The set of `others` blocked with the viewer in either direction. */
async function blockedSetFor(
  db: D1Database,
  viewerId: string,
  others: string[],
): Promise<Set<string>> {
  const blocked = new Set<string>();
  const ids = others.filter((id) => id !== viewerId);
  if (ids.length === 0) return blocked;
  const marks = ids.map(() => '?').join(',');
  const rows = await db
    .prepare(
      `SELECT user_id, blocked_user_id FROM blocked_users
       WHERE (user_id = ? AND blocked_user_id IN (${marks}))
          OR (blocked_user_id = ? AND user_id IN (${marks}))`,
    )
    .bind(viewerId, ...ids, viewerId, ...ids)
    .all<{ user_id: string; blocked_user_id: string }>();
  for (const b of rows.results) {
    blocked.add(b.user_id === viewerId ? b.blocked_user_id : b.user_id);
  }
  return blocked;
}

interface MemberFace {
  id: string;
  displayName: string;
  profilePhotoUrl: string | null;
}

function face(
  row: { user_id: string; full_name: string | null; username: string | null; avatar_url: string | null },
  blockedIds: Set<string>,
): MemberFace {
  const blocked = blockedIds.has(row.user_id);
  return {
    id: row.user_id,
    displayName: blocked
      ? 'Private User'
      : (row.full_name ?? (row.username ? `@${row.username}` : 'Nuvo member')),
    profilePhotoUrl: blocked ? null : row.avatar_url,
  };
}

/**
 * Up to `cap` member faces per crew, keyed by squad id. Members are ordered
 * by join time so the preview shows the longest-standing faces.
 */
async function memberPreviewsFor(
  db: D1Database,
  squadIds: string[],
  blockedIds: Set<string>,
  cap = 5,
): Promise<Map<string, MemberFace[]>> {
  const out = new Map<string, MemberFace[]>();
  if (squadIds.length === 0) return out;
  const marks = squadIds.map(() => '?').join(',');
  const rows = await db
    .prepare(
      `SELECT sm.squad_id, sm.user_id, p.full_name, p.username, p.avatar_url
       FROM squad_members sm
       LEFT JOIN profiles p ON p.user_id = sm.user_id
       WHERE sm.squad_id IN (${marks}) AND sm.status = 'active'
       ORDER BY sm.joined_at ASC`,
    )
    .bind(...squadIds)
    .all<{ squad_id: string; user_id: string; full_name: string | null; username: string | null; avatar_url: string | null }>();
  for (const row of rows.results) {
    const list = out.get(row.squad_id);
    if (list && list.length >= cap) continue;
    const next = face(row, blockedIds);
    if (list) list.push(next);
    else out.set(row.squad_id, [next]);
  }
  return out;
}

/** Grouped display names for a set of user ids (owner names, inviter, ...). */
async function displayNamesFor(db: D1Database, userIds: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const ids = [...new Set(userIds)];
  if (ids.length === 0) return out;
  const marks = ids.map(() => '?').join(',');
  const rows = await db
    .prepare(
      `SELECT p.user_id, p.full_name, p.username FROM profiles p WHERE p.user_id IN (${marks})`,
    )
    .bind(...ids)
    .all<{ user_id: string; full_name: string | null; username: string | null }>();
  for (const r of rows.results) {
    out.set(r.user_id, r.full_name ?? (r.username ? `@${r.username}` : 'Nuvo member'));
  }
  return out;
}

interface SquadMemberRow {
  user_id: string;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
}

/** Active members of one crew with profile fields for previews/opt-outs. */
async function activeMemberRows(db: D1Database, squadId: string): Promise<SquadMemberRow[]> {
  const rows = await db
    .prepare(
      `SELECT sm.user_id, p.full_name, p.username, p.avatar_url
       FROM squad_members sm LEFT JOIN profiles p ON p.user_id = sm.user_id
       WHERE sm.squad_id = ? AND sm.status = 'active'
       ORDER BY sm.joined_at ASC`,
    )
    .bind(squadId)
    .all<SquadMemberRow>();
  return rows.results;
}

/** Pending join requests (squad_members.status='requested'), oldest first. */
async function joinRequestsFor(db: D1Database, squadId: string) {
  const rows = await db
    .prepare(
      `SELECT sm.user_id, sm.joined_at, p.full_name, p.username, p.avatar_url
       FROM squad_members sm LEFT JOIN profiles p ON p.user_id = sm.user_id
       WHERE sm.squad_id = ? AND sm.status = 'requested'
       ORDER BY sm.joined_at ASC`,
    )
    .bind(squadId)
    .all<{ user_id: string; joined_at: string; full_name: string | null; username: string | null; avatar_url: string | null }>();
  return rows.results;
}

/** Recurring definitions for one or many crews — empty when 0049 is absent. */
async function recurringRowsFor(db: D1Database, squadIds: string[]): Promise<RecurringRow[]> {
  if (squadIds.length === 0) return [];
  return tolerant([], async () => {
    const marks = squadIds.map(() => '?').join(',');
    const rows = await db
      .prepare(`SELECT * FROM squad_recurring_races WHERE squad_id IN (${marks}) ORDER BY created_at ASC`)
      .bind(...squadIds)
      .all<RecurringRow>();
    return rows.results;
  });
}

/** Opt-out user ids per recurring row — empty when the table is absent. */
async function optoutsFor(db: D1Database, recurringIds: string[]): Promise<Map<string, Set<string>>> {
  const out = new Map<string, Set<string>>();
  if (recurringIds.length === 0) return out;
  return tolerant(out, async () => {
    const marks = recurringIds.map(() => '?').join(',');
    const rows = await db
      .prepare(`SELECT recurring_id, user_id FROM squad_recurring_optouts WHERE recurring_id IN (${marks})`)
      .bind(...recurringIds)
      .all<{ recurring_id: string; user_id: string }>();
    for (const r of rows.results) {
      const set = out.get(r.recurring_id) ?? new Set<string>();
      set.add(r.user_id);
      out.set(r.recurring_id, set);
    }
    return out;
  });
}

/** Serialized recurring row as the detail response exposes it. */
function serializeRecurring(
  row: RecurringRow,
  optedOut: boolean,
  previews: MemberFace[],
): Record<string, unknown> {
  const timing = recurringTiming(row);
  return {
    id: row.id,
    title: row.title,
    activityId: row.activity_id,
    raceType: row.race_type,
    targetValue: row.target_value,
    targetUnit: row.target_unit,
    weekday: row.weekday,
    active: row.active === 1,
    autoJoin: row.auto_join === 1 && !optedOut,
    autoJoinPreviews: previews,
    nextAt: timing.nextAt,
    isLive: timing.isLive,
  };
}

/**
 * Crew races that are still open for the joiner — the "pull them into every
 * running crew race" step shared by code-join and request approval.
 */
async function pullIntoOpenCrewRaces(
  c: Ctx,
  squad: SquadRow,
  userId: string,
): Promise<void> {
  const open = await c.env.DB.prepare(
    `SELECT r.id, r.title, r.creator_id, r.score_direction
     FROM squad_races sr JOIN races r ON r.id = sr.race_id
     WHERE sr.squad_id = ? AND r.status = 'active' AND r.deleted_at IS NULL`,
  )
    .bind(squad.id)
    .all<{ id: string; title: string; creator_id: string; score_direction: string | null }>();
  const muted = await isSquadMuted(c.env.DB, squad.id, userId);
  for (const race of open.results) {
    // The seat in the crew is already saved; one race failing to take the new
    // member must not turn the join into an error (the next read heals it).
    await bestEffort('squad_join_add_to_race', async () =>
      addMemberToSquadRace(
        c.env,
        (p) => c.executionCtx.waitUntil(p),
        race,
        userId,
        await getProfileName(c.env.DB, race.creator_id),
        { muted },
      ),
    );
  }
}

// POST /squads
squadsRouter.post('/', async (c) => {
  const userId = c.get('userId');
  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json(badRequest('You must accept the Terms of Service to create a crew'), 403);
  }
  const body = await readJson(c);
  if (!body) return c.json(badRequest('Invalid JSON body'), 400);
  const name = typeof body.name === 'string' ? body.name.trim().replace(/\s+/g, ' ') : '';
  if (name.length < 2 || name.length > 40) {
    return c.json(badRequest('Crew name must be 2-40 characters'), 400);
  }

  if ((await activeMembershipCount(c.env.DB, userId)) >= MAX_SQUADS_PER_USER) {
    return c.json(badRequest('You are in the maximum number of crews'), 409);
  }

  const id = generateId();
  let code = '';
  for (let attempt = 0; attempt < 5; attempt++) {
    code = generateJoinCode();
    const taken = await c.env.DB.prepare('SELECT id FROM squads WHERE join_code = ?')
      .bind(code)
      .first<{ id: string }>();
    if (!taken) break;
    code = '';
  }
  if (!code) return c.json(badRequest('Could not create a crew code. Try again.'), 500);

  try {
    await c.env.DB.batch([
      c.env.DB.prepare(
        'INSERT INTO squads (id, name, join_code, owner_id, created_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)',
      ).bind(id, name, code, userId),
      c.env.DB.prepare(
        `INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at)
         VALUES (?, ?, ?, 'owner', 'active', CURRENT_TIMESTAMP)`,
      ).bind(generateId(), id, userId),
    ]);
  } catch (err) {
    // Lost a join-code race (UNIQUE) or the batch failed; the batch is atomic,
    // so nothing was written. Ask the app to try again.
    console.error(JSON.stringify({ evt: 'squad_create_failed', message: err instanceof Error ? err.message : String(err) }));
    return c.json(badRequest('Could not create the crew. Try again.'), 409);
  }

  return c.json({ ok: true, squad: { id, name, joinCode: code, isOwner: true, memberCount: 1, raceCount: 0 } }, 201);
});

// GET /squads — my crews. v13 adds the crew-card fields the tab renders:
// ownerName, memberPreviews (<=5 faces), myRankWeek (competition rank over
// verified proof value inside crew races since Monday 00:00 UTC), and
// nextRecurring (the soonest recurring-race instance). Every addition is
// tolerant of a schema without migration 0049.
squadsRouter.get('/', async (c) => {
  const userId = c.get('userId');
  // Validator: my membership rows + crew creation/join times + per-crew
  // member and race counts, bounded by a 60s bucket.
  const stamp = await c.env.DB.prepare(
    `SELECT COUNT(*) AS n,
            MAX(sm.joined_at) AS max_joined,
            MAX(s.created_at) AS max_created,
            COALESCE(SUM((SELECT COUNT(*) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active')), 0) AS members,
            COALESCE(SUM((SELECT COUNT(*) FROM squad_races r WHERE r.squad_id = s.id)), 0) AS races,
            MAX((SELECT MAX(m.joined_at) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active')) AS max_member_joined,
            COALESCE(GROUP_CONCAT(s.name, '|'), '') AS names
     FROM squads s
     JOIN squad_members sm ON sm.squad_id = s.id AND sm.user_id = ? AND sm.status = 'active'
     WHERE s.deleted_at IS NULL`,
  )
    .bind(userId)
    .first<{
      n: number;
      max_joined: string | null;
      max_created: string | null;
      members: number;
      races: number;
      max_member_joined: string | null;
      names: string | null;
    }>();
  // 0049-era signals in one tolerant read: crew identity columns + my mute
  // flags + recurring definitions + this week's verified proof totals.
  const extras = await tolerant(
    { identity: '', recurring: '', weekPoints: '' },
    () =>
      c.env.DB.prepare(
        `SELECT
           (SELECT COALESCE(GROUP_CONCAT(COALESCE(s.bio, '') || '|' || COALESCE(s.color_key, '')
              || '|' || COALESCE(s.icon_key, '') || '|' || COALESCE(sm2.muted_at, ''), ','), '')
            FROM squads s
            JOIN squad_members sm2 ON sm2.squad_id = s.id AND sm2.user_id = ?1 AND sm2.status = 'active'
            WHERE s.deleted_at IS NULL) AS identity,
           (SELECT COUNT(*) || ':' || COALESCE(MAX(created_at), '') || ':' || COALESCE(MAX(last_spawned_at), '')
            FROM squad_recurring_races
            WHERE squad_id IN (SELECT squad_id FROM squad_members WHERE user_id = ?1 AND status = 'active')) AS recurring,
           (SELECT COUNT(*) || ':' || COALESCE(MAX(ml.created_at), '') || ':' || COALESCE(SUM(ml.value), 0)
            FROM move_logs ml
            WHERE ml.status = 'verified' AND ml.created_at >= ?2
              AND ml.race_id IN (SELECT race_id FROM squad_races
                                 WHERE squad_id IN (SELECT squad_id FROM squad_members
                                                    WHERE user_id = ?1 AND status = 'active'))) AS weekPoints`,
      )
      .bind(userId, weekStartUtc())
      .first<{ identity: string; recurring: string; weekPoints: string }>(),
  );
  const notModified = conditional(
    c,
    weakEtag(
      'squads',
      stamp?.n,
      stamp?.max_joined,
      stamp?.max_created,
      stamp?.members,
      stamp?.races,
      stamp?.max_member_joined,
      hashString(stamp?.names ?? ''),
      hashString(extras?.identity ?? ''),
      extras?.recurring,
      extras?.weekPoints,
      stalenessBucket(Date.now(), 60_000),
    ),
  );
  if (notModified) return notModified;

  const rows = await c.env.DB.prepare(
    `SELECT s.*,
            (SELECT COUNT(*) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active') AS member_count,
            (SELECT COUNT(*) FROM squad_races r WHERE r.squad_id = s.id) AS race_count
     FROM squads s
     JOIN squad_members sm ON sm.squad_id = s.id AND sm.user_id = ? AND sm.status = 'active'
     WHERE s.deleted_at IS NULL
     ORDER BY sm.joined_at DESC`,
  )
    .bind(userId)
    .all<SquadRow & { member_count: number; race_count: number }>();

  const squadIds = rows.results.map((r) => r.id);
  const allMemberIds = (
    await c.env.DB.prepare(
      `SELECT DISTINCT user_id FROM squad_members WHERE squad_id IN (${squadIds.map(() => '?').join(',') || "''"}) AND status = 'active'`,
    )
      .bind(...squadIds)
      .all<{ user_id: string }>()
  ).results.map((r) => r.user_id);
  const blockedIds = await blockedSetFor(c.env.DB, userId, allMemberIds);

  const [ownerNames, previews, weekPoints, recurring] = await Promise.all([
    displayNamesFor(c.env.DB, rows.results.map((r) => r.owner_id)),
    memberPreviewsFor(c.env.DB, squadIds, blockedIds),
    squadProofPointsMany(c.env.DB, squadIds, weekStartUtc()),
    recurringRowsFor(c.env.DB, squadIds),
  ]);

  // Soonest upcoming recurring race per crew (the card's "next race" tag).
  const nextBySquad = new Map<string, { id: string; title: string; weekday: number; nextAt: string; isLive: boolean }>();
  for (const rr of recurring) {
    if (rr.active !== 1) continue;
    const timing = recurringTiming(rr);
    const prev = nextBySquad.get(rr.squad_id);
    if (!prev || timing.nextAt < prev.nextAt) {
      nextBySquad.set(rr.squad_id, { id: rr.id, title: rr.title, weekday: rr.weekday, ...timing });
    }
  }

  return c.json({
    ok: true,
    squads: rows.results.map((r) => ({
      id: r.id,
      name: r.name,
      joinCode: r.join_code,
      isOwner: r.owner_id === userId,
      memberCount: r.member_count,
      raceCount: r.race_count,
      ownerName: ownerNames.get(r.owner_id) ?? null,
      memberPreviews: previews.get(r.id) ?? [],
      // No linked races yet → no rank to show rather than a bogus "#1".
      myRankWeek:
        r.race_count > 0 && weekPoints
          ? competitionRank(weekPoints.get(r.id) ?? new Map([[userId, 0]]), userId)
          : null,
      nextRecurring: nextBySquad.get(r.id) ?? null,
      colorKey: r.color_key ?? null,
      iconKey: r.icon_key ?? null,
    })),
  });
});

// POST /squads/join { code }
squadsRouter.post('/join', async (c) => {
  const userId = c.get('userId');
  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json(badRequest('You must accept the Terms of Service to join a crew'), 403);
  }
  const body = await readJson(c);
  const code = typeof body?.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (!code) return c.json(badRequest('Crew code is required'), 400);

  const squad = await c.env.DB.prepare('SELECT * FROM squads WHERE join_code = ? AND deleted_at IS NULL')
    .bind(code)
    .first<SquadRow>();
  if (!squad) return c.json(badRequest('No crew found for that code'), 404);

  if (
    squad.owner_id !== userId &&
    ((await isBlocked(c.env.DB, userId, squad.owner_id)) || (await isBlocked(c.env.DB, squad.owner_id, userId)))
  ) {
    return c.json(badRequest('No crew found for that code'), 404);
  }

  const existing = await c.env.DB.prepare('SELECT id, status FROM squad_members WHERE squad_id = ? AND user_id = ?')
    .bind(squad.id, userId)
    .first<{ id: string; status: string }>();
  if (existing?.status === 'removed') {
    return c.json(badRequest('You were removed from this crew'), 403);
  }
  const alreadyJoined = existing?.status === 'active';

  if (!alreadyJoined) {
    if ((await memberCount(c.env.DB, squad.id)) >= MAX_MEMBERS) {
      return c.json(badRequest('This crew is full'), 409);
    }
    if ((await activeMembershipCount(c.env.DB, userId, squad.id)) >= MAX_SQUADS_PER_USER) {
      return c.json(badRequest('You are in the maximum number of crews'), 409);
    }
    if (existing) {
      await c.env.DB.prepare(
        "UPDATE squad_members SET status = 'active', role = 'member', joined_at = CURRENT_TIMESTAMP WHERE id = ?",
      )
        .bind(existing.id)
        .run();
    } else {
      await c.env.DB.prepare(
        `INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at)
         VALUES (?, ?, ?, 'member', 'active', CURRENT_TIMESTAMP)`,
      )
        .bind(generateId(), squad.id, userId)
        .run();
    }

    // Late joiners are pulled into every crew race that is still running.
    await pullIntoOpenCrewRaces(c, squad, userId);
  }

  return c.json({ ok: true, alreadyJoined, squadId: squad.id });
});

// GET /squads/discover — crews where at least one of my active friends is an
// active member and I'm neither a member nor a pending requester. Blocked
// relationships are excluded in both directions.
squadsRouter.get('/discover', async (c) => {
  const userId = c.get('userId');

  const rows = await c.env.DB.prepare(
    `SELECT s.*,
            (SELECT COUNT(*) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active') AS member_count
     FROM squads s
     WHERE s.deleted_at IS NULL
       AND s.id NOT IN (SELECT squad_id FROM squad_members WHERE user_id = ?1 AND status IN ('active', 'requested'))
       AND EXISTS (
         SELECT 1 FROM squad_members fm
         WHERE fm.squad_id = s.id AND fm.status = 'active'
           AND EXISTS (
             SELECT 1 FROM crew_connections cc
             WHERE cc.user_id = ?1 AND cc.crew_user_id = fm.user_id AND cc.status = 'active'))
       AND NOT EXISTS (
         SELECT 1 FROM squad_members bm
         WHERE bm.squad_id = s.id AND bm.status = 'active'
           AND EXISTS (
             SELECT 1 FROM blocked_users b
             WHERE (b.user_id = ?1 AND b.blocked_user_id = bm.user_id)
                OR (b.blocked_user_id = ?1 AND b.user_id = bm.user_id)))
     ORDER BY member_count DESC
     LIMIT 50`,
  )
    .bind(userId)
    .all<SquadRow & { member_count: number }>();

  const squadIds = rows.results.map((r) => r.id);
  const allMemberIds =
    squadIds.length === 0
      ? []
      : (
          await c.env.DB.prepare(
            `SELECT DISTINCT user_id FROM squad_members WHERE squad_id IN (${squadIds.map(() => '?').join(',')}) AND status = 'active'`,
          )
            .bind(...squadIds)
            .all<{ user_id: string }>()
        ).results.map((r) => r.user_id);
  const blockedIds = await blockedSetFor(c.env.DB, userId, allMemberIds);
  const [previews, names] = await Promise.all([
    memberPreviewsFor(c.env.DB, squadIds, blockedIds),
    displayNamesFor(c.env.DB, rows.results.map((r) => r.owner_id)),
  ]);

  return c.json({
    ok: true,
    squads: rows.results.map((r) => ({
      id: r.id,
      name: r.name,
      iconKey: r.icon_key ?? null,
      colorKey: r.color_key ?? null,
      memberCount: r.member_count,
      ownerName: names.get(r.owner_id) ?? null,
      memberPreviews: previews.get(r.id) ?? [],
    })),
  });
});

// GET /squads/:id/preview — the card a non-member sees before asking to join.
// Members get the same shape (viewerStatus 'member') so the client can reuse
// it; the full detail endpoint stays members-only.
squadsRouter.get('/:id/preview', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('not_found'), 404);

  const membership = await roleOf(c.env.DB, squad.id, userId);
  const pending = await tolerant(null, async () => {
    const row = await c.env.DB.prepare(
      `SELECT 1 AS one FROM squad_members WHERE squad_id = ? AND user_id = ? AND status = 'requested'`,
    )
      .bind(squad.id, userId)
      .first<{ one: number }>();
    return row?.one ?? null;
  });

  const members = await activeMemberRows(c.env.DB, squad.id);
  const blockedIds = await blockedSetFor(c.env.DB, userId, members.map((m) => m.user_id));
  const ownerName = await getProfileName(c.env.DB, squad.owner_id);

  return c.json({
    ok: true,
    squad: {
      id: squad.id,
      name: squad.name,
      iconKey: squad.icon_key ?? null,
      colorKey: squad.color_key ?? null,
      memberCount: members.length,
      ownerName: blockedIds.has(squad.owner_id) ? 'Private User' : ownerName,
      memberPreviews: members.slice(0, 5).map((m) => face(m, blockedIds)),
      viewerStatus: membership ? 'member' : pending ? 'requested' : 'none',
    },
  });
});

// GET /squads/:id/standings?period=week|all — points are verified proof
// values submitted by members inside this crew's races. "week" starts Monday
// 00:00 UTC; "all" has no time bound. Members only.
squadsRouter.get('/:id/standings', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('not_found'), 404);
  const role = await roleOf(c.env.DB, squad.id, userId);
  if (!role) return c.json(badRequest('forbidden'), 403);

  const period = c.req.query('period') === 'all' ? 'all' : 'week';
  const since = period === 'week' ? weekStartUtc() : null;
  const points = await squadProofPoints(c.env.DB, squad.id, since);
  const members = await c.env.DB.prepare(
    `SELECT sm.user_id, sm.role, p.full_name, p.username, p.avatar_url
     FROM squad_members sm LEFT JOIN profiles p ON p.user_id = sm.user_id
     WHERE sm.squad_id = ? AND sm.status = 'active'
     ORDER BY sm.joined_at ASC`,
  )
    .bind(squad.id)
    .all<{ user_id: string; role: string; full_name: string | null; username: string | null; avatar_url: string | null }>();

  // Every active member gets a row — zero points still earns a place.
  const byUser = new Map(members.results.map((m) => [m.user_id, m]));
  const ptMap = points ?? new Map<string, number>();
  const rows = members.results
    .map((m) => ({ uid: m.user_id, points: ptMap.get(m.user_id) ?? 0 }))
    .sort((a, b) => (b.points !== a.points ? b.points - a.points : a.uid.localeCompare(b.uid)));

  const blockedIds = await blockedSetFor(c.env.DB, userId, members.results.map((m) => m.user_id));
  let rank = 0;
  let lastPoints: number | null = null;
  const out = rows.map((row) => {
    if (lastPoints === null || row.points < lastPoints) {
      rank += 1;
      lastPoints = row.points;
    }
    const m = byUser.get(row.uid);
    const blocked = blockedIds.has(row.uid);
    return {
      userId: row.uid,
      displayName: blocked
        ? 'Private User'
        : (m?.full_name ?? (m?.username ? `@${m.username}` : 'Nuvo member')),
      profilePhotoUrl: blocked ? null : (m?.avatar_url ?? null),
      role: m?.role ?? 'member',
      points: row.points,
      rank,
      isMe: row.uid === userId,
    };
  });

  return c.json({ ok: true, period, standings: out });
});

// GET /squads/:id
squadsRouter.get('/:id', async (c) => {
  const userId = c.get('userId');
  const squadId = c.req.param('id');
  const [squad, isMember] = await Promise.all([
    getSquad(c.env.DB, squadId),
    isActiveMember(c.env.DB, squadId, userId),
  ]);
  if (!squad || !isMember) {
    return c.json(badRequest('Crew not found'), 404);
  }

  // Validator: members, linked races, race version/updated_at and progress
  // updates (standings depend on them), bounded by a 60s bucket.
  const stamp = await c.env.DB.prepare(
    `SELECT
       (SELECT COUNT(*) FROM squad_members WHERE squad_id = ?1 AND status = 'active') AS members,
       (SELECT MAX(joined_at) FROM squad_members WHERE squad_id = ?1 AND status = 'active') AS max_joined,
       (SELECT GROUP_CONCAT(user_id || role, '') FROM
         (SELECT user_id, role FROM squad_members WHERE squad_id = ?1 AND status = 'active' ORDER BY user_id)) AS roles,
       (SELECT COUNT(*) FROM squad_races sr JOIN races r ON r.id = sr.race_id
         WHERE sr.squad_id = ?1 AND r.deleted_at IS NULL) AS races,
       (SELECT MAX(r.version) FROM squad_races sr JOIN races r ON r.id = sr.race_id
         WHERE sr.squad_id = ?1 AND r.deleted_at IS NULL) AS max_version,
       (SELECT MAX(r.updated_at) FROM squad_races sr JOIN races r ON r.id = sr.race_id
         WHERE sr.squad_id = ?1 AND r.deleted_at IS NULL) AS max_race_updated,
       (SELECT MAX(rp.updated_at) FROM squad_races sr JOIN race_progress rp ON rp.race_id = sr.race_id
         WHERE sr.squad_id = ?1) AS max_progress,
       (SELECT COALESCE(SUM(rp.progress_value), 0) FROM squad_races sr
         JOIN race_progress rp ON rp.race_id = sr.race_id
         JOIN squad_members sm ON sm.squad_id = sr.squad_id AND sm.user_id = rp.user_id AND sm.status = 'active'
         WHERE sr.squad_id = ?1) AS progress_sum`,
  )
    .bind(squad.id)
    .first<{
      members: number;
      max_joined: string | null;
      roles: string | null;
      races: number;
      max_version: number | null;
      max_race_updated: string | null;
      max_progress: string | null;
      progress_sum: number | null;
    }>();
  // 0049-era signals in one tolerant read: recurring rows (+this week's
  // spawn stamp), pending join requests, my mute flag, and this week's
  // verified proof totals (the weekly standings source).
  const extras = await tolerant(
    { recurring: '', pending: 0, myMuted: null as string | null, weekPoints: '' },
    () =>
      c.env.DB.prepare(
        `SELECT
           (SELECT COUNT(*) || ':' || COALESCE(MAX(created_at), '') || ':' ||
             COALESCE(MAX(last_spawned_at), '')
            FROM squad_recurring_races WHERE squad_id = ?1) AS recurring,
           (SELECT COUNT(*) FROM squad_members WHERE squad_id = ?1 AND status = 'requested') AS pending,
           (SELECT muted_at FROM squad_members WHERE squad_id = ?1 AND user_id = ?2 AND status = 'active') AS myMuted,
           (SELECT COUNT(*) || ':' || COALESCE(MAX(ml.created_at), '')
            FROM move_logs ml
            WHERE ml.status = 'verified' AND ml.created_at >= ?3
              AND ml.race_id IN (SELECT race_id FROM squad_races WHERE squad_id = ?1)) AS weekPoints`,
      )
      .bind(squad.id, userId, weekStartUtc())
      .first<{ recurring: string; pending: number; myMuted: string | null; weekPoints: string }>(),
  );
  const notModified = conditional(
    c,
    weakEtag(
      'squad',
      squad.id,
      stamp?.members,
      stamp?.max_joined,
      stamp?.roles ? stamp.roles.length + ':' + hashString(stamp.roles) : '',
      hashString(squad.name),
      stamp?.races,
      stamp?.max_version,
      stamp?.max_race_updated,
      stamp?.max_progress,
      stamp?.progress_sum,
      hashString(`${squad.bio ?? ''}|${squad.color_key ?? ''}|${squad.icon_key ?? ''}`),
      extras?.recurring,
      extras?.pending,
      extras?.myMuted ? 'muted' : '',
      extras?.weekPoints,
      stalenessBucket(Date.now(), 60_000),
    ),
  );
  if (notModified) return notModified;

  const [members, races] = await Promise.all([
    c.env.DB.prepare(
      `SELECT sm.user_id, sm.role, sm.joined_at, p.full_name, p.username, p.avatar_url
       FROM squad_members sm
       LEFT JOIN profiles p ON p.user_id = sm.user_id
       WHERE sm.squad_id = ? AND sm.status = 'active'
       ORDER BY sm.joined_at ASC`,
    )
      .bind(squad.id)
      .all<{
        user_id: string;
        role: string;
        joined_at: string;
        full_name: string | null;
        username: string | null;
        avatar_url: string | null;
      }>(),
    c.env.DB.prepare(
      `SELECT r.id, r.title, r.status, r.target_value, r.target_unit, r.score_direction, r.activity_id, r.format, r.race_type, sr.created_at
       FROM squad_races sr JOIN races r ON r.id = sr.race_id
       WHERE sr.squad_id = ? AND r.deleted_at IS NULL
       ORDER BY sr.created_at DESC`,
    )
      .bind(squad.id)
      .all<{
        id: string;
        title: string;
        status: string;
        target_value: number | null;
        target_unit: string | null;
        format: string | null;
        race_type: string | null;
        score_direction: string | null;
        activity_id: string | null;
        created_at: string;
      }>(),
  ]);

  const memberIds = members.results.map((m) => m.user_id);
  // Blocked pairs (either direction) are anonymized; everyone else shows
  // their real name and photo.
  const blockedIds = await blockedSetFor(c.env.DB, userId, memberIds);

  // v13 additions: recurring definitions with per-viewer auto-join state and
  // the faces already opted in, plus crew stats and pending join requests
  // (owner/admin only).
  const [recurringRows, stats] = await Promise.all([
    recurringRowsFor(c.env.DB, [squad.id]),
    squadCrewStats(c.env.DB, squad.id, races.results.length),
  ]);
  const recurringIds = recurringRows.map((r) => r.id);
  const optouts = await optoutsFor(c.env.DB, recurringIds);
  const myMemberRow = members.results.find((m) => m.user_id === userId);
  const myRole = effectiveRole(squad.owner_id, userId, myMemberRow?.role ?? 'member');
  const joinRequests = myRole === 'member' ? [] : await joinRequestsFor(c.env.DB, squad.id);
  const autoJoinPreviewRows = await Promise.all(
    recurringRows.map(async (rr) => {
      const opted = optouts.get(rr.id);
      const included = members.results.filter(
        (m) => rr.auto_join === 1 && !(opted?.has(m.user_id) ?? false),
      );
      return included.slice(0, 5).map((m) => face(m, blockedIds));
    }),
  );

  // One score query for every crew race (chunked: D1 caps bound parameters at
  // 100 per statement), grouped by race in JS.
  type ScoreRow = {
    race_id: string;
    user_id: string;
    joined_at: string;
    progress_value: number | null;
    completed_at: string | null;
  };
  const raceIds = races.results.map((r) => r.id);
  const chunks: string[][] = [];
  for (let i = 0; i < raceIds.length; i += 80) chunks.push(raceIds.slice(i, i + 80));
  const scoreSets =
    chunks.length === 0
      ? []
      : await c.env.DB.batch<ScoreRow>(
          chunks.map((ids) =>
            c.env.DB.prepare(
              `SELECT rm.race_id, rm.user_id, rm.joined_at, rp.progress_value, rp.completed_at
               FROM race_members rm
               LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
               JOIN squad_members sm ON sm.squad_id = ? AND sm.user_id = rm.user_id AND sm.status = 'active'
               WHERE rm.race_id IN (${ids.map(() => '?').join(',')}) AND rm.status = 'active'`,
            ).bind(squad.id, ...ids),
          ),
        );
  const scoresByRace = new Map<string, ScoreRow[]>();
  for (const set of scoreSets) {
    for (const row of set.results) {
      const list = scoresByRace.get(row.race_id);
      if (list) list.push(row);
      else scoresByRace.set(row.race_id, [row]);
    }
  }
  const raceInputs: SquadRaceInput[] = races.results.map((race) => ({
    raceId: race.id,
    direction: race.score_direction === 'lower' ? 'lower' : 'higher',
    scores: (scoresByRace.get(race.id) ?? []).map((s) => ({
      user_id: s.user_id,
      joined_at: s.joined_at,
      progress_value: s.progress_value ?? 0,
      completed_at: s.completed_at,
    })),
  }));

  const standings = computeSquadStandings(memberIds, raceInputs);
  const byUser = new Map(members.results.map((m) => [m.user_id, m]));

  return c.json({
    ok: true,
    squad: {
      id: squad.id,
      name: squad.name,
      joinCode: squad.join_code,
      isOwner: squad.owner_id === userId,
      myRole,
      memberCount: members.results.length,
      raceCount: races.results.length,
      createdAt: squad.created_at,
      bio: squad.bio ?? null,
      colorKey: squad.color_key ?? null,
      iconKey: squad.icon_key ?? null,
      stats,
      muted: (extras?.myMuted ?? null) != null,
      // Reserved for the crew-vs-crew surface; nothing to report until W4.
      battle: null,
    },
    recurring: recurringRows.map((rr, i) =>
      serializeRecurring(rr, optouts.get(rr.id)?.has(userId) ?? false, autoJoinPreviewRows[i] ?? []),
    ),
    joinRequests: joinRequests.map((r) => {
      const blocked = blockedIds.has(r.user_id);
      return {
        userId: r.user_id,
        requestedAt: r.joined_at,
        displayName: blocked
          ? 'Private User'
          : (r.full_name ?? (r.username ? `@${r.username}` : 'Nuvo member')),
        profilePhotoUrl: blocked ? null : r.avatar_url,
      };
    }),
    members: members.results.map((m) => ({
      userId: m.user_id,
      displayName: blockedIds.has(m.user_id)
        ? 'Private User'
        : (m.full_name ?? (m.username ? `@${m.username}` : 'Nuvo member')),
      username: blockedIds.has(m.user_id) ? null : m.username,
      profilePhotoUrl: blockedIds.has(m.user_id) ? null : m.avatar_url,
      role: effectiveRole(squad.owner_id, m.user_id, m.role),
    })),
    races: races.results.map((r) => ({
      id: r.id,
      title: r.title,
      status: r.status,
      targetValue: effectiveTargetValue(r.format ?? r.race_type, r.target_value),
      targetUnit: r.target_unit,
      activityId: r.activity_id,
    })),
    standings: standings.map((s) => {
      const m = byUser.get(s.user_id);
      return {
        userId: s.user_id,
        rank: s.rank,
        points: s.points,
        wins: s.wins,
        races: s.races,
        displayName: blockedIds.has(s.user_id)
          ? 'Private User'
          : (m?.full_name ?? (m?.username ? `@${m.username}` : 'Nuvo member')),
        profilePhotoUrl: blockedIds.has(s.user_id) ? null : (m?.avatar_url ?? null),
        isYou: s.user_id === userId,
      };
    }),
  });
});

// POST /squads/:id/races { raceId } — bring a race the caller created into
// the crew. Any active member may do this (v13); the race itself still has to
// be theirs — you can only put your own races on the crew board.
squadsRouter.post('/:id/races', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad || !(await isActiveMember(c.env.DB, squad.id, userId))) {
    return c.json(badRequest('Crew not found'), 404);
  }
  const body = await readJson(c);
  const raceId = typeof body?.raceId === 'string' ? body.raceId.trim() : '';
  if (!raceId) return c.json(badRequest('raceId is required'), 400);

  const race = await getRace(c.env.DB, raceId);
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) {
    return c.json(badRequest('Only the race creator can bring a race to a crew'), 403);
  }
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  const linked = await c.env.DB.prepare('SELECT squad_id FROM squad_races WHERE race_id = ?')
    .bind(race.id)
    .first<{ squad_id: string }>();
  if (linked && linked.squad_id !== squad.id) {
    return c.json(badRequest('This race already belongs to another crew'), 409);
  }
  if (!linked) {
    await c.env.DB.prepare(
      `INSERT INTO squad_races (id, squad_id, race_id, created_by, created_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
    )
      .bind(generateId(), squad.id, race.id, userId)
      .run();
  }

  const members = await c.env.DB.prepare(
    "SELECT user_id FROM squad_members WHERE squad_id = ? AND status = 'active'",
  )
    .bind(squad.id)
    .all<{ user_id: string }>();
  const inviterName = await getProfileName(c.env.DB, userId);
  const muted = await squadMutedSet(c.env.DB, squad.id);
  const waitUntil = (p: Promise<unknown>) => c.executionCtx.waitUntil(p);
  let added = 0;
  for (const m of members.results) {
    if (
      await bestEffort('squad_add_race_member', () =>
        addMemberToSquadRace(c.env, waitUntil, race, m.user_id, inviterName, {
          muted: muted.has(m.user_id),
        }),
      )
    ) {
      added += 1;
    }
  }

  return c.json({ ok: true, raceId: race.id, added, memberCount: members.results.length });
});

// PATCH /squads/:id { name?, bio?, colorKey?, iconKey? } — owner/admin crew
// settings. Every field is optional; at least one must be present. The 0049
// columns are probed once so a schema without them still takes plain renames.
squadsRouter.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (!myRole) return c.json(badRequest('Crew not found'), 404);
  if (myRole === 'member') return c.json(badRequest('Only crew admins can edit the crew'), 403);
  const body = await readJson(c);
  if (!body || typeof body !== 'object') return c.json(badRequest('nothing to update'), 400);

  const sets: string[] = [];
  const binds: (string | number | null)[] = [];
  const out: Record<string, unknown> = {};

  if (body.name !== undefined) {
    const name = typeof body.name === 'string' ? body.name.trim().replace(/\s+/g, ' ') : '';
    if (name.length < 2 || name.length > 40) {
      return c.json(badRequest('Crew name must be 2-40 characters'), 400);
    }
    sets.push('name = ?');
    binds.push(name);
    out.name = name;
  }
  if (body.bio !== undefined) {
    if (body.bio !== null && typeof body.bio !== 'string') {
      return c.json(badRequest('bio must be a string'), 400);
    }
    const bio = typeof body.bio === 'string' ? body.bio.trim() : null;
    if (bio != null && bio.length > BIO_MAX) {
      return c.json(badRequest(`Crew bio must be ${BIO_MAX} characters or fewer`), 400);
    }
    sets.push('bio = ?');
    binds.push(bio);
    out.bio = bio;
  }
  if (body.colorKey !== undefined) {
    if (body.colorKey !== null && (typeof body.colorKey !== 'string' || !CREW_COLORS.has(body.colorKey))) {
      return c.json(badRequest(`colorKey must be one of ${[...CREW_COLORS].join('|')}`), 400);
    }
    sets.push('color_key = ?');
    binds.push(body.colorKey ?? null);
    out.colorKey = body.colorKey ?? null;
  }
  if (body.iconKey !== undefined) {
    if (body.iconKey !== null && (typeof body.iconKey !== 'string' || body.iconKey.length > ICON_MAX)) {
      return c.json(badRequest(`iconKey must be a string of at most ${ICON_MAX} characters`), 400);
    }
    sets.push('icon_key = ?');
    binds.push(body.iconKey ?? null);
    out.iconKey = body.iconKey ?? null;
  }
  if (sets.length === 0) return c.json(badRequest('nothing to update'), 400);

  try {
    await c.env.DB.prepare(`UPDATE squads SET ${sets.join(', ')} WHERE id = ?`)
      .bind(...binds, squad.id)
      .run();
  } catch (err) {
    // A schema without the 0049 columns can still be renamed.
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('no such column')) {
      return c.json(badRequest('This crew field is not available yet'), 400);
    }
    throw err;
  }
  return c.json({ ok: true, ...out });
});

// DELETE /squads/:id — the owner deletes the crew. Soft delete: the crew
// disappears for everyone; races stay as they are, just no longer linked to a
// live crew. Members' races and proofs are untouched.
squadsRouter.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (!myRole) return c.json(badRequest('Crew not found'), 404);
  if (myRole !== 'owner') return c.json(badRequest('Only the crew owner can delete the crew'), 403);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE squads SET deleted_at = CURRENT_TIMESTAMP WHERE id = ?').bind(squad.id),
    c.env.DB.prepare("UPDATE squad_members SET status = 'left', role = 'member' WHERE squad_id = ? AND status = 'active'").bind(
      squad.id,
    ),
  ]);
  return c.json({ ok: true });
});

// DELETE /squads/:id/races/:raceId — unlink a race from the crew (owner/admin).
// Members stay in the race itself; it just stops counting for the crew.
squadsRouter.delete('/:id/races/:raceId', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (!myRole) return c.json(badRequest('Crew not found'), 404);
  if (myRole === 'member') return c.json(badRequest('Only crew admins can remove races'), 403);
  await c.env.DB.prepare('DELETE FROM squad_races WHERE squad_id = ? AND race_id = ?')
    .bind(squad.id, c.req.param('raceId'))
    .run();
  return c.json({ ok: true });
});

// POST /squads/:id/members/:userId/role { role: 'admin' | 'member' } — owner only.
squadsRouter.post('/:id/members/:userId/role', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (!myRole) return c.json(badRequest('Crew not found'), 404);
  if (myRole !== 'owner') return c.json(badRequest('Only the crew owner can change roles'), 403);

  const targetId = c.req.param('userId');
  const body = await readJson(c);
  const role = body?.role;
  if (role !== 'admin' && role !== 'member') {
    return c.json(badRequest("role must be 'admin' or 'member'"), 400);
  }
  const targetRole = await roleOf(c.env.DB, squad.id, targetId);
  if (!targetRole) return c.json(badRequest('Member not found'), 404);
  if (targetRole === 'owner') return c.json(badRequest('The owner role cannot be changed'), 400);

  await c.env.DB.prepare("UPDATE squad_members SET role = ? WHERE squad_id = ? AND user_id = ? AND status = 'active'")
    .bind(role, squad.id, targetId)
    .run();
  return c.json({ ok: true, userId: targetId, role });
});

// DELETE /squads/:id/members/:userId — remove a member. The owner can remove
// anyone; an admin can remove regular members. Nobody removes the owner.
squadsRouter.delete('/:id/members/:userId', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (!myRole) return c.json(badRequest('Crew not found'), 404);

  const targetId = c.req.param('userId');
  if (targetId === userId) return c.json(badRequest('Use leave to exit the crew'), 400);
  const targetRole = await roleOf(c.env.DB, squad.id, targetId);
  if (!targetRole) return c.json(badRequest('Member not found'), 404);
  const allowed =
    targetRole !== 'owner' &&
    (myRole === 'owner' || (myRole === 'admin' && targetRole === 'member'));
  if (!allowed) return c.json(badRequest('You cannot remove this member'), 403);

  await c.env.DB.prepare("UPDATE squad_members SET status = 'removed', role = 'member' WHERE squad_id = ? AND user_id = ?")
    .bind(squad.id, targetId)
    .run();
  return c.json({ ok: true });
});

// POST /squads/:id/leave
squadsRouter.post('/:id/leave', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad || !(await isActiveMember(c.env.DB, squad.id, userId))) {
    return c.json(badRequest('Crew not found'), 404);
  }
  // One atomic batch. The owner leaving hands the crew to an admin first, else
  // the longest-standing member, or retires it when nobody is left. The leaver
  // always drops back to a plain member role so it cannot survive a re-join.
  const statements = [
    c.env.DB.prepare(
      "UPDATE squad_members SET status = 'left', role = 'member' WHERE squad_id = ? AND user_id = ?",
    ).bind(squad.id, userId),
  ];
  if (squad.owner_id === userId) {
    statements.push(
      c.env.DB.prepare(
        `UPDATE squads SET owner_id = COALESCE(
           (SELECT user_id FROM squad_members WHERE squad_id = ?1 AND status = 'active'
            ORDER BY (role = 'admin') DESC, joined_at ASC LIMIT 1), owner_id)
         WHERE id = ?1 AND owner_id = ?2`,
      ).bind(squad.id, userId),
      c.env.DB.prepare(
        `UPDATE squad_members SET role = 'owner'
         WHERE squad_id = ?1 AND status = 'active' AND user_id != ?2
           AND user_id = (SELECT owner_id FROM squads WHERE id = ?1)`,
      ).bind(squad.id, userId),
      c.env.DB.prepare(
        `UPDATE squads SET deleted_at = CURRENT_TIMESTAMP
         WHERE id = ?1 AND deleted_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM squad_members WHERE squad_id = ?1 AND status = 'active')`,
      ).bind(squad.id),
    );
  }
  await c.env.DB.batch(statements);
  return c.json({ ok: true });
});

// ── Join requests ───────────────────────────────────────────────────────────

// POST /squads/:id/join-request — ask to join a crew you found via the crew
// board (a friend is inside). Members and pending requesters get an
// idempotent ok; a removed member cannot ask again.
squadsRouter.post('/:id/join-request', async (c) => {
  const userId = c.get('userId');
  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json(badRequest('You must accept the Terms of Service to join a crew'), 403);
  }
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);

  const existing = await c.env.DB.prepare(
    'SELECT id, status FROM squad_members WHERE squad_id = ? AND user_id = ?',
  )
    .bind(squad.id, userId)
    .first<{ id: string; status: string }>();
  if (existing?.status === 'active') {
    return c.json({ ok: true, status: 'member', squadId: squad.id });
  }
  if (existing?.status === 'requested') {
    return c.json({ ok: true, status: 'requested', squadId: squad.id });
  }
  if (existing?.status === 'removed') {
    return c.json(badRequest('You were removed from this crew'), 403);
  }
  if ((await memberCount(c.env.DB, squad.id)) >= MAX_MEMBERS) {
    return c.json(badRequest('This crew is full'), 409);
  }
  if ((await activeMembershipCount(c.env.DB, userId, squad.id)) >= MAX_SQUADS_PER_USER) {
    return c.json(badRequest('You are in the maximum number of crews'), 409);
  }
  // Owner-blocked pairs never see a request — either direction.
  if (
    (await isBlocked(c.env.DB, userId, squad.owner_id)) ||
    (await isBlocked(c.env.DB, squad.owner_id, userId))
  ) {
    return c.json(badRequest('Crew not found'), 404);
  }

  if (existing) {
    await c.env.DB.prepare(
      "UPDATE squad_members SET status = 'requested', role = 'member', joined_at = CURRENT_TIMESTAMP WHERE id = ?",
    )
      .bind(existing.id)
      .run();
  } else {
    await c.env.DB.prepare(
      `INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at)
       VALUES (?, ?, ?, 'member', 'requested', CURRENT_TIMESTAMP)`,
    )
      .bind(generateId(), squad.id, userId)
      .run();
  }

  // Owner + admins get the in-app ping. Muted members and people who blocked
  // the requester don't.
  const admins = await c.env.DB.prepare(
    `SELECT sm.user_id FROM squad_members sm
     WHERE sm.squad_id = ? AND sm.status = 'active'
       AND (sm.user_id = ? OR sm.role = 'admin')`,
  )
    .bind(squad.id, squad.owner_id)
    .all<{ user_id: string }>();
  const muted = await squadMutedSet(c.env.DB, squad.id);
  const requesterName = await getProfileName(c.env.DB, userId);
  const waitUntil = (p: Promise<unknown>) => c.executionCtx.waitUntil(p);
  for (const admin of admins.results) {
    if (muted.has(admin.user_id)) continue;
    if (await isBlocked(c.env.DB, admin.user_id, userId)) continue;
    await bestEffort('squad_join_request_notice', () =>
      notifyEvent(c.env, waitUntil, {
        type: 'squad_join_requested',
        userId: admin.user_id,
        actorUserId: userId,
        actorName: requesterName,
        squadId: squad.id,
        squadName: squad.name,
      }),
    );
  }
  return c.json({ ok: true, status: 'requested', squadId: squad.id });
});

// POST /squads/:id/join-requests/:userId/approve — owner/admin turns a
// pending request into a member, then pulls them into open crew races
// exactly like the code-join path does.
squadsRouter.post('/:id/join-requests/:userId/approve', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can approve join requests'), 403);
  }
  const targetId = c.req.param('userId');
  const request = await c.env.DB.prepare(
    "SELECT id, status FROM squad_members WHERE squad_id = ? AND user_id = ?",
  )
    .bind(squad.id, targetId)
    .first<{ id: string; status: string }>();
  if (request?.status === 'active') {
    return c.json({ ok: true, status: 'member' });
  }
  if (request?.status !== 'requested') {
    return c.json(badRequest('No pending request for that member'), 404);
  }
  if ((await memberCount(c.env.DB, squad.id)) >= MAX_MEMBERS) {
    return c.json(badRequest('This crew is full'), 409);
  }
  if ((await activeMembershipCount(c.env.DB, targetId, squad.id)) >= MAX_SQUADS_PER_USER) {
    return c.json(badRequest('They are in the maximum number of crews'), 409);
  }

  await c.env.DB.prepare(
    "UPDATE squad_members SET status = 'active', role = 'member', joined_at = CURRENT_TIMESTAMP WHERE id = ?",
  )
    .bind(request.id)
    .run();
  await pullIntoOpenCrewRaces(c, squad, targetId);

  // Tell the requester they are in — unless they muted this crew already.
  if (!(await isSquadMuted(c.env.DB, squad.id, targetId))) {
    const approverName = await getProfileName(c.env.DB, userId);
    await bestEffort('squad_join_approved_notice', () =>
      notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
        type: 'squad_join_approved',
        userId: targetId,
        actorUserId: userId,
        actorName: approverName,
        squadId: squad.id,
        squadName: squad.name,
      }),
    );
  }
  return c.json({ ok: true, status: 'member' });
});

// POST /squads/:id/join-requests/:userId/decline — owner/admin drops the
// pending request. The requester can ask again later.
squadsRouter.post('/:id/join-requests/:userId/decline', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can decline join requests'), 403);
  }
  const targetId = c.req.param('userId');
  const res = await c.env.DB.prepare(
    "UPDATE squad_members SET status = 'left' WHERE squad_id = ? AND user_id = ? AND status = 'requested'",
  )
    .bind(squad.id, targetId)
    .run();
  if ((res.meta?.changes ?? 0) === 0) {
    return c.json(badRequest('No pending request for that member'), 404);
  }
  return c.json({ ok: true, status: 'declined' });
});

// ── Crew mute ───────────────────────────────────────────────────────────────

// POST /squads/:id/mute { on } — suppress this crew's notifications for me.
// The flag lives on my membership row (squad_members.muted_at, 0049) and is
// honored by every crew notification path through squadMutedSet /
// isSquadMuted. user_mutes 'crew' rows count too — both surfaces mute the
// same crew.
squadsRouter.post('/:id/mute', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad || !(await isActiveMember(c.env.DB, squad.id, userId))) {
    return c.json(badRequest('Crew not found'), 404);
  }
  const body = await readJson(c);
  const on = body?.on !== false;
  try {
    await c.env.DB.prepare(
      'UPDATE squad_members SET muted_at = CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END WHERE squad_id = ? AND user_id = ?',
    )
      .bind(on ? 1 : 0, squad.id, userId)
      .run();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('no such column')) {
      return c.json(badRequest('Crew mute is not available yet'), 400);
    }
    throw err;
  }
  return c.json({ ok: true, muted: on });
});

// ── Recurring crew races ────────────────────────────────────────────────────

function parseWeekday(v: unknown): number | null {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > 6) return null;
  return v;
}

// POST /squads/:id/recurring { title, activityId, raceType, targetValue,
// targetUnit, weekday } — owner/admin defines a weekly crew race.
squadsRouter.post('/:id/recurring', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can set up recurring races'), 403);
  }
  const body = await readJson(c);
  const title = typeof body?.title === 'string' ? body.title.trim().replace(/\s+/g, ' ') : '';
  if (title.length < 2 || title.length > 60) {
    return c.json(badRequest('Race title must be 2-60 characters'), 400);
  }
  const weekday = parseWeekday(body?.weekday);
  if (weekday === null) return c.json(badRequest('weekday must be an integer 0-6'), 400);
  const activityId = typeof body?.activityId === 'string' ? body.activityId : null;
  const raceType = typeof body?.raceType === 'string' ? body.raceType : null;
  const targetValue = typeof body?.targetValue === 'number' ? body.targetValue : null;
  const targetUnit = typeof body?.targetUnit === 'string' ? body.targetUnit : null;

  const id = generateId();
  try {
    await c.env.DB.prepare(
      `INSERT INTO squad_recurring_races
         (id, squad_id, title, activity_id, race_type, target_value, target_unit,
          weekday, auto_join, active, created_by, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?, CURRENT_TIMESTAMP)`,
    )
      .bind(id, squad.id, title, activityId, raceType, targetValue, targetUnit, weekday, userId)
      .run();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('no such table')) {
      return c.json(badRequest('Recurring races are not available yet'), 400);
    }
    throw err;
  }
  const row = await c.env.DB.prepare('SELECT * FROM squad_recurring_races WHERE id = ?')
    .bind(id)
    .first<RecurringRow>();
  return c.json({ ok: true, recurring: row ? serializeRecurring(row, false, []) : { id } }, 201);
});

// PATCH /squads/:id/recurring/:rid — owner/admin edits a recurring race.
// Accepts the create fields plus { active } to pause/resume.
squadsRouter.patch('/:id/recurring/:rid', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can edit recurring races'), 403);
  }
  const rid = c.req.param('rid');
  const row = await tolerant(null, () =>
    c.env.DB.prepare('SELECT * FROM squad_recurring_races WHERE id = ? AND squad_id = ?')
      .bind(rid, squad.id)
      .first<RecurringRow>(),
  );
  if (!row) return c.json(badRequest('Recurring race not found'), 404);
  const body = await readJson(c);
  if (!body || typeof body !== 'object') return c.json(badRequest('nothing to update'), 400);

  const sets: string[] = [];
  const binds: (string | number | null)[] = [];
  if (body.title !== undefined) {
    const title = typeof body.title === 'string' ? body.title.trim().replace(/\s+/g, ' ') : '';
    if (title.length < 2 || title.length > 60) {
      return c.json(badRequest('Race title must be 2-60 characters'), 400);
    }
    sets.push('title = ?');
    binds.push(title);
  }
  if (body.activityId !== undefined) {
    if (body.activityId !== null && typeof body.activityId !== 'string') {
      return c.json(badRequest('activityId must be a string or null'), 400);
    }
    sets.push('activity_id = ?');
    binds.push(body.activityId ?? null);
  }
  if (body.raceType !== undefined) {
    if (body.raceType !== null && typeof body.raceType !== 'string') {
      return c.json(badRequest('raceType must be a string or null'), 400);
    }
    sets.push('race_type = ?');
    binds.push(body.raceType ?? null);
  }
  if (body.targetValue !== undefined) {
    if (body.targetValue !== null && typeof body.targetValue !== 'number') {
      return c.json(badRequest('targetValue must be a number or null'), 400);
    }
    sets.push('target_value = ?');
    binds.push(body.targetValue ?? null);
  }
  if (body.targetUnit !== undefined) {
    if (body.targetUnit !== null && typeof body.targetUnit !== 'string') {
      return c.json(badRequest('targetUnit must be a string or null'), 400);
    }
    sets.push('target_unit = ?');
    binds.push(body.targetUnit ?? null);
  }
  if (body.weekday !== undefined) {
    const weekday = parseWeekday(body.weekday);
    if (weekday === null) return c.json(badRequest('weekday must be an integer 0-6'), 400);
    sets.push('weekday = ?');
    binds.push(weekday);
  }
  if (body.active !== undefined) {
    sets.push('active = ?');
    binds.push(body.active === false ? 0 : 1);
  }
  if (body.autoJoin !== undefined) {
    // Crew-level default: individual members can still opt out for themselves.
    sets.push('auto_join = ?');
    binds.push(body.autoJoin === false ? 0 : 1);
  }
  if (sets.length === 0) return c.json(badRequest('nothing to update'), 400);

  await c.env.DB.prepare(`UPDATE squad_recurring_races SET ${sets.join(', ')} WHERE id = ?`)
    .bind(...binds, rid)
    .run();
  const updated = await c.env.DB.prepare('SELECT * FROM squad_recurring_races WHERE id = ?')
    .bind(rid)
    .first<RecurringRow>();
  const opted = await tolerant(false, async () => {
    const o = await c.env.DB.prepare(
      'SELECT 1 AS one FROM squad_recurring_optouts WHERE recurring_id = ? AND user_id = ?',
    )
      .bind(rid, userId)
      .first<{ one: number }>();
    return Boolean(o?.one);
  });
  return c.json({ ok: true, recurring: updated ? serializeRecurring(updated, opted, []) : null });
});

// DELETE /squads/:id/recurring/:rid — owner/admin removes the weekly race.
// Already-spawned races keep running; only the template goes away.
squadsRouter.delete('/:id/recurring/:rid', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad) return c.json(badRequest('Crew not found'), 404);
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can remove recurring races'), 403);
  }
  const rid = c.req.param('rid');
  try {
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM squad_recurring_optouts WHERE recurring_id = ?').bind(rid),
      c.env.DB.prepare('DELETE FROM squad_recurring_races WHERE id = ? AND squad_id = ?').bind(rid, squad.id),
    ]);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('no such table')) {
      return c.json(badRequest('Recurring race not found'), 404);
    }
    throw err;
  }
  return c.json({ ok: true });
});

// POST /squads/:id/recurring/:rid/auto-join { on } — a member's personal
// opt-out for one recurring race. Opted-out members are skipped when the
// next instance spawns; opting back in re-joins future instances.
squadsRouter.post('/:id/recurring/:rid/auto-join', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad || !(await isActiveMember(c.env.DB, squad.id, userId))) {
    return c.json(badRequest('Crew not found'), 404);
  }
  const rid = c.req.param('rid');
  const row = await tolerant(null, () =>
    c.env.DB.prepare('SELECT id FROM squad_recurring_races WHERE id = ? AND squad_id = ?')
      .bind(rid, squad.id)
      .first<{ id: string }>(),
  );
  if (!row) return c.json(badRequest('Recurring race not found'), 404);
  const body = await readJson(c);
  const on = body?.on !== false;
  try {
    if (on) {
      await c.env.DB.prepare('DELETE FROM squad_recurring_optouts WHERE recurring_id = ? AND user_id = ?')
        .bind(rid, userId)
        .run();
    } else {
      await c.env.DB.prepare(
        'INSERT OR IGNORE INTO squad_recurring_optouts (recurring_id, user_id, created_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
      )
        .bind(rid, userId)
        .run();
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes('no such table')) {
      return c.json(badRequest('Auto-join is not available yet'), 400);
    }
    throw err;
  }
  return c.json({ ok: true, autoJoin: on });
});
