/**
 * Friendship badges — the per-pair achievements v13 shows on a connected
 * member's profile ("First race", "Rivals", ...). These are computed display
 * objects, deliberately NOT unlock_definitions rows: they describe one
 * friendship, not a member's global record.
 */

export interface FriendshipBadge {
  key: string;
  name: string;
  description: string;
  earned: boolean;
  progress: number;
  threshold: number;
}

export interface Friendship {
  connectedSince: string;
  badges: FriendshipBadge[];
}

interface BadgeDef {
  key: string;
  name: string;
  description: string;
  threshold: number;
  value: (f: FriendshipFacts) => number;
}

export interface FriendshipFacts {
  /** Completed races both members were on the roster of. */
  racesTogether: number;
  /** Reactions either member left on the other's activity. */
  pairReactions: number;
  /** Whole days the pair has been connected. */
  daysConnected: number;
  /** Current day streaks of each member (viewer-local tz). */
  streakYou: number;
  streakThem: number;
}

const DEFS: BadgeDef[] = [
  {
    key: 'first_race',
    name: 'First race',
    description: 'Finish your first race together',
    threshold: 1,
    value: (f) => f.racesTogether,
  },
  {
    key: 'rivals',
    name: 'Rivals',
    description: 'Race together 10 times',
    threshold: 10,
    value: (f) => f.racesTogether,
  },
  {
    key: 'cheer_squad',
    name: 'Cheer squad',
    description: 'Trade 20 reactions on each other’s activity',
    threshold: 20,
    value: (f) => f.pairReactions,
  },
  {
    key: 'best_friends',
    name: 'Best friends',
    description: 'Stay friends for 30 days',
    threshold: 30,
    value: (f) => f.daysConnected,
  },
  {
    key: 'streak_buddies',
    name: 'Streak buddies',
    description: 'Both keep a 7-day streak alive',
    threshold: 7,
    value: (f) => Math.min(f.streakYou, f.streakThem),
  },
];

export function friendshipBadges(facts: FriendshipFacts): FriendshipBadge[] {
  return DEFS.map((d) => {
    const progress = d.value(facts);
    return {
      key: d.key,
      name: d.name,
      description: d.description,
      earned: progress >= d.threshold,
      progress,
      threshold: d.threshold,
    };
  });
}

/** Whole days between `createdAt` (sqlite CURRENT_TIMESTAMP or ISO) and now. */
export function daysSince(createdAt: string): number {
  const iso = createdAt.includes('T') ? createdAt : createdAt.replace(' ', 'T') + 'Z';
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return 0;
  return Math.max(0, Math.floor((Date.now() - ms) / 86_400_000));
}

/**
 * Completed races the pair shared — same definition as `racesWithYou.total`
 * (both on the roster, race completed), kept as its own small query so the
 * friendship bundle never depends on the public-identity read.
 */
export async function racesTogetherFor(
  db: D1Database,
  a: string,
  b: string,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n
         FROM race_members a
         JOIN race_members b ON b.race_id = a.race_id
           AND b.user_id = ? AND b.status != 'removed'
         JOIN races r ON r.id = a.race_id
        WHERE a.user_id = ? AND a.status != 'removed'
          AND r.status = 'completed'`,
    )
    .bind(b, a)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

/**
 * Reactions traded between the pair, either direction — a reaction counts
 * when one member reacted to an entity owned by the other. Entity ownership
 * mirrors resolveReactionTarget: move_log → its user, race_event → actor (or
 * subject), crew → the connection row the pair shares.
 */
export async function pairReactionsFor(
  db: D1Database,
  a: string,
  b: string,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM activity_reactions ar
        WHERE (
          ar.user_id = ? AND (
            (ar.entity_type = 'move_log' AND EXISTS (
              SELECT 1 FROM move_logs ml WHERE ml.id = ar.entity_id AND ml.user_id = ?))
            OR (ar.entity_type = 'race_event' AND EXISTS (
              SELECT 1 FROM race_events re WHERE re.id = ar.entity_id
                AND COALESCE(re.actor_user_id, re.subject_user_id) = ?))
            OR (ar.entity_type = 'crew' AND EXISTS (
              SELECT 1 FROM crew_connections cc WHERE cc.id = ar.entity_id
                AND ((cc.user_id = ? AND cc.crew_user_id = ?)
                  OR (cc.user_id = ? AND cc.crew_user_id = ?))))
          )
        ) OR (
          ar.user_id = ? AND (
            (ar.entity_type = 'move_log' AND EXISTS (
              SELECT 1 FROM move_logs ml WHERE ml.id = ar.entity_id AND ml.user_id = ?))
            OR (ar.entity_type = 'race_event' AND EXISTS (
              SELECT 1 FROM race_events re WHERE re.id = ar.entity_id
                AND COALESCE(re.actor_user_id, re.subject_user_id) = ?))
            OR (ar.entity_type = 'crew' AND EXISTS (
              SELECT 1 FROM crew_connections cc WHERE cc.id = ar.entity_id
                AND ((cc.user_id = ? AND cc.crew_user_id = ?)
                  OR (cc.user_id = ? AND cc.crew_user_id = ?))))
          )
        )`,
    )
    .bind(b, a, a, a, b, b, a, a, b, b, b, a, a, b)
    .first<{ n: number }>();
  return row?.n ?? 0;
}
