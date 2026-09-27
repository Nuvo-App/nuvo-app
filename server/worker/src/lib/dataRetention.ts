/**
 * Retention enforcement for the durations already promised publicly —
 * this is the machinery that makes the numbers true rather than aspirational.
 *
 *  - email_codes: OTP rows die <= 24h after they expire or are used.
 *  - sessions: expired or revoked sessions die <= 30 days after expiry/revocation.
 *
 * Ran once daily from the '0 3 * * *' cron alongside the motion-data purge.
 * Anything without a stated retention number is intentionally NOT purged here.
 */
import type { D1Database } from '@cloudflare/workers-types';

export async function purgeExpiredAuthData(
  db: D1Database,
): Promise<{ emailCodes: number; sessions: number }> {
  const codes = await db
    .prepare(
      `DELETE FROM email_codes
       WHERE expires_at < datetime('now', '-1 day')
          OR (used_at IS NOT NULL AND used_at < datetime('now', '-1 day'))`,
    )
    .run();
  const sessions = await db
    .prepare(
      `DELETE FROM sessions
       WHERE expires_at < datetime('now', '-30 days')
          OR (revoked_at IS NOT NULL AND revoked_at < datetime('now', '-30 days'))`,
    )
    .run();
  return {
    emailCodes: codes.meta.changes ?? 0,
    sessions: sessions.meta.changes ?? 0,
  };
}
