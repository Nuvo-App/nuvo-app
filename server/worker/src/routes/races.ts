import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';

export const racesRouter = new Hono<AppEnv>();

racesRouter.use('*', requireAuth);

const REVIEW_STATUSES = new Set([
  'submitted',
  'accepted',
  'rejected',
  'needs_review',
  'ai_check_pending',
  'ai_verified',
  'ai_failed',
]);

const RACE_STATUSES = new Set(['active', 'archived', 'cancelled']);
const PROOF_REQUIREMENTS = new Set(['manual', 'photo_video', 'ai_check']);
const PROOF_REVIEW_MODES = new Set(['auto_accept', 'owner_review', 'ai_review']);
const VISIBILITIES = new Set(['private', 'crew_only', 'invite_code']);
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

interface RaceRow {
  id: string;
  creator_id: string;
  title: string;
  description: string | null;
  category: string | null;
  goal_type: string;
  target_value: number | null;
  unit: string | null;
  ai_activity_type: string | null;
  target_unit: string | null;
  proof_mode: string | null;
  status: string;
  start_line_at: string | null;
  finish_line_at: string | null;
  rules: string | null;
  proof_requirement: string;
  proof_review_mode: string;
  visibility: string;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

interface ParticipantRow {
  id: string;
  race_id: string;
  user_id: string;
  display_name: string | null;
  progress_value: number;
  progress_percent: number;
  joined_at: string;
}

interface ProofRow {
  id: string;
  race_id: string;
  user_id: string;
  proof_type: string;
  ai_activity_type: string | null;
  note: string | null;
  value: number | null;
  detected_value: number | null;
  target_value: number | null;
  confidence: number | null;
  validator_version: string | null;
  frames_analyzed: number | null;
  valid_pose_frames: number | null;
  duration_ms: number | null;
  verification_status: string;
  verification_summary: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  created_at: string;
}

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
  const suffix = Array.from(buf)
    .map((b) => CODE_CHARS[b % CODE_CHARS.length])
    .join('');
  return `NUV-${suffix}`;
}

async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db
    .prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL')
    .bind(raceId)
    .first<RaceRow>();
}

async function getProfileName(db: D1Database, userId: string): Promise<string | null> {
  const profile = await db
    .prepare('SELECT full_name FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<{ full_name: string | null }>();
  return profile?.full_name ?? null;
}

async function ensureParticipant(db: D1Database, race: RaceRow, userId: string): Promise<void> {
  const existing = await db
    .prepare('SELECT id FROM race_participants WHERE race_id = ? AND user_id = ?')
    .bind(race.id, userId)
    .first<{ id: string }>();
  if (existing) return;

  const displayName = await getProfileName(db, userId);
  await db
    .prepare(
      `INSERT INTO race_participants
         (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
       VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`,
    )
    .bind(generateId(), race.id, userId, displayName)
    .run();
}

async function applyProofProgress(db: D1Database, race: RaceRow, proof: ProofRow): Promise<void> {
  const increment = proof.value && proof.value > 0 ? Math.floor(proof.value) : 0;
  if (increment <= 0) return;

  await ensureParticipant(db, race, proof.user_id);
  const participant = await db
    .prepare('SELECT progress_value FROM race_participants WHERE race_id = ? AND user_id = ?')
    .bind(race.id, proof.user_id)
    .first<{ progress_value: number }>();

  const newProgressValue = (participant?.progress_value ?? 0) + increment;
  const newProgressPercent =
    race.target_value && race.target_value > 0
      ? Math.min(100, Math.round((newProgressValue / race.target_value) * 100))
      : 0;

  await db
    .prepare(
      `UPDATE race_participants
       SET progress_value = ?, progress_percent = ?
       WHERE race_id = ? AND user_id = ?`,
    )
    .bind(newProgressValue, newProgressPercent, race.id, proof.user_id)
    .run();
}

async function buildRaceResponse(db: D1Database, race: RaceRow) {
  const [participants, proofs, invite] = await Promise.all([
    db
      .prepare(
        `SELECT rp.id, rp.race_id, rp.user_id,
                COALESCE(rp.display_name, p.full_name, 'Unknown') as display_name,
                rp.progress_value, rp.progress_percent, rp.joined_at
         FROM race_participants rp
         LEFT JOIN profiles p ON p.user_id = rp.user_id
         WHERE rp.race_id = ?
         ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rp.joined_at ASC`,
      )
      .bind(race.id)
      .all<ParticipantRow>(),
    db
      .prepare(
        `SELECT pr.id, pr.race_id, pr.user_id, pr.proof_type,
                pr.ai_activity_type, pr.note, pr.value, pr.detected_value,
                pr.target_value, pr.confidence, pr.validator_version,
                pr.frames_analyzed, pr.valid_pose_frames, pr.duration_ms,
                pr.verification_status, pr.verification_summary, pr.reviewed_by,
                pr.reviewed_at, pr.created_at,
                COALESCE(p.full_name, 'Unknown') as display_name
         FROM proofs pr
         LEFT JOIN profiles p ON p.user_id = pr.user_id
         WHERE pr.race_id = ?
         ORDER BY pr.created_at DESC
         LIMIT 20`,
      )
      .bind(race.id)
      .all<ProofRow & { display_name: string }>(),
    db
      .prepare(
        `SELECT * FROM race_invites
         WHERE race_id = ? AND status = 'active'
         ORDER BY created_at DESC
         LIMIT 1`,
      )
      .bind(race.id)
      .first<InviteRow>(),
  ]);

  return {
    id: race.id,
    creatorId: race.creator_id,
    title: race.title,
    description: race.description,
    category: race.category,
    goalType: race.goal_type,
    targetValue: race.target_value,
    unit: race.unit,
    aiActivityType: race.ai_activity_type,
    targetUnit: race.target_unit,
    proofMode: race.proof_mode,
    status: race.status,
    startLineAt: race.start_line_at,
    finishLineAt: race.finish_line_at,
    rules: race.rules,
    proofRequirement: race.proof_requirement,
    proofReviewMode: race.proof_review_mode,
    visibility: race.visibility,
    inviteCode: invite?.invite_code ?? null,
    createdAt: race.created_at,
    updatedAt: race.updated_at,
    participants: participants.results.map((p) => ({
      id: p.id,
      userId: p.user_id,
      displayName: p.display_name ?? 'Unknown',
      progressValue: p.progress_value,
      progressPercent: p.progress_percent,
      joinedAt: p.joined_at,
    })),
    recentProofs: proofs.results.map((pr) => ({
      id: pr.id,
      userId: pr.user_id,
      displayName: (pr as ProofRow & { display_name: string }).display_name,
      proofType: pr.proof_type,
      aiActivityType: pr.ai_activity_type,
      note: pr.note,
      value: pr.value,
      detectedValue: pr.detected_value,
      targetValue: pr.target_value,
      confidence: pr.confidence,
      validatorVersion: pr.validator_version,
      framesAnalyzed: pr.frames_analyzed,
      validPoseFrames: pr.valid_pose_frames,
      durationMs: pr.duration_ms,
      verificationStatus: pr.verification_status,
      verificationSummary: pr.verification_summary,
      reviewedBy: pr.reviewed_by,
      reviewedAt: pr.reviewed_at,
      createdAt: pr.created_at,
    })),
  };
}

// POST /races/join-code - join a race through an active invite code.
racesRouter.post('/join-code', async (c) => {
  const userId = c.get('userId');
  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const code = typeof body.code === 'string' ? body.code.trim().toUpperCase() : '';
  if (!code) return c.json({ ok: false, error: 'Invite code is required' }, 400);

  const invite = await c.env.DB.prepare(
    `SELECT * FROM race_invites
     WHERE invite_code = ? AND status = 'active'
       AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)`,
  )
    .bind(code)
    .first<InviteRow>();
  if (!invite) return c.json({ ok: false, error: 'Invite code not found' }, 404);

  const race = await getRace(c.env.DB, invite.race_id);
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.status !== 'active') return c.json({ ok: false, error: 'Race is not active' }, 400);

  await ensureParticipant(c.env.DB, race, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// GET /races - all races the current user created or joined.
racesRouter.get('/', async (c) => {
  const userId = c.get('userId');

  const rows = await c.env.DB.prepare(
    `SELECT DISTINCT r.* FROM races r
     LEFT JOIN race_participants rp ON rp.race_id = r.id AND rp.user_id = ?
     WHERE r.deleted_at IS NULL AND (r.creator_id = ? OR rp.user_id IS NOT NULL)
     ORDER BY r.created_at DESC`,
  )
    .bind(userId, userId)
    .all<RaceRow>();

  const races = await Promise.all(rows.results.map((r) => buildRaceResponse(c.env.DB, r)));
  return c.json({ ok: true, races });
});

// POST /races - create a new race and auto-join creator as participant.
racesRouter.post('/', async (c) => {
  const userId = c.get('userId');

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!title) return c.json({ ok: false, error: 'title is required' }, 400);

  const description = stringOrNull(body.description) ?? null;
  const category = stringOrNull(body.category) ?? null;
  const goalType = typeof body.goalType === 'string' ? body.goalType : 'manual';
  const targetValue = positiveIntOrNull(body.targetValue) ?? null;
  const unit = stringOrNull(body.unit) ?? null;
  const aiActivityType = stringOrNull(body.aiActivityType) ?? null;
  const targetUnit = stringOrNull(body.targetUnit) ?? unit;
  const startLineAt = stringOrNull(body.startLineAt) ?? null;
  const finishLineAt = stringOrNull(body.finishLineAt) ?? null;
  const rules = stringOrNull(body.rules) ?? null;
  const proofRequirement =
    typeof body.proofRequirement === 'string' && PROOF_REQUIREMENTS.has(body.proofRequirement)
      ? body.proofRequirement
      : 'manual';
  const proofMode = stringOrNull(body.proofMode) ?? proofRequirement;
  const proofReviewMode =
    typeof body.proofReviewMode === 'string' && PROOF_REVIEW_MODES.has(body.proofReviewMode)
      ? body.proofReviewMode
      : 'auto_accept';
  const visibility =
    typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility)
      ? body.visibility
      : 'private';

  const raceId = generateId();

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO races
         (id, creator_id, title, description, category, goal_type, target_value, unit,
          ai_activity_type, target_unit, proof_mode, status, start_line_at, finish_line_at, rules, proof_requirement,
          proof_review_mode, visibility, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    ).bind(
      raceId,
      userId,
      title,
      description,
      category,
      goalType,
      targetValue,
      unit,
      aiActivityType,
      targetUnit,
      proofMode,
      startLineAt,
      finishLineAt,
      rules,
      proofRequirement,
      proofReviewMode,
      visibility,
    ),
    c.env.DB.prepare(
      `INSERT INTO race_participants
         (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
       VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`,
    ).bind(generateId(), raceId, userId, await getProfileName(c.env.DB, userId)),
  ]);

  const race = await getRace(c.env.DB, raceId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race!) }, 201);
});

// GET /races/:id
racesRouter.get('/:id', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// PATCH /races/:id - creator-only edit.
racesRouter.patch('/:id', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id !== userId) return c.json({ ok: false, error: 'Only the race creator can edit this race' }, 403);

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const updates: string[] = [];
  const values: unknown[] = [];

  const textFields: Array<[string, string]> = [
    ['title', 'title'],
    ['description', 'description'],
    ['category', 'category'],
    ['goalType', 'goal_type'],
    ['unit', 'unit'],
    ['aiActivityType', 'ai_activity_type'],
    ['targetUnit', 'target_unit'],
    ['proofMode', 'proof_mode'],
    ['startLineAt', 'start_line_at'],
    ['finishLineAt', 'finish_line_at'],
    ['rules', 'rules'],
  ];

  for (const [jsonKey, dbKey] of textFields) {
    const parsed = stringOrNull(body[jsonKey]);
    if (parsed !== undefined) {
      if (jsonKey === 'title' && !parsed) {
        return c.json({ ok: false, error: 'title is required' }, 400);
      }
      updates.push(`${dbKey} = ?`);
      values.push(parsed);
    }
  }

  const targetValue = positiveIntOrNull(body.targetValue);
  if (targetValue !== undefined) {
    updates.push('target_value = ?');
    values.push(targetValue);
  }

  if (typeof body.status === 'string' && RACE_STATUSES.has(body.status)) {
    updates.push('status = ?');
    values.push(body.status);
  }
  if (typeof body.proofRequirement === 'string' && PROOF_REQUIREMENTS.has(body.proofRequirement)) {
    updates.push('proof_requirement = ?');
    values.push(body.proofRequirement);
  }
  if (typeof body.proofReviewMode === 'string' && PROOF_REVIEW_MODES.has(body.proofReviewMode)) {
    updates.push('proof_review_mode = ?');
    values.push(body.proofReviewMode);
  }
  if (typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility)) {
    updates.push('visibility = ?');
    values.push(body.visibility);
  }

  if (updates.length === 0) {
    return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
  }

  updates.push('updated_at = CURRENT_TIMESTAMP');
  await c.env.DB.prepare(`UPDATE races SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...values, race.id)
    .run();

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});

async function setRaceStatus(c: Context<AppEnv>, status: string) {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id') ?? '');
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id !== userId) return c.json({ ok: false, error: 'Only the race creator can change this race' }, 403);

  await c.env.DB.prepare('UPDATE races SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(status, race.id)
    .run();
  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
}

racesRouter.post('/:id/archive', (c) => setRaceStatus(c, 'archived'));
racesRouter.post('/:id/cancel', (c) => setRaceStatus(c, 'cancelled'));

// DELETE /races/:id - creator-only soft delete.
racesRouter.delete('/:id', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id !== userId) return c.json({ ok: false, error: 'Only the race creator can delete this race' }, 403);

  await c.env.DB.prepare(
    'UPDATE races SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
  )
    .bind(race.id)
    .run();
  return c.json({ ok: true });
});

// POST /races/:id/leave - non-owner participant leaves.
racesRouter.post('/:id/leave', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id === userId) {
    return c.json({ ok: false, error: 'Race creator cannot leave their own race' }, 400);
  }

  await c.env.DB.prepare('DELETE FROM race_participants WHERE race_id = ? AND user_id = ?')
    .bind(race.id, userId)
    .run();
  return c.json({ ok: true });
});

// POST /races/:id/join - join if race is directly joinable.
racesRouter.post('/:id/join', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.status !== 'active') return c.json({ ok: false, error: 'Race is not active' }, 400);
  if (race.visibility === 'private') {
    return c.json({ ok: false, error: 'Use an invite code to join this race' }, 403);
  }

  await ensureParticipant(c.env.DB, race, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/participants - add a user directly to a race.
racesRouter.post('/:id/participants', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.status !== 'active') return c.json({ ok: false, error: 'Race is not active' }, 400);

  const currentParticipant = await c.env.DB.prepare(
    'SELECT id FROM race_participants WHERE race_id = ? AND user_id = ?',
  )
    .bind(race.id, userId)
    .first<{ id: string }>();
  if (race.creator_id !== userId && !currentParticipant) {
    return c.json({ ok: false, error: 'Only race crew can add participants' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const targetUserId = typeof body.userId === 'string' ? body.userId.trim() : '';
  if (!targetUserId) return c.json({ ok: false, error: 'userId is required' }, 400);

  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(targetUserId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, error: 'User not found' }, 404);

  await ensureParticipant(c.env.DB, race, targetUserId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/invite-code - create or return active invite code.
racesRouter.post('/:id/invite-code', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id !== userId) return c.json({ ok: false, error: 'Only the race creator can invite crew' }, 403);

  const existing = await c.env.DB.prepare(
    `SELECT * FROM race_invites
     WHERE race_id = ? AND status = 'active'
     ORDER BY created_at DESC
     LIMIT 1`,
  )
    .bind(race.id)
    .first<InviteRow>();
  if (existing) {
    return c.json({ ok: true, inviteCode: existing.invite_code, race: await buildRaceResponse(c.env.DB, race) });
  }

  let code = generateInviteCode();
  for (let attempt = 0; attempt < 5; attempt++) {
    const taken = await c.env.DB.prepare('SELECT id FROM race_invites WHERE invite_code = ?')
      .bind(code)
      .first<{ id: string }>();
    if (!taken) break;
    code = generateInviteCode();
  }

  await c.env.DB.prepare(
    `INSERT INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
     VALUES (?, ?, ?, ?, 'active', CURRENT_TIMESTAMP)`,
  )
    .bind(generateId(), race.id, userId, code)
    .run();

  return c.json({ ok: true, inviteCode: code, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/proof - submit progress proof.
racesRouter.post('/:id/proof', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.status !== 'active') return c.json({ ok: false, error: 'Race is not active' }, 400);

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const proofType = typeof body.proofType === 'string' ? body.proofType : 'manual';
  const note = stringOrNull(body.note) ?? null;
  const isAiMotion = proofType === 'ai_motion';
  const value = isAiMotion
    ? nonNegativeIntOrNull(body.value)
    : positiveIntOrNull(body.value);
  const increment = value ?? 0;
  if (!isAiMotion && increment <= 0) return c.json({ ok: false, error: 'value must be greater than 0' }, 400);

  await ensureParticipant(c.env.DB, race, userId);

  const proofId = generateId();
  const aiStatus =
    typeof body.verificationStatus === 'string' &&
    (body.verificationStatus === 'ai_verified' ||
      body.verificationStatus === 'ai_failed' ||
      body.verificationStatus === 'needs_review')
      ? body.verificationStatus
      : '';
  const status = isAiMotion
    ? aiStatus || 'needs_review'
    : race.proof_review_mode === 'owner_review'
      ? 'submitted'
      : 'accepted';
  if (isAiMotion && status === 'ai_verified' && increment <= 0) {
    return c.json({ ok: false, error: 'AI motion proof value must be greater than 0' }, 400);
  }

  const activityType = isAiMotion ? stringOrNull(body.activityType) ?? 'jumping_jacks' : null;
  const activityLabel = activityType?.replaceAll('_', ' ') ?? 'motion';
  const detectedValue = isAiMotion ? nonNegativeIntOrNull(body.detectedValue) ?? increment : null;
  const targetValue = isAiMotion ? positiveIntOrNull(body.targetValue) ?? null : null;
  const confidence = isAiMotion ? confidenceOrNull(body.confidence) ?? null : null;
  const validatorVersion = isAiMotion ? stringOrNull(body.validatorVersion) ?? 'nuvo-ai-motion-v1' : null;
  const framesAnalyzed = isAiMotion ? nonNegativeIntOrNull(body.framesAnalyzed) ?? null : null;
  const validPoseFrames = isAiMotion ? nonNegativeIntOrNull(body.validPoseFrames) ?? null : null;
  const durationMs = isAiMotion ? nonNegativeIntOrNull(body.durationMs) ?? null : null;
  const summary =
    stringOrNull(body.verificationSummary) ??
    (isAiMotion
      ? status === 'ai_verified'
        ? `Detected ${detectedValue ?? increment} ${activityLabel} from live pose tracking.`
        : `Nuvo detected ${detectedValue ?? increment} clean reps out of ${targetValue ?? 'the target'}.`
      : status === 'accepted'
        ? 'Manual proof accepted. AI validation coming soon.'
        : 'Submitted for owner review. AI validation coming soon.');

  await c.env.DB.prepare(
    `INSERT INTO proofs
       (id, race_id, user_id, proof_type, ai_activity_type, note, value,
        detected_value, target_value, confidence, validator_version,
        frames_analyzed, valid_pose_frames, duration_ms, verification_status,
        verification_summary, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
  )
    .bind(
      proofId,
      race.id,
      userId,
      proofType,
      activityType,
      note,
      increment,
      detectedValue,
      targetValue,
      confidence,
      validatorVersion,
      framesAnalyzed,
      validPoseFrames,
      durationMs,
      status,
      summary,
    )
    .run();

  const proof = await c.env.DB.prepare('SELECT * FROM proofs WHERE id = ?')
    .bind(proofId)
    .first<ProofRow>();
  if (proof && (status === 'accepted' || status === 'ai_verified')) {
    await applyProofProgress(c.env.DB, race, proof);
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});

// GET /races/:id/proofs
racesRouter.get('/:id/proofs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);

  const proofs = await c.env.DB.prepare(
    `SELECT pr.id, pr.race_id, pr.user_id, pr.proof_type,
            pr.ai_activity_type, pr.note, pr.value, pr.detected_value,
            pr.target_value, pr.confidence, pr.validator_version,
            pr.frames_analyzed, pr.valid_pose_frames, pr.duration_ms,
            pr.verification_status, pr.verification_summary, pr.reviewed_by,
            pr.reviewed_at, pr.created_at,
            COALESCE(p.full_name, 'Unknown') as display_name
     FROM proofs pr
     LEFT JOIN profiles p ON p.user_id = pr.user_id
     WHERE pr.race_id = ?
     ORDER BY pr.created_at DESC`,
  )
    .bind(race.id)
    .all<ProofRow & { display_name: string }>();

  return c.json({
    ok: true,
    proofs: proofs.results.map((pr) => ({
      id: pr.id,
      userId: pr.user_id,
      displayName: (pr as ProofRow & { display_name: string }).display_name,
      proofType: pr.proof_type,
      aiActivityType: pr.ai_activity_type,
      note: pr.note,
      value: pr.value,
      detectedValue: pr.detected_value,
      targetValue: pr.target_value,
      confidence: pr.confidence,
      validatorVersion: pr.validator_version,
      framesAnalyzed: pr.frames_analyzed,
      validPoseFrames: pr.valid_pose_frames,
      durationMs: pr.duration_ms,
      verificationStatus: pr.verification_status,
      verificationSummary: pr.verification_summary,
      reviewedBy: pr.reviewed_by,
      reviewedAt: pr.reviewed_at,
      createdAt: pr.created_at,
    })),
  });
});

// PATCH /races/:id/proofs/:proofId - owner proof review.
racesRouter.patch('/:id/proofs/:proofId', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id !== userId) return c.json({ ok: false, error: 'Only the race creator can review proof' }, 403);

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const verificationStatus =
    typeof body.verificationStatus === 'string' && REVIEW_STATUSES.has(body.verificationStatus)
      ? body.verificationStatus
      : '';
  if (!verificationStatus) return c.json({ ok: false, error: 'Invalid verification status' }, 400);

  const proof = await c.env.DB.prepare('SELECT * FROM proofs WHERE id = ? AND race_id = ?')
    .bind(c.req.param('proofId'), race.id)
    .first<ProofRow>();
  if (!proof) return c.json({ ok: false, error: 'Proof not found' }, 404);

  const summary = stringOrNull(body.verificationSummary) ?? null;
  await c.env.DB.prepare(
    `UPDATE proofs
     SET verification_status = ?, verification_summary = ?, reviewed_by = ?,
         reviewed_at = CURRENT_TIMESTAMP
     WHERE id = ? AND race_id = ?`,
  )
    .bind(verificationStatus, summary, userId, proof.id, race.id)
    .run();

  if (
    (verificationStatus === 'accepted' || verificationStatus === 'ai_verified') &&
    proof.verification_status !== 'accepted' &&
    proof.verification_status !== 'ai_verified'
  ) {
    await applyProofProgress(c.env.DB, race, proof);
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});
