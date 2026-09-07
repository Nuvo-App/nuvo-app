import { Hono, type Context } from 'hono';
import type { AppEnv } from '../types';

// Internal Motion Session lookup — for the coding agent / support tooling to
// pull what Nuvo actually saw during a verification attempt. Gated on a shared
// secret (`INTERNAL_API_KEY`), NOT a user JWT, so it can read any user's
// sessions. Never mount this behind the public app surface without the guard.

export const internalRouter = new Hono<AppEnv>();

internalRouter.use('*', async (c, next) => {
  const expected = c.env.INTERNAL_API_KEY;
  if (!expected) return c.json({ ok: false, error: 'Internal API not configured.' }, 503);
  if (c.req.header('X-Internal-Key') !== expected) {
    return c.json({ ok: false, error: 'Forbidden' }, 403);
  }
  await next();
  return;
});

type SessionRow = Record<string, unknown>;

const SUMMARY_COLS = `session_id, user_id, race_id, activity_id, kind, outcome,
  detected_value, goal_value, confidence, failed_rule_reason, started_at, ended_at,
  duration_ms, frame_count, schema_version, app_version, git_commit,
  verifier_version, model_version, object_key, created_at`;

function sessionSummary(row: SessionRow) {
  return {
    sessionId: row.session_id,
    userId: row.user_id,
    raceId: row.race_id,
    activityId: row.activity_id,
    kind: row.kind,
    outcome: row.outcome,
    detectedValue: row.detected_value,
    goalValue: row.goal_value,
    confidence: row.confidence,
    failedRuleReason: row.failed_rule_reason,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    durationMs: row.duration_ms,
    frameCount: row.frame_count,
    schemaVersion: row.schema_version,
    appVersion: row.app_version,
    gitCommit: row.git_commit,
    verifierVersion: row.verifier_version,
    modelVersion: row.model_version,
    objectKey: row.object_key,
    createdAt: row.created_at,
  };
}

async function decompressGzip(buf: ArrayBuffer): Promise<ArrayBuffer> {
  const stream = new Response(buf).body!.pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream).arrayBuffer();
}

/** DB row + its full R2 artifact, decompressed — the self-contained payload. */
async function fullSession(c: Context<AppEnv>, row: SessionRow) {
  const obj = await c.env.PROFILE_PHOTOS.get(String(row.object_key));
  let artifact: unknown = null;
  if (obj) {
    try {
      const bytes = await decompressGzip(await obj.arrayBuffer());
      artifact = JSON.parse(new TextDecoder().decode(bytes));
    } catch (e) {
      artifact = { error: `Could not decode artifact: ${e instanceof Error ? e.message : String(e)}` };
    }
  }
  return {
    ok: true as const,
    session: sessionSummary(row),
    metadata: typeof row.metadata_json === 'string' ? JSON.parse(row.metadata_json) : null,
    artifact,
  };
}

// Resolve a user by email / username / id → the id to use in the calls below.
internalRouter.get('/users/resolve', async (c) => {
  const email = c.req.query('email')?.trim().toLowerCase();
  const username = c.req.query('username')?.trim().toLowerCase();
  const id = c.req.query('id')?.trim();
  if (!email && !username && !id) {
    return c.json({ ok: false, error: 'Pass one of ?email=, ?username=, ?id=.' }, 400);
  }

  let where: string;
  let param: string;
  if (id) { where = 'u.id = ?'; param = id; }
  else if (email) { where = "LOWER(COALESCE(u.primary_email, '')) = ?"; param = email; }
  else { where = "LOWER(COALESCE(p.username, '')) = ?"; param = username!; }

  const row = await c.env.DB.prepare(
    `SELECT u.id, u.primary_email, u.status, p.full_name, p.username
       FROM users u LEFT JOIN profiles p ON p.user_id = u.id
      WHERE ${where} LIMIT 1`,
  ).bind(param).first<Record<string, unknown>>();

  if (!row) return c.json({ ok: false, error: 'No matching user.' }, 404);
  return c.json({
    ok: true,
    user: {
      id: row.id,
      email: row.primary_email,
      username: row.username,
      displayName: row.full_name ?? row.username ?? null,
      status: row.status,
    },
  });
});

// Recent failed / abandoned sessions across all users — the triage queue.
internalRouter.get('/motion-sessions/failed', async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 20), 1), 100);
  const rs = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS} FROM motion_sessions
      WHERE outcome IN ('failed', 'incomplete')
      ORDER BY created_at DESC LIMIT ?`,
  ).bind(limit).all<SessionRow>();
  return c.json({ ok: true, count: rs.results.length, sessions: rs.results.map(sessionSummary) });
});

// One session by id — metadata + the full artifact from R2, self-contained.
internalRouter.get('/motion-sessions/:sessionId', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS}, metadata_json FROM motion_sessions WHERE session_id = ? LIMIT 1`,
  ).bind(c.req.param('sessionId')).first<SessionRow>();
  if (!row) return c.json({ ok: false, error: 'Session not found.' }, 404);
  return c.json(await fullSession(c, row));
});

// A user's sessions, newest first; optional ?activityId= and ?outcome= filters.
internalRouter.get('/users/:userId/motion-sessions', async (c) => {
  const userId = c.req.param('userId');
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 20), 1), 100);
  const activityId = c.req.query('activityId');
  const outcome = c.req.query('outcome');

  const clauses = ['user_id = ?'];
  const binds: unknown[] = [userId];
  if (activityId) { clauses.push('activity_id = ?'); binds.push(activityId); }
  if (outcome) { clauses.push('outcome = ?'); binds.push(outcome); }
  binds.push(limit);

  const rs = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS} FROM motion_sessions
      WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT ?`,
  ).bind(...binds).all<SessionRow>();
  return c.json({ ok: true, count: rs.results.length, sessions: rs.results.map(sessionSummary) });
});

// The user's single latest session (optionally for one activity) + its artifact.
internalRouter.get('/users/:userId/motion-sessions/latest', async (c) => {
  const userId = c.req.param('userId');
  const activityId = c.req.query('activityId');
  const row = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS}, metadata_json FROM motion_sessions
      WHERE user_id = ?${activityId ? ' AND activity_id = ?' : ''}
      ORDER BY created_at DESC LIMIT 1`,
  ).bind(...(activityId ? [userId, activityId] : [userId])).first<SessionRow>();
  if (!row) return c.json({ ok: false, error: 'No sessions for this user.' }, 404);
  return c.json(await fullSession(c, row));
});

// Latest session for a given activity across all users.
internalRouter.get('/activities/:activityId/motion-sessions/latest', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS}, metadata_json FROM motion_sessions
      WHERE activity_id = ? ORDER BY created_at DESC LIMIT 1`,
  ).bind(c.req.param('activityId')).first<SessionRow>();
  if (!row) return c.json({ ok: false, error: 'No sessions for this activity.' }, 404);
  return c.json(await fullSession(c, row));
});
