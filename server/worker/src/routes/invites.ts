import { Hono } from 'hono';
import type { MiddlewareHandler } from 'hono';
import type { AppEnv } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth, verifyJwt } from '../lib/jwt';
import { hasAcceptedTerms } from '../lib/terms';
import { isBlocked, isProfilePrivate, resolveRaceMemberVisibility } from '../lib/privacy';
import {
  ensureMember,
  ensureProgress,
  getRace,
} from '../domain/raceMembership';
import {
  INVITE_KINDS,
  type InviteKind,
  type InviteRow,
  defaultExpirySeconds,
  generateInviteToken,
  inviteAvailability,
  looksLikeInviteToken,
  shareUrl,
  statusForAvailability,
  targetTypeForKind,
} from '../lib/invites';

export const invitesRouter = new Hono<AppEnv>();

/** Parse a bearer token if present; never rejects. Sets userId when valid. */
const optionalAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const h = c.req.header('Authorization');
  if (h?.startsWith('Bearer ')) {
    try {
      const payload = await verifyJwt(h.slice(7), c.env.JWT_SECRET);
      c.set('userId', payload.sub);
    } catch {
      /* fall through as anonymous */
    }
  }
  await next();
};

function reqOrigin(c: { req: { url: string } }): string {
  return new URL(c.req.url).origin;
}

async function loadInvite(db: D1Database, token: string): Promise<InviteRow | null> {
  if (!looksLikeInviteToken(token)) return null;
  return db.prepare('SELECT * FROM invites WHERE token = ?').bind(token).first<InviteRow>();
}

interface PublicPerson {
  userId: string;
  displayName: string;
  username: string | null;
  profilePhotoUrl: string | null;
  isPrivate: boolean;
}

async function personCard(
  db: D1Database,
  viewerUserId: string | undefined,
  targetUserId: string,
): Promise<PublicPerson | null> {
  const row = await db
    .prepare(
      `SELECT u.id, p.full_name, p.username, p.avatar_url, p.private_profile, mp.member_id
       FROM users u
       LEFT JOIN profiles p ON p.user_id = u.id
       LEFT JOIN member_passes mp ON mp.user_id = u.id
       WHERE u.id = ? AND u.status = 'active'`,
    )
    .bind(targetUserId)
    .first<{
      id: string;
      full_name: string | null;
      username: string | null;
      avatar_url: string | null;
      private_profile: number | null;
      member_id: string | null;
    }>();
  if (!row) return null;

  const vis = resolveRaceMemberVisibility(
    viewerUserId,
    {
      userId: row.id,
      displayName: row.full_name,
      username: row.username,
      profilePhotoUrl: row.avatar_url,
      privateProfile: Boolean(row.private_profile),
    },
    { crewIds: new Set(), blockedEitherWay: new Set(), coRacerIds: new Set() },
  );
  return {
    userId: row.id,
    displayName: vis.anonymized ? (row.username ? `@${row.username}` : 'Nuvo member') : vis.displayName,
    username: row.username,
    profilePhotoUrl: vis.profilePhotoUrl,
    isPrivate: Boolean(row.private_profile),
  };
}

async function raceCard(db: D1Database, viewerUserId: string | undefined, raceId: string) {
  const race = await getRace(db, raceId);
  if (!race) return null;
  const [{ count: participantCount }, creator] = await Promise.all([
    db
      .prepare(`SELECT COUNT(*) as count FROM race_members WHERE race_id = ? AND status = 'active'`)
      .bind(raceId)
      .first<{ count: number }>()
      .then((r) => r ?? { count: 0 }),
    personCard(db, viewerUserId, race.creator_id),
  ]);
  const alreadyJoined = viewerUserId
    ? Boolean(
        await db
          .prepare(`SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active'`)
          .bind(raceId, viewerUserId)
          .first<{ id: string }>(),
      )
    : false;
  return {
    id: race.id,
    title: race.title,
    activityId: race.activity_id ?? race.movement_type ?? null,
    targetValue: race.target_value,
    targetUnit: race.target_unit,
    goalType: race.race_type,
    status: race.status,
    visibility: race.visibility,
    participantCount,
    creator: creator
      ? { displayName: creator.displayName, profilePhotoUrl: creator.profilePhotoUrl }
      : null,
    alreadyJoined,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /invites — mint a token for an entity the caller can share.
// ─────────────────────────────────────────────────────────────────────────────
invitesRouter.post('/', requireAuth, async (c) => {
  const userId = c.get('userId');
  let body: { kind?: unknown; targetId?: unknown; maxUses?: unknown; expiresInSeconds?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid JSON body' }, 400);
  }

  const kind = body.kind as InviteKind;
  if (!INVITE_KINDS.includes(kind)) {
    return c.json({ ok: false, error: 'Unknown invite kind' }, 400);
  }
  if (kind === 'squad_join') {
    return c.json({ ok: false, error: 'Squads are not available yet' }, 501);
  }

  const targetType = targetTypeForKind(kind);
  let targetId = typeof body.targetId === 'string' ? body.targetId.trim() : '';

  if (kind === 'crew_connect') {
    // "connect with me" — always the caller's own id, reusable.
    targetId = userId;
  } else if (kind === 'race_join') {
    if (!targetId) return c.json({ ok: false, error: 'targetId is required' }, 400);
    const race = await getRace(c.env.DB, targetId);
    if (!race) return c.json({ ok: false, error: 'Race not found' }, 404);
    if (race.creator_id !== userId) {
      return c.json({ ok: false, error: 'Only the race creator can create an invite' }, 403);
    }
  }

  // Rate limit: 20 invites / user / hour.
  const recent = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM invites
     WHERE actor_user_id = ? AND created_at > datetime('now', '-1 hour')`,
  )
    .bind(userId)
    .first<{ count: number }>();
  if ((recent?.count ?? 0) >= 20) {
    return c.json({ ok: false, error: 'Too many invites — try again later' }, 429);
  }

  // Reuse an existing live invite for the same (actor, target, kind) so a
  // "Share" button is stable across taps.
  const existing = await c.env.DB.prepare(
    `SELECT * FROM invites
     WHERE actor_user_id = ? AND kind = ? AND target_type = ? AND target_id = ?
       AND revoked_at IS NULL
       AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
     ORDER BY created_at DESC LIMIT 1`,
  )
    .bind(userId, kind, targetType, targetId)
    .first<InviteRow>();

  let row = existing;
  if (!row) {
    const maxUses =
      typeof body.maxUses === 'number' && body.maxUses > 0 ? Math.floor(body.maxUses) : null;
    const explicitExp =
      typeof body.expiresInSeconds === 'number' && body.expiresInSeconds > 0
        ? Math.floor(body.expiresInSeconds)
        : defaultExpirySeconds(kind);
    const expiresAt = explicitExp
      ? new Date(Date.now() + explicitExp * 1000).toISOString()
      : null;
    const id = generateId();
    const token = generateInviteToken();
    await c.env.DB.prepare(
      `INSERT INTO invites (id, token, kind, actor_user_id, target_type, target_id, max_uses, use_count, expires_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, CURRENT_TIMESTAMP)`,
    )
      .bind(id, token, kind, userId, targetType, targetId, maxUses, expiresAt)
      .run();
    row = (await c.env.DB.prepare('SELECT * FROM invites WHERE id = ?').bind(id).first<InviteRow>())!;
  }

  // Races also keep a human-typable short code (legacy race_invites).
  let code: string | null = null;
  if (kind === 'race_join') {
    const existingCode = await c.env.DB.prepare(
      `SELECT invite_code FROM race_invites WHERE race_id = ? AND status = 'active' ORDER BY created_at DESC LIMIT 1`,
    )
      .bind(targetId)
      .first<{ invite_code: string }>();
    code = existingCode?.invite_code ?? null;
    if (!code) {
      code = randomShortCode();
      await c.env.DB.prepare(
        `INSERT INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
         VALUES (?, ?, ?, ?, 'active', CURRENT_TIMESTAMP)`,
      )
        .bind(generateId(), targetId, userId, code)
        .run();
    }
  }

  return c.json({
    ok: true,
    token: row.token,
    url: shareUrl(reqOrigin(c), row.token),
    kind,
    code,
    expiresAt: row.expires_at,
  });
});

function randomShortCode(): string {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((b) => chars[b % chars.length])
    .join('');
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /invites/:token — safe preview. Works logged-out. Never mutates.
// ─────────────────────────────────────────────────────────────────────────────
invitesRouter.get('/:token', optionalAuth, async (c) => {
  const viewerUserId = c.get('userId') as string | undefined;
  const token = c.req.param('token');
  const invite = await loadInvite(c.env.DB, token);
  const availability = inviteAvailability(invite);
  if (availability !== 'active') {
    return c.json({ ok: false, status: availability }, statusForAvailability(availability));
  }
  const row = invite!;

  // Blocking wins — a blocked viewer gets the generic "not available".
  if (viewerUserId) {
    const blockTarget = row.kind === 'crew_connect' ? row.target_id : row.actor_user_id;
    if (
      blockTarget &&
      blockTarget !== viewerUserId &&
      ((await isBlocked(c.env.DB, viewerUserId, blockTarget)) ||
        (await isBlocked(c.env.DB, blockTarget, viewerUserId)))
    ) {
      return c.json({ ok: false, status: 'revoked' }, 410);
    }
  }

  if (row.kind === 'race_join') {
    const race = await raceCard(c.env.DB, viewerUserId, row.target_id);
    if (!race) return c.json({ ok: false, status: 'not_found' }, 404);
    return c.json({
      ok: true,
      status: 'active',
      kind: row.kind,
      requiresAuth: !viewerUserId,
      destination: { type: 'race', id: race.id },
      preview: { race },
    });
  }

  // crew_connect
  const person = await personCard(c.env.DB, viewerUserId, row.target_id);
  if (!person) return c.json({ ok: false, status: 'not_found' }, 404);
  return c.json({
    ok: true,
    status: 'active',
    kind: row.kind,
    requiresAuth: !viewerUserId,
    destination: { type: 'profile', id: person.userId },
    preview: { person, inviter: person },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /invites/:token/accept — join the race / connect. Auth required. Idempotent.
// ─────────────────────────────────────────────────────────────────────────────
invitesRouter.post('/:token/accept', requireAuth, async (c) => {
  const userId = c.get('userId');
  const token = c.req.param('token');
  const invite = await loadInvite(c.env.DB, token);
  const availability = inviteAvailability(invite);
  if (availability !== 'active') {
    return c.json({ ok: false, status: availability }, statusForAvailability(availability));
  }
  const row = invite!;

  const alreadyUsed = Boolean(
    await c.env.DB.prepare('SELECT id FROM invite_uses WHERE invite_id = ? AND user_id = ?')
      .bind(row.id, userId)
      .first<{ id: string }>(),
  );

  // ── race_join ──────────────────────────────────────────────────────────────
  if (row.kind === 'race_join') {
    if (!(await hasAcceptedTerms(c.env.DB, userId))) {
      return c.json({ ok: false, error: 'Accept the Terms of Service to join a race' }, 403);
    }
    const race = await getRace(c.env.DB, row.target_id);
    if (!race) return c.json({ ok: false, status: 'not_found' }, 404);
    if (race.status !== 'active') {
      return c.json({ ok: false, status: 'closed', error: 'This race is not open' }, 409);
    }
    // Blocking: if the race creator blocked this user (or vice versa), refuse.
    if (
      race.creator_id !== userId &&
      ((await isBlocked(c.env.DB, userId, race.creator_id)) ||
        (await isBlocked(c.env.DB, race.creator_id, userId)))
    ) {
      return c.json({ ok: false, status: 'revoked' }, 410);
    }
    const { created } = await ensureMember(c.env.DB, race.id, userId);
    await ensureProgress(c.env.DB, race.id, userId);
    await recordUse(c.env.DB, row, userId, alreadyUsed);
    return c.json({
      ok: true,
      kind: row.kind,
      alreadyJoined: !created,
      destination: { type: 'race', id: race.id },
    });
  }

  // ── crew_connect ───────────────────────────────────────────────────────────
  const targetUserId = row.target_id;
  if (targetUserId === userId) {
    return c.json({ ok: false, error: 'That is your own invite' }, 400);
  }
  if (
    (await isBlocked(c.env.DB, userId, targetUserId)) ||
    (await isBlocked(c.env.DB, targetUserId, userId))
  ) {
    return c.json({ ok: false, status: 'revoked' }, 410);
  }
  const target = await c.env.DB.prepare("SELECT id FROM users WHERE id = ? AND status = 'active'")
    .bind(targetUserId)
    .first<{ id: string }>();
  if (!target) return c.json({ ok: false, status: 'not_found' }, 404);

  const targetPrivate = await isProfilePrivate(c.env.DB, targetUserId);
  const connectionStatus = targetPrivate ? 'pending' : 'active';

  // Canonical directional rows, kept in sync (matches the existing crew route).
  await upsertConnection(c.env.DB, userId, targetUserId, connectionStatus, userId);
  await upsertConnection(
    c.env.DB,
    targetUserId,
    userId,
    connectionStatus === 'active' ? 'active' : 'pending',
    userId,
  );
  await recordUse(c.env.DB, row, userId, alreadyUsed);

  return c.json({
    ok: true,
    kind: row.kind,
    connectionStatus,
    destination: { type: 'profile', id: targetUserId },
  });
});

async function upsertConnection(
  db: D1Database,
  userId: string,
  crewUserId: string,
  status: string,
  requestedBy: string,
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO crew_connections (id, user_id, crew_user_id, status, requested_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id, crew_user_id) DO UPDATE SET
         status = CASE WHEN crew_connections.status = 'active' THEN 'active' ELSE excluded.status END,
         requested_by = COALESCE(crew_connections.requested_by, excluded.requested_by),
         updated_at = CURRENT_TIMESTAMP`,
    )
    .bind(generateId(), userId, crewUserId, status, requestedBy)
    .run();
}

async function recordUse(
  db: D1Database,
  row: InviteRow,
  userId: string,
  alreadyUsed: boolean,
): Promise<void> {
  if (alreadyUsed) return;
  await db
    .prepare(
      `INSERT OR IGNORE INTO invite_uses (id, invite_id, user_id, created_at)
       VALUES (?, ?, ?, CURRENT_TIMESTAMP)`,
    )
    .bind(generateId(), row.id, userId)
    .run();
  await db
    .prepare('UPDATE invites SET use_count = use_count + 1 WHERE id = ?')
    .bind(row.id)
    .run();
}

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /invites/:token — revoke (creator only).
// ─────────────────────────────────────────────────────────────────────────────
invitesRouter.delete('/:token', requireAuth, async (c) => {
  const userId = c.get('userId');
  const invite = await loadInvite(c.env.DB, c.req.param('token'));
  if (!invite) return c.json({ ok: false, status: 'not_found' }, 404);
  if (invite.actor_user_id !== userId) {
    return c.json({ ok: false, error: 'Only the creator can revoke this invite' }, 403);
  }
  await c.env.DB.prepare('UPDATE invites SET revoked_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(invite.id)
    .run();
  return c.json({ ok: true });
});
