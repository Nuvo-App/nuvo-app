/**
 * Reactions — lightweight social responses (🔥 👏 💪) on activity entities.
 *
 * Targets are the same (entityType, entityId) refs notifications already
 * carry ('race', 'move_log'), so counts aggregate across every recipient's
 * copy of the same event and stay valid when the feed source moves from
 * notification rows to the canonical race_events log (Race V2 §19).
 *
 * A write here is the durable ReactionAdded fact, handed to the policy
 * layer as a `reaction_added` domain event. Crew never calls
 * emitNotification or sendPush — the notification policy layer owns whether
 * a reaction ever interrupts anyone.
 */
import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import { isBlocked } from '../lib/privacy';
import { notifyEvent } from '../domain/notificationPolicy';

export const reactionsRouter = new Hono<AppEnv>();
reactionsRouter.use('*', requireAuth);

const EMOJIS = new Set(['fire', 'clap', 'muscle']);

/** Entity types a reaction can target — the same refs the feed emits. */
const REACTABLE_ENTITIES = new Set(['race_event', 'move_log', 'crew', 'race']);

interface ResolvedTarget {
  /** The person this reaction is about — null when the entity can't be
   *  attributed to one user (a bare 'race' entity). */
  recipientId: string | null;
  /** Race to deep-link into, when the entity lives inside one. */
  raceId: string | null;
  /** Display context for notification copy (the race title). */
  context: string | null;
}

/**
 * Resolve who a reaction is FOR. The entity id is the durable ref the feed
 * already emits — race_events carry actor/subject, move_logs carry their
 * owner, crew entities are the connection row (notify the other side).
 * Returns null when the entity doesn't exist.
 */
async function resolveReactionTarget(
  db: D1Database,
  entityType: string,
  entityId: string,
  reactorId: string,
): Promise<ResolvedTarget | null> {
  switch (entityType) {
    case 'race_event': {
      const row = await db
        .prepare(
          `SELECT re.actor_user_id, re.subject_user_id, re.race_id, r.title
           FROM race_events re LEFT JOIN races r ON r.id = re.race_id
           WHERE re.id = ?`,
        )
        .bind(entityId)
        .first<{ actor_user_id: string | null; subject_user_id: string | null; race_id: string; title: string | null }>();
      if (!row) return null;
      const recipient = row.actor_user_id ?? row.subject_user_id;
      return {
        recipientId: recipient && recipient !== reactorId ? recipient : null,
        raceId: row.race_id,
        context: row.title,
      };
    }
    case 'move_log': {
      const row = await db
        .prepare(
          `SELECT ml.user_id, ml.race_id, r.title
           FROM move_logs ml LEFT JOIN races r ON r.id = ml.race_id
           WHERE ml.id = ?`,
        )
        .bind(entityId)
        .first<{ user_id: string; race_id: string | null; title: string | null }>();
      if (!row) return null;
      return {
        recipientId: row.user_id !== reactorId ? row.user_id : null,
        raceId: row.race_id,
        context: row.title,
      };
    }
    case 'crew': {
      const row = await db
        .prepare('SELECT user_id, crew_user_id FROM crew_connections WHERE id = ?')
        .bind(entityId)
        .first<{ user_id: string; crew_user_id: string }>();
      if (!row) return null;
      const other = row.user_id === reactorId ? row.crew_user_id : row.user_id;
      return { recipientId: other !== reactorId ? other : null, raceId: null, context: null };
    }
    case 'race': {
      const row = await db
        .prepare('SELECT id, title FROM races WHERE id = ?')
        .bind(entityId)
        .first<{ id: string; title: string | null }>();
      if (!row) return null;
      return { recipientId: null, raceId: row.id, context: row.title };
    }
    default:
      return null;
  }
}

interface ReactionCountRow {
  emoji: string;
  n: number;
}

async function reactionSummary(
  db: D1Database,
  entityType: string,
  entityId: string,
  userId: string,
) {
  const [rows, mine] = await Promise.all([
    db
      .prepare(
        `SELECT emoji, COUNT(*) as n FROM activity_reactions
         WHERE entity_type = ? AND entity_id = ? GROUP BY emoji`,
      )
      .bind(entityType, entityId)
      .all<ReactionCountRow>(),
    db
      .prepare(
        `SELECT emoji FROM activity_reactions
         WHERE entity_type = ? AND entity_id = ? AND user_id = ?`,
      )
      .bind(entityType, entityId, userId)
      .first<{ emoji: string }>(),
  ]);
  const counts: Record<string, number> = {};
  for (const row of rows.results) counts[row.emoji] = row.n;
  return { counts, myReaction: mine?.emoji ?? null };
}

function parseTarget(body: Record<string, unknown>) {
  const entityType = typeof body.entityType === 'string' ? body.entityType.trim() : '';
  const entityId = typeof body.entityId === 'string' ? body.entityId.trim() : '';
  if (!entityType || !entityId || entityType.length > 64 || entityId.length > 128) {
    return null;
  }
  return { entityType, entityId };
}

// POST /reactions  { entityType, entityId, emoji }
// Upsert: one reaction per user per entity — posting again with a different
// emoji changes it (no duplicates), posting the same emoji is idempotent.
reactionsRouter.post('/', async (c) => {
  const userId = c.get('userId');
  let body: Record<string, unknown>;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }
  const target = parseTarget(body);
  const emoji = typeof body.emoji === 'string' ? body.emoji : '';
  if (!target) {
    return c.json({ ok: false, error: 'entityType and entityId are required' }, 400);
  }
  if (!REACTABLE_ENTITIES.has(target.entityType)) {
    return c.json({ ok: false, error: 'Unsupported entity type' }, 400);
  }
  if (!EMOJIS.has(emoji)) {
    return c.json({ ok: false, error: 'Unsupported reaction' }, 400);
  }

  // Resolve who this reaction is for — gates blocking and feeds the
  // notification policy. An unknown entity id can't be reacted to.
  const resolved = await resolveReactionTarget(c.env.DB, target.entityType, target.entityId, userId);
  if (!resolved) {
    return c.json({ ok: false, error: 'Target not found' }, 404);
  }
  if (
    resolved.recipientId &&
    ((await isBlocked(c.env.DB, resolved.recipientId, userId)) ||
      (await isBlocked(c.env.DB, userId, resolved.recipientId)))
  ) {
    return c.json({ ok: false, error: 'This person is not available' }, 403);
  }

  const previous = await c.env.DB
    .prepare(
      `SELECT emoji FROM activity_reactions
       WHERE user_id = ? AND entity_type = ? AND entity_id = ?`,
    )
    .bind(userId, target.entityType, target.entityId)
    .first<{ emoji: string }>();

  await c.env.DB.prepare(
    `INSERT INTO activity_reactions (id, user_id, entity_type, entity_id, emoji)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id, entity_type, entity_id)
     DO UPDATE SET emoji = excluded.emoji`,
  )
    .bind(generateId(), userId, target.entityType, target.entityId, emoji)
    .run();

  // Hand the ReactionAdded fact to the policy layer when it actually changed
  // something — a repeat of the same emoji is a no-op, not a second event.
  // Notification copy, dedupe, aggregation and push eligibility are all the
  // policy's call; a failure here must not fail the reaction write.
  if (resolved.recipientId && previous?.emoji !== emoji) {
    try {
      const reactor = await c.env.DB
        .prepare('SELECT full_name, username FROM profiles WHERE user_id = ?')
        .bind(userId)
        .first<{ full_name: string | null; username: string | null }>();
      await notifyEvent(c.env, undefined, {
        type: 'reaction_added',
        userId: resolved.recipientId,
        actorUserId: userId,
        actorName: reactor?.full_name ?? reactor?.username,
        emoji,
        entityType: target.entityType,
        entityId: target.entityId,
        raceId: resolved.raceId,
        context: resolved.context,
      });
    } catch (err) {
      console.error('[reactions] reaction_added notify failed:', (err as Error).message);
    }
  }

  return c.json({
    ok: true,
    ...(await reactionSummary(c.env.DB, target.entityType, target.entityId, userId)),
  });
});

// DELETE /reactions  { entityType, entityId } — remove my reaction.
reactionsRouter.delete('/', async (c) => {
  const userId = c.get('userId');
  let body: Record<string, unknown>;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }
  const target = parseTarget(body);
  if (!target) {
    return c.json({ ok: false, error: 'entityType and entityId are required' }, 400);
  }
  await c.env.DB.prepare(
    `DELETE FROM activity_reactions
     WHERE user_id = ? AND entity_type = ? AND entity_id = ?`,
  )
    .bind(userId, target.entityType, target.entityId)
    .run();
  return c.json({
    ok: true,
    ...(await reactionSummary(c.env.DB, target.entityType, target.entityId, userId)),
  });
});
