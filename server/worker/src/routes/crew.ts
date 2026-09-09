import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';
import { isBlocked, isProfilePrivate } from '../lib/privacy';
import { connectResult } from '../domain/crewLifecycle';
import { safeEmit } from '../domain/notifications';

async function actorName(db: D1Database, userId: string): Promise<string> {
  const row = await db
    .prepare('SELECT full_name, username FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<{ full_name: string | null; username: string | null }>();
  return row?.full_name || (row?.username ? `@${row.username}` : 'Someone');
}

export const crewRouter = new Hono<AppEnv>();

crewRouter.use('*', requireAuth);

interface CrewUserRow {
  id: string;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
  member_id: string | null;
  primary_email: string | null;
  created_at: string;
  requested_by?: string | null;
  connection_id?: string;
}

function initialsFor(displayName: string | null, username: string | null, email: string | null): string {
  const source = displayName?.trim() || username?.trim() || email?.split('@')[0] || 'N';
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return source.slice(0, 1).toUpperCase();
}

function serializeCrewUser(row: CrewUserRow) {
  return {
    id: row.id,
    displayName: row.full_name ?? row.username ?? 'Nuvo member',
    username: row.username,
    memberId: row.member_id,
    initials: initialsFor(row.full_name, row.username, row.primary_email),
    profilePhotoUrl: row.avatar_url,
    addedAt: row.created_at,
  };
}

const CREW_USER_SELECT = `
  SELECT u.id, u.primary_email, p.full_name, p.username, p.avatar_url, mp.member_id, cc.created_at,
         cc.requested_by, cc.id as connection_id
  FROM crew_connections cc
  JOIN users u ON u.id = cc.crew_user_id
  LEFT JOIN profiles p ON p.user_id = u.id
  LEFT JOIN member_passes mp ON mp.user_id = u.id
`;

async function getCrewUser(db: D1Database, userId: string, crewUserId: string) {
  return db
    .prepare(`${CREW_USER_SELECT} WHERE cc.user_id = ? AND cc.crew_user_id = ? AND cc.status = 'active'`)
    .bind(userId, crewUserId)
    .first<CrewUserRow>();
}

/**
 * Write both directional rows for a connection at once. `mine` is the caller's
 * outgoing row status; `theirs` is the other side's row. `requestedBy` is
 * recorded once and never overwritten.
 */
async function setConnection(
  db: D1Database,
  a: string,
  b: string,
  mine: string,
  theirs: string,
  requestedBy: string,
): Promise<void> {
  const rows: Array<[string, string, string]> = [
    [a, b, mine],
    [b, a, theirs],
  ];
  for (const [u, cu, status] of rows) {
    await db
      .prepare(
        `INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT(user_id, crew_user_id) DO UPDATE SET
           status = excluded.status,
           requested_by = COALESCE(crew_connections.requested_by, excluded.requested_by),
           updated_at = CURRENT_TIMESTAMP`,
      )
      .bind(generateId(), u, cu, status, requestedBy)
      .run();
  }
}

// GET /crew — active connections
crewRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `${CREW_USER_SELECT} WHERE cc.user_id = ? AND cc.status = 'active' ORDER BY cc.created_at DESC`,
  )
    .bind(userId)
    .all<CrewUserRow>();
  return c.json({ ok: true, crew: rows.results.map(serializeCrewUser) });
});

// GET /crew/requests — incoming pending requests (someone asked to connect with me)
crewRouter.get('/requests', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `${CREW_USER_SELECT}
     WHERE cc.user_id = ? AND cc.status = 'pending' AND cc.requested_by IS NOT NULL AND cc.requested_by != ?
     ORDER BY cc.updated_at DESC, cc.created_at DESC`,
  )
    .bind(userId, userId)
    .all<CrewUserRow>();
  return c.json({
    ok: true,
    requests: rows.results.map((r) => ({
      ...serializeCrewUser(r),
      requestedBy: r.requested_by,
    })),
  });
});

async function connectByUserId(c: Context<AppEnv>, crewUserId: string) {
  const userId = c.get('userId');
  if (!crewUserId) return c.json({ ok: false, error: 'userId is required' }, 400);
  if (crewUserId === userId) return c.json({ ok: false, error: 'You cannot add yourself to crew' }, 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(crewUserId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, error: 'User not found' }, 404);

  if ((await isBlocked(c.env.DB, userId, crewUserId)) || (await isBlocked(c.env.DB, crewUserId, userId))) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }

  // Already connected? no-op success.
  const existing = await c.env.DB.prepare(
    `SELECT status FROM crew_connections WHERE user_id = ? AND crew_user_id = ?`,
  )
    .bind(userId, crewUserId)
    .first<{ status: string }>();
  if (existing?.status === 'active') {
    const crewUser = await getCrewUser(c.env.DB, userId, crewUserId);
    return c.json({ ok: true, status: 'active', user: crewUser ? serializeCrewUser(crewUser) : null });
  }

  const targetPrivate = await isProfilePrivate(c.env.DB, crewUserId);
  const { mine, theirs, outcome } = connectResult(targetPrivate);
  await setConnection(c.env.DB, userId, crewUserId, mine, theirs, userId);
  if (outcome === 'pending') {
    await safeEmit(c, {
      userId: crewUserId,
      category: 'crew_request',
      actorUserId: userId,
      title: `${await actorName(c.env.DB, userId)} wants to connect`,
      dest: { type: 'profile', id: userId },
      entityType: 'crew_request',
      entityId: userId,
      dedupeKey: `crew_request:${userId}`,
    });
    return c.json({ ok: true, status: 'pending' });
  }
  const crewUser = await getCrewUser(c.env.DB, userId, crewUserId);
  return c.json({ ok: true, status: 'active', user: crewUser ? serializeCrewUser(crewUser) : null });
}

// POST /crew/add  { userId }
crewRouter.post('/add', async (c) => {
  let body: { userId?: unknown };
  try {
    body = await c.req.json<{ userId?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }
  const crewUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  return connectByUserId(c, crewUserId);
});

// POST /crew/requests/:userId/accept
crewRouter.post('/requests/:userId/accept', async (c) => {
  const userId = c.get('userId');
  const otherId = c.req.param('userId');
  const row = await c.env.DB.prepare(
    `SELECT status, requested_by FROM crew_connections WHERE user_id = ? AND crew_user_id = ?`,
  )
    .bind(userId, otherId)
    .first<{ status: string; requested_by: string | null }>();
  if (!row || row.status !== 'pending') {
    return c.json({ ok: false, error: 'No pending request from this person' }, 404);
  }
  if ((await isBlocked(c.env.DB, userId, otherId)) || (await isBlocked(c.env.DB, otherId, userId))) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }
  await setConnection(c.env.DB, userId, otherId, 'active', 'active', row.requested_by ?? otherId);
  await safeEmit(c, {
    userId: otherId,
    category: 'crew_request_accepted',
    actorUserId: userId,
    title: `${await actorName(c.env.DB, userId)} accepted your crew request`,
    dest: { type: 'profile', id: userId },
    entityType: 'crew',
    entityId: userId,
    dedupeKey: `crew_accepted:${userId}:${otherId}`,
  });
  const crewUser = await getCrewUser(c.env.DB, userId, otherId);
  return c.json({ ok: true, status: 'active', user: crewUser ? serializeCrewUser(crewUser) : null });
});

// POST /crew/requests/:userId/decline
crewRouter.post('/requests/:userId/decline', async (c) => {
  const userId = c.get('userId');
  const otherId = c.req.param('userId');
  await c.env.DB.prepare(
    `UPDATE crew_connections SET status = 'declined', updated_at = CURRENT_TIMESTAMP
     WHERE user_id IN (?, ?) AND crew_user_id IN (?, ?) AND status = 'pending'`,
  )
    .bind(userId, otherId, userId, otherId)
    .run();
  return c.json({ ok: true });
});

// DELETE /crew/:userId — remove a connection (either side)
crewRouter.delete('/:userId', async (c) => {
  const userId = c.get('userId');
  const crewUserId = c.req.param('userId');
  await c.env.DB.prepare(
    `UPDATE crew_connections SET status = 'removed', updated_at = CURRENT_TIMESTAMP
     WHERE (user_id = ? AND crew_user_id = ?) OR (user_id = ? AND crew_user_id = ?)`,
  )
    .bind(userId, crewUserId, crewUserId, userId)
    .run();
  return c.json({ ok: true });
});
