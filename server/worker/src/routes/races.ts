import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv, MoveLogRow, RaceProgressRow, RaceRow } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';

export const racesRouter = new Hono<AppEnv>();
racesRouter.use('*', requireAuth);

const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const RACE_STATUSES = new Set(['draft', 'active', 'completed', 'archived', 'cancelled']);
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
    default: return 'first_to_target';
  }
}

function mapRaceTypeToGoalType(raceType: string): string {
  switch (raceType) {
    case 'most_in_time': return 'most';
    case 'daily_streak': return 'streak';
    case 'habit_check': return 'habit';
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

async function recomputeRanks(db: D1Database, raceId: string): Promise<void> {
  const rows = await db.prepare(
    `SELECT id FROM race_progress WHERE race_id = ? ORDER BY progress_percent DESC, progress_value DESC, updated_at ASC`
  ).bind(raceId).all<{ id: string }>();
  const stmts = rows.results.map((r, i) => db.prepare('UPDATE race_progress SET rank_cache = ? WHERE id = ?').bind(i + 1, r.id));
  if (stmts.length) await db.batch(stmts);
}

async function applyMoveProgress(db: D1Database, race: RaceRow, userId: string, value: number): Promise<void> {
  const increment = Math.max(0, Math.floor(value));
  if (increment <= 0) return;
  await ensureMember(db, race.id, userId);
  await ensureProgress(db, race.id, userId);

  const progress = await db.prepare(
    'SELECT progress_value, completed_at FROM race_progress WHERE race_id = ? AND user_id = ?'
  ).bind(race.id, userId).first<RaceProgressRow>();

  const current = progress?.progress_value ?? 0;
  const newValue = current + increment;
  const newPercent = race.target_value && race.target_value > 0
    ? Math.min(100, Math.round((newValue / race.target_value) * 100))
    : 0;
  const completedAt = newPercent >= 100 && !progress?.completed_at
    ? new Date().toISOString()
    : progress?.completed_at ?? null;

  await db.prepare(
    `UPDATE race_progress SET progress_value = ?, progress_percent = ?, completed_at = ?, updated_at = CURRENT_TIMESTAMP
     WHERE race_id = ? AND user_id = ?`
  ).bind(newValue, newPercent, completedAt, race.id, userId).run();
  await recomputeRanks(db, race.id);
}

async function buildRaceResponse(db: D1Database, race: RaceRow) {
  const [participants, moves, invite] = await Promise.all([
    db.prepare(
      `SELECT rm.id, rm.user_id, rm.joined_at,
              COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name,
              COALESCE(rm.cached_avatar_url, p.avatar_url) as profile_photo_url,
              rp.progress_value, rp.progress_percent
       FROM race_members rm
       LEFT JOIN profiles p ON p.user_id = rm.user_id
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'
       ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rm.joined_at ASC`
    ).bind(race.id).all<{ id: string; user_id: string; joined_at: string; display_name: string; profile_photo_url: string | null; progress_value: number; progress_percent: number }>(),
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
  ]);

  const proofRequirement = mapVerificationTypeToProofRequirement(race.verification_type);

  return {
    id: race.id,
    creatorId: race.creator_id,
    title: race.title,
    description: race.description,
    category: '',
    goalType: mapRaceTypeToGoalType(race.race_type),
    targetValue: race.target_value,
    unit: race.target_unit,
    aiActivityType: race.movement_type,
    targetUnit: race.target_unit,
    proofMode: proofRequirement,
    status: race.status,
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
        createdAt: m.created_at,
      };
    }),
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
  const raceType = mapGoalTypeToRaceType(raceTypeRaw);
  const verificationRaw = typeof body.proofRequirement === 'string' ? body.proofRequirement : 'manual';
  const verificationType = mapProofRequirementToVerificationType(verificationRaw);

  const raceId = generateId();
  const description = stringOrNull(body.description) ?? null;
  const targetValue = positiveIntOrNull(body.targetValue) ?? null;
  const targetUnit = stringOrNull(body.targetUnit) ?? stringOrNull(body.unit) ?? null;
  const movementType = stringOrNull(body.aiActivityType) ?? null;
  const visibility = typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility) ? body.visibility : 'private';
  const startAt = stringOrNull(body.startLineAt) ?? null;
  const endAt = stringOrNull(body.finishLineAt) ?? null;

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,
        target_value, target_unit, status, visibility, start_at, end_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
    ).bind(raceId, userId, title, description, raceType, movementType, verificationType, targetValue, targetUnit, visibility, startAt, endAt),
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
  if (race.status !== 'active') return c.json(badRequest('Race is not active'), 400);

  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json(badRequest('Invalid JSON body'), 400); }

  const proofType = typeof body.proofType === 'string' ? body.proofType : 'manual';
  const isAiMotion = proofType === 'ai_motion';
  const value = isAiMotion ? nonNegativeIntOrNull(body.value) : positiveIntOrNull(body.value);
  const increment = value ?? 0;
  if (!isAiMotion && increment <= 0) return c.json(badRequest('value must be greater than 0'), 400);

  await ensureMember(c.env.DB, race.id, userId);
  await ensureProgress(c.env.DB, race.id, userId);

  const activityType = isAiMotion ? stringOrNull(body.activityType) ?? 'jumping_jacks' : null;
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
    `INSERT INTO move_logs (id, race_id, user_id, source, movement_type, value, unit, status, summary,
      validator_version, duration_ms, metadata_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
  ).bind(moveId, race.id, userId, isAiMotion ? 'movecheck' : 'manual', activityType, increment,
    race.target_unit, moveStatus, summary, validatorVersion, durationMs, metadata).run();

  if (moveStatus === 'verified') await applyMoveProgress(c.env.DB, race, userId, increment);

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
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
