/**
 * Nuvo Levels — persistent player progression as a PROJECTION of canonical
 * race_events. Race truth is written first (applyMoveProgress /
 * finalizeRaceIfEnded); XP derives from the durable event log afterwards.
 * A progression failure can never fail a race action, and the same reconcile
 * pass serves live play and historical backfill, so the two paths cannot
 * diverge or double-award (xp_events is unique per canonical event).
 */
import { generateId } from '../lib/crypto';

// ── XP awards ─────────────────────────────────────────────────────────────────
// Canonical event_type → award. Winning accelerates progression; it never
// gates it — a consistent racer levels up without a single win.
export const XP_AWARDS: Record<string, number> = {
  progress_accepted: 10,
  participant_finished: 25,
  winner_determined: 10,
  personal_best: 5,
};
const XP_SOURCE_TYPES = Object.keys(XP_AWARDS);

// ── Level curve ───────────────────────────────────────────────────────────────
// Single deterministic curve — tune here, nowhere else. Cumulative XP needed
// to BE level n: linear + quadratic growth, intentionally not exponential.
//   levelUpCost(n→n+1) = LEVEL_BASE + LEVEL_GROWTH * (n - 1)
//   xpForLevel(n)      = Σ = LEVEL_BASE*(n-1) + LEVEL_GROWTH/2 *(n-1)(n-2)
const LEVEL_BASE = 60;
const LEVEL_GROWTH = 60;

/** Cumulative total XP required to reach `level` (level 1 = 0 XP). */
export function xpForLevel(level: number): number {
  if (level <= 1) return 0;
  const k = level - 1;
  return LEVEL_BASE * k + (LEVEL_GROWTH / 2) * k * (k - 1);
}

export interface LevelProgress {
  level: number;
  /** XP earned inside the current level. */
  currentLevelXp: number;
  /** XP required to leave the current level. */
  nextLevelXp: number;
  /** 0..1 fill for the progress bar. */
  progress: number;
}

export function levelForXp(totalXp: number): LevelProgress {
  let level = 1;
  while (xpForLevel(level + 1) <= totalXp) level++;
  const floor = xpForLevel(level);
  const span = xpForLevel(level + 1) - floor;
  return {
    level,
    currentLevelXp: totalXp - floor,
    nextLevelXp: span,
    progress: span > 0 ? (totalXp - floor) / span : 0,
  };
}

// ── Rows ──────────────────────────────────────────────────────────────────────
interface ProgressionRow {
  user_id: string;
  total_xp: number;
  level: number;
  last_seen_level: number;
}

export interface UnlockRow {
  id: string;
  required_level: number;
  unlock_type: string;
  unlock_key: string;
  name: string;
  description: string | null;
  metadata_json: string | null;
}

export interface ReconcileResult {
  totalXp: number;
  level: number;
  previousLevel: number;
  newUnlockIds: string[];
}

/**
 * Project un-awarded canonical race events for one user into xp_events,
 * recompute cached totals, and grant any level unlocks now reached.
 * INSERT OR IGNORE on the unique (user, source_type, source_id) key makes
 * every caller — live path, backfill, retry — safely idempotent.
 */
export async function reconcileProgression(
  db: D1Database,
  userId: string,
): Promise<ReconcileResult> {
  const prior = await db
    .prepare('SELECT level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ level: number }>();
  const previousLevel = prior?.level ?? 1;

  const events = await db
    .prepare(
      `SELECT id, event_type, race_id FROM race_events
       WHERE subject_user_id = ? AND event_type IN (${XP_SOURCE_TYPES.map(() => '?').join(',')})
       ORDER BY created_at ASC`,
    )
    .bind(userId, ...XP_SOURCE_TYPES)
    .all<{ id: string; event_type: string; race_id: string }>();

  if (events.results.length > 0) {
    await db.batch(
      events.results.map((e) =>
        db
          .prepare(
            `INSERT OR IGNORE INTO xp_events (id, user_id, source_type, source_id, race_id, xp_amount, created_at)
             VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
          )
          .bind(generateId(), userId, e.event_type, e.id, e.race_id, XP_AWARDS[e.event_type] ?? 0),
      ),
    );
  }

  const totals = await db
    .prepare('SELECT COALESCE(SUM(xp_amount), 0) AS total FROM xp_events WHERE user_id = ?')
    .bind(userId)
    .first<{ total: number }>();
  const totalXp = totals?.total ?? 0;
  const level = levelForXp(totalXp).level;

  await db
    .prepare(
      `INSERT INTO user_progression (user_id, total_xp, level, last_seen_level, created_at, updated_at)
       VALUES (?, ?, ?, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id) DO UPDATE SET
         total_xp = excluded.total_xp,
         level = excluded.level,
         updated_at = CURRENT_TIMESTAMP`,
    )
    .bind(userId, totalXp, level)
    .run();

  // Grant every active definition at or below the user's level. Idempotent —
  // re-runs unlock nothing twice.
  const defs = await db
    .prepare('SELECT id FROM unlock_definitions WHERE required_level <= ? AND active = 1')
    .bind(level)
    .all<{ id: string }>();
  const newUnlockIds: string[] = [];
  if (defs.results.length > 0) {
    const stmts = defs.results.map((d) =>
      db
        .prepare(
          `INSERT OR IGNORE INTO user_unlocks (id, user_id, unlock_id, unlocked_at, source)
           VALUES (?, ?, ?, CURRENT_TIMESTAMP, 'level')`,
        )
        .bind(generateId(), userId, d.id),
    );
    const results = await db.batch(stmts);
    results.forEach((r, i) => {
      if ((r.meta.changes ?? 0) > 0) newUnlockIds.push(defs.results[i].id);
    });
  }

  return { totalXp, level, previousLevel, newUnlockIds };
}

// ── Reads ─────────────────────────────────────────────────────────────────────
export interface ProgressionPayload {
  level: number;
  totalXp: number;
  currentLevelXp: number;
  nextLevelXp: number;
  progress: number;
  xpToNext: number;
  lastSeenLevel: number;
  nextUnlock: {
    unlockId: string;
    level: number;
    type: string;
    key: string;
    name: string;
    description: string | null;
    metadata: Record<string, unknown> | null;
  } | null;
  /** The unlock granted at the current level — what the level-up moment
   *  celebrates. Null when the current level carries no reward. */
  levelUnlock: BadgeView | null;
  featuredBadges: BadgeView[];
}

export interface BadgeView {
  unlockId: string;
  type: string;
  key: string;
  name: string;
  description: string | null;
  requiredLevel: number;
  metadata: Record<string, unknown> | null;
  unlocked: boolean;
  unlockedAt: string | null;
  featured: boolean;
  position: number | null;
}

function parseMetadata(json: string | null): Record<string, unknown> | null {
  if (!json) return null;
  try {
    const parsed = JSON.parse(json) as unknown;
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function badgeView(
  def: UnlockRow,
  ownedAt: string | null,
  featuredPosition: number | null,
): BadgeView {
  return {
    unlockId: def.id,
    type: def.unlock_type,
    key: def.unlock_key,
    name: def.name,
    description: def.description,
    requiredLevel: def.required_level,
    metadata: parseMetadata(def.metadata_json),
    unlocked: ownedAt !== null,
    unlockedAt: ownedAt,
    featured: featuredPosition !== null,
    position: featuredPosition,
  };
}

/**
 * Authoritative progression read. Always reconciles first — the projection
 * is self-healing, so a missed post-write reconcile can never leave the
 * user stuck at a stale level.
 */
export async function readProgression(
  db: D1Database,
  userId: string,
): Promise<ProgressionPayload> {
  await reconcileProgression(db, userId);

  const row = await db
    .prepare('SELECT user_id, total_xp, level, last_seen_level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<ProgressionRow>();
  const totalXp = row?.total_xp ?? 0;
  const lp = levelForXp(totalXp);

  const nextDef = await db
    .prepare(
      `SELECT * FROM unlock_definitions
       WHERE active = 1 AND required_level > ? AND
             id NOT IN (SELECT unlock_id FROM user_unlocks WHERE user_id = ?)
       ORDER BY required_level ASC, unlock_type, unlock_key LIMIT 1`,
    )
    .bind(lp.level, userId)
    .first<UnlockRow>();

  const levelUnlock = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at FROM user_unlocks u
       JOIN unlock_definitions d ON d.id = u.unlock_id
       WHERE u.user_id = ? AND d.required_level = ? AND d.active = 1
       ORDER BY d.unlock_type, d.unlock_key LIMIT 1`,
    )
    .bind(userId, lp.level)
    .first<UnlockRow & { owned_at: string | null }>();

  const featuredRows = await db
    .prepare(
      `SELECT d.*, f.position, u.unlocked_at AS owned_at FROM user_featured_badges f
       JOIN unlock_definitions d ON d.id = f.unlock_id
       LEFT JOIN user_unlocks u ON u.unlock_id = d.id AND u.user_id = f.user_id
       WHERE f.user_id = ? ORDER BY f.position ASC`,
    )
    .bind(userId)
    .all<UnlockRow & { position: number; owned_at: string | null }>();

  return {
    level: lp.level,
    totalXp,
    currentLevelXp: lp.currentLevelXp,
    nextLevelXp: lp.nextLevelXp,
    progress: lp.progress,
    xpToNext: xpForLevel(lp.level + 1) - totalXp,
    lastSeenLevel: row?.last_seen_level ?? 1,
    nextUnlock: nextDef
      ? {
          unlockId: nextDef.id,
          level: nextDef.required_level,
          type: nextDef.unlock_type,
          key: nextDef.unlock_key,
          name: nextDef.name,
          description: nextDef.description,
          metadata: parseMetadata(nextDef.metadata_json),
        }
      : null,
    levelUnlock: levelUnlock
      ? badgeView(levelUnlock, levelUnlock.owned_at, null)
      : null,
    featuredBadges: featuredRows.results.map((d) =>
      badgeView(d, d.owned_at, d.position),
    ),
  };
}

/** Full badge collection — unlocked and locked with their requirements. */
export async function readBadgeCollection(
  db: D1Database,
  userId: string,
): Promise<BadgeView[]> {
  await reconcileProgression(db, userId);
  const rows = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at, f.position AS featured_position
       FROM unlock_definitions d
       LEFT JOIN user_unlocks u ON u.unlock_id = d.id AND u.user_id = ?
       LEFT JOIN user_featured_badges f ON f.unlock_id = d.id AND f.user_id = ?
       WHERE d.active = 1
       ORDER BY d.required_level ASC, d.unlock_key ASC`,
    )
    .bind(userId, userId)
    .all<UnlockRow & { owned_at: string | null; featured_position: number | null }>();
  return rows.results.map((d) => badgeView(d, d.owned_at, d.featured_position));
}

export const FEATURED_BADGE_SLOTS = 3;

/**
 * Replace the user's featured set. Server-side validation: every unlock must
 * be owned, be a badge-type unlock, dedupe, and fit the slot count.
 */
export async function setFeaturedBadges(
  db: D1Database,
  userId: string,
  unlockIds: string[],
): Promise<{ ok: true } | { ok: false; error: string }> {
  await reconcileProgression(db, userId);
  const deduped = [...new Set(unlockIds)];
  if (deduped.length !== unlockIds.length) {
    return { ok: false, error: 'Duplicate badges are not allowed' };
  }
  if (deduped.length > FEATURED_BADGE_SLOTS) {
    return { ok: false, error: `You can feature up to ${FEATURED_BADGE_SLOTS} badges` };
  }
  for (const id of deduped) {
    const owned = await db
      .prepare(
        `SELECT 1 AS yes FROM user_unlocks u
         JOIN unlock_definitions d ON d.id = u.unlock_id
         WHERE u.user_id = ? AND u.unlock_id = ? AND d.unlock_type = 'badge'`,
      )
      .bind(userId, id)
      .first<{ yes: number }>();
    if (!owned) return { ok: false, error: 'Badge not unlocked' };
  }
  const stmts = [
    db.prepare('DELETE FROM user_featured_badges WHERE user_id = ?').bind(userId),
    ...deduped.map((id, i) =>
      db
        .prepare(
          `INSERT INTO user_featured_badges (user_id, unlock_id, position, updated_at)
           VALUES (?, ?, ?, CURRENT_TIMESTAMP)`,
        )
        .bind(userId, id, i),
    ),
  ];
  await db.batch(stmts);
  return { ok: true };
}

/** Acknowledge the level-up presentation once — never replays per level. */
export async function markLevelSeen(db: D1Database, userId: string): Promise<void> {
  await db
    .prepare(
      `UPDATE user_progression SET last_seen_level = level, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = ?`,
    )
    .bind(userId)
    .run();
}

/** Level for display on other users' surfaces — read-only, no reconcile. */
export async function publicLevelFor(
  db: D1Database,
  userId: string,
): Promise<number> {
  const row = await db
    .prepare('SELECT level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ level: number }>();
  return row?.level ?? 1;
}
