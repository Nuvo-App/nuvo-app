/**
 * Notifications are DOMAIN OBJECTS, not push messages (docs/agents/19 §9).
 * `emitNotification` is called inline from the route that caused the event; it
 * checks the recipient's per-category preference, writes one durable row
 * (idempotent on `dedupe_key`), and — later, phase F — enqueues a push.
 *
 * `dest` is a STRUCTURED destination ({type,id,context}); the client turns it
 * into a route via NuvoDestination.fromDescriptor. Never store a route string.
 */
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { sendPush } from './push';

export const NOTIFICATION_CATEGORIES = [
  'race_invite',
  'race_joined',
  'race_starting',
  'race_completed',
  'passed_on_leaderboard',
  'proof_accepted',
  'proof_rejected',
  'crew_request',
  'crew_request_accepted',
] as const;
export type NotificationCategory = (typeof NOTIFICATION_CATEGORIES)[number];

/** Category defaults when the user has no notification_preferences row. */
export const CATEGORY_DEFAULTS: Record<
  NotificationCategory,
  { inApp: boolean; push: boolean }
> = {
  race_invite: { inApp: true, push: true },
  race_joined: { inApp: true, push: true },
  race_starting: { inApp: true, push: true },
  race_completed: { inApp: true, push: true },
  passed_on_leaderboard: { inApp: true, push: true },
  proof_accepted: { inApp: true, push: true },
  proof_rejected: { inApp: true, push: true },
  crew_request: { inApp: true, push: true },
  crew_request_accepted: { inApp: true, push: false }, // nice-to-know, not urgent
};

export interface DestinationDescriptor {
  type: 'race' | 'profile' | 'crew' | 'invite' | 'notifications';
  id?: string;
  context?: string;
}

export interface EmitOptions {
  userId: string; // recipient
  category: NotificationCategory;
  title: string;
  body?: string;
  actorUserId?: string;
  dest?: DestinationDescriptor;
  entityType?: string;
  entityId?: string;
  /** Idempotency key — a second emit with the same (userId, dedupeKey) no-ops. */
  dedupeKey?: string;
}

interface PrefRow {
  in_app: number;
  push: number;
}

/**
 * Returns the created notification id, or null when it was suppressed
 * (preference off) or de-duped. Best-effort: a failure here must never break
 * the transaction that triggered it — callers wrap in try/catch or waitUntil.
 */
export async function emitNotification(
  db: D1Database,
  opts: EmitOptions,
): Promise<string | null> {
  const pref = await db
    .prepare('SELECT in_app, push FROM notification_preferences WHERE user_id = ? AND category = ?')
    .bind(opts.userId, opts.category)
    .first<PrefRow>();
  const inApp = pref ? pref.in_app === 1 : CATEGORY_DEFAULTS[opts.category].inApp;
  if (!inApp) return null;

  const id = generateId();
  const dedupe = opts.dedupeKey ?? `${opts.category}:${id}`;
  const res = await db
    .prepare(
      `INSERT OR IGNORE INTO notifications
        (id, user_id, category, actor_user_id, title, body, dest_type, dest_id, dest_context,
         entity_type, entity_id, dedupe_key, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
    )
    .bind(
      id,
      opts.userId,
      opts.category,
      opts.actorUserId ?? null,
      opts.title,
      opts.body ?? null,
      opts.dest?.type ?? null,
      opts.dest?.id ?? null,
      opts.dest?.context ?? null,
      opts.entityType ?? null,
      opts.entityId ?? null,
      dedupe,
    )
    .run();

  const inserted = (res.meta?.changes ?? 0) > 0;
  return inserted ? id : null;
}

function pushEligible(pref: PrefRow | null | undefined, category: NotificationCategory): boolean {
  return pref ? pref.push === 1 : CATEGORY_DEFAULTS[category].push;
}

/**
 * Emit a notification AND (best-effort, off the response path) deliver a push
 * for it. The single entry point every route uses — swallows all errors so a
 * notification never 500s the transaction that triggered it.
 */
export async function safeEmit(
  c: Context<AppEnv>,
  opts: EmitOptions,
): Promise<void> {
  try {
    const db = c.env.DB as D1Database;
    const id = await emitNotification(db, opts);
    if (!id) return;

    const pref = await db
      .prepare('SELECT in_app, push FROM notification_preferences WHERE user_id = ? AND category = ?')
      .bind(opts.userId, opts.category)
      .first<PrefRow>();
    if (!pushEligible(pref, opts.category)) return;

    const deliver = sendPush(c.env, opts.userId, {
      title: opts.title,
      body: opts.body,
      category: opts.category,
      dest: opts.dest,
    });
    if (c.executionCtx?.waitUntil) {
      c.executionCtx.waitUntil(deliver);
    } else {
      await deliver;
    }
  } catch (err) {
    console.error('[notifications] emit failed:', (err as Error).message, opts.category);
  }
}
