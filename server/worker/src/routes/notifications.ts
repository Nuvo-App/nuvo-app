import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { clampedInt, readJsonObject } from '../lib/safe';
import { conditional, stalenessBucket, weakEtag } from '../lib/etag';
import {
  CATEGORY_DEFAULTS,
  NOTIFICATION_CATEGORIES,
  type NotificationCategory,
} from '../domain/notifications';

export const notificationsRouter = new Hono<AppEnv>();
notificationsRouter.use('*', requireAuth);

interface NotificationRow {
  id: string;
  category: string;
  actor_user_id: string | null;
  title: string;
  body: string | null;
  dest_type: string | null;
  dest_id: string | null;
  dest_context: string | null;
  read_at: string | null;
  created_at: string;
  actor_name: string | null;
  actor_avatar: string | null;
}

function serialize(row: NotificationRow) {
  return {
    id: row.id,
    category: row.category,
    title: row.title,
    body: row.body,
    createdAt: row.created_at,
    read: row.read_at != null,
    actor: row.actor_user_id
      ? {
          id: row.actor_user_id,
          displayName: row.actor_name ?? 'Nuvo member',
          profilePhotoUrl: row.actor_avatar,
        }
      : null,
    destination: row.dest_type
      ? { type: row.dest_type, id: row.dest_id ?? undefined, context: row.dest_context ?? undefined }
      : null,
  };
}

// GET /notifications?cursor=<iso>&limit=<n>
notificationsRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const limit = clampedInt(c.req.query('limit'), 30, 1, 50);
  const cursor = c.req.query('cursor');

  const rows = await c.env.DB.prepare(
    `SELECT n.*, p.full_name as actor_name, p.avatar_url as actor_avatar
     FROM notifications n
     LEFT JOIN profiles p ON p.user_id = n.actor_user_id
     WHERE n.user_id = ?
       ${cursor ? 'AND n.created_at < ?' : ''}
     ORDER BY n.created_at DESC
     LIMIT ?`,
  )
    .bind(...(cursor ? [userId, cursor, limit + 1] : [userId, limit + 1]))
    .all<NotificationRow>();

  const items = rows.results.slice(0, limit).map(serialize);
  const nextCursor = rows.results.length > limit ? items[items.length - 1].createdAt : null;

  const unread = await c.env.DB.prepare(
    'SELECT COUNT(*) as n FROM notifications WHERE user_id = ? AND read_at IS NULL',
  )
    .bind(userId)
    .first<{ n: number }>();

  // Validator: every param shaping the page, newest created_at / read_at over
  // the returned rows, row count, unread count, plus a 60s bucket (covers
  // actor name/avatar edits). Auth already ran.
  const page = rows.results.slice(0, limit);
  let maxCreated = '';
  let maxRead = '';
  for (const r of page) {
    if (r.created_at > maxCreated) maxCreated = r.created_at;
    if (r.read_at && r.read_at > maxRead) maxRead = r.read_at;
  }
  const notModified = conditional(
    c,
    weakEtag(
      'notif',
      limit,
      cursor ?? '',
      page.length,
      rows.results.length > limit ? 1 : 0,
      maxCreated,
      maxRead,
      unread?.n ?? 0,
      stalenessBucket(Date.now(), 60_000),
    ),
  );
  if (notModified) return notModified;

  return c.json({
    ok: true,
    notifications: items,
    unreadCount: unread?.n ?? 0,
    nextCursor,
  });
});

// POST /notifications/:id/read
notificationsRouter.post('/:id/read', async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(
    `UPDATE notifications SET read_at = CURRENT_TIMESTAMP
     WHERE id = ? AND user_id = ? AND read_at IS NULL`,
  )
    .bind(c.req.param('id'), userId)
    .run();
  return c.json({ ok: true });
});

// POST /notifications/read-all
notificationsRouter.post('/read-all', async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(
    `UPDATE notifications SET read_at = CURRENT_TIMESTAMP WHERE user_id = ? AND read_at IS NULL`,
  )
    .bind(userId)
    .run();
  return c.json({ ok: true });
});

// ── Preferences ──────────────────────────────────────────────────────────────

// GET /notification-preferences — merged with category defaults.
notificationsRouter.get('/preferences', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    'SELECT category, in_app, push FROM notification_preferences WHERE user_id = ?',
  )
    .bind(userId)
    .all<{ category: string; in_app: number; push: number }>();
  const overrides = new Map(rows.results.map((r) => [r.category, r]));

  const preferences = NOTIFICATION_CATEGORIES.map((category) => {
    const o = overrides.get(category);
    const d = CATEGORY_DEFAULTS[category];
    return {
      category,
      inApp: o ? o.in_app === 1 : d.inApp,
      push: o ? o.push === 1 : d.push,
    };
  });
  return c.json({ ok: true, preferences });
});

// PATCH /notification-preferences  { category, inApp?, push? }
notificationsRouter.patch('/preferences', async (c) => {
  const userId = c.get('userId');
  const body = (await readJsonObject(c)) as { category?: unknown; inApp?: unknown; push?: unknown } | null;
  if (!body) return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  const category = body.category as NotificationCategory;
  if (!NOTIFICATION_CATEGORIES.includes(category)) {
    return c.json({ ok: false, error: 'Unknown category' }, 400);
  }
  const d = CATEGORY_DEFAULTS[category];
  const inApp = typeof body.inApp === 'boolean' ? body.inApp : d.inApp;
  const push = typeof body.push === 'boolean' ? body.push : d.push;

  await c.env.DB.prepare(
    `INSERT INTO notification_preferences (user_id, category, in_app, push, updated_at)
     VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, category) DO UPDATE SET
       in_app = excluded.in_app, push = excluded.push, updated_at = CURRENT_TIMESTAMP`,
  )
    .bind(userId, category, inApp ? 1 : 0, push ? 1 : 0)
    .run();
  return c.json({ ok: true, preference: { category, inApp, push } });
});
