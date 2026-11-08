import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { muteTarget, unmuteTarget } from '../domain/mutes';

export const mutesRouter = new Hono<AppEnv>();

mutesRouter.use('*', requireAuth);

function initialsFor(displayName: string | null, username: string | null, email: string | null): string {
  const source = displayName?.trim() || username?.trim() || email?.split('@')[0] || 'N';
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return source.slice(0, 1).toUpperCase();
}

// POST /mutes/users/:id — mute a person. Invisible to them: no notification,
// no state they can read. Idempotent — muting twice is still one mute.
mutesRouter.post('/users/:id', async (c) => {
  const userId = c.get('userId');
  const targetId = c.req.param('id');
  if (userId === targetId) return c.json({ ok: false, error: 'Cannot mute yourself' }, 400);
  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(targetId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, error: 'User not found' }, 404);
  await muteTarget(c.env.DB, userId, 'user', targetId);
  return c.json({ ok: true, muted: true });
});

// DELETE /mutes/users/:id — unmute; also idempotent (not muted → still ok).
mutesRouter.delete('/users/:id', async (c) => {
  const userId = c.get('userId');
  const targetId = c.req.param('id');
  await unmuteTarget(c.env.DB, userId, 'user', targetId);
  return c.json({ ok: true, muted: false });
});

// POST /mutes/crews/:id — mute a crew group's activity in the feed.
mutesRouter.post('/crews/:id', async (c) => {
  const userId = c.get('userId');
  const squadId = c.req.param('id');
  const squad = await c.env.DB.prepare('SELECT id FROM squads WHERE id = ? AND deleted_at IS NULL')
    .bind(squadId)
    .first<{ id: string }>();
  if (!squad) return c.json({ ok: false, error: 'Crew not found' }, 404);
  await muteTarget(c.env.DB, userId, 'crew', squadId);
  return c.json({ ok: true, muted: true });
});

// DELETE /mutes/crews/:id
mutesRouter.delete('/crews/:id', async (c) => {
  const userId = c.get('userId');
  await unmuteTarget(c.env.DB, userId, 'crew', c.req.param('id'));
  return c.json({ ok: true, muted: false });
});

// GET /mutes — the viewer's mute list. Mutes are private by definition, so
// this route only ever shows the caller's own rows.
mutesRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const [users, crews] = await Promise.all([
    c.env.DB.prepare(
      `SELECT u.id, p.full_name, p.username, p.avatar_url, u.primary_email, mp.member_id, um.created_at
         FROM user_mutes um
         JOIN users u ON u.id = um.target_id
         LEFT JOIN profiles p ON p.user_id = u.id
         LEFT JOIN member_passes mp ON mp.user_id = u.id
        WHERE um.user_id = ? AND um.target_type = 'user'
        ORDER BY um.created_at DESC`,
    )
      .bind(userId)
      .all<{
        id: string;
        full_name: string | null;
        username: string | null;
        avatar_url: string | null;
        primary_email: string | null;
        member_id: string | null;
        created_at: string;
      }>(),
    c.env.DB.prepare(
      `SELECT s.id, s.name, um.created_at,
              (SELECT COUNT(*) FROM squad_members sm WHERE sm.squad_id = s.id AND sm.status = 'active') AS members
         FROM user_mutes um
         JOIN squads s ON s.id = um.target_id
        WHERE um.user_id = ? AND um.target_type = 'crew' AND s.deleted_at IS NULL
        ORDER BY um.created_at DESC`,
    )
      .bind(userId)
      .all<{ id: string; name: string; created_at: string; members: number }>(),
  ]);

  return c.json({
    ok: true,
    users: users.results.map((r) => ({
      id: r.id,
      displayName: r.full_name ?? r.username ?? 'Nuvo member',
      username: r.username,
      memberId: r.member_id,
      initials: initialsFor(r.full_name, r.username, r.primary_email),
      profilePhotoUrl: r.avatar_url,
      mutedAt: r.created_at,
    })),
    crews: crews.results.map((r) => ({
      id: r.id,
      name: r.name,
      memberCount: r.members,
      mutedAt: r.created_at,
    })),
  });
});
