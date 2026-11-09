/**
 * Onboarding v2 reward — the one-time 100 XP grant made when a new account
 * finishes the guided onboarding. Additive and idempotent: the grant is one
 * row in the existing xp_events ledger keyed (user, 'onboarding_v2',
 * 'onboarding_v2'), so a retry, a second device, or an old build calling
 * POST /onboarding/complete again can never pay twice.
 *
 * 100 XP lands a fresh account on Level 2 (xpForLevel(2) = 60, Level 3 = 180).
 */
import { generateId } from '../lib/crypto';
import { dayStreaksFor } from './dayStreak';
import { levelForXp, reconcileProgression } from './progression';

export const ONBOARDING_XP = 100;
export const ONBOARDING_SOURCE = 'onboarding_v2';
const DAY_ONE_UNLOCK_ID = 'bdg-day-one';

export interface OnboardingReward {
  /** XP paid by THIS call (0 on every call after the first). */
  xpGranted: number;
  totalXp: number;
  level: number;
  previousLevel: number;
  leveledUp: boolean;
  badge: { key: string; name: string } | null;
  /** Current day streak, floored at 1 — finishing onboarding is day one. */
  streakDays: number;
}

export async function grantOnboardingReward(
  db: D1Database,
  userId: string,
): Promise<OnboardingReward> {
  const prior = await db
    .prepare('SELECT total_xp, level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ total_xp: number; level: number }>();

  const ins = await db
    .prepare(
      `INSERT OR IGNORE INTO xp_events (id, user_id, source_type, source_id, race_id, xp_amount, created_at)
       VALUES (?, ?, ?, ?, NULL, ?, CURRENT_TIMESTAMP)`,
    )
    .bind(generateId(), userId, ONBOARDING_SOURCE, ONBOARDING_SOURCE, ONBOARDING_XP)
    .run();
  const granted = (ins.meta?.changes ?? 0) > 0;

  // Reconcile recomputes total/level from the whole ledger (it sums every
  // xp_events row, ours included) and grants any level-gated unlocks.
  const rec = await reconcileProgression(db, userId);
  const row = await db
    .prepare('SELECT total_xp FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ total_xp: number }>();
  const totalXp = row?.total_xp ?? ONBOARDING_XP;
  const level = levelForXp(totalXp).level;

  // Day One badge: only ever granted here. Tolerates a missing 0052 seed
  // (migration not yet applied) so the XP grant above is never lost.
  let badge: { key: string; name: string } | null = null;
  try {
    await db
      .prepare(
        `INSERT OR IGNORE INTO user_unlocks (id, user_id, unlock_id, unlocked_at, source)
         VALUES (?, ?, ?, CURRENT_TIMESTAMP, 'onboarding')`,
      )
      .bind(generateId(), userId, DAY_ONE_UNLOCK_ID)
      .run();
    badge = await db
      .prepare(
        `SELECT d.unlock_key AS key, d.name AS name FROM user_unlocks u
         JOIN unlock_definitions d ON d.id = u.unlock_id
         WHERE u.user_id = ? AND u.unlock_id = ?`,
      )
      .bind(userId, DAY_ONE_UNLOCK_ID)
      .first<{ key: string; name: string }>();
  } catch {
    badge = null;
  }

  let streakDays = 0;
  try {
    streakDays = (await dayStreaksFor(db, userId, 0)).streakDays;
  } catch {
    streakDays = 0;
  }

  const previousLevel = granted ? (prior?.level ?? rec.previousLevel ?? 1) : level;
  return {
    xpGranted: granted ? ONBOARDING_XP : 0,
    totalXp,
    level,
    previousLevel,
    leveledUp: granted && level > previousLevel,
    badge: badge ?? null,
    streakDays: Math.max(1, streakDays),
  };
}
