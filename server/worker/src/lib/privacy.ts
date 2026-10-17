/**
 * Privacy helpers for block enforcement, crew/connection checks, and user
 * anonymization. There is no such thing as a private profile: everyone is
 * visible to everyone except people who have blocked each other.
 */

export async function isConnected(
  db: D1Database,
  viewerUserId: string,
  targetUserId: string,
): Promise<boolean> {
  if (viewerUserId === targetUserId) return true;
  const row = await db
    .prepare(
      `SELECT id FROM crew_connections
       WHERE user_id = ? AND crew_user_id = ? AND status = 'active'`,
    )
    .bind(viewerUserId, targetUserId)
    .first<{ id: string }>();
  return Boolean(row);
}

export async function isBlocked(
  db: D1Database,
  viewerUserId: string,
  targetUserId: string,
): Promise<boolean> {
  const row = await db
    .prepare('SELECT id FROM blocked_users WHERE user_id = ? AND blocked_user_id = ?')
    .bind(viewerUserId, targetUserId)
    .first<{ id: string }>();
  return Boolean(row);
}

export async function canViewFullProfile(
  db: D1Database,
  viewerUserId: string,
  targetUserId: string,
): Promise<boolean> {
  if (viewerUserId === targetUserId) return true;
  if (await isBlocked(db, targetUserId, viewerUserId)) return false;
  if (await isBlocked(db, viewerUserId, targetUserId)) return false;
  return true;
}

/**
 * Race-identity visibility policy — the single source of truth for what a
 * viewer sees for another user inside a race.
 *
 * Rules:
 *  - self / no viewer            → real name + photo
 *  - blocked (either direction)  → anonymized
 *  - everyone else               → real name + photo
 */
export function resolveRaceMemberVisibility(
  viewerUserId: string | undefined,
  target: {
    userId: string | null;
    displayName: string | null;
    username: string | null;
    profilePhotoUrl: string | null;
  },
  ctx: {
    crewIds: Set<string>;
    blockedEitherWay: Set<string>;
    coRacerIds: Set<string>; // participants of the shared race, if viewer is in it
  },
): { displayName: string; profilePhotoUrl: string | null; anonymized: boolean } {
  const realName =
    (target.displayName ?? '').trim() && (target.displayName ?? '').trim() !== 'Unknown'
      ? (target.displayName as string).trim()
      : (target.username ?? '').trim() || 'Nuvo member';

  if (!viewerUserId || !target.userId || target.userId === viewerUserId) {
    return { displayName: realName, profilePhotoUrl: target.profilePhotoUrl, anonymized: false };
  }
  if (ctx.blockedEitherWay.has(target.userId)) {
    return { displayName: 'Private User', profilePhotoUrl: null, anonymized: true };
  }
  return { displayName: realName, profilePhotoUrl: target.profilePhotoUrl, anonymized: false };
}

export interface AnonymizedUser {
  displayName: string;
  username: string | null;
  profilePhotoUrl: null;
  isPrivate: false; // legacy key kept for older app builds; always false
}

export function anonymizeUser(): AnonymizedUser {
  return {
    displayName: 'Private User',
    username: null,
    profilePhotoUrl: null,
    isPrivate: false,
  };
}

export async function getVisibleUserFields(
  db: D1Database,
  viewerUserId: string,
  targetUserId: string,
  displayName: string | null,
  username: string | null,
  profilePhotoUrl: string | null,
): Promise<{ displayName: string; username: string | null; profilePhotoUrl: string | null; isPrivate: boolean }> {
  if (await canViewFullProfile(db, viewerUserId, targetUserId)) {
    return {
      displayName: displayName ?? username ?? 'Nuvo member',
      username,
      profilePhotoUrl,
      isPrivate: false,
    };
  }
  return anonymizeUser();
}
