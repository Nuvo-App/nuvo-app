import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';

export const crewRouter = new Hono<AppEnv>();

crewRouter.use('*', requireAuth);

interface CrewUserRow {
  id: string;
  full_name: string | null;
  username: string | null;
  member_id: string | null;
  primary_email: string | null;
  created_at: string;
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
    addedAt: row.created_at,
  };
}

async function getCrewUser(db: D1Database, userId: string, crewUserId: string) {
  return db
    .prepare(
      `SELECT u.id, u.primary_email, p.full_name, p.username, mp.member_id, cc.created_at
       FROM crew_connections cc
       JOIN users u ON u.id = cc.crew_user_id
       LEFT JOIN profiles p ON p.user_id = u.id
       LEFT JOIN member_passes mp ON mp.user_id = u.id
       WHERE cc.user_id = ? AND cc.crew_user_id = ? AND cc.status = 'active'`,
    )
    .bind(userId, crewUserId)
    .first<CrewUserRow>();
}

// GET /crew
crewRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, p.full_name, p.username, mp.member_id, cc.created_at
     FROM crew_connections cc
     JOIN users u ON u.id = cc.crew_user_id
     LEFT JOIN profiles p ON p.user_id = u.id
     LEFT JOIN member_passes mp ON mp.user_id = u.id
     WHERE cc.user_id = ? AND cc.status = 'active'
     ORDER BY cc.created_at DESC`,
  )
    .bind(userId)
    .all<CrewUserRow>();

  return c.json({ ok: true, crew: rows.results.map(serializeCrewUser) });
});

// POST /crew/add
crewRouter.post('/add', async (c) => {
  const userId = c.get('userId');
  let body: { userId?: unknown };
  try {
    body = await c.req.json<{ userId?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const crewUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!crewUserId) return c.json({ ok: false, error: 'userId is required' }, 400);
  if (crewUserId === userId) return c.json({ ok: false, error: 'You cannot add yourself to crew' }, 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(crewUserId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, error: 'User not found' }, 404);

  await c.env.DB.prepare(
    `INSERT INTO crew_connections (id, user_id, crew_user_id, status, created_at)
     VALUES (?, ?, ?, 'active', CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, crew_user_id) DO UPDATE SET status = 'active'`,
  )
    .bind(generateId(), userId, crewUserId)
    .run();

  // Demo-friendly mutual connection, while preserving one-way semantics if this fails later.
  await c.env.DB.prepare(
    `INSERT INTO crew_connections (id, user_id, crew_user_id, status, created_at)
     VALUES (?, ?, ?, 'active', CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, crew_user_id) DO UPDATE SET status = 'active'`,
  )
    .bind(generateId(), crewUserId, userId)
    .run();

  const crewUser = await getCrewUser(c.env.DB, userId, crewUserId);
  return c.json({ ok: true, user: crewUser ? serializeCrewUser(crewUser) : null });
});

// DELETE /crew/:userId
crewRouter.delete('/:userId', async (c) => {
  const userId = c.get('userId');
  const crewUserId = c.req.param('userId');
  await c.env.DB.prepare(
    `UPDATE crew_connections
     SET status = 'removed'
     WHERE user_id = ? AND crew_user_id = ?`,
  )
    .bind(userId, crewUserId)
    .run();
  return c.json({ ok: true });
});
