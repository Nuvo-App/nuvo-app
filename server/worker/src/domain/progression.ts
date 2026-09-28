/**
 * Nuvo progression v2 — the persistent meta-game projected from canonical
 * race truth. Race actions commit first; XP, achievements, and unlocks are
 * derived afterwards from the durable event log, so a progression failure
 * can never fail a race action.
 *
 * Sources:
 *   xp_events       — XP ledger, unique per (user, source_type, source_id)
 *   user_progression— cached totals + stats snapshot (recomputed, never input)
 *   unlock_definitions — achievements (stat/level gated) + capabilities
 *   user_unlocks    — earned achievements/capabilities (idempotent awards)
 *   user_featured_badges — featured achievement slots
 *
 * The same reconcile pass serves live play and historical backfill, so the
 * two paths cannot diverge or double-award.
 */
import { generateId } from '../lib/crypto';

// ── XP awards ─────────────────────────────────────────────────────────────────
// Canonical event_type → award. Race creation, joining, invites, reactions,
// and reads earn nothing — XP comes only from doing.
export const XP_AWARDS: Record<string, number> = {
  progress_accepted: 10,
  participant_finished: 25,
  winner_determined: 15,
  personal_best: 5,
};
const XP_SOURCE_TYPES = Object.keys(XP_AWARDS);

/** First accepted result inside a canonical category the racer hasn't
 *  touched before — a small nudge toward variety, deduped per event. */
const XP_DISCOVERY_BONUS = 5;
const XP_DISCOVERY_SOURCE = 'discovery_category';

// ── Level curve ───────────────────────────────────────────────────────────────
// Single deterministic curve — tune here, nowhere else. Cumulative XP needed
// to BE level n: linear + quadratic growth, intentionally not exponential.
//   levelUpCost(n→n+1) = LEVEL_BASE + LEVEL_GROWTH * (n - 1)
//   xpForLevel(n)      = Σ = LEVEL_BASE*(n-1) + LEVEL_GROWTH/2 *(n-1)(n-2)
const LEVEL_BASE = 60;
const LEVEL_GROWTH = 60;

/** Cumulative total XP required to reach `level` (level 1 = 0 XP). */
export function xpForLevel(level: number): number {
  if (level <= 1) return 0;
  const k = level - 1;
  return LEVEL_BASE * k + (LEVEL_GROWTH / 2) * k * (k - 1);
}

export interface LevelProgress {
  level: number;
  /** XP earned inside the current level. */
  currentLevelXp: number;
  /** XP required to leave the current level. */
  nextLevelXp: number;
  /** 0..1 fill for the progress bar. */
  progress: number;
}

export function levelForXp(totalXp: number): LevelProgress {
  let level = 1;
  while (xpForLevel(level + 1) <= totalXp) level++;
  const floor = xpForLevel(level);
  const span = xpForLevel(level + 1) - floor;
  return {
    level,
    currentLevelXp: totalXp - floor,
    nextLevelXp: span,
    progress: span > 0 ? (totalXp - floor) / span : 0,
  };
}

// ── Canonical stats ───────────────────────────────────────────────────────────
// Every achievement threshold reads this snapshot — nothing here is a client
// input; it is derived per reconcile from race_events/races/race_members.
export interface UserStats {
  progressesAccepted: number;
  racesFinished: number;
  racesWon: number;
  racesCreated: number;
  pbsSet: number;
  motionFinished: number;
  photoFinished: number;
  photoProofs: number;
  timedFinished: number;
  socialFinished: number;
  bigRaceFinished: number;
  /** Best same-rival finish count — "finish 5 races against the same person". */
  rivalryMax: number;
  distinctCategories: number;
  comebacks: number;
  wireToWires: number;
  /** Canonical category slug → finishes (variety + category families). */
  categories: Record<string, number>;
}

interface RaceMeta {
  activity_id: string | null;
  custom_activity_name: string | null;
  verification_type: string | null;
  format: string | null;
}

interface UserEventRow {
  id: string;
  event_type: string;
  race_id: string;
  actor_user_id: string | null;
  subject_user_id: string | null;
  payload_json: string | null;
  created_at: string;
  activity_id: string | null;
  custom_activity_name: string | null;
  verification_type: string | null;
  format: string | null;
}

/** Canonical category slug — preset activity id, else the normalized custom
 *  activity name recorded at race creation. Never parsed from titles. */
export function categoryFor(race: RaceMeta): string {
  const a = race.activity_id ?? '';
  if (a && !a.startsWith('custom:') && !a.startsWith('manual:')) {
    return a.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'other';
  }
  const raw = a.startsWith('custom:') ? a.slice(7) : (race.custom_activity_name ?? '');
  const slug = raw.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return slug || 'other';
}

function isMotionRace(race: RaceMeta): boolean {
  const v = race.verification_type;
  return v === 'camera_pose' || v === 'movecheck';
}

function isPhotoRace(race: RaceMeta): boolean {
  const v = race.verification_type;
  return v === 'photo' || v === 'photo_video';
}

function isTimedRace(race: RaceMeta): boolean {
  return race.format === 'timed_attempt';
}

function payloadOf(json: string | null): Record<string, unknown> {
  if (!json) return {};
  try {
    const p = JSON.parse(json) as unknown;
    return p && typeof p === 'object' ? (p as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

const OTHER_CATEGORY_ALIASES = /^category:/;

/**
 * Resolve one achievement's progress value from the stats snapshot.
 * `category:<family>` sums finishes whose canonical slug matches any alias in
 * the def's metadata `categoryAliases` (plus the family slug itself) — new
 * families are pure data.
 */
export function statValue(
  stats: UserStats,
  statKey: string | null,
  aliases?: string[] | null,
): number {
  if (!statKey) return 0;
  if (OTHER_CATEGORY_ALIASES.test(statKey)) {
    const family = statKey.slice('category:'.length);
    const names = new Set([family, ...(aliases ?? [])]);
    let n = 0;
    for (const [cat, count] of Object.entries(stats.categories)) {
      if (names.has(cat)) n += count;
    }
    return n;
  }
  const s = stats as Partial<UserStats>;
  switch (statKey) {
    case 'progresses_accepted': return s.progressesAccepted ?? 0;
    case 'races_finished': return s.racesFinished ?? 0;
    case 'races_won': return s.racesWon ?? 0;
    case 'races_created': return s.racesCreated ?? 0;
    case 'pbs_set': return s.pbsSet ?? 0;
    case 'motion_finished': return s.motionFinished ?? 0;
    case 'photo_finished': return s.photoFinished ?? 0;
    case 'photo_proofs': return s.photoProofs ?? 0;
    case 'timed_finished': return s.timedFinished ?? 0;
    case 'social_finished': return s.socialFinished ?? 0;
    case 'big_race_finished': return s.bigRaceFinished ?? 0;
    case 'rivalry_max': return s.rivalryMax ?? 0;
    case 'distinct_categories': return s.distinctCategories ?? 0;
    case 'comebacks': return s.comebacks ?? 0;
    case 'wire_to_wires': return s.wireToWires ?? 0;
    default: return 0;
  }
}

/**
 * Aggregate a racer's canonical history. Reads the event log joined to race
 * metadata plus member rosters — the same events that pay XP also feed
 * achievements, so stats, XP, and awards can never disagree.
 */
export async function computeUserStats(
  db: D1Database,
  userId: string,
): Promise<UserStats> {
  const events = await db
    .prepare(
      `SELECT e.id, e.event_type, e.race_id, e.actor_user_id, e.subject_user_id,
              e.payload_json, e.created_at,
              r.activity_id, r.custom_activity_name, r.verification_type, r.format
       FROM race_events e LEFT JOIN races r ON r.id = e.race_id
       WHERE (e.subject_user_id = ? OR e.actor_user_id = ?) AND e.voided_at IS NULL
       ORDER BY e.created_at ASC, e.id ASC`,
    )
    .bind(userId, userId)
    .all<UserEventRow>();

  const stats: UserStats = {
    progressesAccepted: 0,
    racesFinished: 0,
    racesWon: 0,
    racesCreated: 0,
    pbsSet: 0,
    motionFinished: 0,
    photoFinished: 0,
    photoProofs: 0,
    timedFinished: 0,
    socialFinished: 0,
    bigRaceFinished: 0,
    rivalryMax: 0,
    distinctCategories: 0,
    comebacks: 0,
    wireToWires: 0,
    categories: {},
  };

  const meta: RaceMeta = { activity_id: null, custom_activity_name: null, verification_type: null, format: null };
  const finishedRaces = new Map<string, RaceMeta>();
  const wonRaces = new Set<string>();
  /** race_id → ordered newRank values from the user's own progress events. */
  const ownRanks = new Map<string, number[]>();

  for (const e of events.results) {
    const race: RaceMeta = e.activity_id !== undefined && e.race_id
      ? { activity_id: e.activity_id, custom_activity_name: e.custom_activity_name, verification_type: e.verification_type, format: e.format }
      : meta;
    switch (e.event_type) {
      case 'race_created':
        if (e.actor_user_id === userId) stats.racesCreated += 1;
        break;
      case 'progress_accepted': {
        if (e.subject_user_id !== userId) break;
        stats.progressesAccepted += 1;
        if (isPhotoRace(race)) stats.photoProofs += 1;
        const p = payloadOf(e.payload_json);
        const rank = typeof p.newRank === 'number' ? (p.newRank as number) : null;
        if (rank !== null) {
          const list = ownRanks.get(e.race_id) ?? [];
          list.push(rank);
          ownRanks.set(e.race_id, list);
        } else {
          // First submission can predate any ranking — record as leading.
          const list = ownRanks.get(e.race_id) ?? [];
          list.push(1);
          ownRanks.set(e.race_id, list);
        }
        break;
      }
      case 'participant_finished': {
        if (e.subject_user_id !== userId) break;
        stats.racesFinished += 1;
        finishedRaces.set(e.race_id, race);
        const cat = categoryFor(race);
        stats.categories[cat] = (stats.categories[cat] ?? 0) + 1;
        if (isMotionRace(race)) stats.motionFinished += 1;
        if (isPhotoRace(race)) stats.photoFinished += 1;
        if (isTimedRace(race)) stats.timedFinished += 1;
        break;
      }
      case 'winner_determined':
        if (e.subject_user_id === userId) {
          stats.racesWon += 1;
          wonRaces.add(e.race_id);
        }
        break;
      case 'personal_best':
        if (e.subject_user_id === userId) stats.pbsSet += 1;
        break;
      default:
        break;
    }
  }

  stats.distinctCategories = Object.keys(stats.categories).length;

  if (finishedRaces.size > 0) {
    const ids = [...finishedRaces.keys()];
    const placeholders = ids.map(() => '?').join(',');
    const memberRows = await db
      .prepare(
        `SELECT race_id, user_id FROM race_members
         WHERE race_id IN (${placeholders}) AND status != 'removed'`,
      )
      .bind(...ids)
      .all<{ race_id: string; user_id: string }>();
    const memberCount = new Map<string, number>();
    const shared = new Map<string, number>();
    for (const row of memberRows.results) {
      memberCount.set(row.race_id, (memberCount.get(row.race_id) ?? 0) + 1);
      if (row.user_id !== userId) {
        shared.set(row.user_id, (shared.get(row.user_id) ?? 0) + 1);
      }
    }
    for (const raceId of finishedRaces.keys()) {
      const n = memberCount.get(raceId) ?? 0;
      if (n >= 2) stats.socialFinished += 1;
      if (n >= 10) stats.bigRaceFinished += 1;
    }
    for (const n of shared.values()) {
      if (n > stats.rivalryMax) stats.rivalryMax = n;
    }
  }

  if (wonRaces.size > 0) {
    // Lead history only exists as lead_changed events — a race where nobody
    // else ever led is provable "wire to wire"; trailing then winning is a
    // provable comeback. Anything we cannot prove is simply not awarded.
    const ids = [...wonRaces.keys()];
    const leadRows = await db
      .prepare(
        `SELECT race_id, payload_json FROM race_events
         WHERE race_id IN (${ids.map(() => '?').join(',')}) AND event_type = 'lead_changed'
           AND voided_at IS NULL`,
      )
      .bind(...ids)
      .all<{ race_id: string; payload_json: string | null }>();
    const otherLed = new Set<string>();
    for (const row of leadRows.results) {
      const p = payloadOf(row.payload_json);
      if (p.newLeaderUserId && p.newLeaderUserId !== userId) otherLed.add(row.race_id);
    }
    for (const raceId of wonRaces) {
      const ranks = ownRanks.get(raceId) ?? [];
      const trailed = otherLed.has(raceId) || ranks.some((r) => r > 1);
      if (trailed) {
        stats.comebacks += 1;
      } else if (ranks.length > 0) {
        stats.wireToWires += 1;
      }
    }
  }

  return stats;
}

// ── Rows ──────────────────────────────────────────────────────────────────────
interface ProgressionRow {
  user_id: string;
  total_xp: number;
  level: number;
  last_seen_level: number;
  stats_json: string | null;
}

export interface UnlockRow {
  id: string;
  required_level: number;
  unlock_type: string;
  unlock_key: string;
  name: string;
  description: string | null;
  metadata_json: string | null;
  category: string | null;
  icon_key: string | null;
  requirement_kind: string;
  stat_key: string | null;
  threshold: number | null;
  sort_order: number;
}

export interface ReconcileResult {
  totalXp: number;
  level: number;
  previousLevel: number;
  newUnlockIds: string[];
}

/**
 * Project un-awarded canonical race events for one user into xp_events,
 * recompute the stats snapshot and cached totals, then grant every unlock
 * now provable — level-gated defs at/below the level and stat-gated
 * achievements at/over their threshold. INSERT OR IGNORE on the unique
 * (user, source_type, source_id) and user_unlocks keys makes every caller —
 * live path, backfill, retry — safely idempotent.
 */
export async function reconcileProgression(
  db: D1Database,
  userId: string,
): Promise<ReconcileResult> {
  const prior = await db
    .prepare('SELECT level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ level: number }>();
  const previousLevel = prior?.level ?? 1;

  // Projection hygiene: XP rows derived from race events that were later
  // voided (proof vetoed / review-invalidated) no longer have a valid source.
  // Remove them so totals, level, and stats re-derive from valid history.
  await db
    .prepare(
      `DELETE FROM xp_events WHERE user_id = ? AND source_id IN
       (SELECT id FROM race_events WHERE voided_at IS NOT NULL)`,
    )
    .bind(userId)
    .run();

  const events = await db
    .prepare(
      `SELECT e.id, e.event_type, e.race_id, e.created_at,
              r.activity_id, r.custom_activity_name
       FROM race_events e LEFT JOIN races r ON r.id = e.race_id
       WHERE e.subject_user_id = ? AND e.voided_at IS NULL
         AND e.event_type IN (${XP_SOURCE_TYPES.map(() => '?').join(',')})
       ORDER BY e.created_at ASC, e.id ASC`,
    )
    .bind(userId, ...XP_SOURCE_TYPES)
    .all<{ id: string; event_type: string; race_id: string; created_at: string; activity_id: string | null; custom_activity_name: string | null }>();

  const stmts: D1PreparedStatement[] = [];
  const seenCategories = new Set<string>();
  for (const e of events.results) {
    stmts.push(
      db
        .prepare(
          `INSERT OR IGNORE INTO xp_events (id, user_id, source_type, source_id, race_id, xp_amount, created_at)
           VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
        )
        .bind(generateId(), userId, e.event_type, e.id, e.race_id, XP_AWARDS[e.event_type] ?? 0),
    );
    // Discovery bonus — the first accepted result in each canonical category
    // rides the same event id, so it can never be double-awarded.
    if (e.event_type === 'progress_accepted') {
      const cat = categoryFor({
        activity_id: e.activity_id,
        custom_activity_name: e.custom_activity_name,
        verification_type: null,
        format: null,
      });
      if (!seenCategories.has(cat)) {
        seenCategories.add(cat);
        stmts.push(
          db
            .prepare(
              `INSERT OR IGNORE INTO xp_events (id, user_id, source_type, source_id, race_id, xp_amount, created_at)
               VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
            )
            .bind(generateId(), userId, XP_DISCOVERY_SOURCE, e.id, e.race_id, XP_DISCOVERY_BONUS),
        );
      }
    }
  }
  if (stmts.length > 0) await db.batch(stmts);

  const totals = await db
    .prepare('SELECT COALESCE(SUM(xp_amount), 0) AS total FROM xp_events WHERE user_id = ?')
    .bind(userId)
    .first<{ total: number }>();
  const totalXp = totals?.total ?? 0;
  const level = levelForXp(totalXp).level;

  const stats = await computeUserStats(db, userId);

  await db
    .prepare(
      `INSERT INTO user_progression (user_id, total_xp, level, last_seen_level, stats_json, created_at, updated_at)
       VALUES (?, ?, ?, 1, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id) DO UPDATE SET
         total_xp = excluded.total_xp,
         level = excluded.level,
         stats_json = excluded.stats_json,
         updated_at = CURRENT_TIMESTAMP`,
    )
    .bind(userId, totalXp, level, JSON.stringify(stats))
    .run();

  const defs = await db
    .prepare('SELECT * FROM unlock_definitions WHERE active = 1')
    .all<UnlockRow>();
  const grantable = defs.results.filter((d) =>
    d.requirement_kind === 'stat'
      ? statValue(stats, d.stat_key, aliasesFor(d)) >= (d.threshold ?? 0)
      : d.required_level <= level,
  );
  const newUnlockIds: string[] = [];
  if (grantable.length > 0) {
    const grantStmts = grantable.map((d) =>
      db
        .prepare(
          `INSERT OR IGNORE INTO user_unlocks (id, user_id, unlock_id, unlocked_at, source)
           VALUES (?, ?, ?, CURRENT_TIMESTAMP, ?)`,
        )
        .bind(generateId(), userId, d.id, d.requirement_kind === 'stat' ? 'achievement' : 'level'),
    );
    const results = await db.batch(grantStmts);
    results.forEach((r, i) => {
      if ((r.meta.changes ?? 0) > 0) newUnlockIds.push(grantable[i].id);
    });
  }

  // Revocation — the same projection rule runs both ways. When invalidated
  // proof pulls a stat or the level below a definition's requirement, the
  // award is no longer provable and is removed. Only reconcile-granted
  // sources ('level'/'achievement') on active defs are ever revoked.
  const grantableIds = grantable.map((d) => d.id);
  const revokeSql = grantableIds.length
    ? `DELETE FROM user_unlocks WHERE user_id = ? AND source IN ('level', 'achievement')
         AND unlock_id IN (SELECT id FROM unlock_definitions WHERE active = 1)
         AND unlock_id NOT IN (${grantableIds.map(() => '?').join(',')})`
    : `DELETE FROM user_unlocks WHERE user_id = ? AND source IN ('level', 'achievement')
         AND unlock_id IN (SELECT id FROM unlock_definitions WHERE active = 1)`;
  await db.prepare(revokeSql).bind(userId, ...grantableIds).run();
  await db
    .prepare(
      `DELETE FROM user_featured_badges WHERE user_id = ?
         AND unlock_id NOT IN (SELECT unlock_id FROM user_unlocks WHERE user_id = ?)`,
    )
    .bind(userId, userId)
    .run();

  return { totalXp, level, previousLevel, newUnlockIds };
}

// ── Reads ─────────────────────────────────────────────────────────────────────
export interface AchievementView {
  unlockId: string;
  type: string;
  key: string;
  name: string;
  description: string | null;
  requiredLevel: number;
  metadata: Record<string, unknown> | null;
  category: string | null;
  iconKey: string | null;
  statKey: string | null;
  threshold: number | null;
  /** Canonical progress toward a locked stat achievement (0 for level defs). */
  progressValue: number;
  unlocked: boolean;
  unlockedAt: string | null;
  featured: boolean;
  position: number | null;
}

/** Back-compat alias — featured rows and levelUnlock still type as badges. */
export type BadgeView = AchievementView;

export interface ProgressionPayload {
  level: number;
  totalXp: number;
  currentLevelXp: number;
  nextLevelXp: number;
  progress: number;
  xpToNext: number;
  lastSeenLevel: number;
  featuredSlots: number;
  achievementsEarned: number;
  achievementsTotal: number;
  nextUnlock: {
    unlockId: string;
    level: number;
    type: string;
    key: string;
    name: string;
    description: string | null;
    metadata: Record<string, unknown> | null;
  } | null;
  /** The unlock granted at the current level — what the level-up moment
   *  celebrates. Null when the current level carries no reward. */
  levelUnlock: BadgeView | null;
  /** Locked stat achievement closest to completion — Profile "Next up". */
  nextAchievement: BadgeView | null;
  featuredBadges: BadgeView[];
  /** Achievements granted during this read's reconcile — populated exactly
   *  once (the reconcile that wrote them), so whichever surface reads first
   *  carries the earned moment. Later reads return []. */
  newlyEarned: BadgeView[];
}

/** Achievement views for unlock ids just granted this reconcile. */
async function newlyEarnedViews(
  db: D1Database,
  userId: string,
  unlockIds: string[],
  stats: UserStats | null,
): Promise<AchievementView[]> {
  const achievementIds = unlockIds.slice(0, 8);
  if (achievementIds.length === 0) return [];
  const rows = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at FROM user_unlocks u
       JOIN unlock_definitions d ON d.id = u.unlock_id
       WHERE u.user_id = ? AND d.unlock_type = 'achievement' AND
             u.unlock_id IN (${achievementIds.map(() => '?').join(',')})
       ORDER BY d.sort_order ASC`,
    )
    .bind(userId, ...achievementIds)
    .all<UnlockRow & { owned_at: string | null }>();
  return rows.results.map((d) => achievementView(d, d.owned_at, null, stats));
}

function parseMetadata(json: string | null): Record<string, unknown> | null {
  if (!json) return null;
  try {
    const parsed = JSON.parse(json) as unknown;
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function aliasesFor(def: UnlockRow): string[] | null {
  const meta = parseMetadata(def.metadata_json);
  const aliases = meta?.categoryAliases;
  return Array.isArray(aliases)
    ? aliases.filter((a): a is string => typeof a === 'string')
    : null;
}

function parseStats(json: string | null): UserStats | null {
  if (!json) return null;
  try {
    const p = JSON.parse(json) as UserStats;
    return p && typeof p === 'object' ? p : null;
  } catch {
    return null;
  }
}

function achievementView(
  def: UnlockRow,
  ownedAt: string | null,
  featuredPosition: number | null,
  stats: UserStats | null,
): AchievementView {
  return {
    unlockId: def.id,
    type: def.unlock_type,
    key: def.unlock_key,
    name: def.name,
    description: def.description,
    requiredLevel: def.required_level,
    metadata: parseMetadata(def.metadata_json),
    category: def.category,
    iconKey: def.icon_key,
    statKey: def.stat_key,
    threshold: def.threshold ?? (def.requirement_kind === 'level' ? def.required_level : null),
    // Locked level milestones carry no incremental progress — "Reach Level 5"
    // is the whole requirement, so they stay out of the next-goal race.
    progressValue:
      def.requirement_kind === 'stat' && stats
        ? Math.min(statValue(stats, def.stat_key, aliasesFor(def)), def.threshold ?? Number.MAX_SAFE_INTEGER)
        : 0,
    unlocked: ownedAt !== null,
    unlockedAt: ownedAt,
    featured: featuredPosition !== null,
    position: featuredPosition,
  };
}

/** Featured slots come from the unlock ladder — base 1, +1 per slot unlock. */
export function featuredSlotsFor(unlockTypesAndKeys: Array<{ type: string; key: string }>): number {
  return 1 + unlockTypesAndKeys.filter((u) => u.type === 'badge_slot').length;
}

/**
 * Authoritative progression read. Always reconciles first — the projection
 * is self-healing, so a missed post-write reconcile can never leave the
 * user stuck at a stale level.
 */
export async function readProgression(
  db: D1Database,
  userId: string,
): Promise<ProgressionPayload> {
  const rec = await reconcileProgression(db, userId);

  const row = await db
    .prepare('SELECT user_id, total_xp, level, last_seen_level, stats_json FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<ProgressionRow>();
  const totalXp = row?.total_xp ?? 0;
  const lp = levelForXp(totalXp);
  const stats = parseStats(row?.stats_json ?? null);

  const nextDef = await db
    .prepare(
      `SELECT * FROM unlock_definitions
       WHERE active = 1 AND requirement_kind = 'level' AND required_level > ? AND
             id NOT IN (SELECT unlock_id FROM user_unlocks WHERE user_id = ?)
       ORDER BY required_level ASC, sort_order ASC, unlock_key ASC LIMIT 1`,
    )
    .bind(lp.level, userId)
    .first<UnlockRow>();

  const levelUnlock = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at FROM user_unlocks u
       JOIN unlock_definitions d ON d.id = u.unlock_id
       WHERE u.user_id = ? AND d.required_level = ? AND d.active = 1
       ORDER BY d.sort_order ASC, d.unlock_type, d.unlock_key LIMIT 1`,
    )
    .bind(userId, lp.level)
    .first<UnlockRow & { owned_at: string | null }>();

  const featuredRows = await db
    .prepare(
      `SELECT d.*, f.position, u.unlocked_at AS owned_at FROM user_featured_badges f
       JOIN unlock_definitions d ON d.id = f.unlock_id
       LEFT JOIN user_unlocks u ON u.unlock_id = d.id AND u.user_id = f.user_id
       WHERE f.user_id = ? ORDER BY f.position ASC`,
    )
    .bind(userId)
    .all<UnlockRow & { position: number; owned_at: string | null }>();

  const ownedUnlocks = await db
    .prepare(
      `SELECT d.unlock_type AS type, d.unlock_key AS key FROM user_unlocks u
       JOIN unlock_definitions d ON d.id = u.unlock_id WHERE u.user_id = ?`,
    )
    .bind(userId)
    .all<{ type: string; key: string }>();

  const achievements = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at FROM unlock_definitions d
       LEFT JOIN user_unlocks u ON u.unlock_id = d.id AND u.user_id = ?
       WHERE d.active = 1 AND d.unlock_type = 'achievement'
       ORDER BY d.sort_order ASC, d.unlock_key ASC`,
    )
    .bind(userId)
    .all<UnlockRow & { owned_at: string | null }>();

  const views = achievements.results.map((d) => achievementView(d, d.owned_at, null, stats));
  const earned = views.filter((v) => v.unlocked).length;

  // "Next up" — the locked stat achievement nearest to done. Prefer ones with
  // real progress; fall back to the lowest threshold so Level 1 still has a
  // visible first goal.
  const locked = views.filter((v) => !v.unlocked && v.threshold !== null && v.threshold > 0);
  const withProgress = locked.filter((v) => v.progressValue > 0);
  let nextAchievement: BadgeView | null = null;
  if (withProgress.length > 0) {
    nextAchievement = withProgress.sort(
      (a, b) => b.progressValue / (b.threshold ?? 1) - a.progressValue / (a.threshold ?? 1),
    )[0];
  } else if (locked.length > 0) {
    nextAchievement = locked.sort((a, b) => (a.threshold ?? 0) - (b.threshold ?? 0))[0];
  }

  return {
    level: lp.level,
    totalXp,
    currentLevelXp: lp.currentLevelXp,
    nextLevelXp: lp.nextLevelXp,
    progress: lp.progress,
    xpToNext: xpForLevel(lp.level + 1) - totalXp,
    lastSeenLevel: row?.last_seen_level ?? 1,
    featuredSlots: featuredSlotsFor(ownedUnlocks.results),
    achievementsEarned: earned,
    achievementsTotal: views.length,
    nextUnlock: nextDef
      ? {
          unlockId: nextDef.id,
          level: nextDef.required_level,
          type: nextDef.unlock_type,
          key: nextDef.unlock_key,
          name: nextDef.name,
          description: nextDef.description,
          metadata: parseMetadata(nextDef.metadata_json),
        }
      : null,
    levelUnlock: levelUnlock
      ? achievementView(levelUnlock, levelUnlock.owned_at, null, stats)
      : null,
    nextAchievement,
    featuredBadges: featuredRows.results.map((d) =>
      achievementView(d, d.owned_at, d.position, stats),
    ),
    newlyEarned: await newlyEarnedViews(db, userId, rec.newUnlockIds, stats),
  };
}

/** Full achievement collection — earned and locked with live progress. */
export async function readBadgeCollection(
  db: D1Database,
  userId: string,
): Promise<BadgeView[]> {
  await reconcileProgression(db, userId);
  const row = await db
    .prepare('SELECT stats_json FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ stats_json: string | null }>();
  const stats = parseStats(row?.stats_json ?? null);
  const rows = await db
    .prepare(
      `SELECT d.*, u.unlocked_at AS owned_at, f.position AS featured_position
       FROM unlock_definitions d
       LEFT JOIN user_unlocks u ON u.unlock_id = d.id AND u.user_id = ?
       LEFT JOIN user_featured_badges f ON f.unlock_id = d.id AND f.user_id = ?
       WHERE d.active = 1
       ORDER BY d.category ASC, d.sort_order ASC, d.unlock_key ASC`,
    )
    .bind(userId, userId)
    .all<UnlockRow & { owned_at: string | null; featured_position: number | null }>();
  return rows.results.map((d) => achievementView(d, d.owned_at, d.featured_position, stats));
}

/** Per-race XP breakdown for the finish screen — what this race paid out. */
export interface RaceXpBreakdown {
  lines: Array<{ label: string; xp: number }>;
  totalXp: number;
  /** Achievements this reconcile granted — the finish screen's earned moment. */
  earned: BadgeView[];
}

export async function readRaceXp(
  db: D1Database,
  userId: string,
  raceId: string,
): Promise<RaceXpBreakdown> {
  const rec = await reconcileProgression(db, userId);
  const rows = await db
    .prepare(
      `SELECT source_type, COALESCE(SUM(xp_amount), 0) AS xp FROM xp_events
       WHERE user_id = ? AND race_id = ? GROUP BY source_type`,
    )
    .bind(userId, raceId)
    .all<{ source_type: string; xp: number }>();
  const LABELS: Record<string, string> = {
    progress_accepted: 'Progress',
    participant_finished: 'Finish',
    winner_determined: 'Win bonus',
    personal_best: 'Personal best',
    discovery_category: 'New ground',
  };
  const order = ['progress_accepted', 'participant_finished', 'winner_determined', 'personal_best', 'discovery_category'];
  const lines = rows.results
    .map((r) => ({ label: LABELS[r.source_type] ?? r.source_type, xp: r.xp, source: r.source_type }))
    .sort((a, b) => order.indexOf(a.source) - order.indexOf(b.source))
    .map(({ label, xp }) => ({ label, xp }));
  const earned = await newlyEarnedViews(db, userId, rec.newUnlockIds, null);
  return { lines, totalXp: lines.reduce((n, l) => n + l.xp, 0), earned };
}

/**
 * Replace the user's featured set. Server-side validation: every unlock must
 * be owned, be an achievement, dedupe, and fit the slot count the user's
 * level unlocks currently grant.
 */
export async function setFeaturedBadges(
  db: D1Database,
  userId: string,
  unlockIds: string[],
): Promise<{ ok: true } | { ok: false; error: string }> {
  await reconcileProgression(db, userId);
  const deduped = [...new Set(unlockIds)];
  if (deduped.length !== unlockIds.length) {
    return { ok: false, error: 'Duplicate badges are not allowed' };
  }
  const owned = await db
    .prepare(
      `SELECT d.unlock_type AS type, d.unlock_key AS key, u.unlock_id FROM user_unlocks u
       JOIN unlock_definitions d ON d.id = u.unlock_id WHERE u.user_id = ?`,
    )
    .bind(userId)
    .all<{ type: string; key: string; unlock_id: string }>();
  const slots = featuredSlotsFor(owned.results);
  if (deduped.length > slots) {
    return { ok: false, error: `You can feature up to ${slots} badges` };
  }
  const ownedIds = new Set(
    owned.results.filter((o) => o.type === 'achievement').map((o) => o.unlock_id),
  );
  for (const id of deduped) {
    if (!ownedIds.has(id)) return { ok: false, error: 'Achievement not earned' };
  }
  const stmts = [
    db.prepare('DELETE FROM user_featured_badges WHERE user_id = ?').bind(userId),
    ...deduped.map((id, i) =>
      db
        .prepare(
          `INSERT INTO user_featured_badges (user_id, unlock_id, position, updated_at)
           VALUES (?, ?, ?, CURRENT_TIMESTAMP)`,
        )
        .bind(userId, id, i),
    ),
  ];
  await db.batch(stmts);
  return { ok: true };
}

/** Acknowledge the level-up presentation once — never replays per level. */
export async function markLevelSeen(db: D1Database, userId: string): Promise<void> {
  await db
    .prepare(
      `UPDATE user_progression SET last_seen_level = level, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = ?`,
    )
    .bind(userId)
    .run();
}

/** Level for display on other users' surfaces — read-only, no reconcile. */
export async function publicLevelFor(
  db: D1Database,
  userId: string,
): Promise<number> {
  const row = await db
    .prepare('SELECT level FROM user_progression WHERE user_id = ?')
    .bind(userId)
    .first<{ level: number }>();
  return row?.level ?? 1;
}

/**
 * Public identity bundle for Crew/person surfaces: level, earned count, and
 * up to `limit` featured achievements (icon + name only — compact identity,
 * not a stats dump). Returns null fields when nothing is earned yet.
 */
export async function publicIdentityFor(
  db: D1Database,
  userId: string,
  limit = 3,
): Promise<{
  level: number;
  achievementsEarned: number;
  featured: Array<{ unlockId: string; key: string; name: string; iconKey: string | null }>;
}> {
  const [level, earnedRow, featuredRows] = await Promise.all([
    publicLevelFor(db, userId),
    db
      .prepare(
        `SELECT COUNT(*) AS n FROM user_unlocks u
         JOIN unlock_definitions d ON d.id = u.unlock_id
         WHERE u.user_id = ? AND d.unlock_type = 'achievement' AND d.active = 1`,
      )
      .bind(userId)
      .first<{ n: number }>(),
    db
      .prepare(
        `SELECT d.id, d.unlock_key, d.name, d.icon_key FROM user_featured_badges f
         JOIN unlock_definitions d ON d.id = f.unlock_id
         WHERE f.user_id = ? AND d.active = 1
         ORDER BY f.position ASC LIMIT ?`,
      )
      .bind(userId, limit)
      .all<{ id: string; unlock_key: string; name: string; icon_key: string | null }>(),
  ]);
  return {
    level,
    achievementsEarned: earnedRow?.n ?? 0,
    featured: featuredRows.results.map((r) => ({
      unlockId: r.id,
      key: r.unlock_key,
      name: r.name,
      iconKey: r.icon_key,
    })),
  };
}

// ── Public profile progression ───────────────────────────────────────────────
// Another member's competitive identity. The contract deliberately differs
// from /progression: level is the social signal, so public viewers get the
// level + a 0..1 progress fraction — never absolute XP. Locked achievement
// progress is also self-only; public surfaces get the earned collection.

export interface PublicAchievement {
  unlockId: string;
  type: string;
  key: string;
  name: string;
  description: string | null;
  category: string | null;
  iconKey: string | null;
  unlocked: boolean;
  unlockedAt: string | null;
  featured: boolean;
}

export interface SharedRace {
  raceId: string;
  title: string;
  winnerUserId: string | null;
  completedAt: string | null;
}

export interface PublicProfileProgression {
  level: number;
  /** 0..1 fill inside the current level — fraction only, never XP numbers. */
  levelProgress: number;
  achievementsEarned: number;
  achievementsTotal: number;
  featured: Array<{ unlockId: string; key: string; name: string; iconKey: string | null }>;
  earned: PublicAchievement[];
  stats: { races: number; wins: number };
  racesWithYou: {
    total: number;
    viewerWins: number;
    targetWins: number;
    recent: SharedRace[];
  };
}

/**
 * Public progression + racing context for `/users/:id`. Read-only: looking at
 * someone's profile never reconciles their projection — totals come from the
 * progression cache and light event counts, never writes.
 */
export async function publicProfileProgressionFor(
  db: D1Database,
  viewerId: string,
  targetId: string,
): Promise<PublicProfileProgression> {
  const [progRow, statRows, earnedRows, totalRow, featuredRows, sharedRows] =
    await Promise.all([
      db
        .prepare('SELECT total_xp FROM user_progression WHERE user_id = ?')
        .bind(targetId)
        .first<{ total_xp: number }>(),
      db
        .prepare(
          `SELECT event_type, COUNT(*) AS n FROM race_events
           WHERE subject_user_id = ? AND event_type IN ('participant_finished', 'winner_determined')
           GROUP BY event_type`,
        )
        .bind(targetId)
        .all<{ event_type: string; n: number }>(),
      db
        .prepare(
          `SELECT d.*, u.unlocked_at AS owned_at FROM user_unlocks u
           JOIN unlock_definitions d ON d.id = u.unlock_id
           WHERE u.user_id = ? AND d.unlock_type = 'achievement' AND d.active = 1
           ORDER BY d.sort_order ASC, d.unlock_key ASC`,
        )
        .bind(targetId)
        .all<UnlockRow & { owned_at: string | null }>(),
      db
        .prepare(
          `SELECT COUNT(*) AS n FROM unlock_definitions
           WHERE active = 1 AND unlock_type = 'achievement'`,
        )
        .first<{ n: number }>(),
      db
        .prepare(
          `SELECT d.id, d.unlock_key, d.name, d.icon_key FROM user_featured_badges f
           JOIN unlock_definitions d ON d.id = f.unlock_id
           WHERE f.user_id = ? AND d.active = 1
           ORDER BY f.position ASC LIMIT 3`,
        )
        .bind(targetId)
        .all<{ id: string; unlock_key: string; name: string; icon_key: string | null }>(),
      // Races-with-you: canonical finished races where both racers were on
      // the roster. Wins come from the recorded winner, never inferred.
      db
        .prepare(
          `SELECT r.id, r.title, r.winner_user_id, r.completed_at
           FROM race_members a
           JOIN race_members b ON b.race_id = a.race_id
             AND b.user_id = ? AND b.status != 'removed'
           JOIN races r ON r.id = a.race_id
           WHERE a.user_id = ? AND a.status != 'removed'
             AND r.status = 'completed'
           ORDER BY r.completed_at DESC`,
        )
        .bind(targetId, viewerId)
        .all<{
          id: string;
          title: string;
          winner_user_id: string | null;
          completed_at: string | null;
        }>(),
    ]);

  const lp = levelForXp(progRow?.total_xp ?? 0);
  let races = 0;
  let wins = 0;
  for (const row of statRows.results) {
    if (row.event_type === 'participant_finished') races = row.n;
    if (row.event_type === 'winner_determined') wins = row.n;
  }

  const shared = sharedRows.results;
  const featuredIds = new Set(featuredRows.results.map((r) => r.id));
  return {
    level: lp.level,
    levelProgress: lp.progress,
    achievementsEarned: earnedRows.results.length,
    achievementsTotal: totalRow?.n ?? 0,
    featured: featuredRows.results.map((r) => ({
      unlockId: r.id,
      key: r.unlock_key,
      name: r.name,
      iconKey: r.icon_key,
    })),
    earned: earnedRows.results.map((d) => ({
      unlockId: d.id,
      type: d.unlock_type,
      key: d.unlock_key,
      name: d.name,
      description: d.description,
      category: d.category,
      iconKey: d.icon_key,
      unlocked: true,
      unlockedAt: d.owned_at,
      featured: featuredIds.has(d.id),
    })),
    stats: { races, wins },
    racesWithYou: {
      total: shared.length,
      viewerWins: shared.filter((r) => r.winner_user_id === viewerId).length,
      targetWins: shared.filter((r) => r.winner_user_id === targetId).length,
      recent: shared.slice(0, 3).map((r) => ({
        raceId: r.id,
        title: r.title,
        winnerUserId: r.winner_user_id,
        completedAt: r.completed_at,
      })),
    },
  };
}
