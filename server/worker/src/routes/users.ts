import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { canViewFullProfile, isBlocked } from '../lib/privacy';
import { canSeeIdentity, crewConnectionStatus } from '../domain/crewLifecycle';
import { publicLevelFor } from '../domain/progression';

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
    `SELECT u.id, u.primary_email, p.full_name, p.username, p.avatar_url, p.private_profile, mp.member_id,
            cc.status AS conn_status, cc.requested_by AS conn_requested_by
     FROM users u
     LEFT JOIN profiles p ON p.user_id = u.id
     LEFT JOIN member_passes mp ON mp.user_id = u.id
     -- The join covers both directions so a legacy asymmetric row still
     -- reports a status; requested_by is viewer-agnostic.
     LEFT JOIN crew_connections cc
       ON (cc.user_id = ? AND cc.crew_user_id = u.id)
        OR (cc.user_id = u.id AND cc.crew_user_id = ?)
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
    .bind(userId, userId, userId, like, like, like, like, userId, q, q)
    .all<{
      id: string;
      primary_email: string | null;
      full_name: string | null;
      username: string | null;
      avatar_url: string | null;
      private_profile: number;
      member_id: string | null;
      conn_status: string | null;
      conn_requested_by: string | null;
    }>();

  const users = await Promise.all(
    rows.results.map(async (row) => {
      const isBlockedBy = await isBlocked(c.env.DB, row.id, userId);
      const visible = isBlockedBy ? false : await canViewFullProfile(c.env.DB, userId, row.id);
      // Mutual crew — the "why is this person suggested" context. One small
      // aggregate per row; the result set is already capped at 10.
      const mutual = await c.env.DB
        .prepare(
          `SELECT COUNT(*) AS n FROM crew_connections mine
           JOIN crew_connections theirs ON theirs.crew_user_id = mine.crew_user_id
           WHERE mine.user_id = ? AND theirs.user_id = ?
             AND mine.status = 'active' AND theirs.status = 'active'`,
        )
        .bind(userId, row.id)
        .first<{ n: number }>();
      const mutualCount = mutual?.n ?? 0;
      // Additive field — older clients ignore it and fall back to 'none'.
      const connectionStatus = crewConnectionStatus(
        userId,
        row.id,
        row.conn_status == null
          ? null
          : { status: row.conn_status, requested_by: row.conn_requested_by },
      );
      if (visible) {
        return {
          id: row.id,
          displayName: row.full_name ?? row.username ?? 'Nuvo member',
          username: row.username,
          memberId: row.member_id,
          initials: initialsFor(row.full_name, row.username, row.primary_email),
          profilePhotoUrl: row.avatar_url,
          isPrivate: Boolean(row.private_profile),
          connectionStatus,
          mutualCount,
        };
      }
      // Minimal card for a private profile with no shared context: their
      // handle (how you found them) but no real name / photo. Never a dead
      // "Private User" string when there's a username to show.
      return {
        id: row.id,
        displayName: row.username ? `@${row.username}` : 'Private profile',
        username: row.username,
        memberId: row.member_id,
        initials: initialsFor(row.username, row.username, null),
        profilePhotoUrl: null,
        isPrivate: true,
        connectionStatus,
        mutualCount,
      };
    }),
  );

  return c.json({ ok: true, users });
});

// GET /users/:id — a single public profile card + this viewer's connection state.
usersRouter.get('/:id', async (c) => {
  const viewerId = c.get('userId');
  const targetId = c.req.param('id');

  const row = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, u.last_active_at, p.full_name, p.username, p.avatar_url, p.private_profile, mp.member_id
     FROM users u
     LEFT JOIN profiles p ON p.user_id = u.id
     LEFT JOIN member_passes mp ON mp.user_id = u.id
     WHERE u.id = ? AND u.status = 'active'`,
  )
    .bind(targetId)
    .first<{
      id: string;
      primary_email: string | null;
      last_active_at: string | null;
      full_name: string | null;
      username: string | null;
      avatar_url: string | null;
      private_profile: number;
      member_id: string | null;
    }>();
  if (!row) return c.json({ ok: false, error: 'User not found' }, 404);

  const blockedEitherWay =
    (await isBlocked(c.env.DB, viewerId, targetId)) ||
    (await isBlocked(c.env.DB, targetId, viewerId));
  if (blockedEitherWay) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }

  // Connection state from the viewer's outgoing row.
  const conn = await c.env.DB.prepare(
    `SELECT status, requested_by FROM crew_connections WHERE user_id = ? AND crew_user_id = ?`,
  )
    .bind(viewerId, targetId)
    .first<{ status: string; requested_by: string | null }>();
  const connectionStatus = crewConnectionStatus(viewerId, targetId, conn);
  const canSee = canSeeIdentity(
    viewerId,
    targetId,
    Boolean(row.private_profile),
    connectionStatus,
  );

  // Nuvo Level is part of a member's competitive identity — it follows the
  // same visibility rule as the name/photo.
  const level = canSee ? await publicLevelFor(c.env.DB, targetId) : null;

  return c.json({
    ok: true,
    user: {
      id: row.id,
      displayName: canSee
        ? row.full_name ?? row.username ?? 'Nuvo member'
        : row.username
          ? `@${row.username}`
          : 'Private profile',
      username: row.username,
      memberId: row.member_id,
      initials: initialsFor(
        canSee ? row.full_name : row.username,
        row.username,
        row.primary_email,
      ),
      profilePhotoUrl: canSee ? row.avatar_url : null,
      isPrivate: Boolean(row.private_profile),
      connectionStatus,
      level,
      // Presence is a crew signal — the client only renders it for connected
      // people, matching the crew-list rule (strangers don't get a readout).
      lastActiveAt:
        connectionStatus === 'connected' ? row.last_active_at : null,
    },
  });
});
