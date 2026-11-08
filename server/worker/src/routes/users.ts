import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { canViewFullProfile, isBlocked } from '../lib/privacy';
import { canSeeIdentity, crewConnectionStatus } from '../domain/crewLifecycle';
import { publicLevelFor, publicProfileProgressionFor } from '../domain/progression';
import { readProfileRecord } from '../domain/profileRecord';
import { readProfilePrefs } from '../domain/profilePrefs';
import { activityDays, dayStreaksFor, proofsInWindow, tzShift } from '../domain/dayStreak';
import { isUserMuted } from '../domain/mutes';
import {
  daysSince,
  friendshipBadges,
  pairReactionsFor,
  racesTogetherFor,
} from '../domain/friendship';

export const usersRouter = new Hono<AppEnv>();

usersRouter.use('*', requireAuth);

function initialsFor(displayName: string | null, username: string | null, email: string | null): string {
  const source = displayName?.trim() || username?.trim() || email?.split('@')[0] || 'N';
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
  return source.slice(0, 1).toUpperCase();
}

/** One side of the "vs you" scoreboard — same definition for viewer and
 *  target so the rows are always comparable. */
async function versusStats(db: D1Database, userId: string, tz: number) {
  const [level, record, streaks, proofs] = await Promise.all([
    publicLevelFor(db, userId),
    readProfileRecord(db, userId),
    dayStreaksFor(db, userId, tz),
    proofsInWindow(db, userId, tz, 7),
  ]);
  return {
    level,
    wins: record.wins,
    winRatePercent: record.winRatePercent,
    bestStreakDays: streaks.bestStreakDays,
    proofsThisWeek: proofs,
  };
}

/** Mutual friends of viewer + target: count plus up to 3 preview cards. */
async function mutualFor(db: D1Database, viewerId: string, targetId: string) {
  const [count, preview] = await Promise.all([
    db
      .prepare(
        `SELECT COUNT(*) AS n FROM crew_connections mine
         JOIN crew_connections theirs ON theirs.crew_user_id = mine.crew_user_id
         WHERE mine.user_id = ? AND theirs.user_id = ?
           AND mine.status = 'active' AND theirs.status = 'active'`,
      )
      .bind(viewerId, targetId)
      .first<{ n: number }>(),
    db
      .prepare(
        `SELECT u.id, p.full_name, p.username, p.avatar_url
         FROM crew_connections mine
         JOIN crew_connections theirs
           ON theirs.crew_user_id = mine.crew_user_id AND theirs.user_id = ? AND theirs.status = 'active'
         JOIN users u ON u.id = mine.crew_user_id AND u.status = 'active'
         LEFT JOIN profiles p ON p.user_id = u.id
         WHERE mine.user_id = ? AND mine.status = 'active'
         ORDER BY p.full_name COLLATE NOCASE ASC
         LIMIT 3`,
      )
      .bind(targetId, viewerId)
      .all<{ id: string; full_name: string | null; username: string | null; avatar_url: string | null }>(),
  ]);
  return {
    count: count?.n ?? 0,
    preview: preview.results.map((r) => ({
      id: r.id,
      displayName: r.full_name ?? r.username ?? 'Nuvo member',
      profilePhotoUrl: r.avatar_url,
    })),
  };
}

/** Achievement catalog rows the target hasn't earned — metadata only, never
 *  their progress (locked progress stays self-only by design). */
async function lockedAchievementsFor(db: D1Database, targetId: string) {
  const rows = await db
    .prepare(
      `SELECT d.unlock_key, d.name, d.icon_key, d.category
         FROM unlock_definitions d
        WHERE d.active = 1 AND d.unlock_type = 'achievement'
          AND d.id NOT IN (SELECT unlock_id FROM user_unlocks WHERE user_id = ?)
        ORDER BY d.sort_order ASC, d.unlock_key ASC`,
    )
    .bind(targetId)
    .all<{ unlock_key: string; name: string; icon_key: string | null; category: string | null }>();
  return rows.results.map((d) => ({
    key: d.unlock_key,
    name: d.name,
    iconKey: d.icon_key,
    category: d.category,
  }));
}

// GET /users/search?q=<query>
usersRouter.get('/search', async (c) => {
  const userId = c.get('userId');
  const q = (c.req.query('q') ?? '').trim().toLowerCase();
  if (q.length < 2) return c.json({ ok: true, users: [] });

  const like = `%${q}%`;
  const rows = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, p.full_name, p.username, p.avatar_url, mp.member_id,
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
          isPrivate: false, // legacy key for older app builds
          connectionStatus,
          mutualCount,
        };
      }
      // Minimal card for a blocked-relationship row: their handle but no
      // real name / photo.
      return {
        id: row.id,
        displayName: row.username ? `@${row.username}` : 'Private profile',
        username: row.username,
        memberId: row.member_id,
        initials: initialsFor(row.username, row.username, null),
        profilePhotoUrl: null,
        isPrivate: false,
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
  const { tz } = tzShift(c.req.query('tz'));

  const row = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, u.last_active_at, p.full_name, p.username, p.avatar_url, mp.member_id
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
    `SELECT status, requested_by, created_at FROM crew_connections WHERE user_id = ? AND crew_user_id = ?`,
  )
    .bind(viewerId, targetId)
    .first<{ status: string; requested_by: string | null; created_at: string }>();
  const connectionStatus = crewConnectionStatus(viewerId, targetId, conn);
  const canSee = canSeeIdentity(viewerId, targetId, false, connectionStatus);

  // Nuvo Level + achievements + racing context are part of a member's
  // competitive identity — they follow the same visibility rule as the
  // name/photo. The bundle is read-only: viewing a profile never reconciles
  // the target's progression.
  const self = viewerId === targetId;
  const connected = !self && connectionStatus === 'connected';
  const [identity, prefs, friendsRow, lockedAchievements, muted, mutual, versus, friendship] =
    await Promise.all([
      canSee ? publicProfileProgressionFor(c.env.DB, viewerId, targetId) : Promise.resolve(null),
      readProfilePrefs(c.env.DB, targetId),
      c.env.DB.prepare(
        "SELECT COUNT(*) AS n FROM crew_connections WHERE user_id = ? AND status = 'active'",
      )
        .bind(targetId)
        .first<{ n: number }>(),
      canSee ? lockedAchievementsFor(c.env.DB, targetId) : Promise.resolve(null),
      self ? Promise.resolve(false) : isUserMuted(c.env.DB, viewerId, targetId),
      self ? Promise.resolve(null) : mutualFor(c.env.DB, viewerId, targetId),
      self
        ? Promise.resolve(null)
        : Promise.all([
            versusStats(c.env.DB, viewerId, tz),
            versusStats(c.env.DB, targetId, tz),
          ]).then(([you, them]) => ({ you, them })),
      connected
        ? Promise.all([
            racesTogetherFor(c.env.DB, viewerId, targetId),
            pairReactionsFor(c.env.DB, viewerId, targetId),
            dayStreaksFor(c.env.DB, viewerId, tz),
            dayStreaksFor(c.env.DB, targetId, tz),
          ]).then(([racesTogether, pairReactions, streakYou, streakThem]) => ({
            connectedSince: conn!.created_at,
            badges: friendshipBadges({
              racesTogether,
              pairReactions,
              daysConnected: daysSince(conn!.created_at),
              streakYou: streakYou.streakDays,
              streakThem: streakThem.streakDays,
            }),
          }))
        : Promise.resolve(null),
    ]);

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
      isPrivate: false, // legacy key for older app builds
      connectionStatus,
      level: identity?.level ?? null,
      levelProgress: identity?.levelProgress ?? null,
      achievementsEarned: identity?.achievementsEarned ?? null,
      achievementsTotal: identity?.achievementsTotal ?? null,
      featuredAchievements: identity?.featured ?? null,
      earnedAchievements: identity?.earned ?? null,
      raceStats: identity?.stats ?? null,
      racesWithYou: identity?.racesWithYou ?? null,
      // Presence is a crew signal — the client only renders it for connected
      // people, matching the crew-list rule (strangers don't get a readout).
      lastActiveAt:
        connectionStatus === 'connected' ? row.last_active_at : null,
      // v13 additive keys (migration 0048). Older clients ignore them.
      bio: canSee ? prefs.bio : null,
      favoriteMovementKey: canSee ? prefs.favoriteMovementKey : null,
      friendsCount: friendsRow?.n ?? 0,
      mutual,
      versus,
      friendship,
      lockedAchievements,
      muted,
      activityShared: prefs.activityMapShared,
    },
  });
});

// GET /users/:id/activity?days&tz — another member's activity map. Same shape
// as GET /profile/activity, gated by their "show my activity map" pref; blocks
// still win outright in either direction.
usersRouter.get('/:id/activity', async (c) => {
  const viewerId = c.get('userId');
  const targetId = c.req.param('id');
  const days = activityDays(c.req.query('days'));
  const { shift } = tzShift(c.req.query('tz'));

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(targetId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, error: 'User not found' }, 404);

  const blockedEitherWay =
    (await isBlocked(c.env.DB, viewerId, targetId)) ||
    (await isBlocked(c.env.DB, targetId, viewerId));
  if (blockedEitherWay) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }

  const prefs = await readProfilePrefs(c.env.DB, targetId);
  c.header('Cache-Control', 'private, max-age=60');
  c.header('Vary', 'Authorization');
  if (!prefs.activityMapShared) {
    return c.json({ ok: true, shared: false, days: [] });
  }

  const { results } = await c.env.DB.prepare(
    `SELECT date(created_at, ?) AS day, COUNT(*) AS proofs
       FROM move_logs
      WHERE user_id = ? AND status = 'verified'
        AND created_at >= datetime('now', ?)
      GROUP BY day
      ORDER BY day`,
  )
    .bind(shift, targetId, `-${days} days`)
    .all<{ day: string; proofs: number }>();
  return c.json({
    ok: true,
    shared: true,
    days: (results ?? []).map((r) => ({ date: r.day, proofs: r.proofs })),
  });
});
