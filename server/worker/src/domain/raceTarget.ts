/**
 * Only a race to a goal has a finish line. Window / attempt races ("most in an
 * hour", best single attempt, timed attempt) are decided by score, so any
 * stored target on them is a client placeholder and must never be shown,
 * scored against, or treated as a reason to finish the race.
 */
export function raceHasFinishLine(format: string | null | undefined): boolean {
  return !format || format === 'first_to_goal' || format === 'first_to_target';
}

/** The target to expose / score against, or null when the format has none. */
export function effectiveTargetValue(
  format: string | null | undefined,
  target: number | null | undefined,
): number | null {
  return raceHasFinishLine(format) && target != null && target > 0 ? target : null;
}
