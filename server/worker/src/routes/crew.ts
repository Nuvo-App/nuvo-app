import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { isBlocked } from '../lib/privacy';
import { transitionCrew } from '../domain/crewLifecycle';
import { deliverNotificationPushes } from '../domain/notifications';

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
  last_active_at: string | null;
  requested_by?: string | null;
  connection_id?: string;
  level?: number | null;
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
    lastActiveAt: row.last_active_at,
    level: row.level ?? null,
  };
}

const CREW_USER_SELECT = `
  SELECT u.id, u.primary_email, u.last_active_at, p.full_name, p.username, p.avatar_url, mp.member_id, cc.created_at,
         cc.requested_by, cc.id as connection_id, COALESCE(up.level, 1) as level
  FROM crew_connections cc
  JOIN users u ON u.id = cc.crew_user_id
  LEFT JOIN profiles p ON p.user_id = u.id
  LEFT JOIN member_passes mp ON mp.user_id = u.id
  LEFT JOIN user_progression up ON up.user_id = u.id
`;

async function getCrewUser(db: D1Database, userId: string, crewUserId: string) {
  return db
    .prepare(`${CREW_USER_SELECT} WHERE cc.user_id = ? AND cc.crew_user_id = ? AND cc.status = 'active'`)
    .bind(userId, crewUserId)
    .first<CrewUserRow>();
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

// GET /crew/requests — incoming pending requests + outgoing requests I sent.
// `outgoing` is additive: older clients simply ignore the field.
crewRouter.get('/requests', async (c) => {
  const userId = c.get('userId');
  const [incoming, outgoing] = await Promise.all([
    c.env.DB.prepare(
      `${CREW_USER_SELECT}
       WHERE cc.user_id = ? AND cc.status = 'pending' AND cc.requested_by IS NOT NULL AND cc.requested_by != ?
       ORDER BY cc.updated_at DESC, cc.created_at DESC`,
    )
      .bind(userId, userId)
      .all<CrewUserRow>(),
    c.env.DB.prepare(
      `${CREW_USER_SELECT}
       WHERE cc.user_id = ? AND cc.status = 'pending' AND cc.requested_by = ?
       ORDER BY cc.updated_at DESC, cc.created_at DESC`,
    )
      .bind(userId, userId)
      .all<CrewUserRow>(),
  ]);
  return c.json({
    ok: true,
    requests: incoming.results.map((r) => ({
      ...serializeCrewUser(r),
      requestedBy: r.requested_by,
    })),
    outgoing: outgoing.results.map(serializeCrewUser),
  });
});

// GET /crew/feed — Crew's typed social-activity projection.
//
// Shape mirrors the Race V2 §18 contract ({type, actor, raceId?, title,
// summary, occurredAt}) plus the entity refs reactions key off.
//
// Two sources, merged — this is the "Domain Event → Crew Activity" seam:
//   1. race_events — the canonical append-only domain log (Race V2 §19).
//      Race activity is consumed from events, never reverse-engineered from
//      notification rows. Scope: races the viewer is an active member of,
//      plus events whose actor is in the viewer's crew (doc 15's feed rule).
//      Blocked actors (either direction) are filtered server-side.
//   2. notifications — crew-lifecycle categories only (crew_request /
//      crew_request_accepted / crew_connected). Interim source until a crew
//      domain-event log exists; race activity deliberately does NOT come
//      from these rows anymore.
//
// The client renders Nuvo-language headlines from {type, actor, raceTitle,
// payload} — the server stays copy-free (§14: copy lives in the app).
interface FeedEventRow {
  id: string;
  event_type: string;
  race_id: string;
  race_title: string;
  actor_user_id: string | null;
  subject_user_id: string | null;
  payload_json: string | null;
  created_at: string;
  actor_name: string | null;
  actor_avatar: string | null;
  reactions: string | null;
  my_reaction: string | null;
}

interface FeedNoteRow {
  id: string;
  category: string;
  actor_user_id: string | null;
  title: string;
  body: string | null;
  dest_type: string | null;
  dest_id: string | null;
  dest_context: string | null;
  entity_type: string | null;
  entity_id: string | null;
  read_at: string | null;
  created_at: string;
  actor_name: string | null;
  actor_avatar: string | null;
  reactions: string | null;
  my_reaction: string | null;
}

function parseJsonObject(raw: string | null): Record<string, unknown> {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object'
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

crewRouter.get('/feed', async (c) => {
  const userId = c.get('userId');
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 40), 1), 80);
  const cursor = c.req.query('cursor');
  const db = c.env.DB;

  const eventQuery = db.prepare(
    `SELECT re.id, re.event_type, re.race_id, r.title as race_title,
            re.actor_user_id, re.subject_user_id, re.payload_json, re.created_at,
            p.full_name as actor_name, p.avatar_url as actor_avatar,
            COALESCE((SELECT json_group_object(emoji, n2) FROM (
              SELECT emoji, COUNT(*) as n2 FROM activity_reactions
              WHERE entity_type = 'race_event' AND entity_id = re.id
              GROUP BY emoji)), '{}') as reactions,
            (SELECT emoji FROM activity_reactions ar
              WHERE ar.entity_type = 'race_event' AND ar.entity_id = re.id
                AND ar.user_id = ?) as my_reaction
     FROM race_events re
     JOIN races r ON r.id = re.race_id
     LEFT JOIN profiles p ON p.user_id = re.actor_user_id
     WHERE (re.race_id IN (SELECT race_id FROM race_members
                            WHERE user_id = ? AND status = 'active')
         -- Crew activity surfaces only when the race isn't strictly private —
         -- a crew member's private race with others must not leak its title.
         OR (r.visibility <> 'private'
             AND re.actor_user_id IN (SELECT crew_user_id FROM crew_connections
                                      WHERE user_id = ? AND status = 'active')))
       AND (re.actor_user_id IS NULL OR re.actor_user_id NOT IN (
             SELECT blocked_user_id FROM blocked_users WHERE user_id = ?))
       AND (re.actor_user_id IS NULL OR re.actor_user_id NOT IN (
             SELECT user_id FROM blocked_users WHERE blocked_user_id = ?))
       ${cursor ? 'AND re.created_at < ?' : ''}
     ORDER BY re.created_at DESC
     LIMIT ?`,
  );
  const noteQuery = db.prepare(
    `SELECT n.id, n.category, n.actor_user_id, n.title, n.body,
            n.dest_type, n.dest_id, n.dest_context,
            n.entity_type, n.entity_id, n.read_at, n.created_at,
            p.full_name as actor_name, p.avatar_url as actor_avatar,
            COALESCE((SELECT json_group_object(emoji, n2) FROM (
              SELECT emoji, COUNT(*) as n2 FROM activity_reactions
              WHERE entity_type = n.entity_type AND entity_id = n.entity_id
              GROUP BY emoji)), '{}') as reactions,
            (SELECT emoji FROM activity_reactions ar
              WHERE ar.entity_type = n.entity_type AND ar.entity_id = n.entity_id
                AND ar.user_id = ?) as my_reaction
     FROM notifications n
     LEFT JOIN profiles p ON p.user_id = n.actor_user_id
     WHERE n.user_id = ?
       AND n.category IN ('crew_request', 'crew_request_accepted', 'crew_connected')
       ${cursor ? 'AND n.created_at < ?' : ''}
     ORDER BY n.created_at DESC
     LIMIT ?`,
  );

  const [events, notes] = await Promise.all([
    eventQuery
      .bind(...(cursor ? [userId, userId, userId, userId, userId, cursor, limit + 1] : [userId, userId, userId, userId, userId, limit + 1]))
      .all<FeedEventRow>(),
    noteQuery
      .bind(...(cursor ? [userId, userId, cursor, limit + 1] : [userId, userId, limit + 1]))
      .all<FeedNoteRow>(),
  ]);

  interface FeedItem {
    id: string;
    type: string;
    occurredAt: string;
    actor: { id: string; displayName: string; profilePhotoUrl: string | null } | null;
    raceId: string | null;
    raceTitle: string | null;
    title: string | null;
    summary: string | null;
    payload: Record<string, unknown> | null;
    entityType: string | null;
    entityId: string | null;
    destination: { type: string; id?: string; context?: string } | null;
    read: boolean;
    reactions: Record<string, number>;
    myReaction: string | null;
  }

  const items: FeedItem[] = [];
  for (const row of events.results) {
    items.push({
      id: `evt:${row.id}`,
      type: row.event_type,
      occurredAt: row.created_at,
      actor: row.actor_user_id
        ? {
            id: row.actor_user_id,
            displayName: row.actor_name ?? 'Nuvo member',
            profilePhotoUrl: row.actor_avatar,
          }
        : null,
      raceId: row.race_id,
      raceTitle: row.race_title,
      title: null,
      summary: null,
      payload: parseJsonObject(row.payload_json),
      entityType: 'race_event',
      entityId: row.id,
      destination: { type: 'race', id: row.race_id },
      read: true,
      reactions: parseJsonObject(row.reactions) as Record<string, number>,
      myReaction: row.my_reaction,
    });
  }
  for (const row of notes.results) {
    items.push({
      id: `ntf:${row.id}`,
      type: row.category,
      occurredAt: row.created_at,
      actor: row.actor_user_id
        ? {
            id: row.actor_user_id,
            displayName: row.actor_name ?? 'Nuvo member',
            profilePhotoUrl: row.actor_avatar,
          }
        : null,
      raceId: row.dest_type === 'race' ? row.dest_id : null,
      raceTitle: null,
      title: row.title,
      summary: row.body,
      payload: null,
      entityType: row.entity_type,
      entityId: row.entity_id,
      destination: row.dest_type
        ? { type: row.dest_type, id: row.dest_id ?? undefined, context: row.dest_context ?? undefined }
        : null,
      read: row.read_at != null,
      reactions: parseJsonObject(row.reactions) as Record<string, number>,
      myReaction: row.my_reaction,
    });
  }

  items.sort((a, b) => (a.occurredAt < b.occurredAt ? 1 : -1));
  const page = items.slice(0, limit);
  const nextCursor =
    page.length === limit ? page[page.length - 1].occurredAt : null;
  return c.json({ ok: true, items: page, nextCursor });
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

  // transitionCrew resolves the previous pair, writes both directional rows,
  // resolves stale request notifications and emits the new notification in a
  // single D1 batch — concurrent adds and retries self-heal rather than
  // producing asymmetric or duplicate state.
  const transition = await transitionCrew(c.env.DB, userId, crewUserId, 'connect');
  if (!transition) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }
  await deliverNotificationPushes(c, transition.notificationIds);
  if (transition.status !== 'active') {
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

// POST /crew/requests/:userId/accept — only an incoming request can be
// accepted; transitionCrew enforces requested_by == target inside the batch,
// so a requester can never approve their own outgoing request.
crewRouter.post('/requests/:userId/accept', async (c) => {
  const userId = c.get('userId');
  const otherId = c.req.param('userId');
  if ((await isBlocked(c.env.DB, userId, otherId)) || (await isBlocked(c.env.DB, otherId, userId))) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }
  const transition = await transitionCrew(c.env.DB, userId, otherId, 'accept');
  if (!transition || transition.status !== 'active') {
    return c.json({ ok: false, error: 'No pending request from this person' }, 404);
  }
  await deliverNotificationPushes(c, transition.notificationIds);
  const crewUser = await getCrewUser(c.env.DB, userId, otherId);
  return c.json({ ok: true, status: 'active', user: crewUser ? serializeCrewUser(crewUser) : null });
});

// POST /crew/requests/:userId/decline
crewRouter.post('/requests/:userId/decline', async (c) => {
  const userId = c.get('userId');
  const otherId = c.req.param('userId');
  await transitionCrew(c.env.DB, userId, otherId, 'decline');
  return c.json({ ok: true });
});

// DELETE /crew/:userId — remove a connection or cancel a request (either side)
crewRouter.delete('/:userId', async (c) => {
  const userId = c.get('userId');
  const crewUserId = c.req.param('userId');
  await transitionCrew(c.env.DB, userId, crewUserId, 'remove');
  return c.json({ ok: true });
});
