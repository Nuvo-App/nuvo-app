import { Hono } from 'hono';
import type { Context } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import { assignmentForNextSession } from '../domain/motionAssignments';
import { recordReleaseMetric } from '../domain/motionTelemetry';

export const verificationSessionsRouter = new Hono<AppEnv>();

type RaceAccessRow = {
  id: string;
  activity_id: string | null;
  status: string;
};

type VerificationSessionRow = {
  id: string;
  race_id: string;
  user_id: string;
  activity_id: string;
  release_id: string;
  release_checksum: string;
  spec_schema_version: number;
  engine_type: string;
  app_version: string;
  app_build: string;
  runtime_capabilities_json: string;
  status: string;
  result_value: number | null;
  confidence: number | null;
  failure_reason: string | null;
  started_at: string | null;
  completed_at: string | null;
  motion_session_id: string | null;
  created_at: string;
};

function stringValue(value: unknown, fallback: string): string {
  return typeof value === 'string' && value.trim() ? value.trim() : fallback;
}

function capabilities(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((entry): entry is string => typeof entry === 'string' && Boolean(entry.trim())).map((entry) => entry.trim()))].slice(0, 64);
}

function sessionView(row: VerificationSessionRow) {
  let runtimeCapabilities: string[] = [];
  try {
    const parsed = JSON.parse(row.runtime_capabilities_json);
    if (Array.isArray(parsed)) runtimeCapabilities = parsed.filter((entry): entry is string => typeof entry === 'string');
  } catch {
    // Keep the API readable if an old row contains malformed telemetry.
  }
  return {
    id: row.id,
    raceId: row.race_id,
    userId: row.user_id,
    activityId: row.activity_id,
    releaseId: row.release_id,
    releaseChecksum: row.release_checksum,
    specSchemaVersion: row.spec_schema_version,
    engineType: row.engine_type,
    appVersion: row.app_version,
    appBuild: row.app_build,
    runtimeCapabilities,
    status: row.status,
    resultValue: row.result_value,
    confidence: row.confidence,
    failureReason: row.failure_reason,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    motionSessionId: row.motion_session_id,
    createdAt: row.created_at,
  };
}

async function readSession(db: D1Database, sessionId: string, userId: string): Promise<VerificationSessionRow | null> {
  return db.prepare(
    'SELECT id, race_id, user_id, activity_id, release_id, release_checksum, spec_schema_version, ' +
    'engine_type, app_version, app_build, runtime_capabilities_json, status, result_value, confidence, ' +
    'failure_reason, started_at, completed_at, motion_session_id, created_at ' +
    'FROM verification_sessions WHERE id = ? AND user_id = ? LIMIT 1',
  ).bind(sessionId, userId).first<VerificationSessionRow>();
}

async function readJson(c: Context<AppEnv>): Promise<Record<string, unknown> | null> {
  try {
    const body = await c.req.json<unknown>();
    if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
    return body as Record<string, unknown>;
  } catch {
    return null;
  }
}

verificationSessionsRouter.post('/races/:raceId/verification-sessions', requireAuth, async (c) => {
  const raceId = c.req.param('raceId');
  const userId = c.get('userId');
  const race = await c.env.DB.prepare(
    "SELECT id, activity_id, status FROM races WHERE id = ? AND deleted_at IS NULL LIMIT 1",
  ).bind(raceId).first<RaceAccessRow>();
  if (!race) return c.json({ ok: false, error: 'Race not found.' }, 404);
  if (race.status === 'cancelled' || race.status === 'archived' || race.status === 'completed') {
    return c.json({ ok: false, error: 'This race is no longer accepting proof.' }, 409);
  }
  const member = await c.env.DB.prepare(
    "SELECT id FROM race_members WHERE race_id = ? AND user_id = ? AND status = 'active' LIMIT 1",
  ).bind(raceId, userId).first<{ id: string }>();
  if (!member) return c.json({ ok: false, error: 'Join the race before submitting proof.' }, 403);
  if (!race.activity_id) return c.json({ ok: false, error: 'This race does not have a supported verifier.' }, 409);

  const assignment = await assignmentForNextSession(c.env.DB, raceId);
  if (!assignment || assignment.assignment.activityId !== race.activity_id) {
    return c.json({ ok: false, code: 'verifier_unavailable', error: 'A compatible verifier is not available for this race yet.' }, 503);
  }
  if (assignment.release.status !== 'stable') {
    return c.json({ ok: false, code: 'verifier_unavailable', error: 'This verifier release is not currently available.' }, 503);
  }

  const body = await readJson(c);
  if (!body) return c.json({ ok: false, error: 'Invalid JSON body.' }, 400);
  const runtimeCapabilities = capabilities(body.runtimeCapabilities);
  const missingCapabilities = assignment.release.requiredCapabilities.filter((required) => !runtimeCapabilities.includes(required));
  if (missingCapabilities.length > 0) {
    return c.json({
      ok: false,
      code: 'unsupported_client',
      error: 'This app build cannot run the verifier assigned to the race.',
      missingCapabilities,
      releaseId: assignment.release.id,
      releaseChecksum: assignment.release.checksum,
    }, 409);
  }

  const sessionId = generateId();
  await c.env.DB.prepare(
    'INSERT INTO verification_sessions ' +
    '(id, race_id, user_id, activity_id, release_id, release_checksum, spec_schema_version, engine_type, ' +
    'app_version, app_build, runtime_capabilities_json, status) ' +
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'created')",
  ).bind(
    sessionId,
    raceId,
    userId,
    assignment.release.activityId,
    assignment.release.id,
    assignment.release.checksum,
    assignment.release.specSchemaVersion,
    assignment.release.engineType,
    stringValue(body.appVersion, 'unknown'),
    stringValue(body.appBuild, 'unknown'),
    JSON.stringify(runtimeCapabilities),
  ).run();

  return c.json({
    ok: true,
    session: {
      id: sessionId,
      raceId,
      activityId: assignment.release.activityId,
      releaseId: assignment.release.id,
      releaseChecksum: assignment.release.checksum,
      assignmentPolicy: assignment.assignment.assignmentPolicy,
      assignmentReason: assignment.assignment.assignmentReason,
      status: 'created',
    },
    verifier: {
      releaseId: assignment.release.id,
      checksum: assignment.release.checksum,
      activityId: assignment.release.activityId,
      engineType: assignment.release.engineType,
      specSchemaVersion: assignment.release.specSchemaVersion,
      spec: assignment.release.spec,
      requiredCapabilities: assignment.release.requiredCapabilities,
      minimumAppBuild: assignment.release.minimumAppBuild,
    },
  }, 201);
});

verificationSessionsRouter.post('/verification-sessions/:sessionId/start', requireAuth, async (c) => {
  const sessionId = c.req.param('sessionId');
  const session = await readSession(c.env.DB, sessionId, c.get('userId'));
  if (!session) return c.json({ ok: false, error: 'Verification session not found.' }, 404);
  if (session.status === 'running') return c.json({ ok: true, session: sessionView(session) });
  if (session.status !== 'created') return c.json({ ok: false, error: 'This verification session is no longer startable.' }, 409);
  await c.env.DB.prepare(
    "UPDATE verification_sessions SET status = 'running', started_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ? AND status = 'created'",
  ).bind(sessionId, c.get('userId')).run();
  const updated = await readSession(c.env.DB, sessionId, c.get('userId'));
  return updated ? c.json({ ok: true, session: sessionView(updated) }) : c.json({ ok: false, error: 'Verification session could not be started.' }, 500);
});

verificationSessionsRouter.post('/verification-sessions/:sessionId/complete', requireAuth, async (c) => {
  const sessionId = c.req.param('sessionId');
  const userId = c.get('userId');
  const session = await readSession(c.env.DB, sessionId, userId);
  if (!session) return c.json({ ok: false, error: 'Verification session not found.' }, 404);
  const body = await readJson(c);
  if (!body) return c.json({ ok: false, error: 'Invalid JSON body.' }, 400);

  const releaseId = stringValue(body.releaseId, '');
  const releaseChecksum = stringValue(body.releaseChecksum, '');
  if (!releaseId || !releaseChecksum) return c.json({ ok: false, error: 'releaseId and releaseChecksum are required.' }, 400);
  if (releaseId !== session.release_id || releaseChecksum !== session.release_checksum) {
    return c.json({ ok: false, code: 'release_mismatch', error: 'The submitted proof used a different verifier release than this session.' }, 409);
  }
  if (session.status === 'completed' || session.status === 'failed') {
    return c.json({ ok: true, idempotent: true, session: sessionView(session) });
  }
  if (session.status !== 'running' && session.status !== 'created') {
    return c.json({ ok: false, error: 'This verification session cannot be completed.' }, 409);
  }

  const rawResult = body.resultValue;
  const resultValue = typeof rawResult === 'number' && Number.isFinite(rawResult) ? Math.max(0, Math.trunc(rawResult)) : null;
  const rawConfidence = body.confidence;
  const confidence = typeof rawConfidence === 'number' && Number.isFinite(rawConfidence) ? Math.max(0, Math.min(1, rawConfidence)) : null;
  const failureReason = typeof body.failureReason === 'string' && body.failureReason.trim() ? body.failureReason.trim().slice(0, 500) : null;
  const status = body.status === 'failed' || failureReason ? 'failed' : 'completed';
  const motionSessionId = typeof body.motionSessionId === 'string' && body.motionSessionId.trim() ? body.motionSessionId.trim() : null;
  await c.env.DB.prepare(
    'UPDATE verification_sessions SET status = ?, result_value = ?, confidence = ?, failure_reason = ?, ' +
    'completed_at = CURRENT_TIMESTAMP, motion_session_id = ?, started_at = COALESCE(started_at, CURRENT_TIMESTAMP) ' +
    'WHERE id = ? AND user_id = ? AND status IN (?, ?)',
  ).bind(status, resultValue, confidence, failureReason, motionSessionId, sessionId, userId, 'created', 'running').run();

  // Link the already-uploaded artifact to the immutable release that actually
  // ran. Older clients may upload before this endpoint completes; in that case
  // this update is simply a no-op and the historical artifact remains readable.
  if (motionSessionId) {
    await c.env.DB.prepare(
      'UPDATE motion_sessions SET verifier_release_id = ?, verifier_release_checksum = ?, ' +
      'engine_type = ?, spec_schema_version = ?, assignment_policy = ? WHERE session_id = ?',
    ).bind(
      session.release_id,
      session.release_checksum,
      session.engine_type,
      session.spec_schema_version,
      null,
      motionSessionId,
    ).run();

    const artifact = await c.env.DB.prepare(
      'SELECT activity_id, outcome, failed_rule_reason, detected_value, confidence ' +
      'FROM motion_sessions WHERE session_id = ? LIMIT 1',
    ).bind(motionSessionId).first<{
      activity_id: string;
      outcome: string;
      failed_rule_reason: string;
      detected_value: number;
      confidence: number;
    }>();
    if (artifact) {
      await recordReleaseMetric(c.env.DB, {
        releaseId: session.release_id,
        activityId: artifact.activity_id,
        outcome: artifact.outcome,
        failureReason: artifact.failed_rule_reason,
        detectedValue: artifact.detected_value,
        confidence: artifact.confidence,
      });
    }
  }
  const updated = await readSession(c.env.DB, sessionId, userId);
  return updated ? c.json({ ok: true, session: sessionView(updated) }) : c.json({ ok: false, error: 'Verification session could not be completed.' }, 500);
});
