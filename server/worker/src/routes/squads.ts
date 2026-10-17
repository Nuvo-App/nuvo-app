import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';
import { conditional, stalenessBucket, weakEtag } from '../lib/etag';
import { hasAcceptedTerms } from '../lib/terms';
import { isBlocked } from '../lib/privacy';
import { ensureMember, ensureProgress, getProfileName, getRace } from '../domain/raceMembership';
import { effectiveTargetValue } from '../domain/raceTarget';
import { notifyEvent } from '../domain/notificationPolicy';
import { computeSquadStandings, type SquadRaceInput } from '../domain/squadStandings';

/**
 * Crew groups. "Squad" in the API, "crew" in the app's copy.
 *
 *   POST /squads              create (caller becomes owner)
 *   GET  /squads              my crews
 *   POST /squads/join         join by code
 *   GET  /squads/:id          detail: members, linked races, standings
 *   POST /squads/:id/races    link a race I created -> every member is added
 *   POST /squads/:id/leave
 */
export const squadsRouter = new Hono<AppEnv>();

squadsRouter.use('*', requireAuth);

const MAX_MEMBERS = 100;
const MAX_SQUADS_PER_USER = 10;
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

type Ctx = Context<AppEnv>;

interface SquadRow {
  id: string;
  name: string;
  join_code: string;
  owner_id: string;
  created_at: string;
}

const badRequest = (error: string) => ({ ok: false, error });

function generateJoinCode(): string {
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((b) => CODE_CHARS[b % CODE_CHARS.length])
    .join('');
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

async function roleOf(db: D1Database, squadId: string, userId: string): Promise<CrewRole | null> {
  const row = await db
    .prepare("SELECT role FROM squad_members WHERE squad_id = ? AND user_id = ? AND status = 'active'")
    .bind(squadId, userId)
    .first<{ role: string }>();
  if (!row) return null;
  return row.role === 'owner' || row.role === 'admin' ? row.role : 'member';
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

/** Puts a user into a race as a squad-linked racer. Returns true when newly added. */
async function addToRace(
  c: Ctx,
  race: { id: string; title: string; creator_id: string },
  userId: string,
  inviterName: string | null,
): Promise<boolean> {
  const db = c.env.DB;
  if (userId !== race.creator_id) {
    if ((await isBlocked(db, userId, race.creator_id)) || (await isBlocked(db, race.creator_id, userId))) {
      return false;
    }
  }
  const { created } = await ensureMember(db, race.id, userId);
  await ensureProgress(db, race.id, userId);
  if (created && userId !== race.creator_id) {
    await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
      type: 'race_invited',
      userId,
      actorUserId: race.creator_id,
      actorName: inviterName,
      raceId: race.id,
      raceTitle: race.title,
    });
  }
  return created;
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

  const owned = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM squad_members WHERE user_id = ? AND status = 'active'`,
  )
    .bind(userId)
    .first<{ count: number }>();
  if ((owned?.count ?? 0) >= MAX_SQUADS_PER_USER) {
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

  await c.env.DB.batch([
    c.env.DB.prepare(
      'INSERT INTO squads (id, name, join_code, owner_id, created_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)',
    ).bind(id, name, code, userId),
    c.env.DB.prepare(
      `INSERT INTO squad_members (id, squad_id, user_id, role, status, joined_at)
       VALUES (?, ?, ?, 'owner', 'active', CURRENT_TIMESTAMP)`,
    ).bind(generateId(), id, userId),
  ]);

  return c.json({ ok: true, squad: { id, name, joinCode: code, isOwner: true, memberCount: 1, raceCount: 0 } }, 201);
});

// GET /squads
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
            MAX((SELECT MAX(m.joined_at) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active')) AS max_member_joined
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
    }>();
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
      stalenessBucket(Date.now(), 60_000),
    ),
  );
  if (notModified) return notModified;

  const rows = await c.env.DB.prepare(
    `SELECT s.id, s.name, s.join_code, s.owner_id,
            (SELECT COUNT(*) FROM squad_members m WHERE m.squad_id = s.id AND m.status = 'active') AS member_count,
            (SELECT COUNT(*) FROM squad_races r WHERE r.squad_id = s.id) AS race_count
     FROM squads s
     JOIN squad_members sm ON sm.squad_id = s.id AND sm.user_id = ? AND sm.status = 'active'
     WHERE s.deleted_at IS NULL
     ORDER BY sm.joined_at DESC`,
  )
    .bind(userId)
    .all<{ id: string; name: string; join_code: string; owner_id: string; member_count: number; race_count: number }>();

  return c.json({
    ok: true,
    squads: rows.results.map((r) => ({
      id: r.id,
      name: r.name,
      joinCode: r.join_code,
      isOwner: r.owner_id === userId,
      memberCount: r.member_count,
      raceCount: r.race_count,
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
    if (existing) {
      await c.env.DB.prepare("UPDATE squad_members SET status = 'active', joined_at = CURRENT_TIMESTAMP WHERE id = ?")
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
    const open = await c.env.DB.prepare(
      `SELECT r.id, r.title, r.creator_id
       FROM squad_races sr JOIN races r ON r.id = sr.race_id
       WHERE sr.squad_id = ? AND r.status = 'active' AND r.deleted_at IS NULL`,
    )
      .bind(squad.id)
      .all<{ id: string; title: string; creator_id: string }>();
    for (const race of open.results) {
      await addToRace(c, race, userId, await getProfileName(c.env.DB, race.creator_id));
    }
  }

  return c.json({ ok: true, alreadyJoined, squadId: squad.id });
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
  const notModified = conditional(
    c,
    weakEtag(
      'squad',
      squad.id,
      stamp?.members,
      stamp?.max_joined,
      stamp?.roles ? stamp.roles.length + ':' + hashString(stamp.roles) : '',
      stamp?.races,
      stamp?.max_version,
      stamp?.max_race_updated,
      stamp?.max_progress,
      stamp?.progress_sum,
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
      myRole: members.results.find((m) => m.user_id === userId)?.role ?? 'member',
      memberCount: members.results.length,
      raceCount: races.results.length,
    },
    members: members.results.map((m) => ({
      userId: m.user_id,
      displayName: m.full_name ?? (m.username ? `@${m.username}` : 'Nuvo member'),
      username: m.username,
      profilePhotoUrl: m.avatar_url,
      role: m.role,
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
        displayName: m?.full_name ?? (m?.username ? `@${m.username}` : 'Nuvo member'),
        profilePhotoUrl: m?.avatar_url ?? null,
        isYou: s.user_id === userId,
      };
    }),
  });
});

// POST /squads/:id/races { raceId } — link a race the caller created.
squadsRouter.post('/:id/races', async (c) => {
  const userId = c.get('userId');
  const squad = await getSquad(c.env.DB, c.req.param('id'));
  if (!squad || !(await isActiveMember(c.env.DB, squad.id, userId))) {
    return c.json(badRequest('Crew not found'), 404);
  }
  const myRole = await roleOf(c.env.DB, squad.id, userId);
  if (myRole !== 'owner' && myRole !== 'admin') {
    return c.json(badRequest('Only crew admins can add races'), 403);
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
  let added = 0;
  for (const m of members.results) {
    if (await addToRace(c, race, m.user_id, inviterName)) added += 1;
  }

  return c.json({ ok: true, raceId: race.id, added, memberCount: members.results.length });
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
  await c.env.DB.prepare("UPDATE squad_members SET status = 'left' WHERE squad_id = ? AND user_id = ?")
    .bind(squad.id, userId)
    .run();

  // The owner leaving hands the crew to an admin first, else the longest-standing member, or
  // retires it when nobody is left.
  if (squad.owner_id === userId) {
    const next = await c.env.DB.prepare(
      `SELECT user_id FROM squad_members WHERE squad_id = ? AND status = 'active' ORDER BY (role = 'admin') DESC, joined_at ASC LIMIT 1`,
    )
      .bind(squad.id)
      .first<{ user_id: string }>();
    if (next) {
      await c.env.DB.batch([
        c.env.DB.prepare('UPDATE squads SET owner_id = ? WHERE id = ?').bind(next.user_id, squad.id),
        c.env.DB.prepare("UPDATE squad_members SET role = 'owner' WHERE squad_id = ? AND user_id = ?").bind(
          squad.id,
          next.user_id,
        ),
      ]);
    } else {
      await c.env.DB.prepare('UPDATE squads SET deleted_at = CURRENT_TIMESTAMP WHERE id = ?')
        .bind(squad.id)
        .run();
    }
  }
  return c.json({ ok: true });
});
