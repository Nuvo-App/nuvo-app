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
