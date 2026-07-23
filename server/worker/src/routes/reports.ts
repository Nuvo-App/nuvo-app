import { Hono } from 'hono';
import type { AppEnv, ReportRow } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';

export const reportsRouter = new Hono<AppEnv>();
reportsRouter.use('*', requireAuth);

function initialsFor(displayName: string | null, username: string | null, email: string | null): string {
  const source = displayName?.trim() || username?.trim() || email?.split('@')[0] || 'N';
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return source.slice(0, 1).toUpperCase();
}

function serializeBlockedUser(row: {
  id: string;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
  primary_email: string | null;
  member_id: string | null;
}) {
  return {
    id: row.id,
    displayName: row.full_name ?? row.username ?? 'Nuvo member',
    username: row.username,
    memberId: row.member_id,
    initials: initialsFor(row.full_name, row.username, row.primary_email),
    profilePhotoUrl: row.avatar_url,
  };
}

// POST /reports/users/:id
reportsRouter.post('/users/:id', async (c) => {
  const reporterUserId = c.get('userId');
  const targetId = c.req.param('id');
  let body: { reason?: unknown };
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body' }, 400); }
  const reason = typeof body.reason === 'string' ? body.reason.trim() : null;

  if (reporterUserId === targetId) return c.json({ ok: false, error: 'Cannot report yourself' }, 400);

  await c.env.DB.prepare(
    `INSERT INTO reports (id, reporter_user_id, target_type, target_id, reason, status, created_at, updated_at)
     VALUES (?, ?, 'user', ?, ?, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
  ).bind(generateId(), reporterUserId, targetId, reason).run();

  return c.json({ ok: true });
});

// POST /reports/races/:id
reportsRouter.post('/races/:id', async (c) => {
  const reporterUserId = c.get('userId');
  const targetId = c.req.param('id');
  let body: { reason?: unknown };
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body' }, 400); }
  const reason = typeof body.reason === 'string' ? body.reason.trim() : null;

  await c.env.DB.prepare(
    `INSERT INTO reports (id, reporter_user_id, target_type, target_id, reason, status, created_at, updated_at)
     VALUES (?, ?, 'race', ?, ?, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
  ).bind(generateId(), reporterUserId, targetId, reason).run();

  return c.json({ ok: true });
});

// POST /reports/content/:id  (move log / proof id)
reportsRouter.post('/content/:id', async (c) => {
  const reporterUserId = c.get('userId');
  const targetId = c.req.param('id');
  let body: { reason?: unknown };
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body' }, 400); }
  const reason = typeof body.reason === 'string' ? body.reason.trim() : null;

  await c.env.DB.prepare(
    `INSERT INTO reports (id, reporter_user_id, target_type, target_id, reason, status, created_at, updated_at)
     VALUES (?, ?, 'content', ?, ?, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
  ).bind(generateId(), reporterUserId, targetId, reason).run();

  return c.json({ ok: true });
});

// POST /blocks/:id
reportsRouter.post('/blocks/:id', async (c) => {
  const userId = c.get('userId');
  const blockedUserId = c.req.param('id');
  if (userId === blockedUserId) return c.json({ ok: false, error: 'Cannot block yourself' }, 400);

  await c.env.DB.prepare(
    `INSERT INTO blocked_users (id, user_id, blocked_user_id, created_at)
     VALUES (?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, blocked_user_id) DO NOTHING`,
  ).bind(generateId(), userId, blockedUserId).run();

  return c.json({ ok: true });
});

// DELETE /blocks/:id
reportsRouter.delete('/blocks/:id', async (c) => {
  const userId = c.get('userId');
  const blockedUserId = c.req.param('id');
  await c.env.DB.prepare('DELETE FROM blocked_users WHERE user_id = ? AND blocked_user_id = ?')
    .bind(userId, blockedUserId).run();
  return c.json({ ok: true });
});

// GET /blocks
reportsRouter.get('/blocks', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `SELECT u.id, p.full_name, p.username, p.avatar_url, u.primary_email, mp.member_id
     FROM blocked_users bu
     JOIN users u ON u.id = bu.blocked_user_id
     LEFT JOIN profiles p ON p.user_id = u.id
     LEFT JOIN member_passes mp ON mp.user_id = u.id
     WHERE bu.user_id = ?
     ORDER BY bu.created_at DESC`,
  )
    .bind(userId)
    .all<{ id: string; full_name: string | null; username: string | null; avatar_url: string | null; primary_email: string | null; member_id: string | null }>();

  return c.json({ ok: true, blocked: rows.results.map(serializeBlockedUser) });
});

// GET /admin/reports  (internal moderation review; role-based auth should be added in production)
reportsRouter.get('/admin/reports', async (c) => {
  const rows = await c.env.DB.prepare(
    `SELECT r.*, reporter.full_name as reporter_name, reporter.username as reporter_username
     FROM reports r
     LEFT JOIN profiles reporter ON reporter.user_id = r.reporter_user_id
     ORDER BY
       CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,
       r.created_at DESC
     LIMIT 100`,
  ).all<ReportRow & { reporter_name: string | null; reporter_username: string | null }>();

  return c.json({
    ok: true,
    reports: rows.results.map((row) => ({
      id: row.id,
      reporterUserId: row.reporter_user_id,
      reporterDisplayName: row.reporter_name ?? row.reporter_username ?? 'Nuvo member',
      targetType: row.target_type,
      targetId: row.target_id,
      reason: row.reason,
      status: row.status,
      reviewedBy: row.reviewed_by,
      notes: row.notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })),
  });
});

// POST /admin/reports/:id
reportsRouter.post('/admin/reports/:id', async (c) => {
  const userId = c.get('userId');
  const reportId = c.req.param('id');
  let body: { status?: unknown; notes?: unknown };
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body' }, 400); }

  const status = typeof body.status === 'string' ? body.status : null;
  const notes = typeof body.notes === 'string' ? body.notes.trim() : null;
  if (!status) return c.json({ ok: false, error: 'status is required' }, 400);

  await c.env.DB.prepare(
    `UPDATE reports SET status = ?, notes = ?, reviewed_by = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?`,
  ).bind(status, notes, userId, reportId).run();

  return c.json({ ok: true });
});
