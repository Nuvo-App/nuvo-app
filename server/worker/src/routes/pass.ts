import { Hono } from 'hono';
import type { AppEnv, PassRow } from '../types';
import { requireAuth } from '../lib/jwt';
import { SHARE_BASE_URL } from '../lib/response';

export const passRouter = new Hono<AppEnv>();

passRouter.use('*', requireAuth);

// GET /pass/me
passRouter.get('/me', async (c) => {
  const userId = c.get('userId');

  const pass = await c.env.DB.prepare('SELECT * FROM member_passes WHERE user_id = ?')
    .bind(userId)
    .first<PassRow>();

  if (!pass) {
    return c.json({ ok: false, error: 'Member pass not found' }, 404);
  }

  return c.json({
    memberId: pass.member_id,
    passSlug: pass.pass_slug,
    shareUrl: `${SHARE_BASE_URL}/pass/${pass.pass_slug}`,
  });
});
