/**
 * Day streaks — the v13 "streak" stat. A day counts when the member has at
 * least one verified move_log on that local day (the same source and the same
 * `tz` convention as GET /profile/activity: `tz` is the viewer's UTC offset
 * in minutes, clamped to ±840, applied as a sqlite datetime modifier).
 *
 *   streakDays     — consecutive verified days ending today; a streak started
 *                    yesterday is still alive until today ends
 *   bestStreakDays — longest run of consecutive verified days ever
 *   proofsThisWeek — verified proofs in the trailing 7 local days (incl. today)
 */

export interface DayStreaks {
  streakDays: number;
  bestStreakDays: number;
}

/** Parse a `?tz=` query value into a sqlite datetime modifier ('+N minutes'). */
export function tzShift(raw: string | undefined | null): { tz: number; shift: string } {
  const parsed = Math.floor(Number(raw));
  const tz = Number.isFinite(parsed) ? Math.min(Math.max(parsed, -840), 840) : 0;
  return { tz, shift: `${tz >= 0 ? '+' : '-'}${Math.abs(tz)} minutes` };
}

/** Parse a `?days=` query value with the same clamps as /profile/activity. */
export function activityDays(raw: string | undefined | null, fallback = 140): number {
  return Math.min(Math.max(Math.floor(Number(raw)) || fallback, 7), 366);
}

function epochDay(day: string): number {
  return Math.floor(Date.parse(`${day}T00:00:00Z`) / 86_400_000);
}

/**
 * Pure streak math over sorted unique 'YYYY-MM-DD' day strings.
 * `today` is the viewer-local current day in the same format.
 */
export function computeDayStreaks(days: readonly string[], today: string): DayStreaks {
  if (days.length === 0) return { streakDays: 0, bestStreakDays: 0 };
  const todayEp = epochDay(today);
  let best = 1;
  let run = 1;
  for (let i = 1; i < days.length; i++) {
    if (epochDay(days[i]) - epochDay(days[i - 1]) === 1) {
      run += 1;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  const last = epochDay(days[days.length - 1]);
  // A gap > 1 day before today breaks the current streak. Landing on tomorrow
  // is impossible by construction (the query caps at now) but counts anyway.
  const streakDays = todayEp - last <= 1 ? run : 0;
  return { streakDays, bestStreakDays: best };
}

/**
 * Verified days for one member, local-date shifted by `tz` minutes.
 * Returns the streak pair; `days` lists every verified local day ever so the
 * best streak is the true maximum, not a window approximation.
 */
export async function dayStreaksFor(
  db: D1Database,
  userId: string,
  tz: number,
): Promise<DayStreaks & { days: string[] }> {
  const shift = `${tz >= 0 ? '+' : '-'}${Math.abs(tz)} minutes`;
  const { results } = await db
    .prepare(
      `SELECT DISTINCT date(created_at, ?) AS day
         FROM move_logs
        WHERE user_id = ? AND status = 'verified'
        ORDER BY day`,
    )
    .bind(shift, userId)
    .all<{ day: string }>();
  const days = (results ?? []).map((r) => r.day).filter(Boolean);
  const today = await db
    .prepare(`SELECT date('now', ?) AS day`)
    .bind(shift)
    .first<{ day: string }>();
  return { ...computeDayStreaks(days, today?.day ?? ''), days };
}

/** Verified proofs in the trailing `days` local days including today. */
export async function proofsInWindow(
  db: D1Database,
  userId: string,
  tz: number,
  days = 7,
): Promise<number> {
  const shift = `${tz >= 0 ? '+' : '-'}${Math.abs(tz)} minutes`;
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM move_logs
        WHERE user_id = ? AND status = 'verified'
          AND date(created_at, ?) >= date('now', ?, ?)`,
    )
    .bind(userId, shift, shift, `-${days - 1} days`)
    .first<{ n: number }>();
  return row?.n ?? 0;
}
