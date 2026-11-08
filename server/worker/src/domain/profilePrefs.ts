/**
 * v13 profile preferences (migration 0048): bio, favorite movement, and the
 * two privacy prefs — "show my activity map" and "who can race me".
 *
 * Reads always go through `SELECT *` so a database that predates 0048 still
 * answers with defaults instead of throwing on an unknown column — the same
 * deploy-order tolerance the motion-registry fallback uses. Writes of the
 * columns happen only when the client actually sends a field.
 *
 * Note: `raceInvitesFrom` still round-trips (old app builds may send or show
 * it), but anyone can race anyone — nothing on the race paths consults it.
 */

export type RaceInvitesFrom = 'everyone' | 'friends';

export interface ProfilePrefs {
  bio: string | null;
  favoriteMovementKey: string | null;
  /** false = GET /users/:id/activity returns an empty map with shared:false. */
  activityMapShared: boolean;
  /** Stored for old app builds only — no race path enforces it. */
  raceInvitesFrom: RaceInvitesFrom;
}

const DEFAULTS: ProfilePrefs = {
  bio: null,
  favoriteMovementKey: null,
  activityMapShared: true,
  raceInvitesFrom: 'everyone',
};

/** Any row that may carry the 0048 columns — a ProfileRow or a SELECT * row. */
export type PrefsSource = {
  bio?: unknown;
  favorite_movement_key?: unknown;
  activity_map_shared?: unknown;
  race_invites_from?: unknown;
} | null | undefined;

/**
 * Normalize a `profiles` row (or any SELECT * superset) into prefs. Columns
 * absent on a pre-0048 schema read as undefined and fall back to defaults.
 */
export function prefsFromRow(row: PrefsSource): ProfilePrefs {
  if (!row) return { ...DEFAULTS };
  return {
    bio: typeof row.bio === 'string' ? row.bio : null,
    favoriteMovementKey:
      typeof row.favorite_movement_key === 'string' ? row.favorite_movement_key : null,
    activityMapShared: row.activity_map_shared === undefined ? true : row.activity_map_shared === 1,
    raceInvitesFrom: row.race_invites_from === 'friends' ? 'friends' : 'everyone',
  };
}

export async function readProfilePrefs(db: D1Database, userId: string): Promise<ProfilePrefs> {
  const row = await db
    .prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<Record<string, unknown>>();
  return prefsFromRow(row);
}


