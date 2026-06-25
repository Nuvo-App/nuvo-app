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
  'checked',
  'pending',
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
  subtitle: string | null;
  description: string | null;
  category: string | null;
  goal_type: string;
  race_type: string | null;
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
  race_key: string | null;
  created_by_person_id: string | null;
  cover_url: string | null;
  cover_r2_key: string | null;
  demo_priority: number | null;
  created_at: string;
  updated_at: string;
}

interface PersonRow {
  id: string;
  user_id: string | null;
  display_name: string;
  username: string | null;
  avatar_url: string | null;
}

interface BoardRow {
  id: string;
  race_id: string;
  person_id: string;
  user_id: string | null;
  display_name: string;
  username: string | null;
  profile_photo_url: string | null;
  score_value: number;
  score_percent: number;
  joined_at: string;
}

interface MoveRow {
  id: string;
  race_id: string;
  person_id: string;
  user_id: string | null;
  display_name: string;
  profile_photo_url: string | null;
  amount_value: number | null;
  amount_unit: string | null;
  move_status: string;
  move_source: string;
  note: string | null;
  media_url: string | null;
  ai_summary: string | null;
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

function slugKey(value: string, fallback: string): string {
  const slug = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return slug || fallback;
}

function legacyStatusFromMove(status: string): string {
  if (status === 'checked') return 'accepted';
  if (status === 'pending') return 'submitted';
  if (status === 'rejected') return 'rejected';
  return status;
}

function moveStatusFromLegacy(status: string): string {
  if (status === 'accepted' || status === 'ai_verified') return 'checked';
  if (status === 'rejected' || status === 'ai_failed') return 'rejected';
  return 'pending';
}

function moveSourceFromProofType(proofType: string): string {
  if (proofType === 'ai_motion') return 'ai';
  if (proofType === 'photo' || proofType === 'photo_video') return 'photo';
  if (proofType === 'admin_demo') return 'admin_demo';
  return 'manual';
}

function proofTypeFromMoveSource(moveSource: string): string {
  if (moveSource === 'ai') return 'ai_motion';
  if (moveSource === 'photo') return 'photo';
  return 'manual';
}

async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db
    .prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL')
    .bind(raceId)
    .first<RaceRow>();
}

async function getPersonByUserId(db: D1Database, userId: string): Promise<PersonRow | null> {
  return db
    .prepare('SELECT id, user_id, display_name, username, avatar_url FROM people WHERE user_id = ?')
    .bind(userId)
    .first<PersonRow>();
}

async function ensurePersonForUser(db: D1Database, userId: string): Promise<PersonRow> {
  const existing = await getPersonByUserId(db, userId);
  if (existing) return existing;

  const row = await db
    .prepare(
      `SELECT u.id, u.primary_email, u.status, u.created_at, u.updated_at,
              p.full_name, p.username, p.avatar_url
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       WHERE u.id = ?`,
    )
    .bind(userId)
    .first<{
      id: string;
      primary_email: string | null;
      status: string;
      created_at: string;
      updated_at: string;
      full_name: string | null;
      username: string | null;
      avatar_url: string | null;
    }>();
  if (!row) throw new Error('User not found');

  const displayName = row.full_name ?? row.username ?? row.primary_email ?? 'Nuvo member';
  const personKey = row.username ?? slugKey(displayName, `user_${userId.slice(0, 8)}`);
  await db
    .prepare(
      `INSERT INTO people
         (id, person_key, user_id, display_name, username, avatar_url, is_demo, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         display_name = excluded.display_name,
         username = excluded.username,
         avatar_url = excluded.avatar_url,
         status = excluded.status,
         updated_at = CURRENT_TIMESTAMP`,
    )
    .bind(
      userId,
      personKey,
      userId,
      displayName,
      row.username,
      row.avatar_url,
      row.status,
      row.created_at,
      row.updated_at,
    )
    .run();

  const created = await getPersonByUserId(db, userId);
  if (!created) throw new Error('Person not found after create');
  return created;
}

async function ensureRaceMember(db: D1Database, race: RaceRow, userId: string): Promise<void> {
  const person = await ensurePersonForUser(db, userId);
  const memberRole = race.creator_id === userId ? 'creator' : 'member';
  await db
    .prepare(
      `INSERT INTO race_members
         (id, race_id, person_id, member_role, member_status, score_value, score_percent,
          is_current_user_highlight, joined_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'active', 0, 0, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT(race_id, person_id) DO UPDATE SET
         member_status = 'active',
         member_role = excluded.member_role,
         updated_at = CURRENT_TIMESTAMP`,
    )
    .bind(generateId(), race.id, person.id, memberRole, race.creator_id === userId ? 1 : 0)
    .run();

  await db
    .prepare(
      `INSERT INTO race_participants
         (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
       VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP)
       ON CONFLICT(race_id, user_id) DO NOTHING`,
    )
    .bind(generateId(), race.id, userId, person.display_name)
    .run();
}

async function applyMoveProgress(db: D1Database, race: RaceRow, userId: string, amount: number): Promise<void> {
  if (amount <= 0) return;
  await ensureRaceMember(db, race, userId);
  const person = await ensurePersonForUser(db, userId);
  const member = await db
    .prepare('SELECT score_value FROM race_members WHERE race_id = ? AND person_id = ?')
    .bind(race.id, person.id)
    .first<{ score_value: number }>();
  const newScoreValue = (member?.score_value ?? 0) + amount;
  const newScorePercent =
    race.target_value && race.target_value > 0
      ? Math.min(100, Math.round((newScoreValue / race.target_value) * 100))
      : 0;

  await db.batch([
    db
      .prepare(
        `UPDATE race_members
         SET score_value = ?, score_percent = ?, last_move_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE race_id = ? AND person_id = ?`,
      )
      .bind(newScoreValue, newScorePercent, race.id, person.id),
    db
      .prepare(
        `UPDATE race_participants
         SET progress_value = ?, progress_percent = ?
         WHERE race_id = ? AND user_id = ?`,
      )
      .bind(newScoreValue, newScorePercent, race.id, userId),
  ]);
}

async function buildRaceResponse(db: D1Database, race: RaceRow) {
  const [members, moves, invite] = await Promise.all([
    db
      .prepare(
        `SELECT rm.id, rm.race_id, rm.person_id, p.user_id,
                p.display_name, p.username, p.avatar_url as profile_photo_url,
                rm.score_value, rm.score_percent, rm.joined_at
         FROM race_members rm
         JOIN people p ON p.id = rm.person_id
         WHERE rm.race_id = ? AND rm.member_status = 'active'
         ORDER BY
           COALESCE(rm.rank_override, 999999) ASC,
           rm.score_percent DESC,
           rm.score_value DESC,
           rm.joined_at ASC`,
      )
      .bind(race.id)
      .all<BoardRow>(),
    db
      .prepare(
        `SELECT m.id, m.race_id, m.person_id, p.user_id,
                p.display_name, p.avatar_url as profile_photo_url,
                m.amount_value, m.amount_unit, m.move_status, m.move_source,
                m.note, m.media_url, m.ai_summary, m.created_at
         FROM moves m
         JOIN people p ON p.id = m.person_id
         WHERE m.race_id = ?
         ORDER BY m.created_at DESC
         LIMIT 20`,
      )
      .bind(race.id)
      .all<MoveRow>(),
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

  const moveLog = moves.results.map((m) => ({
    id: m.id,
    userId: m.user_id,
    personId: m.person_id,
    displayName: m.display_name,
    profilePhotoUrl: m.profile_photo_url,
    moveSource: m.move_source,
    moveStatus: m.move_status,
    note: m.note,
    value: m.amount_value,
    amountValue: m.amount_value,
    amountUnit: m.amount_unit,
    mediaUrl: m.media_url,
    verificationStatus: legacyStatusFromMove(m.move_status),
    verificationSummary: m.ai_summary,
    createdAt: m.created_at,
  }));

  return {
    id: race.id,
    raceKey: race.race_key,
    creatorId: race.creator_id,
    createdByPersonId: race.created_by_person_id,
    title: race.title,
    subtitle: race.subtitle,
    description: race.description,
    category: race.category,
    goalType: race.goal_type,
    raceType: race.race_type,
    targetValue: race.target_value,
    unit: race.unit,
    targetUnit: race.target_unit,
    aiActivityType: race.ai_activity_type,
    proofMode: race.proof_mode,
    status: race.status,
    startLineAt: race.start_line_at,
    finishLineAt: race.finish_line_at,
    rules: race.rules,
    proofRequirement: race.proof_requirement,
    proofReviewMode: race.proof_review_mode,
    visibility: race.visibility,
    inviteCode: invite?.invite_code ?? null,
    coverUrl: race.cover_url,
    createdAt: race.created_at,
    updatedAt: race.updated_at,
    participants: members.results.map((p) => ({
      id: p.id,
      userId: p.user_id ?? p.person_id,
      personId: p.person_id,
      displayName: p.display_name,
      username: p.username,
      profilePhotoUrl: p.profile_photo_url,
      progressValue: p.score_value,
      progressPercent: p.score_percent,
      scoreValue: p.score_value,
      scorePercent: p.score_percent,
      joinedAt: p.joined_at,
    })),
    raceMembers: members.results.map((p) => ({
      id: p.id,
      userId: p.user_id,
      personId: p.person_id,
      displayName: p.display_name,
      username: p.username,
      profilePhotoUrl: p.profile_photo_url,
      scoreValue: p.score_value,
      scorePercent: p.score_percent,
      joinedAt: p.joined_at,
    })),
    recentMoves: moveLog,
    moveLog,
    recentProofs: moveLog.map((m) => ({
      id: m.id,
      userId: m.userId,
      displayName: m.displayName,
      profilePhotoUrl: m.profilePhotoUrl,
      proofType: proofTypeFromMoveSource(m.moveSource),
      moveSource: m.moveSource,
      note: m.note,
      value: m.value,
      detectedValue: null,
      targetValue: null,
      confidence: null,
      validatorVersion: null,
      framesAnalyzed: null,
      validPoseFrames: null,
      durationMs: null,
      verificationStatus: m.verificationStatus,
      verificationSummary: m.verificationSummary,
      reviewedBy: null,
      reviewedAt: null,
      createdAt: m.createdAt,
    })),
  };
}

async function currentUserCanManageRace(db: D1Database, race: RaceRow, userId: string): Promise<boolean> {
  if (race.creator_id === userId) return true;
  const person = await getPersonByUserId(db, userId);
  if (!person) return false;
  const member = await db
    .prepare(
      `SELECT id FROM race_members
       WHERE race_id = ? AND person_id = ? AND member_status = 'active'`,
    )
    .bind(race.id, person.id)
    .first<{ id: string }>();
  return Boolean(member);
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

  await ensureRaceMember(c.env.DB, race, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// GET /races - all races the current user created or joined.
racesRouter.get('/', async (c) => {
  const userId = c.get('userId');
  const person = await ensurePersonForUser(c.env.DB, userId);
  const rows = await c.env.DB.prepare(
    `SELECT DISTINCT r.* FROM races r
     LEFT JOIN race_members rm
       ON rm.race_id = r.id
      AND rm.person_id = ?
      AND rm.member_status = 'active'
     WHERE r.deleted_at IS NULL AND (r.creator_id = ? OR rm.id IS NOT NULL)
     ORDER BY r.created_at DESC`,
  )
    .bind(person.id, userId)
    .all<RaceRow>();

  const races = await Promise.all(rows.results.map((r) => buildRaceResponse(c.env.DB, r)));
  return c.json({ ok: true, races });
});

// POST /races - create a new race and auto-join creator as member.
racesRouter.post('/', async (c) => {
  const userId = c.get('userId');
  const creator = await ensurePersonForUser(c.env.DB, userId);

  let body: Record<string, unknown>;
  try {
    body = await c.req.json<Record<string, unknown>>();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const title = typeof body.title === 'string' ? body.title.trim() : '';
  if (!title) return c.json({ ok: false, error: 'title is required' }, 400);

  const subtitle = stringOrNull(body.subtitle) ?? null;
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
  const raceType = stringOrNull(body.raceType) ?? proofMode;
  const proofReviewMode =
    typeof body.proofReviewMode === 'string' && PROOF_REVIEW_MODES.has(body.proofReviewMode)
      ? body.proofReviewMode
      : 'auto_accept';
  const visibility =
    typeof body.visibility === 'string' && VISIBILITIES.has(body.visibility)
      ? body.visibility
      : 'private';

  const raceId = generateId();
  const raceKey = `${slugKey(title, 'race')}_${raceId.slice(0, 8)}`;
  const memberId = generateId();

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO races
         (id, creator_id, race_key, title, subtitle, description, category, goal_type, race_type,
          target_value, unit, ai_activity_type, target_unit, proof_mode, status,
          start_line_at, finish_line_at, rules, proof_requirement, proof_review_mode,
          visibility, created_by_person_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    ).bind(
      raceId,
      userId,
      raceKey,
      title,
      subtitle,
      description,
      category,
      goalType,
      raceType,
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
      creator.id,
    ),
    c.env.DB.prepare(
      `INSERT INTO race_members
         (id, race_id, person_id, member_role, member_status, score_value, score_percent,
          is_current_user_highlight, joined_at, created_at, updated_at)
       VALUES (?, ?, ?, 'creator', 'active', 0, 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    ).bind(memberId, raceId, creator.id),
    c.env.DB.prepare(
      `INSERT INTO race_participants
         (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
       VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`,
    ).bind(generateId(), raceId, userId, creator.display_name),
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
    ['subtitle', 'subtitle'],
    ['description', 'description'],
    ['category', 'category'],
    ['goalType', 'goal_type'],
    ['raceType', 'race_type'],
    ['unit', 'unit'],
    ['aiActivityType', 'ai_activity_type'],
    ['targetUnit', 'target_unit'],
    ['proofMode', 'proof_mode'],
    ['startLineAt', 'start_line_at'],
    ['finishLineAt', 'finish_line_at'],
    ['rules', 'rules'],
    ['coverUrl', 'cover_url'],
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

// POST /races/:id/leave - non-owner member leaves.
racesRouter.post('/:id/leave', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.creator_id === userId) {
    return c.json({ ok: false, error: 'Race creator cannot leave their own race' }, 400);
  }

  const person = await ensurePersonForUser(c.env.DB, userId);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE race_members
       SET member_status = 'removed', updated_at = CURRENT_TIMESTAMP
       WHERE race_id = ? AND person_id = ?`,
    ).bind(race.id, person.id),
    c.env.DB.prepare('DELETE FROM race_participants WHERE race_id = ? AND user_id = ?')
      .bind(race.id, userId),
  ]);
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

  await ensureRaceMember(c.env.DB, race, userId);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/participants - add a user directly to a race.
racesRouter.post('/:id/participants', async (c) => {
  const userId = c.get('userId');
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
  if (race.status !== 'active') return c.json({ ok: false, error: 'Race is not active' }, 400);

  if (!(await currentUserCanManageRace(c.env.DB, race, userId))) {
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

  await ensureRaceMember(c.env.DB, race, targetUserId);
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
    `INSERT INTO race_invites (id, race_id, created_by, created_by_person_id, invite_code, status, created_at)
     VALUES (?, ?, ?, ?, ?, 'active', CURRENT_TIMESTAMP)`,
  )
    .bind(generateId(), race.id, userId, (await ensurePersonForUser(c.env.DB, userId)).id, code)
    .run();

  return c.json({ ok: true, inviteCode: code, race: await buildRaceResponse(c.env.DB, race) });
});

// POST /races/:id/proof - compatibility endpoint that now writes a move.
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
  const moveSource = typeof body.moveSource === 'string' ? body.moveSource : moveSourceFromProofType(proofType);
  const note = stringOrNull(body.note) ?? null;
  const isAiMotion = proofType === 'ai_motion' || moveSource === 'ai';
  const value = isAiMotion
    ? nonNegativeIntOrNull(body.value)
    : positiveIntOrNull(body.value);
  const increment = value ?? 0;
  if (!isAiMotion && increment <= 0) return c.json({ ok: false, error: 'value must be greater than 0' }, 400);

  await ensureRaceMember(c.env.DB, race, userId);
  const person = await ensurePersonForUser(c.env.DB, userId);

  const aiStatus =
    typeof body.verificationStatus === 'string' &&
    (body.verificationStatus === 'ai_verified' ||
      body.verificationStatus === 'ai_failed' ||
      body.verificationStatus === 'needs_review')
      ? body.verificationStatus
      : '';
  const legacyStatus = isAiMotion
    ? aiStatus || 'needs_review'
    : race.proof_review_mode === 'owner_review'
      ? 'submitted'
      : 'accepted';
  const moveStatus = moveStatusFromLegacy(legacyStatus);
  if (isAiMotion && legacyStatus === 'ai_verified' && increment <= 0) {
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
      ? legacyStatus === 'ai_verified'
        ? `Detected ${detectedValue ?? increment} ${activityLabel} from live pose tracking.`
        : `Nuvo detected ${detectedValue ?? increment} clean reps out of ${targetValue ?? 'the target'}.`
      : moveStatus === 'checked'
        ? 'Manual move checked.'
        : 'Move submitted for review.');

  const moveId = generateId();
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO moves
         (id, race_id, person_id, amount_value, amount_unit, move_status, move_source,
          note, media_url, checked_at, ai_summary, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    ).bind(
      moveId,
      race.id,
      person.id,
      increment,
      race.target_unit ?? race.unit,
      moveStatus,
      moveSource,
      note,
      stringOrNull(body.mediaUrl) ?? null,
      moveStatus === 'checked' ? new Date().toISOString() : null,
      summary,
    ),
    c.env.DB.prepare(
      `INSERT INTO proofs
         (id, race_id, user_id, proof_type, ai_activity_type, note, value,
          detected_value, target_value, confidence, validator_version,
          frames_analyzed, valid_pose_frames, duration_ms, verification_status,
          verification_summary, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
    ).bind(
      moveId,
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
      legacyStatus,
      summary,
    ),
  ]);

  if (moveStatus === 'checked') {
    await applyMoveProgress(c.env.DB, race, userId, increment);
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});

// GET /races/:id/proofs - compatibility endpoint backed by moves.
racesRouter.get('/:id/proofs', async (c) => {
  const race = await getRace(c.env.DB, c.req.param('id'));
  if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);

  const raceResponse = await buildRaceResponse(c.env.DB, race);
  return c.json({
    ok: true,
    proofs: raceResponse.recentProofs,
    moves: raceResponse.recentMoves,
  });
});

// PATCH /races/:id/proofs/:proofId - owner move review through compatibility route.
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

  const moveStatus = moveStatusFromLegacy(verificationStatus);
  const move = await c.env.DB.prepare(
    `SELECT m.*, p.user_id
     FROM moves m
     JOIN people p ON p.id = m.person_id
     WHERE m.id = ? AND m.race_id = ?`,
  )
    .bind(c.req.param('proofId'), race.id)
    .first<MoveRow>();
  if (!move) return c.json({ ok: false, error: 'Proof not found' }, 404);

  const reviewer = await ensurePersonForUser(c.env.DB, userId);
  const summary = stringOrNull(body.verificationSummary) ?? null;
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE moves
       SET move_status = ?, ai_summary = ?, checked_by = ?,
           checked_at = CASE WHEN ? = 'checked' THEN CURRENT_TIMESTAMP ELSE checked_at END,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND race_id = ?`,
    ).bind(moveStatus, summary, reviewer.id, moveStatus, move.id, race.id),
    c.env.DB.prepare(
      `UPDATE proofs
       SET verification_status = ?, verification_summary = ?, reviewed_by = ?,
           reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ? AND race_id = ?`,
    ).bind(legacyStatusFromMove(moveStatus), summary, userId, move.id, race.id),
  ]);

  if (moveStatus === 'checked' && move.move_status !== 'checked' && move.user_id) {
    await applyMoveProgress(c.env.DB, race, move.user_id, move.amount_value ?? 0);
  }

  const updated = await getRace(c.env.DB, race.id);
  return c.json({ ok: true, race: await buildRaceResponse(c.env.DB, updated!) });
});
