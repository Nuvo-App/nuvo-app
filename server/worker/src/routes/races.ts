import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv, MoveLogRow, RaceProgressRow, RaceRow } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import { activityForId, normalizeActivityId, normalizeMetric, type RaceFormat, type RaceScoringRule } from '../domain/raceActivities';
import { assertSubmissionCompatible, configFromBody, type RaceConfig } from '../domain/raceValidation';
import { applyVerifiedSubmission } from '../domain/raceScoring';
import { computeCompetitionRanks, type RankedScore } from '../domain/raceRanking';
import { effectiveRaceStatus } from '../domain/raceLifecycle';

export const racesRouter = new Hono<AppEnv>();
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

async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db.prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL').bind(raceId).first<RaceRow>();
}

async function getProfileName(db: D1Database, userId: string): Promise<string | null> {
  const row = await db.prepare('SELECT full_name FROM profiles WHERE user_id = ?').bind(userId).first<{ full_name: string | null }>();
  return row?.full_name ?? null;
}

function raceConfigFromRow(race: RaceRow): RaceConfig | null {
  const activityId = normalizeActivityId(race.activity_id ?? race.movement_type);
  const activity = activityForId(activityId);
  if (!activity || !activityId) return null;
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

async function ensureMember(db: D1Database, raceId: string, userId: string, role = 'racer'): Promise<void> {
  const existing = await db.prepare('SELECT id FROM race_members WHERE race_id = ? AND user_id = ?').bind(raceId, userId).first<{ id: string }>();
  if (existing) return;
  const displayName = await getProfileName(db, userId);
  await db.prepare(
    `INSERT INTO race_members (id, race_id, user_id, role, status, joined_at, cached_display_name)
     VALUES (?, ?, ?, ?, 'active', CURRENT_TIMESTAMP, ?)`
  ).bind(generateId(), raceId, userId, role, displayName).run();
}

async function ensureProgress(db: D1Database, raceId: string, userId: string): Promise<void> {
  const existing = await db.prepare('SELECT id FROM race_progress WHERE race_id = ? AND user_id = ?').bind(raceId, userId).first<{ id: string }>();
  if (existing) return;
  await db.prepare(
    `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
     VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`
  ).bind(generateId(), raceId, userId).run();
}

async function rankedScores(db: D1Database, raceId: string): Promise<RankedScore[]> {
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
  })));
}

async function recomputeRanks(db: D1Database, raceId: string): Promise<RankedScore[]> {
  const ranked = await rankedScores(db, raceId);
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

async function rankForUser(db: D1Database, raceId: string, userId: string): Promise<number | null> {
  const ranked = await rankedScores(db, raceId);
  return ranked.find((row) => row.user_id === userId)?.rank ?? null;
}

async function applyMoveProgress(db: D1Database, race: RaceRow, userId: string, value: number): Promise<SubmissionResult> {
  const config = raceConfigFromRow(race);
  if (!config) throw new Error('Race is missing activity configuration');
  const increment = Math.max(0, Math.floor(value));
  if (increment <= 0) throw new Error('Verified value must be greater than 0');

  const progress = await db.prepare(
    'SELECT progress_value, completed_at FROM race_progress WHERE race_id = ? AND user_id = ?'
  ).bind(race.id, userId).first<RaceProgressRow>();
  if (!progress) throw new Error('Only race participants can submit proof');

  const current = progress?.progress_value ?? 0;
  const previousRank = await rankForUser(db, race.id, userId);
  const scored = applyVerifiedSubmission({
    format: config.format,
    scoringRule: config.scoringRule,
    previousScore: current,
    submissionValue: increment,
    targetValue: config.targetValue,
  });
  const completedAt = scored.completed && !progress?.completed_at
    ? new Date().toISOString()
    : progress.completed_at ?? null;

  await db.prepare(
    `UPDATE race_progress SET progress_value = ?, progress_percent = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
     WHERE race_id = ? AND user_id = ?`
  ).bind(scored.newScore, scored.progressPercent, completedAt, race.id, userId).run();
  const ranked = await recomputeRanks(db, race.id);
  const newRank = ranked.find((row) => row.user_id === userId)?.rank ?? null;

  let raceCompleted = false;
  let winnerUserId: string | null = race.winner_user_id ?? null;
  const effectiveStatus = effectiveRaceStatus(race.status, race.start_at, race.end_at);
  if (scored.completed && effectiveStatus === 'active') {
    raceCompleted = true;
    winnerUserId = userId;
    await db.prepare(
      `UPDATE races SET status = 'completed', winner_user_id = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'active'`
    ).bind(userId, completedAt, race.id).run();
    await snapshotFinalStandings(db, race.id);
  }

  return {
    verifiedValue: increment,
    previousScore: current,
    newScore: scored.newScore,
    previousRank,
    newRank,
    peoplePassed: previousRank && newRank && newRank < previousRank ? previousRank - newRank : 0,
    raceCompleted,
    winnerUserId,
  };
}

async function buildRaceResponse(db: D1Database, race: RaceRow, submissionResult?: SubmissionResult) {
  const [participants, moves, invite, finalStandings] = await Promise.all([
    db.prepare(
      `SELECT rm.id, rm.user_id, rm.joined_at,
              COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name,
              COALESCE(rm.cached_avatar_url, p.avatar_url) as profile_photo_url,
              rp.progress_value, rp.progress_percent, rp.rank_cache
       FROM race_members rm
       LEFT JOIN profiles p ON p.user_id = rm.user_id
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'
       ORDER BY COALESCE(rp.rank_cache, 9999) ASC, rp.progress_value DESC, rm.joined_at ASC`
    ).bind(race.id).all<{ id: string; user_id: string; joined_at: string; display_name: string; profile_photo_url: string | null; progress_value: number; progress_percent: number; rank_cache: number | null }>(),
    db.prepare(
      `SELECT ml.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url
       FROM move_logs ml
       LEFT JOIN profiles p ON p.user_id = ml.user_id
       WHERE ml.race_id = ? AND ml.status != 'removed'
       ORDER BY ml.created_at DESC LIMIT 20`
    ).bind(race.id).all<MoveLogRow & { display_name: string; profile_photo_url: string | null }>(),
    db.prepare(
      `SELECT * FROM race_invites WHERE race_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1`
    ).bind(race.id).first<InviteRow>(),
    db.prepare(
      `SELECT fs.*, COALESCE(p.full_name, 'Unknown') as display_name, p.avatar_url as profile_photo_url
       FROM race_final_standings fs
       LEFT JOIN profiles p ON p.user_id = fs.user_id
       WHERE fs.race_id = ?
       ORDER BY fs.rank_position ASC`
    ).bind(race.id).all<{ user_id: string; rank_position: number; score_value: number; completed_at: string | null; display_name: string; profile_photo_url: string | null }>(),
  ]);

  const proofRequirement = mapVerificationTypeToProofRequirement(race.verification_type);
  const config = raceConfigFromRow(race);
  const effectiveStatus = effectiveRaceStatus(race.status, race.start_at, race.end_at);

  return {
    id: race.id,
    creatorId: race.creator_id,
    title: race.title,
    description: race.description,
    category: '',
    goalType: mapRaceTypeToGoalType(race.race_type),
    activityId: config?.activityId ?? normalizeActivityId(race.activity_id ?? race.movement_type) ?? null,
    metric: config?.metric ?? normalizeMetric(race.metric ?? race.target_unit, config ? activityForId(config.activityId) : undefined) ?? null,
    format: config?.format ?? 'first_to_goal',
    scoringRule: config?.scoringRule ?? 'cumulative_sum',
    attemptDurationSeconds: race.attempt_duration_seconds ?? null,
    attemptLimit: race.attempt_limit ?? null,
    verificationMethod: race.verification_method ?? (race.verification_type === 'movecheck' ? 'camera_pose' : race.verification_type),
    timezone: race.timezone ?? 'America/New_York',
    recurrence: race.recurrence ?? 'none',
    targetValue: race.target_value,
    unit: race.target_unit,
    aiActivityType: race.movement_type,
    targetUnit: race.target_unit,
    proofMode: proofRequirement,
    status: effectiveStatus,
    storedStatus: race.status,
    winnerUserId: race.winner_user_id ?? null,
    completedAt: race.completed_at ?? null,
    startLineAt: race.start_at,
    finishLineAt: race.end_at,
    rules: '',
    proofRequirement,
    proofReviewMode: 'auto_accept',
    visibility: race.visibility,
    inviteCode: invite?.invite_code ?? null,
    createdAt: race.created_at,
    updatedAt: race.updated_at,
    participants: participants.results.map((p) => ({
      id: p.id,
      userId: p.user_id,
      displayName: p.display_name ?? 'Unknown',
      profilePhotoUrl: p.profile_photo_url,
      progressValue: p.progress_value ?? 0,
      progressPercent: p.progress_percent ?? 0,
      rank: p.rank_cache,
      joinedAt: p.joined_at,
    })),
    recentProofs: moves.results.map((m) => {
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
        profilePhotoUrl: m.profile_photo_url,
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
    finalStandings: finalStandings.results.map((row) => ({
      userId: row.user_id,
      displayName: row.display_name,
      profilePhotoUrl: row.profile_photo_url,
      rank: row.rank_position,
      scoreValue: row.score_value,
      completedAt: row.completed_at,
    })),
    submissionResult: submissionResult ?? null,
  };
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

  const invite = await c.env.DB.prepare(
    `SELECT * FROM race_invites WHERE invite_code = ? AND status = 'active'
     AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)`
  ).bind(code).first<InviteRow>();
  if (!invite) return c.json(badRequest('Invite code not found'), 404);

  const race = await getRace(c.env.DB, invite.race_id);
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
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
  const races = await Promise.all(rows.results.map((r) => buildRaceResponse(c.env.DB, r)));
  return c.json({ ok: true, races });
});

// POST /races
racesRouter.post('/', async (c) => {
  const userId = c.get('userId');
  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!title) return c.json(badRequest('title is required'), 400);

  const raceTypeRaw = typeof body.goalType === 'string' ? body.goalType : 'manual';
  const verificationRaw = typeof body.proofRequirement === 'string' ? body.proofRequirement : 'manual';
  const verificationType = mapProofRequirementToVerificationType(verificationRaw);
  const structuredConfig = configFromBody(body);
  if (verificationType === 'movecheck' && 'error' in structuredConfig) {
    return c.json(badRequest(structuredConfig.error), 400);
  }

  const raceId = generateId();
  const description = stringOrNull(body.description) ?? null;
  const config = 'error' in structuredConfig ? null : structuredConfig;
  const raceType = config?.format ?? mapGoalTypeToRaceType(raceTypeRaw);
  const targetValue = config?.targetValue ?? positiveIntOrNull(body.targetValue) ?? null;
  const targetUnit = config?.metric ?? stringOrNull(body.targetUnit) ?? stringOrNull(body.unit) ?? null;
  const movementType = config?.activityId ?? stringOrNull(body.aiActivityType) ?? null;
  const visibility = typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility) ? body.visibility : 'private';
  const startAt = config?.startsAt ?? stringOrNull(body.startLineAt) ?? null;
  const endAt = config?.endsAt ?? stringOrNull(body.finishLineAt) ?? null;

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
        target_value, target_unit, activity_id, metric, format, scoring_rule, attempt_duration_seconds,
        attempt_limit, verification_method, timezone, recurrence, status, visibility, start_at, end_at,
        created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
    ).bind(
      raceId,
      userId,
      title,
      description,
      raceType,
      movementType,
      verificationType,
      targetValue,
      targetUnit,
      config?.activityId ?? normalizeActivityId(movementType),
      config?.metric ?? normalizeMetric(targetUnit, activityForId(normalizeActivityId(movementType))),
      config?.format ?? raceType,
      config?.scoringRule ?? 'cumulative_sum',
      config?.attemptDurationSeconds ?? null,
      config?.attemptLimit ?? null,
      config?.verificationMethod ?? (verificationType === 'movecheck' ? 'camera_pose' : verificationType),
      config?.timezone ?? 'America/New_York',
      config?.recurrence ?? 'none',
      visibility,
      startAt,
      endAt,
    ),
    c.env.DB.prepare(
      `INSERT INTO race_members (id, race_id, user_id, role, status, joined_at)
       VALUES (?, ?, ?, 'creator', 'active', CURRENT_TIMESTAMP)`
    ).bind(generateId(), raceId, userId),
    c.env.DB.prepare(
      `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
       VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`
    ).bind(generateId(), raceId, userId),
  ]);

  const race = await getRace(c.env.DB, raceId);
  await recomputeRanks(c.env.DB, raceId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race!) }, 201);
});

// GET /races/:id
racesRouter.get('/:id', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json(badRequest('Race not found'), 404);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// PATCH /races/:id
racesRouter.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can edit this race'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

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

  if (updates.length === 0) return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });

  updates.push('updated_at = CURRENT_TIMESTAMP');
  await c.env.DB.prepare(`UPDATE races SET ${updates.join(', ')} WHERE id = ?`).bind(...values, race.id).run();
  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});

async function setRaceStatus(c: Context<AppEnv>, status: string) {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.creator_id !== userId) return c.json(badRequest('Only the race creator can change this race'), 403);
  await c.env.DB.prepare('UPDATE races SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?').bind(status, race.id).run();
  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
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
  if (race.visibility === 'private') return c.json(badRequest('Use an invite code to join this race'), 403);
  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/participants
racesRouter.post('/:id/participants', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  const current = await c.env.DB.prepare('SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = \'active\'')
    .bind(race.id, userId).first<{ id: string }>();
  if (race.creator_id !== userId && !current) return c.json(badRequest('Only race crew can add participants'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }
  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!targetUserId) return c.json(badRequest('userId is required'), 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetUserId).first<{ id: string }>();
  if (!target) return c.json(badRequest('User not found'), 404);

  await ensureMember(c.env.DB, race.id, targetUserId);
  await ensureProgress(c.env.DB, race.id, targetUserId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/members (new endpoint, same as /participants)
racesRouter.post('/:id/members', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  const current = await c.env.DB.prepare('SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = \'active\'')
    .bind(race.id, userId).first<{ id: string }>();
  if (race.creator_id !== userId && !current) return c.json(badRequest('Only race crew can add members'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }
  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!targetUserId) return c.json(badRequest('userId is required'), 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'").bind(targetUserId).first<{ id: string }>();
  if (!target) return c.json(badRequest('User not found'), 404);

  await ensureMember(c.env.DB, race.id, targetUserId);
  await ensureProgress(c.env.DB, race.id, targetUserId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
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
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
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
  if (existing) return c.json({ ok: true, inviteCode: existing.invite_code, race: await buildRaceResponse(c.env.DB, race) });

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
  return c.json({ ok: true, inviteCode: code, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/move-log
racesRouter.post('/:id/move-log', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

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
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});

// GET /races/:id/move-logs
racesRouter.get('/:id/move-logs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

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

  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/proof - legacy endpoint, maps to move_logs.
racesRouter.post('/:id/proof', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);
  if (effectiveRaceStatus(race.status, race.start_at, race.end_at) !== 'active') return c.json(badRequest('Race is not active'), 400);
  const config = raceConfigFromRow(race);
  if (!config) return c.json(badRequest('Race is missing activity configuration'), 400);
  const member = await c.env.DB.prepare(
    "SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'"
  ).bind(race.id, userId).first<{ id: string }>();
  if (!member) return c.json(badRequest('Only race participants can submit proof'), 403);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const proofType = typeof body.proofType === 'string' ? body.proofType : 'manual';
  const isAiMotion = proofType === 'ai_motion';
  const value = isAiMotion ? nonNegativeIntOrNull(body.value) : positiveIntOrNull(body.value);
  const increment = value ?? 0;
  if (!isAiMotion && increment <= 0) return c.json(badRequest('value must be greater than 0'), 400);
  if (isAiMotion && increment <= 0) return c.json(badRequest('Verified value must be greater than 0'), 400);

  const clientSubmissionId = stringOrNull(body.clientSubmissionId) ?? stringOrNull(body.client_submission_id) ?? null;
  if (isAiMotion && !clientSubmissionId) return c.json(badRequest('clientSubmissionId is required'), 400);
  if (clientSubmissionId) {
    const existing = await c.env.DB.prepare(
      'SELECT * FROM move_logs WHERE race_id = ? AND user_id = ? AND client_submission_id = ?'
    ).bind(race.id, userId, clientSubmissionId).first<MoveLogRow>();
    if (existing) {
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
          winnerUserId: race.winner_user_id ?? null,
        }
        : undefined;
      const updated = await getRace(c.env.DB, race.id);
      return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!, result), submissionResult: result ?? null });
    }
  }

  await ensureProgress(c.env.DB, race.id, userId);

  const activityType = isAiMotion ? stringOrNull(body.activityType) : race.movement_type;
  const metric = isAiMotion ? normalizeMetric(stringOrNull(body.metric) ?? stringOrNull(body.unit), activityForId(config.activityId)) : config.metric;
  const compatibilityError = isAiMotion ? assertSubmissionCompatible(config, activityType ?? null, metric ?? null) : null;
  if (compatibilityError) return c.json(badRequest(compatibilityError), 400);
  const detectedValue = isAiMotion ? nonNegativeIntOrNull(body.detectedValue) ?? increment : null;
  const targetValue = isAiMotion ? positiveIntOrNull(body.targetValue) ?? null : null;
  const confidence = isAiMotion ? confidenceOrNull(body.confidence) ?? null : null;
  const validatorVersion = isAiMotion ? stringOrNull(body.validatorVersion) ?? 'nuvo-ai-motion-v1' : null;
  const framesAnalyzed = isAiMotion ? nonNegativeIntOrNull(body.framesAnalyzed) ?? null : null;
  const validPoseFrames = isAiMotion ? nonNegativeIntOrNull(body.validPoseFrames) ?? null : null;
  const durationMs = isAiMotion ? nonNegativeIntOrNull(body.durationMs) ?? null : null;

  const aiStatus = typeof body.verificationStatus === 'string' ? body.verificationStatus : '';
  let moveStatus: string;
  if (isAiMotion) {
    if (aiStatus === 'ai_verified') moveStatus = 'verified';
    else if (aiStatus === 'ai_failed') moveStatus = 'rejected';
    else moveStatus = 'pending';
  } else {
    moveStatus = 'verified';
  }

  const metadata = JSON.stringify({
    confidence,
    detected_value: detectedValue,
    target_value: targetValue,
    frames_analyzed: framesAnalyzed,
    valid_pose_frames: validPoseFrames,
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
      validator_version, duration_ms, metadata_json, client_submission_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
  ).bind(
    moveId,
    race.id,
    userId,
    isAiMotion ? 'movecheck' : 'manual',
    activityType,
    normalizeActivityId(activityType),
    metric ?? config.metric,
    increment,
    race.target_unit,
    moveStatus,
    summary,
    validatorVersion,
    durationMs,
    metadata,
    clientSubmissionId,
  ).run();

  let result: SubmissionResult | undefined;
  if (moveStatus === 'verified') {
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
    } catch (err) {
      await c.env.DB.prepare('UPDATE move_logs SET status = ?, summary = ? WHERE id = ?')
        .bind('rejected', err instanceof Error ? err.message : 'Submission rejected', moveId).run();
      return c.json(badRequest(err instanceof Error ? err.message : 'Submission rejected'), 400);
    }
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!, result), submissionResult: result ?? null });
});

// GET /races/:id/proofs - legacy endpoint, maps to move_logs.
racesRouter.get('/:id/proofs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json(badRequest('Race not found'), 404);

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

  await c.env.DB.prepare(
    'UPDATE move_logs SET status = ?, summary = ? WHERE id = ? AND race_id = ?'
  ).bind(newStatus, stringOrNull(body.verificationSummary) ?? move.summary, move.id, race.id).run();

  if (newStatus === 'verified' && move.status !== 'verified') {
    await applyMoveProgress(c.env.DB, race, move.user_id, move.value ?? 0);
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});
