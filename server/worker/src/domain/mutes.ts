/**
 * Mutes (user_mutes, migration 0048) — a viewer's invisible filter. Muting
 * never notifies the target, never blocks them, and never changes what they
 * can do; it only removes their activity from the muter's feed and
 * notifications.
 *
 * Every READ here tolerates a schema that predates 0048: a missing table
 * means "no mutes exist", never a 500. That keeps older minimal test schemas
 * and a deploy-before-migrate window safe — the same tolerance the
 * motion-registry fallback uses for its table.
 */
import { generateId } from '../lib/crypto';

export type MuteTargetType = 'user' | 'crew';

/** True when `ownerUserId` has muted `targetUserId` (target_type 'user'). */
export async function isUserMuted(
  db: D1Database,
  ownerUserId: string,
  targetUserId: string,
): Promise<boolean> {
  try {
    const row = await db
      .prepare(
        "SELECT id FROM user_mutes WHERE user_id = ? AND target_type = 'user' AND target_id = ?",
      )
      .bind(ownerUserId, targetUserId)
      .first<{ id: string }>();
    return Boolean(row);
  } catch {
    return false;
  }
}

/**
 * A (count, latest) stamp of the owner's mutes of `targetType` — feeds
 * feed-etag inputs and decides whether a mute subquery may run at all.
 * {0, null} when the table is absent or empty.
 */
export async function muteStamp(
  db: D1Database,
  ownerUserId: string,
  targetType: MuteTargetType,
): Promise<{ n: number; latest: string | null }> {
  try {
    const row = await db
      .prepare(
        'SELECT COUNT(*) AS n, MAX(created_at) AS latest FROM user_mutes WHERE user_id = ? AND target_type = ?',
      )
      .bind(ownerUserId, targetType)
      .first<{ n: number; latest: string | null }>();
    return { n: row?.n ?? 0, latest: row?.latest ?? null };
  } catch {
    return { n: 0, latest: null };
  }
}

/**
 * SQL fragment excluding items whose actor the viewer muted. Only call when
 * {@link muteStamp} reports mutes exist — otherwise the clause is skipped
 * entirely and a pre-0048 schema never sees the table name.
 */
export const MUTE_ACTOR_EXCLUSION = (actorColumn: string) =>
  `(${actorColumn} IS NULL OR ${actorColumn} NOT IN (
     SELECT target_id FROM user_mutes WHERE user_id = ? AND target_type = 'user'))`;

/**
 * SQL fragment excluding items tied to a muted crew's races — the race lives
 * in squad_races (0046), the mute in user_mutes (0048); both exist wherever
 * this clause is allowed to run.
 */
export const MUTE_RACE_EXCLUSION = (raceIdColumn: string) =>
  `(${raceIdColumn} IS NULL OR ${raceIdColumn} NOT IN (
     SELECT sr.race_id FROM squad_races sr
     JOIN user_mutes um ON um.target_id = sr.squad_id
     WHERE um.user_id = ? AND um.target_type = 'crew'))`;

// ── Writes (new endpoint — requires 0048, like every new feature) ─────────────

export async function muteTarget(
  db: D1Database,
  userId: string,
  targetType: MuteTargetType,
  targetId: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT OR IGNORE INTO user_mutes (id, user_id, target_type, target_id, created_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
    )
    .bind(generateId(), userId, targetType, targetId)
    .run();
}

export async function unmuteTarget(
  db: D1Database,
  userId: string,
  targetType: MuteTargetType,
  targetId: string,
): Promise<void> {
  await db
    .prepare('DELETE FROM user_mutes WHERE user_id = ? AND target_type = ? AND target_id = ?')
    .bind(userId, targetType, targetId)
    .run();
}
