import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';

export const devicesRouter = new Hono<AppEnv>();
devicesRouter.use('*', requireAuth);

// POST /devices  { token, platform: 'ios'|'android', appVersion? }
// Registers (or refreshes) a push token for this user + device.
devicesRouter.post('/', async (c) => {
  const userId = c.get('userId');
  let body: { token?: unknown; platform?: unknown; appVersion?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }
  const token = typeof body.token === 'string' ? body.token.trim() : '';
  const platform = body.platform === 'android' ? 'android' : 'ios';
  const appVersion = typeof body.appVersion === 'string' ? body.appVersion.slice(0, 40) : null;
  if (!token) return c.json({ ok: false, error: 'token is required' }, 400);

  await c.env.DB.prepare(
    `INSERT INTO device_tokens (id, user_id, token, platform, app_version, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, token) DO UPDATE SET
       platform = excluded.platform,
       app_version = excluded.app_version,
       last_seen_at = CURRENT_TIMESTAMP,
       disabled_at = NULL`,
  )
    .bind(generateId(), userId, token, platform, appVersion)
    .run();
  return c.json({ ok: true });
});

// DELETE /devices/:token — on sign-out.
devicesRouter.delete('/:token', async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(
    'DELETE FROM device_tokens WHERE user_id = ? AND token = ?',
  )
    .bind(userId, c.req.param('token'))
    .run();
  return c.json({ ok: true });
});
