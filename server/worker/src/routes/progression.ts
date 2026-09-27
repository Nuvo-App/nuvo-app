import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import {
  markLevelSeen,
  readBadgeCollection,
  readProgression,
  readRaceXp,
  setFeaturedBadges,
} from '../domain/progression';

export const progressionRouter = new Hono<AppEnv>();

progressionRouter.use('*', requireAuth);

// GET /progression — self-healing read: the projection reconciles from
// canonical race_events before answering, so XP can never go stale.
progressionRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const payload = await readProgression(c.env.DB, userId);
  return c.json({ ok: true, progression: payload });
});

// GET /progression/badges — the full collection, unlocked and locked.
progressionRouter.get('/badges', async (c) => {
  const userId = c.get('userId');
  const badges = await readBadgeCollection(c.env.DB, userId);
  return c.json({ ok: true, badges });
});

// PUT /progression/featured — replace the featured badge set (validated).
progressionRouter.put('/featured', async (c) => {
  const userId = c.get('userId');
  let body: { unlockIds?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }
  const ids = Array.isArray(body.unlockIds)
    ? body.unlockIds.filter((v): v is string => typeof v === 'string')
    : null;
  if (!ids) {
    return c.json({ ok: false, error: 'unlockIds must be a string array' }, 400);
  }
  const result = await setFeaturedBadges(c.env.DB, userId, ids);
  if (!result.ok) return c.json({ ok: false, error: result.error }, 400);
  const badges = await readBadgeCollection(c.env.DB, userId);
  return c.json({ ok: true, badges });
});

// GET /progression/race/:raceId — the XP one race paid out, for the finish
// screen's reward breakdown. Same self-healing reconcile first.
progressionRouter.get('/race/:raceId', async (c) => {
  const userId = c.get('userId');
  const breakdown = await readRaceXp(c.env.DB, userId, c.req.param('raceId'));
  return c.json({ ok: true, xp: breakdown });
});

// POST /progression/level-seen — acknowledge the level-up moment so it
// presents once per level across devices/reinstalls.
progressionRouter.post('/level-seen', async (c) => {
  const userId = c.get('userId');
  await markLevelSeen(c.env.DB, userId);
  const payload = await readProgression(c.env.DB, userId);
  return c.json({ ok: true, progression: payload });
});
