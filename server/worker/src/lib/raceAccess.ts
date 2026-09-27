/**
 * Canonical race-access authorization — the ONE place "who may see / enter
 * this race" is decided. Every race route resolves access through
 * `resolveRaceAccess` (reads) or `checkRaceJoinEligibility` (entries); do not
 * re-implement these rules per endpoint.
 *
 * Read levels:
 *   owner       — race creator; full read + invite code
 *   member      — active race_member; full read + invite code
 *   crew        — creator's crew reading a crew_only race (no invite code)
 *   public      — any signed-in user reading a public_demo race
 *   denied      — no read
 *
 * Denial returns the same 404 body as a missing race so existence itself is
 * not disclosed.
 */
import type { D1Database } from '@cloudflare/workers-types';

export type RaceAccessLevel = 'owner' | 'member' | 'crew' | 'public' | 'denied';

export interface RaceAccess {
  level: RaceAccessLevel;
  /** owner + member + crew + public — the race body may be returned. */
  canRead: boolean;
  /** owner + member — insider data (invite code, live feed, event log). */
  isInsider: boolean;
  /** active race_members row exists (member-level, excludes owner). */
  isMember: boolean;
  isOwner: boolean;
}

interface RaceAccessRow {
  id: string;
  creator_id: string;
  visibility: string;
}

export async function isBlockedEitherWay(
  db: D1Database,
  userA: string,
  userB: string,
): Promise<boolean> {
  const row = await db
    .prepare(
      `SELECT id FROM blocked_users
       WHERE (user_id = ? AND blocked_user_id = ?)
          OR (user_id = ? AND blocked_user_id = ?)`,
    )
    .bind(userA, userB, userB, userA)
    .first<{ id: string }>();
  return Boolean(row);
}

export async function isCrewOf(
  db: D1Database,
  viewerUserId: string,
  targetUserId: string,
): Promise<boolean> {
  const row = await db
    .prepare(
      `SELECT id FROM crew_connections
       WHERE status = 'active'
         AND ((user_id = ? AND crew_user_id = ?)
           OR (user_id = ? AND crew_user_id = ?))`,
    )
    .bind(viewerUserId, targetUserId, targetUserId, viewerUserId)
    .first<{ id: string }>();
  return Boolean(row);
}

export async function resolveRaceAccess(
  db: D1Database,
  race: RaceAccessRow,
  userId: string,
): Promise<RaceAccess> {
  const done = (level: RaceAccessLevel, isMember = false): RaceAccess => {
    const isOwner = level === 'owner';
    return {
      level,
      canRead: level !== 'denied',
      isInsider: isOwner || level === 'member',
      isMember: isMember || isOwner,
      isOwner,
    };
  };

  if (race.creator_id === userId) return done('owner');

  const member = await db
    .prepare(
      `SELECT id FROM race_members
       WHERE race_id = ? AND user_id = ? AND status = 'active'`,
    )
    .bind(race.id, userId)
    .first<{ id: string }>();
  if (member) return done('member', true);

  // A block with the creator in either direction closes the race entirely —
  // a blocked user must not read or join through any visibility path.
  if (await isBlockedEitherWay(db, userId, race.creator_id)) return done('denied');

  if (race.visibility === 'public_demo') return done('public');
  if (race.visibility === 'crew_only' && (await isCrewOf(db, userId, race.creator_id))) {
    return done('crew');
  }
  // private + invite_code races are only readable after membership — the
  // invite code is redeemed through /join-code which creates membership
  // first, so nothing here needs to hand the race body to an outsider.
  return done('denied');
}

export type RaceJoinEligibility =
  | { ok: true }
  | { ok: false; error: string; status: number };

/**
 * Entry policy shared by every path that creates race_membership:
 * /:id/join, /join-code (after code validation), /:id/move-log auto-join.
 * Existing members are always eligible.
 */
export async function checkRaceJoinEligibility(
  db: D1Database,
  race: RaceAccessRow & { status: string; public_join_enabled: number | null },
  userId: string,
): Promise<RaceJoinEligibility> {
  const member = await db
    .prepare(
      `SELECT id FROM race_members
       WHERE race_id = ? AND user_id = ? AND status = 'active'`,
    )
    .bind(race.id, userId)
    .first<{ id: string }>();
  if (member || race.creator_id === userId) return { ok: true };

  if (await isBlockedEitherWay(db, userId, race.creator_id)) {
    return { ok: false, error: 'You cannot join this race', status: 403 };
  }

  switch (race.visibility) {
    case 'private':
    case 'invite_code':
      return {
        ok: false,
        error: 'Use an invite code to join this race',
        status: 403,
      };
    case 'crew_only':
      return (await isCrewOf(db, userId, race.creator_id))
        ? { ok: true }
        : { ok: false, error: 'This race is only open to the crew', status: 403 };
    case 'public_demo':
      return race.public_join_enabled
        ? { ok: true }
        : { ok: false, error: 'Joining is not enabled for this public race', status: 403 };
    default:
      return { ok: false, error: 'This race is not open to join', status: 403 };
  }
}
