import { Hono } from 'hono';
import type { AppEnv, ProfileRow } from '../types';
import { requireAuth } from '../lib/jwt';
import { normalizeUsername, isValidUsername } from '../lib/validation';

export const profileRouter = new Hono<AppEnv>();

// All profile routes require a valid access token
profileRouter.use('*', requireAuth);

// GET /profile/me
profileRouter.get('/me', async (c) => {
  const userId = c.get('userId');
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();

  if (!profile) {
    return c.json({ ok: false, error: 'Profile not found' }, 404);
  }

  return c.json({
    fullName: profile.full_name,
    username: profile.username,
    avatarUrl: profile.avatar_url,
    privateProfile: Boolean(profile.private_profile),
    onboardingComplete: Boolean(profile.onboarding_complete),
  });
});

// POST /profile
profileRouter.post('/', async (c) => {
  const userId = c.get('userId');

  let body: { fullName?: unknown; username?: unknown; privateProfile?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  // Build update fields dynamically to avoid clobbering untouched columns
  const fields: string[] = ['updated_at = CURRENT_TIMESTAMP'];
  const bindings: unknown[] = [];

  if (typeof body.fullName === 'string') {
    const name = body.fullName.trim();
    if (name.length > 100) {
      return c.json({ ok: false, error: 'Full name too long (max 100 chars)' }, 400);
    }
    fields.push('full_name = ?');
    bindings.push(name);
  }

  if (typeof body.username === 'string') {
    const username = normalizeUsername(body.username);
    if (!isValidUsername(username)) {
      return c.json(
        { ok: false, error: 'Username must be 3-20 characters using only letters, numbers, or underscore' },
        400,
      );
    }
    const taken = await c.env.DB.prepare(
      'SELECT user_id FROM profiles WHERE username = ? AND user_id != ?',
    )
      .bind(username, userId)
      .first<{ user_id: string }>();
    if (taken) {
      return c.json({ ok: false, error: 'Username already taken' }, 409);
    }
    fields.push('username = ?');
    bindings.push(username);
  }

  if (typeof body.privateProfile === 'boolean') {
    fields.push('private_profile = ?');
    bindings.push(body.privateProfile ? 1 : 0);
  }

  if (fields.length === 1) {
    // Only the timestamp update — nothing else to change
    return c.json({ ok: false, error: 'No updatable fields provided' }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE profiles SET ${fields.join(', ')} WHERE user_id = ?`,
  )
    .bind(...bindings, userId)
    .run();

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();

  return c.json({
    fullName: profile?.full_name ?? null,
    username: profile?.username ?? null,
    avatarUrl: profile?.avatar_url ?? null,
    privateProfile: Boolean(profile?.private_profile),
    onboardingComplete: Boolean(profile?.onboarding_complete),
  });
});

// POST /profile/username/check
profileRouter.post('/username/check', async (c) => {
  let body: { username?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const rawUsername = typeof body.username === 'string' ? body.username : '';
  if (!rawUsername) {
    return c.json({ ok: false, error: 'username required' }, 400);
  }

  const username = normalizeUsername(rawUsername);
  if (!isValidUsername(username)) {
    return c.json({ available: false, reason: 'invalid_format' });
  }

  const existing = await c.env.DB.prepare(
    'SELECT user_id FROM profiles WHERE username = ?',
  )
    .bind(username)
    .first<{ user_id: string }>();

  return c.json({ available: !existing });
});
