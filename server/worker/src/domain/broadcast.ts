/**
 * Admin broadcast — ONE notification to EVERY active user, sent from the
 * internal surface (POST /internal/notifications/broadcast).
 *
 * Idempotency: every inbox row carries dedupe_key `broadcast:<broadcastId>`
 * and the notifications table already has UNIQUE(user_id, dedupe_key), so
 * `INSERT OR IGNORE` guarantees a user never gets a second copy for the same
 * broadcastId. A push is only sent for rows this call actually inserted, so a
 * re-run after a partial failure completes the remainder without re-pushing
 * anyone. No migration is needed.
 *
 * Batching: recipients are walked in user-id order; `cursor` is the last user
 * id of the previous batch.
 */
import { generateId } from '../lib/crypto';
import { NOTIFICATION_CATEGORIES, CATEGORY_DEFAULTS, type DestinationDescriptor } from './notifications';
import { pushConfigured, sendPush } from './push';

/** Neutral to the shipped client: unknown categories get the plain bell icon
 * and the neutral accent, and refresh only the notifications domain. */
export const BROADCAST_CATEGORY = 'announcement';
export const DEFAULT_BATCH_SIZE = 100;
export const MAX_BATCH_SIZE = 200;

const BROADCAST_ID_RE = /^[A-Za-z0-9_.-]{3,64}$/;
// Destinations the shipped client resolves without an id.
const BROADCAST_DEST_TYPES = ['notifications', 'crew'] as const;

export interface BroadcastEnv {
  DB: D1Database;
  FCM_SERVICE_ACCOUNT?: string;
  FCM_PROJECT_ID?: string;
}

export interface BroadcastRequest {
  title: string;
  body: string;
  category: string;
  dest: DestinationDescriptor | null;
  dryRun: boolean;
  expectedCount: number | null;
  broadcastId: string | null;
  batchSize: number;
  cursor: string | null;
}

export type ParsedBroadcast =
  | { ok: true; req: BroadcastRequest }
  | { ok: false; error: string };

export function parseBroadcastRequest(raw: unknown): ParsedBroadcast {
  if (!raw || typeof raw !== 'object') return { ok: false, error: 'Invalid JSON body.' };
  const b = raw as Record<string, unknown>;
  const title = typeof b.title === 'string' ? b.title.trim() : '';
  const body = typeof b.body === 'string' ? b.body.trim() : '';
  if (!title || title.length > 120) return { ok: false, error: 'title is required (max 120 chars).' };
  if (!body || body.length > 300) return { ok: false, error: 'body is required (max 300 chars).' };

  const category = b.category === undefined ? BROADCAST_CATEGORY : b.category;
  if (
    typeof category !== 'string' ||
    (category !== BROADCAST_CATEGORY && !(NOTIFICATION_CATEGORIES as readonly string[]).includes(category))
  ) {
    return { ok: false, error: 'Unsupported category.' };
  }

  let dest: DestinationDescriptor | null = null;
  if (b.dest !== undefined && b.dest !== null) {
    const d = b.dest as { type?: unknown };
    if (typeof d !== 'object' || !(BROADCAST_DEST_TYPES as readonly unknown[]).includes(d.type)) {
      return { ok: false, error: `dest.type must be one of ${BROADCAST_DEST_TYPES.join(', ')}.` };
    }
    dest = { type: d.type as DestinationDescriptor['type'] };
  }

  // dryRun defaults to TRUE: only an explicit boolean false sends anything.
  const dryRun = b.dryRun !== false;

  let broadcastId: string | null = null;
  if (b.broadcastId !== undefined && b.broadcastId !== null) {
    if (typeof b.broadcastId !== 'string' || !BROADCAST_ID_RE.test(b.broadcastId)) {
      return { ok: false, error: 'broadcastId must be 3-64 chars of letters, digits, _ . -' };
    }
    broadcastId = b.broadcastId;
  }

  let expectedCount: number | null = null;
  if (b.expectedCount !== undefined && b.expectedCount !== null) {
    if (typeof b.expectedCount !== 'number' || !Number.isInteger(b.expectedCount) || b.expectedCount < 0) {
      return { ok: false, error: 'expectedCount must be a non-negative integer.' };
    }
    expectedCount = b.expectedCount;
  }

  let batchSize = DEFAULT_BATCH_SIZE;
  if (b.batchSize !== undefined && b.batchSize !== null) {
    if (typeof b.batchSize !== 'number' || !Number.isInteger(b.batchSize) || b.batchSize < 1) {
      return { ok: false, error: 'batchSize must be a positive integer.' };
    }
    batchSize = Math.min(b.batchSize, MAX_BATCH_SIZE);
  }

  let cursor: string | null = null;
  if (b.cursor !== undefined && b.cursor !== null) {
    if (typeof b.cursor !== 'string' || b.cursor.length === 0 || b.cursor.length > 128) {
      return { ok: false, error: 'cursor must be a string.' };
    }
    cursor = b.cursor;
  }

  if (!dryRun) {
    if (!broadcastId) return { ok: false, error: 'broadcastId is required for a real send.' };
    if (expectedCount === null) return { ok: false, error: 'expectedCount is required for a real send.' };
  }
  return { ok: true, req: { title, body, category, dest, dryRun, expectedCount, broadcastId, batchSize, cursor } };
}

export function broadcastDedupeKey(broadcastId: string): string {
  return `broadcast:${broadcastId}`;
}

export async function countActiveRecipients(db: D1Database): Promise<number> {
  const r = await db
    .prepare("SELECT COUNT(*) AS n FROM users WHERE status = 'active'")
    .first<{ n: number }>();
  return r?.n ?? 0;
}

export type BroadcastResult =
  | { status: 200; body: Record<string, unknown> }
  | { status: 400 | 409; body: { ok: false; error: string; [k: string]: unknown } };

export async function runBroadcast(env: BroadcastEnv, req: BroadcastRequest): Promise<BroadcastResult> {
  const db = env.DB;
  const recipients = await countActiveRecipients(db);
  const configured = pushConfigured(env);

  if (req.dryRun) {
    const withTokens = await db
      .prepare(
        `SELECT COUNT(DISTINCT d.user_id) AS n FROM device_tokens d
         JOIN users u ON u.id = d.user_id
         WHERE u.status = 'active' AND d.disabled_at IS NULL`,
      )
      .first<{ n: number }>();
    let alreadyDelivered: number | null = null;
    if (req.broadcastId) {
      const r = await db
        .prepare('SELECT COUNT(*) AS n FROM notifications WHERE dedupe_key = ?')
        .bind(broadcastDedupeKey(req.broadcastId))
        .first<{ n: number }>();
      alreadyDelivered = r?.n ?? 0;
    }
    const first = await db
      .prepare("SELECT id FROM users WHERE status = 'active' ORDER BY id LIMIT 3")
      .all<{ id: string }>();
    return {
      status: 200,
      body: {
        ok: true,
        dryRun: true,
        recipients,
        withDeviceTokens: withTokens?.n ?? 0,
        pushConfigured: configured,
        alreadyDelivered,
        category: req.category,
        sample: first.results.map((u) => ({
          userId: u.id,
          title: req.title,
          body: req.body,
          category: req.category,
          dest: req.dest,
        })),
      },
    };
  }

  // Real send — guards (parseBroadcastRequest already required the two fields).
  if (req.expectedCount !== recipients) {
    return {
      status: 400,
      body: {
        ok: false,
        error: `expectedCount ${req.expectedCount} does not match current recipients ${recipients}. Re-run the dry run and confirm.`,
        recipients,
      },
    };
  }

  const dedupe = broadcastDedupeKey(req.broadcastId!);
  const users = req.cursor
    ? await db
        .prepare("SELECT id FROM users WHERE status = 'active' AND id > ? ORDER BY id LIMIT ?")
        .bind(req.cursor, req.batchSize)
        .all<{ id: string }>()
    : await db
        .prepare("SELECT id FROM users WHERE status = 'active' ORDER BY id LIMIT ?")
        .bind(req.batchSize)
        .all<{ id: string }>();
  const ids = users.results.map((u) => u.id);
  if (ids.length === 0) {
    return { status: 200, body: { ok: true, dryRun: false, sent: 0, inboxRows: 0, pushSent: 0, pushConfigured: configured, nextCursor: null } };
  }
  const lo = ids[0];
  const hi = ids[ids.length - 1];

  const insert = db.prepare(
    `INSERT OR IGNORE INTO notifications
      (id, user_id, category, actor_user_id, title, body, dest_type, dest_id, dest_context,
       entity_type, entity_id, dedupe_key, priority, created_at)
     VALUES (?, ?, ?, NULL, ?, ?, ?, NULL, NULL, 'broadcast', ?, ?, 'medium', CURRENT_TIMESTAMP)`,
  );
  const results = await db.batch(
    ids.map((uid) =>
      insert.bind(generateId(), uid, req.category, req.title, req.body, req.dest?.type ?? null, req.broadcastId, dedupe),
    ),
  );
  // Users whose row was newly inserted by THIS call — the only ones we push.
  const fresh = ids.filter((_, i) => ((results[i] as D1Result | undefined)?.meta?.changes ?? 0) > 0);

  // Push selection by id RANGE (D1 caps bound parameters at 100 per query).
  const prefRows = await db
    .prepare(
      `SELECT user_id, push FROM notification_preferences
       WHERE category = ? AND user_id >= ? AND user_id <= ?`,
    )
    .bind(req.category, lo, hi)
    .all<{ user_id: string; push: number }>();
  const pushPref = new Map(prefRows.results.map((r) => [r.user_id, r.push === 1]));
  const defaultPush =
    (CATEGORY_DEFAULTS as Record<string, { push: boolean } | undefined>)[req.category]?.push ?? true;
  const tokenRows = await db
    .prepare(
      `SELECT DISTINCT user_id FROM device_tokens
       WHERE disabled_at IS NULL AND user_id >= ? AND user_id <= ?`,
    )
    .bind(lo, hi)
    .all<{ user_id: string }>();
  const hasToken = new Set(tokenRows.results.map((r) => r.user_id));
  const pushTargets = fresh.filter((uid) => hasToken.has(uid) && (pushPref.get(uid) ?? defaultPush));

  let pushSent = 0;
  let pushFailed = 0;
  const CONCURRENCY = 10;
  for (let i = 0; i < pushTargets.length; i += CONCURRENCY) {
    const settled = await Promise.allSettled(
      pushTargets.slice(i, i + CONCURRENCY).map((uid) =>
        sendPush(env, uid, {
          title: req.title,
          body: req.body,
          category: req.category,
          dest: req.dest ?? undefined,
        }),
      ),
    );
    for (const s of settled) {
      if (s.status === 'fulfilled') pushSent += s.value;
      else pushFailed += 1;
    }
  }

  return {
    status: 200,
    body: {
      ok: true,
      dryRun: false,
      sent: ids.length,
      inboxRows: fresh.length,
      alreadyHad: ids.length - fresh.length,
      pushTargets: pushTargets.length,
      pushSent,
      pushFailed,
      pushConfigured: configured,
      nextCursor: ids.length < req.batchSize ? null : hi,
    },
  };
}
