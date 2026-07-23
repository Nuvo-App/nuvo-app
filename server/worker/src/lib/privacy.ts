/**
 * Privacy helpers for private-profile enforcement, crew/connection checks,
 * and user anonymization in shared contexts.
 */

export async function isProfilePrivate(db: D1Database, userId: string): Promise<boolean> {
  const row = await db
    .prepare('SELECT private_profile FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<{ private_profile: number }>();
  return Boolean(row?.private_profile);
}

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
  const isPublic = !(await isProfilePrivate(db, targetUserId));
  if (isPublic) return true;
  return await isConnected(db, viewerUserId, targetUserId);
}

export interface AnonymizedUser {
  displayName: string;
  username: string | null;
  profilePhotoUrl: null;
  isPrivate: true;
}

export function anonymizeUser(): AnonymizedUser {
  return {
    displayName: 'Private User',
    username: null,
    profilePhotoUrl: null,
    isPrivate: true,
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
  return { ...anonymizeUser(), isPrivate: true };
}
