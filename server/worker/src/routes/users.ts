import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { canViewFullProfile, isBlocked } from '../lib/privacy';

export const usersRouter = new Hono<AppEnv>();

usersRouter.use('*', requireAuth);

function initialsFor(displayName: string | null, username: string | null, email: string | null): string {
  const source = displayName?.trim() || username?.trim() || email?.split('@')[0] || 'N';
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return source.slice(0, 1).toUpperCase();
}

// GET /users/search?q=<query>
usersRouter.get('/search', async (c) => {
  const userId = c.get('userId');
  const q = (c.req.query('q') ?? '').trim().toLowerCase();
  if (q.length < 2) return c.json({ ok: true, users: [] });

  const like = `%${q}%`;
  const rows = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, p.full_name, p.username, p.avatar_url, p.private_profile, mp.member_id
     FROM users u
     LEFT JOIN profiles p ON p.user_id = u.id
     LEFT JOIN member_passes mp ON mp.user_id = u.id
     WHERE u.id != ?
       AND u.status = 'active'
       AND (
         LOWER(COALESCE(p.username, '')) LIKE ?
         OR LOWER(COALESCE(mp.member_id, '')) LIKE ?
         OR LOWER(COALESCE(p.full_name, '')) LIKE ?
         OR LOWER(SUBSTR(COALESCE(u.primary_email, ''), 1, INSTR(COALESCE(u.primary_email, ''), '@') - 1)) LIKE ?
       )
       AND u.id NOT IN (SELECT blocked_user_id FROM blocked_users WHERE user_id = ?)
     ORDER BY
       CASE
         WHEN LOWER(COALESCE(p.username, '')) = ? THEN 0
         WHEN LOWER(COALESCE(mp.member_id, '')) = ? THEN 1
         ELSE 2
       END,
       p.full_name COLLATE NOCASE ASC
     LIMIT 10`,
  )
    .bind(userId, like, like, like, like, userId, q, q)
    .all<{
      id: string;
      primary_email: string | null;
      full_name: string | null;
      username: string | null;
      avatar_url: string | null;
      private_profile: number;
      member_id: string | null;
    }>();

  const users = await Promise.all(
    rows.results.map(async (row) => {
      const isBlockedBy = await isBlocked(c.env.DB, row.id, userId);
      const visible = isBlockedBy ? false : await canViewFullProfile(c.env.DB, userId, row.id);
      if (visible) {
        return {
          id: row.id,
          displayName: row.full_name ?? row.username ?? 'Nuvo member',
          username: row.username,
          memberId: row.member_id,
          initials: initialsFor(row.full_name, row.username, row.primary_email),
          profilePhotoUrl: row.avatar_url,
          isPrivate: Boolean(row.private_profile),
        };
      }
      // Minimal card for private profiles.
      return {
        id: row.id,
        displayName: 'Private User',
        username: row.username,
        memberId: row.member_id,
        initials: initialsFor(row.username, row.username, null),
        profilePhotoUrl: null,
        isPrivate: true,
      };
    }),
  );

  return c.json({ ok: true, users });
});
