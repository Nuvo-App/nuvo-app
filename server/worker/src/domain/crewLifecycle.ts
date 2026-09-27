import { generateId } from '../lib/crypto';

/**
 * Shared crew lifecycle for search, member pass, profile and invite entry.
 *
 *   none              no row, or a removed/declined row
 *   connected         both directional rows are 'active' (or self)
 *   pending_outgoing  a 'pending' row this viewer created
 *   pending_incoming  a 'pending' row the other person created
 */
export type CrewConnectionStatus =
  | 'none'
  | 'connected'
  | 'pending_outgoing'
  | 'pending_incoming';

export function crewConnectionStatus(
  viewerId: string,
  targetId: string,
  row: { status: string; requested_by: string | null } | null | undefined,
): CrewConnectionStatus {
  if (viewerId === targetId) return 'connected';
  if (!row) return 'none';
  if (row.status === 'active') return 'connected';
  if (row.status === 'pending') {
    return row.requested_by === viewerId ? 'pending_outgoing' : 'pending_incoming';
  }
  return 'none'; // removed | declined
}

export interface CrewTransition {
  id: string;
  status: string;
  requested_by: string | null;
  notificationIds: string[];
}

/**
 * D1 batches are transactions. Resolve the previous pair INSIDE the write,
 * then mirror the canonical (lexically first) direction in that same batch.
 * Concurrent adds cannot overwrite an acceptance with a stale pending state.
 * The canonical id identifies one connection cycle; a removed/declined pair
 * receives a new id so another real request can produce another notification.
 */
export async function transitionCrew(
  db: D1Database,
  actorId: string,
  targetId: string,
  action: 'connect' | 'accept' | 'decline' | 'remove',
): Promise<CrewTransition | null> {
  if (actorId === targetId) return null;
  const [a, b] = [actorId, targetId].sort();
  const allowed = action === 'connect' || action === 'remove'
    ? '1 = 1'
    : action === 'accept'
      ? "(previous.status = 'active' OR (previous.status = 'pending' AND previous.requested_by = ?))"
      : "(previous.status = 'declined' OR (previous.status = 'pending' AND previous.requested_by = ?))";
  const status = action === 'connect'
    ? `CASE WHEN previous.status = 'active' THEN 'active'
            WHEN previous.status = 'pending' AND previous.requested_by = ? THEN 'active'
            WHEN previous.status = 'pending' THEN 'pending'
            WHEN COALESCE((SELECT private_profile FROM profiles WHERE user_id = ?), 0) = 1 THEN 'pending'
            ELSE 'active' END`
    : `'${action === 'accept' ? 'active' : action === 'decline' ? 'declined' : 'removed'}'`;
  const canonical = db.prepare(`
    WITH previous AS (
      SELECT * FROM crew_connections
      WHERE (user_id = ? AND crew_user_id = ?) OR (user_id = ? AND crew_user_id = ?)
      ORDER BY CASE status WHEN 'active' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
               created_at, user_id
      LIMIT 1
    )
    INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
    SELECT
      CASE WHEN previous.user_id = ? AND previous.status IN ('active', 'pending') THEN previous.id ELSE ? END,
      ?, ?, ${status},
      CASE WHEN previous.status IN ('active', 'pending') THEN COALESCE(previous.requested_by, ?) ELSE ? END,
      CASE WHEN previous.status IN ('active', 'pending') THEN previous.created_at ELSE CURRENT_TIMESTAMP END,
      CURRENT_TIMESTAMP
    FROM (SELECT 1) LEFT JOIN previous ON 1 = 1
    WHERE ${allowed}
      AND EXISTS (SELECT 1 FROM users WHERE id = ? AND status = 'active')
      AND EXISTS (SELECT 1 FROM users WHERE id = ? AND status = 'active')
      ${action === 'remove' ? '' : `AND NOT EXISTS (SELECT 1 FROM blocked_users
        WHERE (user_id = ? AND blocked_user_id = ?) OR (user_id = ? AND blocked_user_id = ?))`}
    ON CONFLICT(user_id, crew_user_id) DO UPDATE SET
      id = excluded.id, status = excluded.status, requested_by = excluded.requested_by,
      created_at = excluded.created_at, updated_at = excluded.updated_at
  `).bind(
    a, b, b, a, a, generateId(), a, b,
    ...(action === 'connect' ? [targetId, targetId] : []),
    actorId, actorId,
    ...(action === 'accept' || action === 'decline' ? [targetId] : []),
    actorId, targetId,
    ...(action === 'remove' ? [] : [a, b, b, a]),
  );
  const expected = action === 'accept' ? "AND status = 'active'"
    : action === 'decline' ? "AND status = 'declined'" : '';
  const mirror = db.prepare(`
    INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
    SELECT ?, crew_user_id, user_id, status, requested_by, created_at, updated_at
    FROM crew_connections WHERE user_id = ? AND crew_user_id = ? ${expected}
    ON CONFLICT(user_id, crew_user_id) DO UPDATE SET
      status = excluded.status, requested_by = excluded.requested_by,
      created_at = excluded.created_at, updated_at = excluded.updated_at
  `).bind(generateId(), a, b);
  const resolveRequests = db.prepare(`
    UPDATE notifications SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP)
    WHERE category = 'crew_request'
      AND ((user_id = ? AND actor_user_id = ?) OR (user_id = ? AND actor_user_id = ?))
      AND NOT EXISTS (SELECT 1 FROM crew_connections WHERE user_id = ? AND crew_user_id = ? AND status = 'pending')
  `).bind(a, b, b, a, a, b);

  const notifications = [
    crewNotificationStatement(db, a, b, a, b, action),
    crewNotificationStatement(db, a, b, b, a, action),
  ];
  const results = await db.batch<{ id: string; status: string; requested_by: string | null }>([
    canonical, mirror, resolveRequests, ...notifications,
    db.prepare('SELECT id, status, requested_by FROM crew_connections WHERE user_id = ? AND crew_user_id = ?').bind(a, b),
  ]);
  const row = results[5].results[0];
  if (!row) return null;
  return { ...row, notificationIds: results.slice(3, 5).flatMap((r) => r.results.map((n) => n.id)) };
}

function crewNotificationStatement(
  db: D1Database,
  a: string,
  b: string,
  recipient: string,
  other: string,
  action: string,
): D1PreparedStatement {
  return db.prepare(`
    WITH connection AS (SELECT * FROM crew_connections WHERE user_id = ? AND crew_user_id = ?),
    content AS (
      SELECT c.id, c.status,
        CASE WHEN c.status = 'pending' THEN 'crew_request'
             WHEN ? = 'accept' AND c.requested_by = ? THEN 'crew_request_accepted'
             ELSE 'crew_connected' END AS category,
        CASE WHEN c.status = 'pending' AND COALESCE(p.private_profile, 0) = 1
          THEN COALESCE('@' || NULLIF(TRIM(p.username), ''), 'Someone')
          ELSE COALESCE(NULLIF(TRIM(p.full_name), ''), '@' || NULLIF(TRIM(p.username), ''), 'Someone') END AS name
      FROM connection c LEFT JOIN profiles p ON p.user_id = ?
      WHERE (c.status = 'pending' AND c.requested_by = ?) OR c.status = 'active'
    )
    INSERT OR IGNORE INTO notifications
      (id, user_id, category, actor_user_id, title, dest_type, dest_id, entity_type, entity_id, dedupe_key, created_at)
    SELECT ?, ?, category, ?, name || CASE category
      WHEN 'crew_request' THEN ' wants to connect'
      WHEN 'crew_request_accepted' THEN ' accepted your crew request'
      ELSE ' joined your crew' END,
      'profile', ?, 'crew', ?, 'crew:' || id || ':' || status, CURRENT_TIMESTAMP
    FROM content
    WHERE ? IN ('connect', 'accept')
      AND COALESCE((SELECT in_app FROM notification_preferences WHERE user_id = ? AND category = content.category), 1) = 1
    RETURNING id
  `).bind(a, b, action, recipient, other, other, generateId(), recipient, other, other, other, action, recipient);
}

/** Whether the viewer may see the target's real name + photo. */
export function canSeeIdentity(
  viewerId: string,
  targetId: string,
  targetPrivate: boolean,
  status: CrewConnectionStatus,
): boolean {
  if (viewerId === targetId) return true;
  if (status === 'connected') return true;
  return !targetPrivate;
}

/**
 * The connection status to write when someone connects. Public target → an
 * immediate mutual 'active'; private target → a 'pending' request they accept.
 */
export function connectResult(targetPrivate: boolean): {
  mine: 'active' | 'pending';
  theirs: 'active' | 'pending';
  outcome: 'active' | 'pending';
} {
  return targetPrivate
    ? { mine: 'pending', theirs: 'pending', outcome: 'pending' }
    : { mine: 'active', theirs: 'active', outcome: 'active' };
}
