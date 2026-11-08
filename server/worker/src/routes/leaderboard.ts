import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { conditional, stalenessBucket, weakEtag } from '../lib/etag';

export const leaderboardRouter = new Hono<AppEnv>();

leaderboardRouter.use('*', requireAuth);

interface LeaderboardRow {
  id: string;
  points: number;
  rank: number;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
}

// People-block filter shared by both scopes: anyone blocked with the viewer
// in either direction drops out of the ranking entirely — they neither get a
// row nor occupy a rank position (a block removes the person from every
// social surface — see lib/privacy.ts). The viewer can never block themself,
// so this never removes the viewer's row.
const BLOCK_EXCLUDE = `
  AND p.id NOT IN (SELECT blocked_user_id FROM blocked_users WHERE user_id = ?1)
  AND p.id NOT IN (SELECT user_id FROM blocked_users WHERE blocked_user_id = ?1)`;

/**
 * GET /leaderboard?scope=friends|global — the Compete weekly leaderboard.
 *
 * points = the sum of a person's `value` on verified move_logs across every
 * non-deleted race, restricted to the last 7 days — i.e. "total verified
 * proof value this week". Pending, rejected and removed proofs never count.
 *
 * rank = competition rank (1 + number of people with strictly more points),
 * so equal points share a rank — the same convention race leaderboards use
 * (domain/raceRanking.ts). The viewer is always present, even on 0 points.
 */
leaderboardRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const scope = c.req.query('scope') === 'global' ? 'global' : 'friends';

  // 'friends' = the viewer + their active crew_connections (both directions,
  // so legacy asymmetric rows still count). 'global' = every active user.
  // The correlated rank subquery mirrors computeCompetitionRanks' "strictly
  // ahead" rule. A rank cap keeps the payload bounded; the viewer's row is
  // unioned in regardless of where they stand.
  const peopleSql =
    scope === 'global'
      ? `SELECT id FROM users WHERE status = 'active'`
      : `SELECT ?1 AS id
         UNION
         SELECT crew_user_id FROM crew_connections WHERE user_id = ?1 AND status = 'active'
         UNION
         SELECT user_id FROM crew_connections WHERE crew_user_id = ?1 AND status = 'active'`;

  const rankCap = scope === 'global' ? 50 : 200;
  const rows = await c.env.DB.prepare(
    `WITH people AS (${peopleSql}),
     scores AS (
       SELECT p.id, COALESCE(SUM(ml.value), 0) AS points
       FROM people p
       LEFT JOIN move_logs ml ON ml.user_id = p.id
         AND ml.status = 'verified'
         AND ml.created_at >= datetime('now', '-7 days')
         AND ml.race_id IN (SELECT id FROM races WHERE deleted_at IS NULL)
       WHERE 1 = 1 ${BLOCK_EXCLUDE}
       GROUP BY p.id
     ),
     ranked AS (
       SELECT s.id, s.points,
              (SELECT COUNT(*) FROM scores s2 WHERE s2.points > s.points) + 1 AS rank
       FROM scores s
     )
     SELECT r.id, r.points, r.rank, pr.full_name, pr.username, pr.avatar_url
     FROM ranked r
     LEFT JOIN profiles pr ON pr.user_id = r.id
     WHERE r.rank <= ?2 OR r.id = ?1
     ORDER BY r.rank ASC, r.id ASC`,
  )
    .bind(userId, rankCap)
    .all<LeaderboardRow>();

  const lbRows = rows.results.map((r) => ({
    userId: r.id,
    displayName: r.full_name ?? r.username ?? 'Nuvo member',
    profilePhotoUrl: r.avatar_url,
    points: r.points,
    rank: r.rank,
    isMe: r.id === userId,
  }));

  const nm = conditional(
    c,
    weakEtag(
      'leaderboard',
      userId,
      scope,
      lbRows.map((r) => `${r.userId}:${r.points}:${r.rank}`).join(','),
      // names/photos aren't covered by the points signature
      stalenessBucket(Date.now(), 60_000),
    ),
  );
  if (nm) return nm;

  return c.json({ ok: true, scope, periodDays: 7, rows: lbRows });
});
