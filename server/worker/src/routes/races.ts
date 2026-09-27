import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv, MoveLogRow, RaceProgressRow, RaceRow } from '../types';
import { requireAuth } from '../lib/jwt';
import {
  checkRaceJoinEligibility,
  isBlockedEitherWay,
  resolveRaceAccess,
} from '../lib/raceAccess';
import { evaluateRaceSafety } from '../domain/raceSafety';
import { generateId } from '../lib/crypto';
import { hasAcceptedTerms } from '../lib/terms';
import { activityForId, normalizeActivityIdLoose, normalizeMetric, type RaceFormat, type RaceMetric, type RaceScoringRule } from '../domain/raceActivities';
import {
  CUSTOM_VERIFIER_TYPE,
  MANUAL_VERIFIER_TYPE,
  PRESET_VERIFIER_TYPE,
  assertSubmissionCompatible,
  configFromBody,
  customConfigFromBody,
  manualConfigFromBody,
  registryConfigFromBody,
  type RaceConfig,
} from '../domain/raceValidation';
import { applyVerifiedSubmission } from '../domain/raceScoring';
import { computeCompetitionRanks, type RankedScore } from '../domain/raceRanking';
import { effectiveRaceStatus } from '../domain/raceLifecycle';
import {
  deadlineEligibility,
  finalizeRaceIfEnded,
  lockedFieldsPresent,
  markRaceStartedIfDue,
  rulesLocked,
  scoreDirectionFor,
} from '../domain/raceFinalize';
import { recordRaceEvents, type RaceEventInput } from '../domain/raceEvents';
import { notifyEvent, notifyLifecycleTransitions, notifyRaceEvents, type LifecycleTransitionLike } from '../domain/notificationPolicy';
import { scheduleRaceStartingSoon } from '../domain/notificationJobs';
import { computeViewerContext } from '../domain/raceContext';
import {
  attemptsUsed,
  bindableOpenAttempt,
  closeAttempt,
  formatUsesAttempts,
  openAttempt,
} from '../domain/raceAttempts';
import { recordPersonalBestIfImproved } from '../domain/raceBests';
import { reconcileProgression } from '../domain/progression';
import { resolveRaceMemberVisibility } from '../lib/privacy';
import { assignmentInsert, stableReleaseForActivity } from '../domain/motionAssignments';
import { readMotionRelease, readRegistryActivity } from '../domain/motionRegistry';
import {
  awsEncode,
  encodeKeyPath,
  extensionFor,
  signUploadToken,
  verifyUploadToken,
} from '../lib/uploadMedia';

export const racesRouter = new Hono<AppEnv>();

const PROOF_MEDIA_ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

function proofMediaKeyPrefix(raceId: string): string {
  return `proof-evidence/${raceId}/`;
}

// PUT /races/:id/proof-media/upload — signature in the URL is the credential
// (same contract as /profile/photo/upload), so this sits above requireAuth.
racesRouter.put('/:id/proof-media/upload', async (c) => {
  const raceId = c.req.param('id');
  const token = c.req.query('token');
  if (!token) return c.json({ ok: false, error: 'Missing upload token' }, 401);

  const upload = await verifyUploadToken(token, c.env.JWT_SECRET, [
    proofMediaKeyPrefix(raceId),
  ]);
  if (!upload) return c.json({ ok: false, error: 'Invalid upload token' }, 401);

  await c.env.PROFILE_PHOTOS.put(upload.key, c.req.raw.body, {
    httpMetadata: { contentType: upload.contentType },
  });
  await c.env.DB.prepare(
    "UPDATE media_objects SET status = 'active' WHERE object_key = ?",
  )
    .bind(upload.key)
    .run();
  return c.json({ ok: true });
});

racesRouter.use('*', requireAuth);

const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const RACE_STATUSES = new Set(['draft', 'scheduled', 'active', 'completed', 'archived', 'cancelled']);
const VISIBILITIES = new Set(['private', 'crew_only', 'invite_code', 'public_demo']);
const MOVE_SOURCES = new Set(['movecheck', 'manual', 'demo', 'import']);
const MOVE_STATUSES = new Set(['pending', 'verified', 'rejected', 'removed']);
const REVIEW_STATUSES = new Set(['accepted', 'rejected', 'ai_verified']);

interface InviteRow {
  id: string;
  race_id: string;
  created_by: string;
  invite_code: string;
  status: string;
  expires_at: string | null;
  created_at: string;
}

function stringOrNull(value: unknown): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') return undefined;
  return value.trim() || null;
}

function positiveIntOrNull(value: unknown): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'number' || value <= 0) return undefined;
  return Math.floor(value);
}

function nonNegativeIntOrNull(value: unknown): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'number' || value < 0) return undefined;
  return Math.floor(value);
}

function confidenceOrNull(value: unknown): number | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'number' || Number.isNaN(value)) return undefined;
  return Math.max(0, Math.min(1, value));
}

function generateInviteCode(): string {
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  return `NUV-${Array.from(buf).map((b) => CODE_CHARS[b % CODE_CHARS.length]).join('')}`;
}

function mapGoalTypeToRaceType(goalType: string): string {
  switch (goalType) {
    case 'most': return 'most_in_time';
    case 'streak': return 'daily_streak';
    case 'habit': return 'habit_check';
    case 'first_to_goal': return 'first_to_goal';
    default: return 'first_to_goal';
  }
}

function mapRaceTypeToGoalType(raceType: string): string {
  switch (raceType) {
    case 'most_in_time': return 'most';
    case 'daily_streak': return 'streak';
    case 'habit_check': return 'habit';
    case 'first_to_goal': return 'first_to_goal';
    case 'first_to_target': return 'first_to_goal';
    default: return 'manual';
  }
}

function mapProofRequirementToVerificationType(req: string): string {
  if (req === 'ai_check') return 'movecheck';
  if (req === 'photo_video') return 'photo';
  return 'manual';
}

function mapVerificationTypeToProofRequirement(type: string): string {
  if (type === 'movecheck') return 'ai_check';
  if (type === 'photo') return 'photo_video';
  return 'manual';
}

function parseMetadata(json: string | null): Record<string, unknown> {
  if (!json) return {};
  try { return JSON.parse(json) as Record<string, unknown>; } catch { return {}; }
}

function parsedVerifierSpec(
  race: RaceRow,
  releasedSpec?: Record<string, unknown> | null,
): { spec: Record<string, unknown> | null; invalidReason: string | null } {
  if (releasedSpec) return { spec: releasedSpec, invalidReason: null };
  if (race.verifier_type !== CUSTOM_VERIFIER_TYPE) {
    return { spec: null, invalidReason: null };
  }
  if (!race.verifier_spec_json) {
    return { spec: null, invalidReason: 'Custom verifier spec is missing.' };
  }
  try {
    const parsed = JSON.parse(race.verifier_spec_json) as unknown;
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return { spec: null, invalidReason: 'Custom verifier spec is invalid.' };
    }
    return { spec: parsed as Record<string, unknown>, invalidReason: null };
  } catch {
    return { spec: null, invalidReason: 'Custom verifier spec is invalid.' };
  }
}

async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db.prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL').bind(raceId).first<RaceRow>();
}

async function getProfileName(db: D1Database, userId: string): Promise<string | null> {
  const row = await db.prepare('SELECT full_name FROM profiles WHERE user_id = ?').bind(userId).first<{ full_name: string | null }>();
  return row?.full_name ?? null;
}

function raceConfigFromRow(race: RaceRow): RaceConfig | null {
  // Registry-published activities have no static catalog entry — the loose
  // normalizer preserves their raw ID so the row still produces a config
  // instead of silently degrading to "no verifier".
  const activityId = normalizeActivityIdLoose(race.activity_id ?? race.movement_type);
  const activity = activityForId(activityId);
  if (!activityId) return null;
  const metric = normalizeMetric(race.metric ?? race.target_unit, activity);
  if (!metric) return null;
  const format = ((race.format ?? race.race_type) === 'first_to_target' ? 'first_to_goal' : (race.format ?? 'first_to_goal')) as RaceFormat;
  const scoringRule = (race.scoring_rule ?? 'cumulative_sum') as RaceScoringRule;
  return {
    activityId,
    metric,
    format,
    scoringRule,
    targetValue: race.target_value,
    attemptDurationSeconds: race.attempt_duration_seconds ?? null,
    attemptLimit: race.attempt_limit ?? null,
    verificationMethod: 'camera_pose',
    timezone: race.timezone ?? 'America/New_York',
    startsAt: race.start_at,
    endsAt: race.end_at,
    recurrence: race.recurrence === 'daily' || race.recurrence === 'weekly' ? race.recurrence : 'none',
  };
}

// The live race_members table keeps a legacy person_id column that is NOT NULL and
// references people(id). Every member row must therefore resolve to a people row.
async function ensurePersonId(db: D1Database, userId: string): Promise<string> {
  const existing = await db.prepare('SELECT id FROM people WHERE user_id = ?').bind(userId).first<{ id: string }>();
  if (existing) return existing.id;
  const personId = generateId();
  const displayName = await getProfileName(db, userId);
  await db.prepare(
    `INSERT INTO people (id, person_key, user_id, display_name, created_at, updated_at)
     VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
  ).bind(personId, `user-${userId}`, userId, displayName ?? 'Racer').run();
  return personId;
}

async function ensureMember(db: D1Database, raceId: string, userId: string, role = 'racer'): Promise<void> {
  const existing = await db.prepare('SELECT id, status FROM race_members WHERE race_id = ? AND user_id = ?').bind(raceId, userId).first<{ id: string; status: string }>();
  if (existing) {
    // A stale 'left'/'removed' row must not lock the user out — rejoining
    // reactivates the same membership rather than inserting a duplicate.
    if (existing.status !== 'active') {
      await db.prepare(
        "UPDATE race_members SET status = 'active', role = ?, joined_at = CURRENT_TIMESTAMP WHERE id = ?"
      ).bind(role, existing.id).run();
    }
    return;
  }
  const displayName = await getProfileName(db, userId);
  const personId = await ensurePersonId(db, userId);
  await db.prepare(
    `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at, cached_display_name)
     VALUES (?, ?, ?, ?, ?, 'active', CURRENT_TIMESTAMP, ?)`
  ).bind(generateId(), raceId, userId, personId, role, displayName).run();
}

/** Emit `race_joined` to the creator iff `userId` was not already a member. */
async function notifyRaceJoined(
  c: Context<AppEnv>,
  race: RaceRow,
  userId: string,
  wasMember: boolean,
): Promise<void> {
  if (!wasMember) {
    await recordRaceEvents(c.env.DB, race.id, [
      { type: 'race_joined', actorUserId: userId, subjectUserId: userId, payload: { title: race.title } },
    ]);
  }
  if (wasMember || race.creator_id === userId) return;
  const joiner = (await getProfileName(c.env.DB, userId)) ?? 'Someone';
  await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
    type: 'race_member_joined',
    userId: race.creator_id,
    actorUserId: userId,
    actorName: joiner,
    raceId: race.id,
    raceTitle: race.title,
  });
}

async function isRaceMember(db: D1Database, raceId: string, userId: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'")
    .bind(raceId, userId)
    .first<{ id: string }>();
  return Boolean(row);
}

async function ensureProgress(db: D1Database, raceId: string, userId: string): Promise<void> {
  const existing = await db.prepare('SELECT id FROM race_progress WHERE race_id = ? AND user_id = ?').bind(raceId, userId).first<{ id: string }>();
  if (existing) return;
  await db.prepare(
    `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
     VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`
  ).bind(generateId(), raceId, userId).run();
}

async function rankedScores(db: D1Database, raceId: string, direction: 'higher' | 'lower' = 'higher'): Promise<RankedScore[]> {
  const rows = await db.prepare(
    `SELECT rm.user_id, rm.joined_at, rp.progress_value, rp.completed_at
     FROM race_members rm
     LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
     WHERE rm.race_id = ? AND rm.status = 'active'`
  ).bind(raceId).all<{ user_id: string; joined_at: string; progress_value: number | null; completed_at: string | null }>();
  return computeCompetitionRanks(rows.results.map((row) => ({
    user_id: row.user_id,
    joined_at: row.joined_at,
    progress_value: row.progress_value ?? 0,
    completed_at: row.completed_at,
  })), { direction: direction === 'lower' ? 'asc' : 'desc' });
}

async function recomputeRanks(db: D1Database, raceId: string, direction: 'higher' | 'lower' = 'higher'): Promise<RankedScore[]> {
  const ranked = await rankedScores(db, raceId, direction);
  const stmts = ranked.map((r) => db.prepare(
    'UPDATE race_progress SET rank_cache = ? WHERE race_id = ? AND user_id = ?'
  ).bind(r.rank, raceId, r.user_id));
  if (stmts.length) await db.batch(stmts);
  return ranked;
}

async function snapshotFinalStandings(db: D1Database, raceId: string): Promise<void> {
  const ranked = await rankedScores(db, raceId);
  if (ranked.length === 0) return;
  const stmts = ranked.map((row) => db.prepare(
    `INSERT OR REPLACE INTO race_final_standings
       (id, race_id, user_id, rank_position, score_value, completed_at, created_at)
     VALUES (
       COALESCE((SELECT id FROM race_final_standings WHERE race_id = ? AND user_id = ?), ?),
       ?, ?, ?, ?, ?, CURRENT_TIMESTAMP
     )`
  ).bind(raceId, row.user_id, generateId(), raceId, row.user_id, row.rank, row.progress_value, row.completed_at));
  await db.batch(stmts);
}

interface SubmissionResult {
  verifiedValue: number;
  previousScore: number;
  newScore: number;
  previousRank: number | null;
  newRank: number | null;
  peoplePassed: number;
  raceCompleted: boolean;
  winnerUserId: string | null;
}

interface RaceScoringConfig {
  metric: RaceMetric;
  format: RaceFormat;
  scoringRule: RaceScoringRule;
  targetValue: number | null;
}

function raceScoringConfigFromRow(race: RaceRow): RaceScoringConfig | null {
  const presetConfig = raceConfigFromRow(race);
  if (presetConfig) {
    return {
      metric: presetConfig.metric,
      format: presetConfig.format,
      scoringRule: presetConfig.scoringRule,
      targetValue: presetConfig.targetValue,
    };
  }
  const isCustom = race.verifier_type === CUSTOM_VERIFIER_TYPE;
  const isManual = race.verifier_type === MANUAL_VERIFIER_TYPE;
  if (!isCustom && !isManual) return null;
  const targetValue = positiveIntOrNull(race.target_value) ?? null;
  if (targetValue == null) return null;
  // Manual races store a free-text unit in target_unit; the wire metric is
  // always 'reps' (an opaque cumulative integer).
  const metric = isManual ? 'reps' : normalizeMetric(race.metric ?? race.target_unit ?? 'reps', undefined);
  if (!metric) return null;
  const format = (((race.format ?? race.race_type) === 'first_to_target' ? 'first_to_goal' : (race.format ?? 'first_to_goal')) as unknown) as RaceFormat;
  const scoringRule = ((race.scoring_rule ?? 'cumulative_sum') as unknown) as RaceScoringRule;
  return {
    metric,
    format,
    scoringRule,
    targetValue,
  };
}

interface ScoredSubmission extends SubmissionResult {
  /** Domain events this submission produced (already persisted). */
  events: RaceEventInput[];
  /** Member rows for notification fan-out (names resolved by caller). */
  memberIds: string[];
  /** The rank-1 member before this submission (for displaced-leader copy). */
  leaderUserIdBefore: string | null;
  finished: boolean;
}

/**
 * Rebuild a member's score from their remaining verified moves. Used when a
 * previously verified proof is rejected — trust must be invalidated, not
 * silently preserved. Folds moves through the race's own scoring rule.
 */
async function recomputeRaceProgressForUser(
  db: D1Database,
  race: RaceRow,
  userId: string,
): Promise<void> {
  const scoring = raceScoringConfigFromRow(race);
  if (!scoring) return;
  const moves = await db
    .prepare(
      "SELECT value FROM move_logs WHERE race_id = ? AND user_id = ? AND status = 'verified' ORDER BY created_at ASC",
    )
    .bind(race.id, userId)
    .all<{ value: number | null }>();

  let score = 0;
  for (const m of moves.results) {
    const v = m.value ?? 0;
    if (scoring.scoringRule === 'maximum_attempt') score = Math.max(score, v);
    else if (scoring.scoringRule === 'minimum_attempt') {
      score = score > 0 ? Math.min(score, v) : v;
    } else score += v;
  }
  const target = scoring.targetValue && scoring.targetValue > 0 ? scoring.targetValue : null;
  const progressPercent = target ? Math.min(100, Math.round((score / target) * 100)) : 0;
  const completed = scoring.format === 'first_to_goal' && Boolean(target && score >= target);

  await db
    .prepare(
      `UPDATE race_progress
       SET progress_value = ?, progress_percent = ?,
           completed_at = CASE WHEN ? THEN COALESCE(completed_at, CURRENT_TIMESTAMP) ELSE NULL END,
           updated_at = CURRENT_TIMESTAMP
       WHERE race_id = ? AND user_id = ?`,
    )
    .bind(score, progressPercent, completed ? 1 : 0, race.id, userId)
    .run();
  await recomputeRanks(db, race.id, scoreDirectionFor(race));
}

async function applyMoveProgress(db: D1Database, race: RaceRow, userId: string, value: number): Promise<ScoredSubmission> {
  const scoring = raceScoringConfigFromRow(race);
  if (!scoring) throw new Error('Race is missing activity configuration');
  const increment = Math.max(0, Math.floor(value));
  if (increment <= 0) throw new Error('Verified value must be greater than 0');
  const direction = scoreDirectionFor(race);

  const progress = await db.prepare(
    'SELECT progress_value, completed_at FROM race_progress WHERE race_id = ? AND user_id = ?'
  ).bind(race.id, userId).first<RaceProgressRow>();
  if (!progress) throw new Error('Only race participants can submit proof');

  const current = progress?.progress_value ?? 0;
  // One pre-submission ranking captures both the submitter's previous rank
  // and the leader who may be displaced — no second scan.
  const rankedBefore = await rankedScores(db, race.id, direction);
  const previousRank = rankedBefore.find((row) => row.user_id === userId)?.rank ?? null;
  const leaderBefore = rankedBefore[0]?.user_id ?? null;

  const scored = applyVerifiedSubmission({
    format: scoring.format,
    scoringRule: scoring.scoringRule,
    previousScore: current,
    submissionValue: increment,
    targetValue: scoring.targetValue,
  });
  const completedAt = scored.completed && !progress?.completed_at
    ? new Date().toISOString()
    : progress.completed_at ?? null;

  await db.prepare(
    `UPDATE race_progress SET progress_value = ?, progress_percent = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
     WHERE race_id = ? AND user_id = ?`
  ).bind(scored.newScore, scored.progressPercent, completedAt, race.id, userId).run();
  const ranked = await recomputeRanks(db, race.id, direction);
  const newRank = ranked.find((row) => row.user_id === userId)?.rank ?? null;
  const leaderAfter = ranked[0]?.user_id ?? null;

  let raceCompleted = false;
  let winnerUserId: string | null = race.winner_user_id ?? null;
  const effectiveStatus = effectiveRaceStatus(race.status, race.start_at, race.end_at);
  if (scored.completed && effectiveStatus === 'active') {
    const completionUpdate = await db.prepare(
      `UPDATE races SET status = 'completed', winner_user_id = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'active'`
    ).bind(userId, completedAt, race.id).run();
    const changed = completionUpdate.meta.changes ?? 0;
    if (changed > 0) {
      raceCompleted = true;
      winnerUserId = userId;
      await snapshotFinalStandings(db, race.id);
    } else {
      const closedRace = await getRace(db, race.id);
      winnerUserId = closedRace?.winner_user_id ?? winnerUserId;
    }
  }

  // Live-poll version counter + durable domain events.
  await db.prepare('UPDATE races SET version = COALESCE(version, 0) + 1 WHERE id = ?').bind(race.id).run();

  const events: RaceEventInput[] = [
    {
      type: 'progress_accepted',
      actorUserId: userId,
      subjectUserId: userId,
      payload: {
        value: increment,
        previousScore: current,
        newScore: scored.newScore,
        previousRank,
        newRank,
        format: scoring.format,
      },
    },
  ];
  if (previousRank !== null && newRank !== null && newRank !== previousRank) {
    // Members whose rank sat between the submitter's new and old rank were
    // just overtaken — the notification policy decides which of those drops
    // are worth an interruption (podium contention / crew only).
    const overtakenUserIds = rankedBefore
      .filter(
        (r) =>
          r.user_id !== userId &&
          r.rank >= newRank &&
          r.rank < previousRank,
      )
      .map((r) => r.user_id)
      .slice(0, 50);
    events.push({
      type: 'rank_changed',
      actorUserId: userId,
      subjectUserId: userId,
      payload: { previousRank, newRank, overtakenUserIds },
    });
  }
  // Lead change = a different member now holds rank 1. Subject is the
  // displaced leader so consumers can target the overtake notification.
  if (leaderAfter && leaderBefore !== leaderAfter) {
    events.push({
      type: 'lead_changed',
      actorUserId: leaderAfter,
      subjectUserId: leaderBefore,
      payload: { newLeaderUserId: leaderAfter, displacedUserId: leaderBefore },
    });
  }
  const finished = scored.completed;
  if (finished) {
    events.push({
      type: 'participant_finished',
      actorUserId: userId,
      subjectUserId: userId,
      payload: { score: scored.newScore, finishedAt: completedAt },
    });
  }
  if (raceCompleted && winnerUserId) {
    events.push(
      {
        type: 'race_finished',
        payload: {
          title: race.title,
          format: scoring.format,
          winnerUserId,
          tiedForFirst: false,
          topScore: scored.newScore,
        },
      },
      {
        type: 'winner_determined',
        subjectUserId: winnerUserId,
        payload: { score: scored.newScore, rank: 1, tied: false },
      },
    );
  }
  await recordRaceEvents(db, race.id, events);

  const memberIds = ranked.map((row) => row.user_id);

  return {
    verifiedValue: increment,
    previousScore: current,
    newScore: scored.newScore,
    previousRank,
    newRank,
    peoplePassed: previousRank && newRank && newRank < previousRank ? previousRank - newRank : 0,
    raceCompleted,
    winnerUserId,
    events,
    memberIds,
    leaderUserIdBefore: leaderBefore,
    finished,
  };
}

type ParticipantRow = { id: string; user_id: string; joined_at: string; finished_at?: string | null; display_name: string; profile_photo_url: string | null; private_profile: number | null; username: string | null; progress_value: number; progress_percent: number; rank_cache: number | null };
type MoveRow = MoveLogRow & { display_name: string; profile_photo_url: string | null; private_profile: number | null; username: string | null };
type StandingRow = { user_id: string; rank_position: number; score_value: number; completed_at: string | null; display_name: string; profile_photo_url: string | null; private_profile: number | null; username: string | null };

/// Viewer-level visibility inputs (crew allowlist + block set) — the same for
/// every race in one request, computed once instead of once per race.
async function loadViewerVisibilityContext(
  db: D1Database,
  viewerUserId: string | undefined,
): Promise<{ allowedIds: Set<string>; blockedEitherWay: Set<string> }> {
  const allowedIds = new Set<string>();
  const blockedEitherWay = new Set<string>();
  if (!viewerUserId) return { allowedIds, blockedEitherWay };
  allowedIds.add(viewerUserId);
  const [crew, blocked, blockedBy] = await Promise.all([
    db.prepare("SELECT crew_user_id FROM crew_connections WHERE user_id = ? AND status = 'active'").bind(viewerUserId).all<{ crew_user_id: string }>(),
    db.prepare('SELECT blocked_user_id FROM blocked_users WHERE user_id = ?').bind(viewerUserId).all<{ blocked_user_id: string }>(),
    db.prepare('SELECT user_id FROM blocked_users WHERE blocked_user_id = ?').bind(viewerUserId).all<{ user_id: string }>(),
  ]);
  for (const r of crew.results) allowedIds.add(r.crew_user_id);
  for (const r of blocked.results) blockedEitherWay.add(r.blocked_user_id);
  for (const r of blockedBy.results) blockedEitherWay.add(r.user_id);
  return { allowedIds, blockedEitherWay };
}

/// Shapes one race's API response from its already-fetched sub-collections.
/// Pure/no I/O — shared by the single-race path (buildRaceResponse) and the
/// batched list path (buildRaceResponsesBatch) so both produce an identical
/// shape from a single source of truth.
function shapeRaceResponse(
  race: RaceRow,
  collections: { participants: ParticipantRow[]; moves: MoveRow[]; invite: InviteRow | null; finalStandings: StandingRow[]; levels?: ReadonlyMap<string, number> },
  viewerUserId: string | undefined,
  visibilityCtx: { allowedIds: Set<string>; blockedEitherWay: Set<string> },
  submissionResult?: SubmissionResult,
  releasedSpec?: Record<string, unknown> | null,
  viewerAttempts?: { used: number; openAttemptId: string | null },
) {
  const { participants, moves, invite, finalStandings } = collections;
  const levels = collections.levels ?? new Map<string, number>();
  const { allowedIds, blockedEitherWay } = visibilityCtx;

  // Being in the same race is itself an opt-in relationship: fellow racers see
  // each other's race identity (name + photo) even with a private profile —
  // a leaderboard / "someone passed you" is unreadable otherwise. Only when
  // the viewer is themselves in this race; blocking still wins.
  const coRacerIds = new Set<string>();
  const viewerIsParticipant = Boolean(
    viewerUserId && participants.some((p) => p.user_id === viewerUserId),
  );
  if (viewerIsParticipant) {
    for (const p of participants) {
      if (p.user_id) coRacerIds.add(p.user_id);
    }
  }

  function visibleFor(row: { user_id: string | null; display_name: string; profile_photo_url: string | null; private_profile: number | null; username?: string | null }): { displayName: string; profilePhotoUrl: string | null; anonymized: boolean } {
    const v = resolveRaceMemberVisibility(
      viewerUserId,
      {
        userId: row.user_id,
        displayName: row.display_name,
        username: row.username ?? null,
        profilePhotoUrl: row.profile_photo_url,
        privateProfile: Boolean(row.private_profile),
      },
      { crewIds: allowedIds, blockedEitherWay, coRacerIds },
    );
    return { displayName: v.displayName, profilePhotoUrl: v.profilePhotoUrl, anonymized: v.anonymized };
  }

  const proofRequirement = mapVerificationTypeToProofRequirement(race.verification_type);
  const config = raceConfigFromRow(race);
  const scoring = raceScoringConfigFromRow(race);
  const verifier = parsedVerifierSpec(race, releasedSpec);
  const isCustomVerifier = race.verifier_type === CUSTOM_VERIFIER_TYPE;
  const effectiveStatus = effectiveRaceStatus(race.status, race.start_at, race.end_at);
  const scoreDirection = scoreDirectionFor(race);
  const now = new Date();

  const viewerContext = computeViewerContext({
    raceId: race.id,
    format: scoring?.format ?? 'first_to_goal',
    targetValue: race.target_value,
    startAt: race.start_at,
    endAt: race.end_at,
    storedStatus: race.status,
    winnerUserId: race.winner_user_id ?? null,
    scoreDirection,
    attemptLimit: race.attempt_limit ?? null,
    attemptDurationSeconds: race.attempt_duration_seconds ?? null,
    standings: participants.map((p) => ({
      userId: p.user_id,
      score: p.progress_value ?? 0,
      rank: p.rank_cache,
      finishedAt: p.finished_at ?? null,
    })),
    attemptsUsed: viewerAttempts?.used ?? 0,
    openAttemptId: viewerAttempts?.openAttemptId ?? null,
    viewerUserId,
    now,
  });

  return {
    id: race.id,
    creatorId: race.creator_id,
    title: race.title,
    description: race.description,
    category: '',
    goalType: mapRaceTypeToGoalType(race.race_type),
    activityId: isCustomVerifier ? null : config?.activityId ?? normalizeActivityIdLoose(race.activity_id ?? race.movement_type) ?? null,
    metric: isCustomVerifier ? scoring?.metric ?? 'reps' : config?.metric ?? normalizeMetric(race.metric ?? race.target_unit, config ? activityForId(config.activityId) : undefined) ?? null,
    format: scoring?.format ?? 'first_to_goal',
    scoringRule: scoring?.scoringRule ?? 'cumulative_sum',
    attemptDurationSeconds: race.attempt_duration_seconds ?? null,
    attemptLimit: race.attempt_limit ?? null,
    verificationMethod: race.verification_method ?? (race.verification_type === 'movecheck' ? 'camera_pose' : race.verification_type),
    verifierType: race.verifier_type ?? PRESET_VERIFIER_TYPE,
    verifierVersion: race.verifier_version ?? null,
    verifierSpec: verifier.spec,
    verifierInvalidReason: verifier.invalidReason,
    customActivityName: race.custom_activity_name ?? null,
    timezone: race.timezone ?? 'America/New_York',
    recurrence: race.recurrence ?? 'none',
    targetValue: race.target_value,
    unit: race.target_unit,
    aiActivityType: isCustomVerifier ? null : race.movement_type,
    targetUnit: race.target_unit,
    proofMode: proofRequirement,
    status: effectiveStatus,
    storedStatus: race.status,
    winnerUserId: race.winner_user_id ?? null,
    completedAt: race.completed_at ?? null,
    verifierReleaseId: race.verifier_release_id ?? null,
    scoreDirection,
    version: race.version ?? 0,
    leaderUserId: participants.length > 0 ? participants[0].user_id : null,
    serverTime: now.toISOString(),
    viewerContext,
    startLineAt: race.start_at,
    finishLineAt: race.end_at,
    rules: '',
    proofRequirement,
    proofReviewMode: race.proof_review_mode ?? 'auto_accept',
    visibility: race.visibility,
    // The invite code is insider data — returning it to a non-member would
    // hand any signed-in user the key to join the race.
    inviteCode: viewerIsParticipant || viewerUserId === race.creator_id
      ? invite?.invite_code ?? null
      : null,
    createdAt: race.created_at,
    updatedAt: race.updated_at,
    participants: participants.map((p) => {
      const visible = visibleFor(p);
      return {
        id: p.id,
        userId: p.user_id,
        displayName: visible.displayName,
        profilePhotoUrl: visible.profilePhotoUrl,
        progressValue: p.progress_value ?? 0,
        progressPercent: p.progress_percent ?? 0,
        rank: p.rank_cache,
        joinedAt: p.joined_at,
        finishedAt: p.finished_at ?? null,
        // Nuvo Level is part of race identity — exposed to whoever can see
        // this racer's identity here, masked with it otherwise.
        level: visible.anonymized || !p.user_id ? null : levels.get(p.user_id) ?? null,
      };
    }),
    recentProofs: moves.map((m) => {
      const meta = parseMetadata(m.metadata_json);
      const isMovecheck = m.source === 'movecheck';
      const visible = visibleFor(m);
      // Evidence is participant-only media — never hand a spectator a URL.
      const mediaUrl = viewerIsParticipant && m.media_object_key
        ? `/races/${race.id}/proof-media/object/${encodeKeyPath(m.media_object_key)}`
        : null;
      let status: string;
      if (m.status === 'verified') status = isMovecheck ? 'ai_verified' : 'accepted';
      else if (m.status === 'rejected') status = 'rejected';
      else status = isMovecheck ? 'needs_review' : 'submitted';
      return {
        id: m.id,
        userId: m.user_id,
        displayName: visible.displayName,
        profilePhotoUrl: visible.profilePhotoUrl,
        proofType: isMovecheck ? 'ai_motion' : 'manual',
        aiActivityType: m.movement_type,
        note: m.summary,
        value: m.value,
        detectedValue: (meta.detected_value as number | undefined) ?? m.value,
        targetValue: (meta.target_value as number | undefined) ?? null,
        confidence: (meta.confidence as number | undefined) ?? null,
        validatorVersion: m.validator_version,
        framesAnalyzed: (meta.frames_analyzed as number | undefined) ?? null,
        validPoseFrames: (meta.valid_pose_frames as number | undefined) ?? null,
        durationMs: m.duration_ms,
        mediaUrl,
        verificationStatus: status,
        verificationSummary: m.summary,
        reviewedBy: null,
        reviewedAt: null,
        rankBefore: m.previous_rank ?? null,
        rankAfter: m.new_rank ?? null,
        peoplePassed: (m.previous_rank && m.new_rank && m.new_rank < m.previous_rank) ? m.previous_rank - m.new_rank : null,
        createdAt: m.created_at,
      };
    }),
    finalStandings: finalStandings.map((row) => {
      const visible = visibleFor(row);
      return {
        userId: row.user_id,
        displayName: visible.displayName,
        profilePhotoUrl: visible.profilePhotoUrl,
        rank: row.rank_position,
        scoreValue: row.score_value,
        completedAt: row.completed_at,
        level: visible.anonymized ? null : levels.get(row.user_id) ?? null,
      };
    }),
    submissionResult: submissionResult ?? null,
  };
}

/** One batched level lookup for every racer on a response — Nuvo Level is
 * part of race identity, masked by the same visibility rule as the name. */
async function levelsForUsers(
  db: D1Database,
  userIds: Iterable<string | null | undefined>,
): Promise<Map<string, number>> {
  const ids = [...new Set([...userIds].filter((x): x is string => Boolean(x)))];
  const map = new Map<string, number>();
  if (ids.length === 0) return map;
  const rows = await db
    .prepare(
      `SELECT user_id, level FROM user_progression
       WHERE user_id IN (${ids.map(() => '?').join(',')})`,
    )
    .bind(...ids)
    .all<{ user_id: string; level: number }>();
  for (const r of rows.results) map.set(r.user_id, r.level);
  return map;
}

/// Single-race response — detail/create/join/proof endpoints. Fetches this
/// race's sub-collections plus the viewer's visibility context, then shapes.
async function buildRaceResponse(
  env: AppEnv['Bindings'],
  viewerUserId: string | undefined,
  race: RaceRow,
  submissionResult?: SubmissionResult,
) {
  const db = env.DB;
  // Lazy lifecycle: correctness never waits for cron. A read that crosses a
  // start line emits race_started once; a read past end_at finalizes
  // (atomic claim inside — concurrent callers can't double-finalize).
  // Transitions must also reach the notification policy HERE — the cron
  // sweep only scans still-active races, so an edge claimed by this read
  // would otherwise produce its durable events but lose its notifications.
  const now = new Date();
  const transitions: LifecycleTransitionLike[] = [];
  if (race.status === 'active') {
    if (race.end_at && new Date(race.end_at).getTime() <= now.getTime()) {
      const fin = await finalizeRaceIfEnded(db, race, now);
      if (fin.finalized) {
        race = { ...race, status: 'completed', completed_at: race.end_at, winner_user_id: fin.winnerUserId };
        transitions.push({ race, events: fin.events });
      }
    } else if (race.start_at && new Date(race.start_at).getTime() <= now.getTime()) {
      if (await markRaceStartedIfDue(db, race, now)) {
        transitions.push({
          race,
          events: [{ type: 'race_started', payload: { title: race.title, startAt: race.start_at } }],
        });
      }
    }
  }
  if (transitions.length > 0) {
    await notifyLifecycleTransitions(env, undefined, transitions);
  }

  const viewerAttempts = viewerUserId && formatUsesAttempts((race.format ?? race.race_type) as string)
    ? {
        used: await attemptsUsed(db, race.id, viewerUserId),
        openAttemptId: (
          await db
            .prepare("SELECT id FROM race_attempts WHERE race_id = ? AND user_id = ? AND status = 'open'")
            .bind(race.id, viewerUserId)
            .first<{ id: string }>()
        )?.id ?? null,
      }
    : undefined;

  const [participants, moves, invite, finalStandings, release] = await Promise.all([
    db.prepare(
      `SELECT rm.id, rm.user_id, rm.joined_at, rm.finished_at,
              COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name,
              COALESCE(rm.cached_avatar_url, p.avatar_url) as profile_photo_url,
              p.private_profile,
              p.username,
              rp.progress_value, rp.progress_percent, rp.rank_cache
       FROM race_members rm
       LEFT JOIN profiles p ON p.user_id = rm.user_id
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'
       ORDER BY COALESCE(rp.rank_cache, 9999) ASC, rp.progress_value DESC, rm.joined_at ASC`
    ).bind(race.id).all<ParticipantRow>(),
    db.prepare(
      `SELECT ml.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url, p.private_profile, p.username
       FROM move_logs ml
       LEFT JOIN profiles p ON p.user_id = ml.user_id
       WHERE ml.race_id = ? AND ml.status != 'removed'
       ORDER BY ml.created_at DESC LIMIT 20`
    ).bind(race.id).all<MoveRow>(),
    db.prepare(
      `SELECT * FROM race_invites WHERE race_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1`
    ).bind(race.id).first<InviteRow>(),
    db.prepare(
      `SELECT fs.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url, p.private_profile, p.username
       FROM race_final_standings fs
       LEFT JOIN profiles p ON p.user_id = fs.user_id
       WHERE fs.race_id = ?
       ORDER BY fs.rank_position ASC`
    ).bind(race.id).all<StandingRow>(),
    race.verifier_release_id
      ? readMotionRelease(db, race.verifier_release_id)
      // Older preset races may not have received a registry assignment. Feed
      // the current stable spec to the client so Verify can open, then let the
      // verification-session route persist the repaired assignment.
      : race.activity_id
      ? stableReleaseForActivity(db, race.activity_id, viewerUserId)
      : Promise.resolve(null),
  ]);

  const [visibilityCtx, levels] = await Promise.all([
    loadViewerVisibilityContext(db, viewerUserId),
    levelsForUsers(db, [
      ...participants.results.map((p) => p.user_id),
      ...finalStandings.results.map((s) => s.user_id),
    ]),
  ]);
  return shapeRaceResponse(
    race,
    { participants: participants.results, moves: moves.results, invite, finalStandings: finalStandings.results, levels },
    viewerUserId,
    visibilityCtx,
    submissionResult,
    release?.spec ?? null,
    viewerAttempts,
  );
}

/// Group rows that carry a `race_id` by that id, in their existing order.
/// `cap` keeps only the first N per group (rows must already be pre-sorted
/// per-race, e.g. `ORDER BY race_id, created_at DESC`).
function groupByRaceId<T extends { race_id: string }>(rows: T[], cap?: number): Map<string, T[]> {
  const map = new Map<string, T[]>();
  for (const row of rows) {
    const list = map.get(row.race_id) ?? [];
    if (cap === undefined || list.length < cap) list.push(row);
    map.set(row.race_id, list);
  }
  return map;
}

/// Batched list response — GET /races. Arena's snapshot endpoint proved the
/// pattern (docs/agents/18): one query for the race list, then ONE batched
/// query per sub-collection across every race (`WHERE race_id IN (...)`)
/// instead of building each race's response one at a time. The previous
/// version called buildRaceResponse in a sequential for-loop — 1 + N*7
/// queries, awaited one race at a time — which is exactly the N+1 request
/// waterfall that made Compete/Verify (both backed by this endpoint) slow
/// to populate while Arena's already-batched /arena endpoint loaded fast.
async function buildRaceResponsesBatch(
  env: AppEnv['Bindings'],
  viewerUserId: string,
  races: RaceRow[],
): Promise<unknown[]> {
  if (races.length === 0) return [];
  const db = env.DB;

  // Lazy lifecycle on the read path: ended races finalize once (atomic
  // claim), races past their start line emit race_started once — and the
  // transitions publish here, or their notifications are lost (the sweep
  // only scans still-active races).
  const now = new Date();
  const transitions: LifecycleTransitionLike[] = [];
  for (const race of races) {
    if (race.status !== 'active') continue;
    if (race.end_at && new Date(race.end_at).getTime() <= now.getTime()) {
      const fin = await finalizeRaceIfEnded(db, race, now);
      if (fin.finalized) {
        race.status = 'completed';
        race.completed_at = race.end_at;
        race.winner_user_id = fin.winnerUserId;
        transitions.push({ race: { ...race }, events: fin.events });
      }
    } else if (race.start_at && new Date(race.start_at).getTime() <= now.getTime()) {
      if (await markRaceStartedIfDue(db, race, now)) {
        transitions.push({
          race,
          events: [{ type: 'race_started', payload: { title: race.title, startAt: race.start_at } }],
        });
      }
    }
  }
  if (transitions.length > 0) {
    await notifyLifecycleTransitions(env, undefined, transitions);
  }

  const ids = races.map((r) => r.id);
  const placeholders = ids.map(() => '?').join(', ');

  const [participantsRows, movesRows, invitesRows, standingsRows, visibilityCtx] = await Promise.all([
    db.prepare(
      `SELECT rm.race_id, rm.id, rm.user_id, rm.joined_at, rm.finished_at,
              COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name,
              COALESCE(rm.cached_avatar_url, p.avatar_url) as profile_photo_url,
              p.private_profile, p.username,
              rp.progress_value, rp.progress_percent, rp.rank_cache
       FROM race_members rm
       LEFT JOIN profiles p ON p.user_id = rm.user_id
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id IN (${placeholders}) AND rm.status = 'active'
       ORDER BY rm.race_id, COALESCE(rp.rank_cache, 9999) ASC, rp.progress_value DESC, rm.joined_at ASC`
    ).bind(...ids).all<ParticipantRow & { race_id: string }>(),
    db.prepare(
      `SELECT ml.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url, p.private_profile, p.username
       FROM move_logs ml
       LEFT JOIN profiles p ON p.user_id = ml.user_id
       WHERE ml.race_id IN (${placeholders}) AND ml.status != 'removed'
       ORDER BY ml.race_id, ml.created_at DESC`
    ).bind(...ids).all<MoveRow & { race_id: string }>(),
    db.prepare(
      `SELECT * FROM race_invites WHERE race_id IN (${placeholders}) AND status = 'active'
       ORDER BY race_id, created_at DESC`
    ).bind(...ids).all<InviteRow>(),
    db.prepare(
      `SELECT fs.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url, p.private_profile, p.username
       FROM race_final_standings fs
       LEFT JOIN profiles p ON p.user_id = fs.user_id
       WHERE fs.race_id IN (${placeholders})
       ORDER BY fs.race_id, fs.rank_position ASC`
    ).bind(...ids).all<StandingRow & { race_id: string }>(),
    loadViewerVisibilityContext(db, viewerUserId),
  ]);

  // move_logs is capped at 20 most-recent per race, same as the single-race
  // path — the batched query fetches all matching rows pre-sorted per race,
  // then this caps each group client-side.
  const participantsByRace = groupByRaceId(participantsRows.results);
  const movesByRace = groupByRaceId(movesRows.results, 20);
  const invitesByRace = groupByRaceId(invitesRows.results);
  const standingsByRace = groupByRaceId(standingsRows.results);
  const levels = await levelsForUsers(db, [
    ...participantsRows.results.map((p) => p.user_id),
    ...standingsRows.results.map((s) => s.user_id),
  ]);

  return races.map((race) =>
    shapeRaceResponse(
      race,
      {
        participants: participantsByRace.get(race.id) ?? [],
        moves: movesByRace.get(race.id) ?? [],
        invite: (invitesByRace.get(race.id) ?? [])[0] ?? null,
        finalStandings: standingsByRace.get(race.id) ?? [],
        levels,
      },
      viewerUserId,
      visibilityCtx,
    ),
  );
}

function badRequest(error: string) {
  return { ok: false, error };
}

// POST /races/join-code
racesRouter.post('/join-code', async (c) => {
  const userId = c.get('userId');
  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (!code) return c.json(badRequest('Invite code is required'), 400);

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before joining a race' }, 403);
  }

  const invite = await c.env.DB.prepare(
    `SELECT * FROM race_invites WHERE invite_code = ? AND status = 'active'
     AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)`
  ).bind(code).first<InviteRow>();
  if (!invite) return c.json(badRequest('Invite code not found'), 404);

  const race = await getRace(c.env.DB, invite.race_id);
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);
  if (await isBlockedEitherWay(c.env.DB, userId, race.creator_id)) {
    return c.json(badRequest('You cannot join this race'), 403);
  }

  const wasMember = await isRaceMember(c.env.DB, race.id, userId);
  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);
  await notifyRaceJoined(c, race, userId, wasMember);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// GET /races
racesRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const rows = await c.env.DB.prepare(
    `SELECT DISTINCT r.* FROM races r
     LEFT JOIN race_members rm ON rm.race_id = r.id AND rm.user_id = ? AND rm.status = 'active'
     WHERE r.deleted_at IS NULL AND (r.creator_id = ? OR rm.user_id IS NOT NULL)
     ORDER BY r.created_at DESC`
  ).bind(userId, userId).all<RaceRow>();
  let races: unknown[];
  try {
    races = await buildRaceResponsesBatch(c.env, userId, rows.results);
  } catch (err) {
    // Batch failed for the whole page (e.g. one bad row) — fall back to the
    // slower per-race path so one corrupt race doesn't blank the entire list.
    const message = err instanceof Error ? err.message : String(err);
    console.error('[races] GET /races batch failed, falling back per-race:', message);
    races = [];
    for (const row of rows.results) {
      try {
        races.push(await buildRaceResponse(c.env, userId, row));
      } catch (rowErr) {
        const rowMessage = rowErr instanceof Error ? rowErr.message : String(rowErr);
        console.error('[races] GET /races skipping corrupt race:', row.id, rowMessage);
      }
    }
  }
  return c.json({ ok: true, races });
});

// POST /races
racesRouter.post('/', async (c) => {
  const userId = c.get('userId');

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before creating a race' }, 403);
  }

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!title) return c.json(badRequest('title is required'), 400);

  // FlexiRace safety boundary — the client may interpret anything, but the
  // server is the last word on what becomes a race (raceSafety.ts mirrors the
  // Dart category policy).
  const raceSubjectText = `${title} ${stringOrNull(body.customActivityName) ?? stringOrNull(body.custom_activity_name) ?? ''}`.trim();
  const safety = evaluateRaceSafety(raceSubjectText);
  if (!safety.ok) {
    return c.json({ ok: false, error: safety.reason, safetyCategory: safety.category }, 400);
  }

  const raceTypeRaw = typeof body.goalType === 'string' ? body.goalType : 'manual';
  const verificationRaw = typeof body.proofRequirement === 'string' ? body.proofRequirement : 'manual';
  const customConfig = customConfigFromBody(body);
  if (customConfig && 'error' in customConfig) {
    return c.json(badRequest(customConfig.error), 400);
  }
  const isCustomConfig = Boolean(customConfig);

  const manualConfig = isCustomConfig ? null : manualConfigFromBody(body);
  if (manualConfig && 'error' in manualConfig) {
    return c.json(badRequest(manualConfig.error), 400);
  }
  const manual = manualConfig && !('error' in manualConfig) ? manualConfig : null;

  const verificationType = isCustomConfig
    ? 'movecheck'
    : mapProofRequirementToVerificationType(verificationRaw);
  let structuredConfig = isCustomConfig || manual ? null : configFromBody(body);
  if (!isCustomConfig && !manual && structuredConfig && 'error' in structuredConfig) {
    // The static catalog rejected the activity — but a control-plane activity
    // this Worker predates may still be legitimate. When the ID normalizes to
    // a safe registry shape, look the activity up in the motion registry and
    // build the config from its published metric/format bounds. Only a
    // supported activity with a live stable pointer can be raced.
    const looseId = normalizeActivityIdLoose(
      stringOrNull(body.activityId) ?? stringOrNull(body.activity_id) ?? stringOrNull(body.aiActivityType),
    );
    const registryActivity = looseId
      ? await readRegistryActivity(c.env.DB, looseId)
      : null;
    if (registryActivity &&
        registryActivity.availability === 'supported' &&
        registryActivity.releaseId) {
      structuredConfig = registryConfigFromBody(body, registryActivity);
    }
  }
  if (!isCustomConfig && !manual && verificationType === 'movecheck' && structuredConfig && 'error' in structuredConfig) {
    return c.json(badRequest(structuredConfig.error), 400);
  }

  const raceId = generateId();
  const description = stringOrNull(body.description) ?? null;
  const config = structuredConfig && !('error' in structuredConfig) ? structuredConfig : null;
  const custom = customConfig && !('error' in customConfig) ? customConfig : null;
  const raceType = manual?.format ?? config?.format ?? mapGoalTypeToRaceType(raceTypeRaw);
  const targetValue = custom?.targetValue ?? manual?.targetValue ?? config?.targetValue ?? positiveIntOrNull(body.targetValue) ?? null;
  // Manual races keep the human unit ("pages") in target_unit; the wire metric
  // is always 'reps'.
  const targetUnit = custom?.metric ?? manual?.unit ?? config?.metric ?? stringOrNull(body.targetUnit) ?? stringOrNull(body.unit) ?? null;
  const movementType = custom || manual ? null : config?.activityId ?? stringOrNull(body.aiActivityType) ?? null;
  const visibility = typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility) ? body.visibility : 'private';
  const startAt = custom?.startsAt ?? manual?.startsAt ?? config?.startsAt ?? stringOrNull(body.startLineAt) ?? null;
  const endAt = custom?.endsAt ?? manual?.endsAt ?? config?.endsAt ?? stringOrNull(body.finishLineAt) ?? null;

  const raceFormat = custom?.format ?? manual?.format ?? config?.format ?? raceType;
  const raceActivityId = custom || manual ? null : config?.activityId ?? normalizeActivityIdLoose(movementType);
  const raceMetric = custom?.metric ?? manual?.metric ?? config?.metric ?? normalizeMetric(stringOrNull(body.metric) ?? targetUnit, activityForId(normalizeActivityIdLoose(movementType)));
  const raceScoringRule = custom?.scoringRule ?? manual?.scoringRule ?? config?.scoringRule ?? 'cumulative_sum';
  const raceAttemptDurationSeconds = custom?.attemptDurationSeconds ?? config?.attemptDurationSeconds ?? null;
  const raceAttemptLimit = custom?.attemptLimit ?? config?.attemptLimit ?? null;
  const raceVerificationMethod = custom?.verificationMethod ?? config?.verificationMethod ?? (verificationType === 'movecheck' ? 'camera_pose' : verificationType);
  const raceTimezone = custom?.timezone ?? manual?.timezone ?? config?.timezone ?? 'America/New_York';
  const raceRecurrence = custom?.recurrence ?? manual?.recurrence ?? config?.recurrence ?? 'none';
  // 'lower' = fastest/lowest verified value wins (time-attack races).
  const raceScoreDirection = body.scoreDirection === 'lower' || body.score_direction === 'lower' ? 'lower' : 'higher';
  // 'peer_review' holds manual submissions pending until the creator accepts;
  // 'auto_accept' (default) scores immediately, rejectable afterwards.
  const raceProofReviewMode = body.proofReviewMode === 'peer_review' || body.proof_review_mode === 'peer_review'
    ? 'peer_review'
    : 'auto_accept';

  // Preset races are assigned to the stable immutable release at creation.
  // Custom-pose and manual races deliberately stay on their existing paths.
  let presetRelease = null;
  if (raceActivityId && !custom && !manual) {
    try {
      presetRelease = await stableReleaseForActivity(c.env.DB, raceActivityId, userId);
    } catch (error) {
      // Keep the pre-0015 compatibility path usable while the registry
      // migration rolls out. A race must never silently point at a wrong
      // verifier; once the registry exists, assignment is transactional.
      console.error('[races] stable verifier lookup unavailable:', error);
    }
  }

  const withVerifierType = custom
    ? { type: custom.verifierType, version: custom.verifierVersion, spec: custom.verifierSpecJson, name: custom.customActivityName }
    : manual
      ? { type: MANUAL_VERIFIER_TYPE, version: null as number | null, spec: null as string | null, name: null as string | null }
      : null;

  const raceStmt = withVerifierType
    ? c.env.DB.prepare(
        `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
          target_value, target_unit, activity_id, metric, format, scoring_rule, attempt_duration_seconds,
          attempt_limit, verification_method, verifier_type, verifier_version, verifier_spec_json, custom_activity_name,
          timezone, recurrence, status, visibility, start_at, end_at, score_direction, proof_review_mode,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
      ).bind(
        raceId,
        userId,
        title,
        description,
        raceFormat,
        movementType,
        verificationType,
        targetValue,
        targetUnit,
        raceActivityId,
        raceMetric,
        raceFormat,
        raceScoringRule,
        raceAttemptDurationSeconds,
        raceAttemptLimit,
        raceVerificationMethod,
        withVerifierType.type,
        withVerifierType.version,
        withVerifierType.spec,
        withVerifierType.name,
        raceTimezone,
        raceRecurrence,
        visibility,
        startAt,
        endAt,
        raceScoreDirection,
        raceProofReviewMode,
      )
    : c.env.DB.prepare(
        `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
          target_value, target_unit, activity_id, metric, format, scoring_rule, attempt_duration_seconds,
          attempt_limit, verification_method, timezone, recurrence, status, visibility, start_at, end_at, score_direction, proof_review_mode,
          created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
      ).bind(
        raceId,
        userId,
        title,
        description,
        raceFormat,
        movementType,
        verificationType,
        targetValue,
        targetUnit,
        raceActivityId,
        raceMetric,
        raceFormat,
        raceScoringRule,
        raceAttemptDurationSeconds,
        raceAttemptLimit,
        raceVerificationMethod,
        raceTimezone,
        raceRecurrence,
        visibility,
        startAt,
        endAt,
        raceScoreDirection,
        raceProofReviewMode,
      );

  const creatorPersonId = await ensurePersonId(c.env.DB, userId);

  try {
    const statements = [
      raceStmt,
      c.env.DB.prepare(
        `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at)
         VALUES (?, ?, ?, ?, 'creator', 'active', CURRENT_TIMESTAMP)`
      ).bind(generateId(), raceId, userId, creatorPersonId),
      c.env.DB.prepare(
        `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
         VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`
      ).bind(generateId(), raceId, userId),
    ];
    if (presetRelease) {
      statements.push(
        assignmentInsert(c.env.DB, raceId, presetRelease),
        c.env.DB.prepare('UPDATE races SET verifier_release_id = ? WHERE id = ?')
          .bind(presetRelease.id, raceId),
      );
    }
    await c.env.DB.batch(statements);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[races] create race DB batch failed:', message);
    if (message.includes('no such column') || message.includes('no column named')) {
      return c.json({ ok: false, error: 'This race type is not supported by the database yet. Please update the server.' }, 503);
    }
    return c.json({ ok: false, error: 'Could not create the race. Please try again.' }, 500);
  }

  const race = await getRace(c.env.DB, raceId);
  if (!race) {
    return c.json({ ok: false, error: 'Race was created but could not be loaded.' }, 500);
  }
  await recomputeRanks(c.env.DB, raceId, raceScoreDirection);
  await recordRaceEvents(c.env.DB, raceId, [
    {
      type: 'race_created',
      actorUserId: userId,
      payload: {
        title,
        format: raceFormat,
        metric: raceMetric,
        targetValue,
        startAt,
        endAt,
        scoreDirection: raceScoreDirection,
      },
    },
  ]);
  // Scheduled start line → "starts in 30 min" reminder job (notification
  // policy owns reminders; the race itself never depends on it firing).
  if (startAt) await scheduleRaceStartingSoon(c.env.DB, raceId, startAt);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) }, 201);
});

// GET /races/:id
racesRouter.get('/:id', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json(badRequest('Race not found'), 404);
  const access = await resolveRaceAccess(c.env.DB, race, c.get('userId'));
  if (!access.canRead) return c.json(badRequest('Race not found'), 404);
  try {
    return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[races] GET /races/:id buildRaceResponse failed:', race.id, message);
    return c.json({ ok: false, error: 'Could not load this race. Please try again.' }, 500);
  }
});

// PATCH /races/:id
racesRouter.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can edit this race'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  // Rule immutability: once competition has begun (any verified proof, or a
  // scheduled start line already passed) the fields that define the
  // competition are locked. Title/description/visibility/status always
  // stay editable — cancel and rename are not rule rewrites.
  const lockedAttempt = lockedFieldsPresent(body);
  if (lockedAttempt.length > 0) {
    const verified = await c.env.DB
      .prepare("SELECT id FROM move_logs WHERE race_id = ? AND status = 'verified' LIMIT 1")
      .bind(race.id)
      .first<{ id: string }>();
    if (
      rulesLocked({ startAt: race.start_at, hasVerifiedMoves: Boolean(verified), now: new Date() })
    ) {
      return c.json(
        badRequest(
          `Race rules are locked once competition starts (${lockedAttempt.join(', ')}). ` +
            'You can still rename the race or cancel it.',
        ),
        409,
      );
    }
  }

  const updates: string[] = [];
  const values: unknown[] = [];

  const textMap: Array<[string, string]> = [
    ['title', 'title'],
    ['description', 'description'],
    ['startLineAt', 'start_at'],
    ['finishLineAt', 'end_at'],
  ];
  for (const [jsonKey, dbKey] of textMap) {
    const parsed = stringOrNull(body[jsonKey]);
    if (parsed !== undefined) {
      if (jsonKey === 'title' && !parsed) return c.json(badRequest('title is required'), 400);
      updates.push(`${dbKey} = ?`);
      values.push(parsed);
    }
  }

  if (typeof body.goalType === 'string') {
    updates.push('race_type = ?');
    values.push(mapGoalTypeToRaceType(body.goalType));
  }
  if (typeof body.aiActivityType === 'string') {
    updates.push('movement_type = ?');
    values.push(body.aiActivityType || null);
  }
  if (typeof body.proofRequirement === 'string') {
    updates.push('verification_type = ?');
    values.push(mapProofRequirementToVerificationType(body.proofRequirement));
  }
  if (typeof body.unit === 'string' || typeof body.targetUnit === 'string') {
    updates.push('target_unit = ?');
    values.push(stringOrNull(body.targetUnit) ?? stringOrNull(body.unit) ?? null);
  }

  const targetValue = positiveIntOrNull(body.targetValue);
  if (targetValue !== undefined) { updates.push('target_value = ?'); values.push(targetValue); }
  if (typeof body.status === 'string' && RACE_STATUSES.has(body.status)) { updates.push('status = ?'); values.push(body.status); }
  if (typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility)) { updates.push('visibility = ?'); values.push(body.visibility); }

  if (updates.length === 0) return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });

  updates.push('updated_at = CURRENT_TIMESTAMP');
  await c.env.DB.prepare(`UPDATE races SET ${updates.join(', ')} WHERE id = ?`).bind(...values, race.id).run();
  const updated = await getRace(c.env.DB, race.id);
  // A moved start line re-arms the pre-start reminder (INSERT OR IGNORE on
  // the job dedupe key keeps this idempotent; stale jobs self-cancel at
  // claim time because they re-check the race's actual start_at).
  if (updated?.start_at) await scheduleRaceStartingSoon(c.env.DB, race.id, updated.start_at);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!) });
});

async function setRaceStatus(c: Context<AppEnv>, status: string) {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can change this race'), 403);
  await c.env.DB.prepare('UPDATE races SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').bind(status, race.id).run();
  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!) });
}

racesRouter.post('/:id/archive', (c) => setRaceStatus(c, 'archived'));
racesRouter.post('/:id/cancel', (c) => setRaceStatus(c, 'cancelled'));

// DELETE /races/:id
racesRouter.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can delete this race'), 403);
  await c.env.DB.prepare('UPDATE races SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?').bind(race.id).run();
  return c.json({ ok: true });
});

// POST /races/:id/leave
racesRouter.post('/:id/leave', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id === userId) return c.json(badRequest('Race creator cannot leave their own race'), 400);
  await c.env.DB.prepare(
    "UPDATE race_members SET status = 'left' WHERE race_id = ? AND user_id = ?"
  ).bind(race.id, userId).run();
  return c.json({ ok: true });
});

// POST /races/:id/join
racesRouter.post('/:id/join', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);
  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before joining a race' }, 403);
  }
  const eligibility = await checkRaceJoinEligibility(c.env.DB, race, userId);
  if (!eligibility.ok) return c.json(badRequest(eligibility.error), eligibility.status as 400 | 403);
  const wasMember = await isRaceMember(c.env.DB, race.id, userId);
  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);
  await notifyRaceJoined(c, race, userId, wasMember);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// POST /races/:id/participants
racesRouter.post('/:id/participants', async (c) => {
  const userId = c.get('userId');

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before adding race participants' }, 403);
  }

  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  // Organizer flow only — an ordinary participant must not silently insert
  // arbitrary users into a race.
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can add participants'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }
  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!targetUserId) return c.json(badRequest('userId is required'), 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetUserId).first<{ id: string }>();
  if (!target) return c.json(badRequest('User not found'), 404);
  if (await isBlockedEitherWay(c.env.DB, userId, targetUserId)) {
    return c.json(badRequest('You cannot add this user'), 403);
  }

  const targetWasMember = await isRaceMember(c.env.DB, race.id, targetUserId);
  await ensureMember(c.env.DB, race.id, targetUserId);
  await ensureProgress(c.env.DB, race.id, targetUserId);
  if (!targetWasMember && targetUserId !== userId) {
    const actorName = await getProfileName(c.env.DB, userId);
    await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
      type: 'race_invited',
      userId: targetUserId,
      actorUserId: userId,
      actorName,
      raceId: race.id,
      raceTitle: race.title,
    });
  }
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// POST /races/:id/members (new endpoint, same as /participants)
racesRouter.post('/:id/members', async (c) => {
  const userId = c.get('userId');

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before adding race members' }, 403);
  }

  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  // Organizer flow only — an ordinary participant must not silently insert
  // arbitrary users into a race.
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can add members'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }
  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!targetUserId) return c.json(badRequest('userId is required'), 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetUserId).first<{ id: string }>();
  if (!target) return c.json(badRequest('User not found'), 404);
  if (await isBlockedEitherWay(c.env.DB, userId, targetUserId)) {
    return c.json(badRequest('You cannot add this user'), 403);
  }

  const targetWasMember = await isRaceMember(c.env.DB, race.id, targetUserId);
  await ensureMember(c.env.DB, race.id, targetUserId);
  await ensureProgress(c.env.DB, race.id, targetUserId);
  if (!targetWasMember && targetUserId !== userId) {
    const actorName = await getProfileName(c.env.DB, userId);
    await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
      type: 'race_invited',
      userId: targetUserId,
      actorUserId: userId,
      actorName,
      raceId: race.id,
      raceTitle: race.title,
    });
  }
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// DELETE /races/:id/members/:userId
racesRouter.delete('/:id/members/:userId', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can remove members'), 403);

  const targetUserId = c.req.param('userId');
  if (targetUserId === race.creator_id) return c.json(badRequest('Cannot remove the race creator'), 400);

  await c.env.DB.prepare(
    "UPDATE race_members SET status = 'removed' WHERE race_id = ? AND user_id = ?"
  ).bind(race.id, targetUserId).run();
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// POST /races/:id/invite-code
racesRouter.post('/:id/invite-code', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can invite crew'), 403);

  const existing = await c.env.DB.prepare(
    `SELECT * FROM race_invites WHERE race_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1`
  ).bind(race.id).first<InviteRow>();
  if (existing) return c.json({ ok: true, inviteCode: existing.invite_code, race: await buildRaceResponse(c.env, c.get('userId'), race) });

  let code = generateInviteCode();
  for (let i = 0; i < 5; i++) {
    const taken = await c.env.DB.prepare('SELECT id FROM race_invites WHERE invite_code = ?').bind(code).first<{ id: string }>();
    if (!taken) break;
    code = generateInviteCode();
  }

  await c.env.DB.prepare(
    `INSERT INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
     VALUES (?, ?, ?, ?, 'active', CURRENT_TIMESTAMP)`
  ).bind(generateId(), race.id, userId, code).run();
  return c.json({ ok: true, inviteCode: code, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// POST /races/:id/move-log
racesRouter.post('/:id/move-log', async (c) => {
  const userId = c.get('userId');

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before submitting proof' }, 403);
  }

  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  // One authoritative lifecycle check — same eligibility as /proof. A
  // scheduled race cannot silently accept progress before its start line.
  if (effectiveRaceStatus(race.status, race.start_at, race.end_at) !== 'active') {
    return c.json(badRequest('Race is not active'), 400);
  }

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const source = typeof body.source === 'string' && MOVE_SOURCES.has(body.source) ? body.source : 'manual';
  const value = nonNegativeIntOrNull(body.value) ?? 0;
  const movementType = stringOrNull(body.movementType) ?? race.movement_type;
  const unit = stringOrNull(body.unit) ?? race.target_unit;
  const status = typeof body.status === 'string' && MOVE_STATUSES.has(body.status) ? body.status : 'verified';
  const summary = stringOrNull(body.summary) ?? null;
  const validatorVersion = stringOrNull(body.validatorVersion) ?? null;
  const durationMs = nonNegativeIntOrNull(body.durationMs) ?? null;
  const metadataJson = typeof body.metadata === 'object' && body.metadata !== null
    ? JSON.stringify(body.metadata)
    : null;

  if (source === 'movecheck' && race.verification_type !== 'movecheck') {
    return c.json(badRequest('Race does not support MoveCheck verification'), 400);
  }
  if (source === 'movecheck' && movementType && movementType !== race.movement_type) {
    return c.json(badRequest('Movement type does not match race movement type'), 400);
  }

  // Submitting a move auto-joins the race — enforce the same entry policy as
  // /:id/join so a private-race ID alone cannot mint membership.
  const joinEligibility = await checkRaceJoinEligibility(c.env.DB, race, userId);
  if (!joinEligibility.ok) return c.json(badRequest(joinEligibility.error), joinEligibility.status as 400 | 403);

  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);

  const moveId = generateId();
  await c.env.DB.prepare(
    `INSERT INTO move_logs (id, race_id, user_id, source, movement_type, value, unit, status, summary,
      validator_version, duration_ms, metadata_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
  ).bind(moveId, race.id, userId, source, movementType, value, unit, status, summary, validatorVersion, durationMs, metadataJson).run();

  if (status === 'verified') await applyMoveProgress(c.env.DB, race, userId, value);

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!) });
});

// GET /races/:id/move-logs
racesRouter.get('/:id/move-logs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

  const viewerMember = await isRaceMember(c.env.DB, race.id, c.get('userId'));
  const logs = await c.env.DB.prepare(
    `SELECT ml.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url
     FROM move_logs ml
     LEFT JOIN profiles p ON p.user_id = ml.user_id
     WHERE ml.race_id = ? AND ml.status != 'removed'
     ORDER BY ml.created_at DESC`
  ).bind(race.id).all<MoveLogRow & { display_name: string; profile_photo_url: string | null }>();

  return c.json({
    ok: true,
    moveLogs: logs.results.map((m) => ({
      id: m.id,
      userId: m.user_id,
      displayName: (m as MoveLogRow & { display_name: string }).display_name,
      profilePhotoUrl: m.profile_photo_url,
      source: m.source,
      movementType: m.movement_type,
      value: m.value,
      unit: m.unit,
      mediaUrl: viewerMember && m.media_object_key
        ? `/races/${race.id}/proof-media/object/${encodeKeyPath(m.media_object_key)}`
        : null,
      status: m.status,
      summary: m.summary,
      validatorVersion: m.validator_version,
      durationMs: m.duration_ms,
      metadata: parseMetadata(m.metadata_json),
      createdAt: m.created_at,
    })),
  });
});

// PATCH /races/:id/progress/:userId (founder/demo/internal use)
racesRouter.patch('/:id/progress/:userId', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can edit progress'), 403);

  const targetUserId = c.req.param('userId');
  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const progressValue = nonNegativeIntOrNull(body.progressValue);
  if (progressValue == null) return c.json(badRequest('progressValue is required'), 400);

  await ensureMember(c.env.DB, race.id, targetUserId);
  await ensureProgress(c.env.DB, race.id, targetUserId);

  const newPercent = race.target_value && race.target_value > 0
    ? Math.min(100, Math.round((progressValue / race.target_value) * 100))
    : 0;
  const completedAt = progressValue >= (race.target_value ?? 0) && race.target_value ? new Date().toISOString() : null;

  await c.env.DB.prepare(
    `UPDATE race_progress SET progress_value = ?, progress_percent = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
     WHERE race_id = ? AND user_id = ?`
  ).bind(progressValue, newPercent, completedAt, race.id, targetUserId).run();
  await recomputeRanks(c.env.DB, race.id);

  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), race) });
});

// POST /races/:id/proof - legacy endpoint, maps to move_logs.
racesRouter.post('/:id/proof', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  const config = raceConfigFromRow(race);
  const scoring = raceScoringConfigFromRow(race);
  const isManualRace = race.verifier_type === MANUAL_VERIFIER_TYPE;
  if (
    !scoring ||
    (!config && race.verifier_type !== CUSTOM_VERIFIER_TYPE && !isManualRace)
  ) {
    return c.json(badRequest('Race is missing activity configuration'), 400);
  }
  const member = await c.env.DB.prepare(
    "SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'"
  ).bind(race.id, userId).first<{ id: string }>();
  if (!member) return c.json(badRequest('Only race participants can submit proof'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const proofType = typeof body.proofType === 'string' ? body.proofType : 'manual';
  const isAiMotion = proofType === 'ai_motion';
  const isCustom = race.verifier_type === CUSTOM_VERIFIER_TYPE;
  if (isCustom && !isAiMotion) return c.json(badRequest('Custom races require AI Motion Proof'), 400);
  // Optional evidence attachment: must be a proof_evidence object the
  // submitter uploaded through /proof-media/upload-url for THIS race.
  const mediaObjectKey = stringOrNull(body.mediaObjectKey) ?? stringOrNull(body.media_object_key) ?? null;
  if (mediaObjectKey) {
    const media = await c.env.DB.prepare(
      "SELECT id FROM media_objects WHERE object_key = ? AND owner_user_id = ? AND purpose = 'proof_evidence'",
    ).bind(mediaObjectKey, userId).first<{ id: string }>();
    if (!media || !mediaObjectKey.startsWith(proofMediaKeyPrefix(race.id))) {
      return c.json(badRequest('Evidence was not uploaded for this race'), 400);
    }
  }

  const clientSubmissionId = stringOrNull(body.clientSubmissionId) ?? stringOrNull(body.client_submission_id) ?? null;
  if (isAiMotion && !clientSubmissionId) return c.json(badRequest('clientSubmissionId is required'), 400);
  if (clientSubmissionId) {
    const existing = await c.env.DB.prepare(
      'SELECT * FROM move_logs WHERE race_id = ? AND user_id = ? AND client_submission_id = ?'
    ).bind(race.id, userId, clientSubmissionId).first<MoveLogRow>();
    if (existing) {
      const updated = await getRace(c.env.DB, race.id);
      const result: SubmissionResult | undefined = existing.status === 'verified'
        ? {
          verifiedValue: existing.value ?? 0,
          previousScore: existing.previous_score ?? 0,
          newScore: existing.new_score ?? 0,
          previousRank: existing.previous_rank ?? null,
          newRank: existing.new_rank ?? null,
          peoplePassed: existing.previous_rank && existing.new_rank && existing.new_rank < existing.previous_rank
            ? existing.previous_rank - existing.new_rank
            : 0,
          raceCompleted: Boolean(existing.race_completed),
          winnerUserId: updated?.winner_user_id ?? race.winner_user_id ?? null,
        }
        : undefined;
      return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!, result), submissionResult: result ?? null });
    }
  }
  // Time authority: the server clock decides eligibility. A submission inside
  // the window is always fine; past the deadline it survives only when the
  // client-reported capture time precedes end_at AND arrives within the
  // grace window (bounded clock-skew tolerance — see domain/raceFinalize).
  const capturedAtRaw = stringOrNull(body.capturedAt) ?? stringOrNull(body.captured_at) ?? null;
  const capturedAt = capturedAtRaw ? new Date(capturedAtRaw) : null;
  const eligibility = deadlineEligibility(race, capturedAt, new Date());
  if (eligibility === 'closed') return c.json(badRequest('Race is not active'), 400);

  const value = isAiMotion ? nonNegativeIntOrNull(body.value) : positiveIntOrNull(body.value);
  const increment = value ?? 0;
  if (!isAiMotion && increment <= 0) return c.json(badRequest('value must be greater than 0'), 400);
  if (isAiMotion && increment <= 0) return c.json(badRequest('Verified value must be greater than 0'), 400);

  await ensureProgress(c.env.DB, race.id, userId);

  const activityType = isAiMotion ? stringOrNull(body.activityType) : race.movement_type;
  const metric = isAiMotion
    ? (isCustom ? normalizeMetric(stringOrNull(body.metric) ?? stringOrNull(body.unit) ?? 'reps', undefined) : normalizeMetric(stringOrNull(body.metric) ?? stringOrNull(body.unit), config ? activityForId(config.activityId) : undefined))
    : scoring.metric;
  const compatibilityError = isAiMotion && !isCustom && config ? assertSubmissionCompatible(config, activityType ?? null, metric ?? null) : null;
  if (compatibilityError) return c.json(badRequest(compatibilityError), 400);
  const detectedValue = isAiMotion ? nonNegativeIntOrNull(body.detectedValue) ?? increment : null;
  const targetValue = isAiMotion ? positiveIntOrNull(body.targetValue) ?? null : null;
  const confidence = isAiMotion ? confidenceOrNull(body.confidence) ?? null : null;
  const validatorVersion = isAiMotion ? stringOrNull(body.validatorVersion) ?? 'nuvo-ai-motion-v1' : null;
  const framesAnalyzed = isAiMotion ? nonNegativeIntOrNull(body.framesAnalyzed) ?? null : null;
  const validPoseFrames = isAiMotion ? nonNegativeIntOrNull(body.validPoseFrames) ?? null : null;
  const durationMs = isAiMotion ? nonNegativeIntOrNull(body.durationMs) ?? null : null;
  const completionEvents = isCustom ? nonNegativeIntOrNull(body.completionEvents) ?? null : null;
  const invalidAttemptCount = isCustom ? nonNegativeIntOrNull(body.invalidAttemptCount) ?? null : null;
  const measurementType = isCustom ? stringOrNull(body.measurementType) ?? null : null;

  const aiStatus = typeof body.verificationStatus === 'string' ? body.verificationStatus : '';
  if (isCustom && aiStatus !== 'custom_verified' && aiStatus !== 'custom_failed') {
    return c.json(badRequest('Custom proof verificationStatus is required.'), 400);
  }
  const bodyVerifierType = isCustom ? stringOrNull(body.verifierType) : null;
  const bodyVerifierVersion = isCustom ? body.verifierVersion : null;
  if (isCustom && bodyVerifierType !== race.verifier_type) {
    return c.json(badRequest('Verifier type does not match race.'), 400);
  }
  if (isCustom && (typeof bodyVerifierVersion !== 'number' || bodyVerifierVersion !== race.verifier_version)) {
    return c.json(badRequest('Verifier version does not match race.'), 400);
  }
  if (isCustom && metric !== 'reps') {
    return c.json(badRequest('Custom proof metric must be reps.'), 400);
  }
  if (isCustom && measurementType !== 'count') {
    return c.json(badRequest('Custom proof measurement type must be count.'), 400);
  }
  if (isCustom && activityType !== race.custom_activity_name) {
    return c.json(badRequest('Custom proof movement does not match race.'), 400);
  }
  if (isCustom && detectedValue !== increment) {
    return c.json(badRequest('Custom proof detected value must match value.'), 400);
  }
  if (isCustom && completionEvents !== null && completionEvents < increment) {
    return c.json(badRequest('Custom proof completion events must cover value.'), 400);
  }
  if (isCustom && framesAnalyzed !== null && validPoseFrames !== null && validPoseFrames > framesAnalyzed) {
    return c.json(badRequest('Custom proof valid frames cannot exceed analyzed frames.'), 400);
  }
  let moveStatus: string;
  if (isAiMotion) {
    if (aiStatus === 'ai_verified' || aiStatus === 'custom_verified') moveStatus = 'verified';
    else if (aiStatus === 'ai_failed' || aiStatus === 'custom_failed') moveStatus = 'rejected';
    else moveStatus = 'pending';
  } else {
    // Review policy: 'peer_review' races hold manual values pending until the
    // creator accepts; 'auto_accept' (default) trusts the self-report and the
    // creator can still reject afterwards, which un-scores it.
    moveStatus = race.proof_review_mode === 'peer_review' ? 'pending' : 'verified';
  }

  const metadata = JSON.stringify({
    confidence,
    detected_value: detectedValue,
    target_value: targetValue,
    frames_analyzed: framesAnalyzed,
    valid_pose_frames: validPoseFrames,
    captured_at: capturedAt?.toISOString() ?? null,
    accepted_in_grace: eligibility === 'grace',
    ...(isCustom ? {
      completion_events: completionEvents,
      invalid_attempt_count: invalidAttemptCount,
      measurement_type: measurementType,
      verifier_type: bodyVerifierType,
      verifier_version: bodyVerifierVersion,
    } : {}),
  });

  const summary = stringOrNull(body.verificationSummary) ??
    (isAiMotion
      ? (moveStatus === 'verified'
        ? `Detected ${detectedValue ?? increment} ${activityType?.replaceAll('_', ' ') ?? 'motion'} from live pose tracking.`
        : `Nuvo detected ${detectedValue ?? increment} clean reps out of ${targetValue ?? 'the target'}.`)
      : 'Manual proof accepted.');

  const moveId = generateId();
  await c.env.DB.prepare(
    `INSERT INTO move_logs (id, race_id, user_id, source, movement_type, activity_id, metric, value, unit, status, summary,
      media_object_key, validator_version, duration_ms, metadata_json, client_submission_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
  ).bind(
    moveId,
    race.id,
    userId,
    isAiMotion ? 'movecheck' : 'manual',
    activityType,
    normalizeActivityIdLoose(activityType) ?? null,
    metric ?? scoring.metric,
    increment,
    race.target_unit,
    moveStatus,
    summary,
    mediaObjectKey,
    validatorVersion,
    durationMs,
    metadata,
    clientSubmissionId,
  ).run();

  let result: ScoredSubmission | undefined;
  if (moveStatus === 'verified') {
    // Attempt races require a declared attempt. Auto-bind: the client opens
    // an attempt, then submits proof through this same unchanged payload —
    // the open attempt claims the verified score (duration enforced in
    // bindableOpenAttempt via deadline + grace).
    const usesAttempts = formatUsesAttempts(scoring.format);
    const boundAttempt = usesAttempts ? await bindableOpenAttempt(c.env.DB, race, userId) : null;
    if (usesAttempts && !boundAttempt) {
      await c.env.DB.prepare('UPDATE move_logs SET status = ?, summary = ? WHERE id = ?')
        .bind('rejected', 'No open attempt — start an attempt first.', moveId).run();
      return c.json(badRequest('Start an attempt before submitting a score for this race.'), 400);
    }
    try {
      result = await applyMoveProgress(c.env.DB, race, userId, increment);
      await c.env.DB.prepare(
        `UPDATE move_logs SET previous_score = ?, new_score = ?, previous_rank = ?, new_rank = ?, race_completed = ?
         WHERE id = ?`
      ).bind(
        result.previousScore,
        result.newScore,
        result.previousRank,
        result.newRank,
        result.raceCompleted ? 1 : 0,
        moveId,
      ).run();

      if (boundAttempt) {
        await closeAttempt(c.env.DB, boundAttempt.id, increment, moveId);
        const attemptEvents: RaceEventInput[] = [
          {
            type: 'attempt_completed',
            actorUserId: userId,
            subjectUserId: userId,
            payload: {
              attemptId: boundAttempt.id,
              attemptIndex: boundAttempt.attempt_index,
              score: increment,
              durationSeconds: race.attempt_duration_seconds ?? null,
            },
          },
        ];
        const pb = await recordPersonalBestIfImproved(c.env.DB, race, userId, increment, moveId);
        if (pb.improved) {
          attemptEvents.push({
            type: 'personal_best',
            actorUserId: userId,
            subjectUserId: userId,
            payload: { previousBest: pb.previousBest, newBest: pb.newBest, metric: race.metric ?? 'reps' },
          });
        }
        await recordRaceEvents(c.env.DB, race.id, attemptEvents);
      }

      // Publish the events that map to notification categories
      // (lead_changed → displaced leader, rank_changed → overtaken members
      // in contention, race_finished → all members). The policy itself
      // decides feed-only vs. delivery — the gate here must include every
      // event type it can act on, or a rank-only submission would persist
      // rank_changed but never deliver the overtake notification.
      if (
        result.events.some(
          (e) =>
            e.type === 'lead_changed' ||
            e.type === 'rank_changed' ||
            e.type === 'race_finished',
        )
      ) {
        const memberRows = await c.env.DB
          .prepare(
            `SELECT rm.user_id, COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name
             FROM race_members rm LEFT JOIN profiles p ON p.user_id = rm.user_id
             WHERE rm.race_id = ? AND rm.status = 'active'`,
          )
          .bind(race.id)
          .all<{ user_id: string; display_name: string }>();
        await notifyRaceEvents(
          c.env,
          (p) => c.executionCtx.waitUntil(p),
          race,
          result.events,
          memberRows.results,
        );
      }
    } catch (err) {
      await c.env.DB.prepare('UPDATE move_logs SET status = ?, summary = ? WHERE id = ?')
        .bind('rejected', err instanceof Error ? err.message : 'Submission rejected', moveId).run();
      return c.json(badRequest(err instanceof Error ? err.message : 'Submission rejected'), 400);
    }
  }

  // Progression is a projection of race truth — reconcile after the action
  // commits, in the background, so an XP failure can never fail the proof.
  if (result) {
    const db = c.env.DB;
    c.executionCtx.waitUntil(
      reconcileProgression(db, userId).catch((err) =>
        console.error('[progression] reconcile failed:', err),
      ),
    );
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!, result), submissionResult: result ?? null });
});

// POST /races/:id/proof-media/upload-url — signed URL for proof evidence.
// Membership-gated: only active participants can attach evidence.
racesRouter.post('/:id/proof-media/upload-url', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  const member = await c.env.DB.prepare(
    "SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'",
  ).bind(race.id, userId).first<{ id: string }>();
  if (!member) return c.json(badRequest('Only race participants can add proof'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }
  const fileName = typeof body.fileName === 'string' && body.fileName.trim()
    ? body.fileName.trim()
    : 'proof.jpg';
  const contentType = typeof body.contentType === 'string' ? body.contentType.trim().toLowerCase() : 'image/jpeg';
  if (!PROOF_MEDIA_ALLOWED_TYPES.includes(contentType)) {
    return c.json(badRequest('Unsupported image type'), 400);
  }

  const extension = extensionFor(fileName, contentType);
  const key = `${proofMediaKeyPrefix(race.id)}${userId}/${Date.now()}.${extension}`;
  const baseUrl = new URL(c.req.url).origin;
  const token = await signUploadToken({ key, contentType, jwtSecret: c.env.JWT_SECRET });
  const uploadUrl = `${baseUrl}/races/${race.id}/proof-media/upload?token=${awsEncode(token)}`;

  // Track the object in media_objects immediately so proof binding can
  // validate ownership + purpose before the bytes even land.
  await c.env.DB.prepare(
    `INSERT INTO media_objects (id, owner_user_id, bucket, object_key, public_url, media_type, purpose, status, created_at)
     VALUES (?, ?, 'nuvor2', ?, ?, 'image', 'proof_evidence', 'pending', CURRENT_TIMESTAMP)`,
  ).bind(generateId(), userId, key, `${baseUrl}/races/${race.id}/proof-media/object/${encodeKeyPath(key)}`).run();

  return c.json({ uploadUrl, key });
});

// GET /races/:id/proof-media/object/* — participant-only evidence fetch.
// View ≠ review: any active member can inspect; only the creator can approve.
racesRouter.get('/:id/proof-media/object/*', async (c) => {
  const userId = c.get('userId');
  const raceId = c.req.param('id');
  const race = await getRace(c.env.DB, raceId);
  if (!race) return c.json({ ok: false, error: 'Not found' }, 404);
  const member = await c.env.DB.prepare(
    "SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'",
  ).bind(raceId, userId).first<{ id: string }>();
  if (!member) return c.json({ ok: false, error: 'Not found' }, 404);

  const key = decodeURIComponent(c.req.path.split('/proof-media/object/')[1] ?? '');
  if (!key.startsWith(proofMediaKeyPrefix(raceId))) {
    return c.json({ ok: false, error: 'Not found' }, 404);
  }
  const object = await c.env.PROFILE_PHOTOS.get(key);
  if (!object) return c.json({ ok: false, error: 'Not found' }, 404);

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'private, max-age=300');
  return new Response(object.body, { headers });
});

// GET /races/:id/proofs - legacy endpoint, maps to move_logs.
racesRouter.get('/:id/proofs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

  const viewerMember = await isRaceMember(c.env.DB, race.id, c.get('userId'));
  const logs = await c.env.DB.prepare(
    `SELECT ml.*, COALESCE(p.full_name, 'Unknown') as display_name
     FROM move_logs ml
     LEFT JOIN profiles p ON p.user_id = ml.user_id
     WHERE ml.race_id = ? AND ml.status != 'removed'
     ORDER BY ml.created_at DESC`
  ).bind(race.id).all<MoveLogRow & { display_name: string }>();

  return c.json({
    ok: true,
    proofs: logs.results.map((m) => {
      const meta = parseMetadata(m.metadata_json);
      const isMovecheck = m.source === 'movecheck';
      let status: string;
      if (m.status === 'verified') status = isMovecheck ? 'ai_verified' : 'accepted';
      else if (m.status === 'rejected') status = 'rejected';
      else status = isMovecheck ? 'needs_review' : 'submitted';
      return {
        id: m.id,
        userId: m.user_id,
        displayName: (m as MoveLogRow & { display_name: string }).display_name,
        proofType: isMovecheck ? 'ai_motion' : 'manual',
        aiActivityType: m.movement_type,
        note: m.summary,
        value: m.value,
        mediaUrl: viewerMember && m.media_object_key
          ? `/races/${race.id}/proof-media/object/${encodeKeyPath(m.media_object_key)}`
          : null,
        detectedValue: meta.detected_value ?? m.value,
        targetValue: meta.target_value ?? null,
        confidence: meta.confidence ?? null,
        validatorVersion: m.validator_version,
        framesAnalyzed: meta.frames_analyzed ?? null,
        validPoseFrames: meta.valid_pose_frames ?? null,
        durationMs: m.duration_ms,
        verificationStatus: status,
        verificationSummary: m.summary,
        reviewedBy: null,
        reviewedAt: null,
        createdAt: m.created_at,
      };
    }),
  });
});

// PATCH /races/:id/proofs/:proofId - legacy review endpoint.
racesRouter.patch('/:id/proofs/:proofId', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can review proof'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const verificationStatus = typeof body.verificationStatus === 'string' && REVIEW_STATUSES.has(body.verificationStatus)
    ? body.verificationStatus
    : '';
  if (!verificationStatus) return c.json(badRequest('Invalid verification status'), 400);

  const move = await c.env.DB.prepare('SELECT * FROM move_logs WHERE id = ? AND race_id = ?')
    .bind(c.req.param('proofId'), race.id).first<MoveLogRow>();
  if (!move) return c.json(badRequest('Proof not found'), 404);

  const newStatus = verificationStatus === 'accepted' || verificationStatus === 'ai_verified'
    ? 'verified'
    : verificationStatus === 'rejected'
      ? 'rejected'
      : 'pending';

  // Attempt-format races bind a score to a declared open attempt — same
  // contract as direct submission (submit opens the attempt; pending proofs
  // keep it open until review closes it). Validate BEFORE the status write
  // so a failed accept never leaves a verified-but-unscored proof.
  const scoring = raceScoringConfigFromRow(race);
  const needsAttempt = newStatus === 'verified' &&
    move.status !== 'verified' &&
    scoring != null &&
    formatUsesAttempts(scoring.format);
  const boundAttempt = needsAttempt
    ? await bindableOpenAttempt(c.env.DB, race, move.user_id)
    : null;
  if (needsAttempt && !boundAttempt) {
    return c.json(badRequest('No open attempt remains to accept this score.'), 400);
  }

  await c.env.DB.prepare(
    'UPDATE move_logs SET status = ?, summary = ? WHERE id = ? AND race_id = ?'
  ).bind(newStatus, stringOrNull(body.verificationSummary) ?? move.summary, move.id, race.id).run();

  if (newStatus === 'verified' && move.status !== 'verified') {
    await applyMoveProgress(c.env.DB, race, move.user_id, move.value ?? 0);
    if (boundAttempt) {
      await closeAttempt(c.env.DB, boundAttempt.id, move.value ?? 0, move.id);
    }
  } else if (move.status === 'verified' && newStatus !== 'verified') {
    // A reject on a scored proof invalidates its progress — recompute from
    // the submitter's remaining verified moves.
    await recomputeRaceProgressForUser(c.env.DB, race, move.user_id);
  }

  // Notify the submitter of the review outcome (skip self-review).
  if (move.user_id !== userId && (newStatus === 'verified' || newStatus === 'rejected')) {
    await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
      type: 'proof_reviewed',
      userId: move.user_id,
      actorUserId: userId,
      raceId: race.id,
      raceTitle: race.title,
      moveId: move.id,
      outcome: newStatus,
      value: move.value,
      unit: race.metric ?? race.target_unit,
    });
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), updated!) });
});

// ── Attempts ─────────────────────────────────────────────────────────────────

// POST /races/:id/attempts — declare an attempt (best_attempt/timed_attempt).
// The authoritative start timestamp is written HERE, server-side; the next
// verified /proof submission binds to this open attempt automatically.
racesRouter.post('/:id/attempts', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

  const member = await isRaceMember(c.env.DB, race.id, userId);
  if (!member && race.creator_id !== userId) {
    return c.json(badRequest('Only race participants can start an attempt'), 403);
  }

  let body: Record<string, unknown> = {};
  try { body = await c.req.json(); } catch { /* empty body is fine */ }
  const clientAttemptId = stringOrNull(body.clientAttemptId) ?? stringOrNull(body.client_attempt_id) ?? null;

  const res = await openAttempt(c.env.DB, race, userId, clientAttemptId);
  if (!res.ok) {
    const status = res.error === 'attempt_in_progress' ? 409 : 400;
    const message =
      res.error === 'attempt_in_progress'
        ? 'You already have an attempt in progress'
        : res.error === 'attempt_limit_reached'
          ? 'No attempts left in this race'
          : res.error === 'not_active'
            ? 'Race is not active'
            : 'This race does not use attempts';
    return c.json(badRequest(message), status);
  }

  const attempt = res.attempt!;
  // Idempotent replays return the same attempt — don't double-emit.
  const isNew = !clientAttemptId || attempt.client_attempt_id === clientAttemptId;
  if (isNew && !attempt.submitted_at) {
    await recordRaceEvents(c.env.DB, race.id, [
      {
        type: 'attempt_started',
        actorUserId: userId,
        subjectUserId: userId,
        payload: { attemptId: attempt.id, attemptIndex: attempt.attempt_index },
      },
    ]);
  }

  const used = res.attemptsUsed ?? (await attemptsUsed(c.env.DB, race.id, userId));
  return c.json({
    ok: true,
    attempt: {
      id: attempt.id,
      attemptIndex: attempt.attempt_index,
      status: attempt.status,
      startedAt: attempt.started_at,
      deadlineAt: attempt.deadline_at,
      clientAttemptId: attempt.client_attempt_id,
    },
    attemptsUsed: used,
    attemptsRemaining: race.attempt_limit != null ? Math.max(0, race.attempt_limit - used) : null,
    serverTime: new Date().toISOString(),
  });
});

// GET /races/:id/events — the durable domain log for this race. Feeds the
// race-history surface and lets Crew/notifications consume transitions
// without reverse-engineering race state.
racesRouter.get('/:id/events', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  const eventAccess = await resolveRaceAccess(c.env.DB, race, c.get('userId'));
  if (!eventAccess.isInsider) return c.json(badRequest('Race not found'), 404);
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 50), 1), 100);
  const before = c.req.query('before');

  const rows = await c.env.DB
    .prepare(
      `SELECT id, event_type, actor_user_id, subject_user_id, payload_json, created_at
       FROM race_events
       WHERE race_id = ? ${before ? 'AND created_at < ?' : ''}
       ORDER BY created_at DESC LIMIT ?`,
    )
    .bind(...(before ? [race.id, before, limit] : [race.id, limit]))
    .all<{
      id: string;
      event_type: string;
      actor_user_id: string | null;
      subject_user_id: string | null;
      payload_json: string | null;
      created_at: string;
    }>();

  return c.json({
    ok: true,
    events: rows.results.map((e) => ({
      id: e.id,
      type: e.event_type,
      actorUserId: e.actor_user_id,
      subjectUserId: e.subject_user_id,
      payload: e.payload_json ? (JSON.parse(e.payload_json) as Record<string, unknown>) : null,
      createdAt: e.created_at,
    })),
  });
});

// GET /races/:id/live — compact poll payload for an in-progress race.
// `version` bumps on every score/member write; an unchanged version means
// nothing moved — cheap polls for live-feel UI without shipping histories.
racesRouter.get('/:id/live', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  const liveAccess = await resolveRaceAccess(c.env.DB, race, userId);
  if (!liveAccess.isInsider) return c.json(badRequest('Race not found'), 404);

  const sinceVersion = Number(c.req.query('version') ?? -1);
  const version = race.version ?? 0;
  if (sinceVersion >= 0 && sinceVersion === version) {
    return c.json({ ok: true, unchanged: true, version, serverTime: new Date().toISOString() });
  }

  const participantRows = await c.env.DB
    .prepare(
      `SELECT rm.user_id, rm.finished_at, rm.joined_at,
              COALESCE(rp.progress_value, 0) as progress_value,
              rp.progress_percent, rp.rank_cache
       FROM race_members rm
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'
       ORDER BY COALESCE(rp.rank_cache, 9999) ASC, rp.progress_value DESC`,
    )
    .bind(race.id)
    .all<{
      user_id: string;
      finished_at: string | null;
      joined_at: string;
      progress_value: number;
      progress_percent: number | null;
      rank_cache: number | null;
    }>();

  const scoring = raceScoringConfigFromRow(race);
  const standings = participantRows.results.map((p) => ({
    userId: p.user_id,
    score: p.progress_value ?? 0,
    rank: p.rank_cache,
    finishedAt: p.finished_at,
  }));
  const viewerContext = computeViewerContext({
    raceId: race.id,
    format: scoring?.format ?? 'first_to_goal',
    targetValue: race.target_value,
    startAt: race.start_at,
    endAt: race.end_at,
    storedStatus: race.status,
    winnerUserId: race.winner_user_id ?? null,
    scoreDirection: scoreDirectionFor(race),
    attemptLimit: race.attempt_limit ?? null,
    attemptDurationSeconds: race.attempt_duration_seconds ?? null,
    standings,
    attemptsUsed: userId ? await attemptsUsed(c.env.DB, race.id, userId) : 0,
    openAttemptId: userId
      ? (
          await c.env.DB
            .prepare("SELECT id FROM race_attempts WHERE race_id = ? AND user_id = ? AND status = 'open'")
            .bind(race.id, userId)
            .first<{ id: string }>()
        )?.id ?? null
      : null,
    viewerUserId: userId,
  });

  return c.json({
    ok: true,
    unchanged: false,
    raceId: race.id,
    version,
    serverTime: new Date().toISOString(),
    status: effectiveRaceStatus(race.status, race.start_at, race.end_at),
    winnerUserId: race.winner_user_id ?? null,
    participants: standings.map((s) => ({
      userId: s.userId,
      score: s.score,
      rank: s.rank,
      finishedAt: s.finishedAt,
    })),
    viewer: viewerContext,
  });
});

// POST /races/:id/rematch — clone the race definition + roster into a fresh
// race. The strongest retention loop in the system: a finished race should
// produce the next one in one tap.
racesRouter.post('/:id/rematch', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

  const member = await isRaceMember(c.env.DB, race.id, userId);
  if (!member && race.creator_id !== userId) {
    return c.json(badRequest('Only race participants can start a rematch'), 403);
  }
  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before creating a race' }, 403);
  }

  const newRaceId = generateId();
  const personId = await ensurePersonId(c.env.DB, userId);
  await c.env.DB
    .prepare(
      `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
        target_value, target_unit, activity_id, metric, format, scoring_rule, attempt_duration_seconds,
        attempt_limit, verification_method, verifier_type, verifier_version, verifier_spec_json, custom_activity_name,
        timezone, recurrence, status, visibility, start_at, end_at, score_direction, proof_review_mode, verifier_release_id,
        created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    )
    .bind(
      newRaceId,
      userId,
      race.title,
      race.description,
      race.format ?? race.race_type,
      race.movement_type,
      race.verification_type,
      race.target_value,
      race.target_unit,
      race.activity_id,
      race.metric,
      race.format ?? 'first_to_goal',
      race.scoring_rule ?? 'cumulative_sum',
      race.attempt_duration_seconds,
      race.attempt_limit,
      race.verification_method,
      race.verifier_type,
      race.verifier_version,
      race.verifier_spec_json,
      race.custom_activity_name,
      race.timezone ?? 'America/New_York',
      'none', // rematch resets recurrence — the new race starts fresh
      race.visibility,
      null, // start line: the rematch begins when created
      null, // deadlines are not carried over
      race.score_direction ?? 'higher',
      race.proof_review_mode ?? 'auto_accept',
      race.verifier_release_id,
    )
    .run();

  const requesterName = await getProfileName(c.env.DB, userId);
  await c.env.DB
    .prepare(
      `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at, cached_display_name)
       VALUES (?, ?, ?, ?, 'creator', 'active', CURRENT_TIMESTAMP, ?)`,
    )
    .bind(generateId(), newRaceId, userId, personId, requesterName)
    .run();
  await ensureProgress(c.env.DB, newRaceId, userId);

  // Re-pull the previous roster as active members — they raced together
  // already; leaving is one tap. Each gets a race_invite notification.
  const roster = await c.env.DB
    .prepare("SELECT user_id FROM race_members WHERE race_id = ? AND status = 'active' AND user_id != ?")
    .bind(race.id, userId)
    .all<{ user_id: string }>();
  for (const row of roster.results) {
    await ensureMember(c.env.DB, newRaceId, row.user_id);
    await ensureProgress(c.env.DB, newRaceId, row.user_id);
    await notifyEvent(c.env, (p) => c.executionCtx.waitUntil(p), {
      type: 'race_invited',
      userId: row.user_id,
      actorUserId: userId,
      actorName: requesterName,
      raceId: newRaceId,
      raceTitle: race.title,
      rematch: true,
    });
  }

  const newRace = await getRace(c.env.DB, newRaceId);
  await recordRaceEvents(c.env.DB, newRaceId, [
    {
      type: 'race_created',
      actorUserId: userId,
      payload: { title: race.title, rematchOf: race.id, format: race.format ?? race.race_type },
    },
    {
      type: 'rematch_requested',
      actorUserId: userId,
      payload: { sourceRaceId: race.id, sourceTitle: race.title, rosterSize: roster.results.length + 1 },
    },
  ]);
  // Mirror the rematch onto the SOURCE race's log — Crew/feed readers of the
  // finished race see that a rematch exists.
  await recordRaceEvents(c.env.DB, race.id, [
    {
      type: 'rematch_requested',
      actorUserId: userId,
      payload: { rematchRaceId: newRaceId, sourceTitle: race.title },
    },
  ]);

  return c.json({ ok: true, race: await buildRaceResponse(c.env, c.get('userId'), newRace!) }, 201);
});
