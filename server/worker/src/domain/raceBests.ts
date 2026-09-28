/**
 * Personal bests — beating yourself counts even when you don't win
 * (docs/agents/21-race-system-v2-design.md §34). Written by the scoring
 * path on verified submissions to attempt-format races.
 */
import { generateId } from '../lib/crypto';
import type { RaceRow } from '../types';

export interface PersonalBestResult {
  improved: boolean;
  previousBest: number | null;
  newBest: number;
}

function activityKey(race: RaceRow): string | null {
  if (race.activity_id) return race.activity_id;
  if (race.custom_activity_name) return `custom:${race.custom_activity_name}`;
  if (race.verifier_type === 'manual_log') return `manual:${race.target_unit ?? 'done'}`;
  return null;
}

/**
 * Update personal_bests when a verified submission beats the user's record
 * for (activity, metric). Direction-aware: 'lower' (fastest) improves when
 * the new value is smaller. Returns whether this submission set a new best.
 */
export async function recordPersonalBestIfImproved(
  db: D1Database,
  race: RaceRow,
  userId: string,
  value: number,
  moveLogId: string,
): Promise<PersonalBestResult> {
  const key = activityKey(race);
  const metric = race.metric ?? race.target_unit ?? 'reps';
  if (!key || value <= 0) return { improved: false, previousBest: null, newBest: value };

  const direction = race.score_direction === 'lower' ? 'lower' : 'higher';
  const existing = await db
    .prepare(
      'SELECT id, best_value FROM personal_bests WHERE user_id = ? AND activity_id = ? AND metric = ?',
    )
    .bind(userId, key, metric)
    .first<{ id: string; best_value: number }>();

  if (!existing) {
    await db
      .prepare(
        `INSERT INTO personal_bests (id, user_id, activity_id, metric, best_value, score_direction, race_id, move_log_id, set_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), userId, key, metric, value, direction, race.id, moveLogId)
      .run();
    return { improved: true, previousBest: null, newBest: value };
  }

  const better = direction === 'lower' ? value < existing.best_value : value > existing.best_value;
  if (!better) return { improved: false, previousBest: existing.best_value, newBest: existing.best_value };

  await db
    .prepare(
      'UPDATE personal_bests SET best_value = ?, race_id = ?, move_log_id = ?, set_at = CURRENT_TIMESTAMP WHERE id = ?',
    )
    .bind(value, race.id, moveLogId, existing.id)
    .run();
  return { improved: true, previousBest: existing.best_value, newBest: value };
}

/**
 * Rebuild a user's personal best for one race's (activity, metric) from their
 * remaining verified attempt submissions. Called after a proof is invalidated
 * (veto / review reject) — if the vetoed move set the record, the PB falls
 * back to the best still-valid submission, or the row is removed entirely.
 * Mirrors recordPersonalBestIfImproved's scope: attempt formats only.
 */
export async function reconcilePersonalBest(
  db: D1Database,
  race: RaceRow,
  userId: string,
): Promise<void> {
  const key = activityKey(race);
  const metric = race.metric ?? race.target_unit ?? 'reps';
  if (!key) return;

  const existing = await db
    .prepare('SELECT id, score_direction FROM personal_bests WHERE user_id = ? AND activity_id = ? AND metric = ?')
    .bind(userId, key, metric)
    .first<{ id: string; score_direction: string | null }>();
  if (!existing) return;

  const direction = existing.score_direction === 'lower' ? 'lower' : 'higher';
  const moves = await db
    .prepare(
      `SELECT ml.id AS move_id, ml.race_id, ml.value FROM move_logs ml
       JOIN races r ON r.id = ml.race_id
       WHERE ml.user_id = ? AND ml.status = 'verified'
         AND COALESCE(
               r.activity_id,
               CASE WHEN r.custom_activity_name IS NOT NULL THEN 'custom:' || r.custom_activity_name END,
               CASE WHEN r.verifier_type = 'manual_log' THEN 'manual:' || COALESCE(r.target_unit, 'done') END
             ) = ?
         AND COALESCE(r.metric, r.target_unit, 'reps') = ?
         AND COALESCE(r.format, r.race_type) IN ('best_attempt', 'timed_attempt')`,
    )
    .bind(userId, key, metric)
    .all<{ move_id: string; race_id: string; value: number | null }>();

  let best: { move_id: string; race_id: string; value: number } | null = null;
  for (const m of moves.results) {
    const v = m.value ?? 0;
    if (v <= 0) continue;
    if (!best || (direction === 'lower' ? v < best.value : v > best.value)) {
      best = { move_id: m.move_id, race_id: m.race_id, value: v };
    }
  }

  if (!best) {
    await db.prepare('DELETE FROM personal_bests WHERE id = ?').bind(existing.id).run();
    return;
  }
  await db
    .prepare('UPDATE personal_bests SET best_value = ?, race_id = ?, move_log_id = ?, set_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(best.value, best.race_id, best.move_id, existing.id)
    .run();
}
