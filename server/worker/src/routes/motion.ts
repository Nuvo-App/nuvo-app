import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import { analyzeMotion, motionAnalysisSchemaVersion, motionModelVersion, motionValidatorVersion, validateMotionRequest } from '../domain/motionAnalysis';
import { recordFeedback, recordReleaseMetric } from '../domain/motionTelemetry';
import {
  encryptMotionBytes,
  encryptMotionText,
  getOrCreateMotionDataKey,
  motionAccountRef,
} from '../lib/motion_privacy';

export const motionRouter = new Hono<AppEnv>();
motionRouter.use('*', requireAuth);

motionRouter.post('/analyze', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  try {
    const request = validateMotionRequest(body);
    const result = analyzeMotion(request);
    const id = generateId();
    await c.env.DB.prepare(
      `INSERT INTO motion_analysis_jobs (id, user_id, motion_id, status, request_schema_version, model_version, validator_version, result_json, frame_count, duration_ms, completed_at)
       VALUES (?, ?, ?, 'completed', ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
    ).bind(id, c.get('userId'), request.motionId, motionAnalysisSchemaVersion, motionModelVersion, motionValidatorVersion, JSON.stringify(result), result.framesAnalyzed, result.durationMs).run();
    return c.json({ ok: true, jobId: id, result });
  } catch (error) {
    return c.json({ ok: false, error: error instanceof Error ? error.message : 'Invalid motion request.' }, 400);
  }
});

motionRouter.get('/jobs/:id', async (c) => {
  const row = await c.env.DB.prepare(
    `SELECT id, motion_id, status, request_schema_version, model_version, validator_version,
            result_json, frame_count, duration_ms, created_at, completed_at
       FROM motion_analysis_jobs
      WHERE id = ? AND user_id = ? LIMIT 1`,
  ).bind(c.req.param('id'), c.get('userId')).first<Record<string, unknown>>();
  if (!row) return c.json({ ok: false, error: 'Analysis job not found.' }, 404);
  return c.json({
    ok: true,
    job: {
      ...row,
      result: typeof row.result_json === 'string' ? JSON.parse(row.result_json) : null,
    },
  });
});

motionRouter.get('/models/current', async (c) => {
  const model = await c.env.DB.prepare(
    `SELECT model_version, input_schema_version, artifact_key, artifact_sha256, supported_motion_ids_json
     FROM motion_model_releases WHERE status = 'production' ORDER BY promoted_at DESC LIMIT 1`,
  ).first();
  return c.json({ ok: true, model: model ?? { model_version: motionModelVersion, input_schema_version: motionAnalysisSchemaVersion, artifactKey: null, artifactSha256: null, supportedMotionIds: [] } });
});

// Model bytes are served only for an explicitly promoted release. The client
// still executes the model locally; this endpoint is a hash-addressed artifact
// transport, not a remote inference path or executable-code download.
motionRouter.get('/models/:modelVersion/artifact', async (c) => {
  const modelVersion = c.req.param('modelVersion').trim();
  if (!modelVersion || modelVersion === 'current') {
    return c.json({ ok: false, error: 'A concrete model version is required.' }, 400);
  }

  const model = await c.env.DB.prepare(
    `SELECT model_version, artifact_key, artifact_sha256
       FROM motion_model_releases
      WHERE model_version = ? AND status = 'production'
      LIMIT 1`,
  ).bind(modelVersion).first<{
    model_version: string;
    artifact_key: string | null;
    artifact_sha256: string | null;
  }>();
  if (!model || !model.artifact_key || !model.artifact_sha256) {
    return c.json({ ok: false, error: 'Production model artifact not found.' }, 404);
  }

  const object = await c.env.PROFILE_PHOTOS.get(model.artifact_key);
  if (!object) {
    return c.json({ ok: false, error: 'Production model artifact is unavailable.' }, 503);
  }

  const etag = `"${model.artifact_sha256}"`;
  c.header('ETag', etag);
  c.header('X-Model-Version', model.model_version);
  c.header('X-Model-SHA256', model.artifact_sha256);
  c.header('Cache-Control', 'private, max-age=300');
  if (c.req.header('If-None-Match') === etag) return c.body(null, 304);

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('ETag', etag);
  headers.set('X-Model-Version', model.model_version);
  headers.set('X-Model-SHA256', model.artifact_sha256);
  headers.set('Cache-Control', 'private, max-age=300');
  return new Response(object.body, { headers });
});

// ── Motion Session telemetry ingest ────────────────────────────────────────
//
// Mounted at `/motion-sessions` (see index.ts). The client sends the gzip
// artifact as the raw body and the searchable metadata as base64 JSON in the
// `X-Motion-Session` header, so the Worker indexes without unpacking the blob.
export const motionSessionsRouter = new Hono<AppEnv>();
motionSessionsRouter.use('*', requireAuth);

function num(v: unknown, fallback = 0): number {
  const n = typeof v === 'string' ? Number(v) : (v as number);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}
function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' && v.length > 0 ? v : fallback;
}

motionSessionsRouter.post('/', async (c) => {
  const userId = c.get('userId');
  const header = c.req.header('X-Motion-Session');
  if (!header) return c.json({ ok: false, error: 'Missing X-Motion-Session metadata header.' }, 400);

  let meta: Record<string, unknown>;
  try {
    meta = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(header), (ch) => ch.charCodeAt(0))));
  } catch {
    return c.json({ ok: false, error: 'X-Motion-Session header is not valid base64 JSON.' }, 400);
  }

  const sessionId = str(meta.sessionId);
  if (!sessionId || !/^ms_[A-Za-z0-9]+$/.test(sessionId)) {
    return c.json({ ok: false, error: 'metadata.sessionId is required.' }, 400);
  }

  const body = await c.req.arrayBuffer();
  if (body.byteLength === 0) return c.json({ ok: false, error: 'Empty artifact body.' }, 400);
  if (body.byteLength > 8 * 1024 * 1024) return c.json({ ok: false, error: 'Artifact too large.' }, 413);

  let accountKey: Uint8Array;
  let accountRef: string;
  try {
    accountKey = await getOrCreateMotionDataKey(c.env.DB, c.env.MOTION_DATA_MASTER_KEY, userId);
    accountRef = await motionAccountRef(c.env.MOTION_DATA_MASTER_KEY!, userId);
  } catch (error) {
    console.error('[motion-privacy] key unavailable:', error instanceof Error ? error.message : String(error));
    return c.json({ ok: false, error: 'Motion privacy storage is not configured.' }, 503);
  }

  const encryptedBody = await encryptMotionBytes(accountKey, new Uint8Array(body));
  const objectKey = `motion-sessions/${generateId()}.bin`;
  await c.env.PROFILE_PHOTOS.put(objectKey, encryptedBody, {
    httpMetadata: { contentType: 'application/octet-stream' },
  });
  const encryptedMetadata = await encryptMotionText(accountKey, JSON.stringify(meta));

  await c.env.DB.prepare(
    `INSERT INTO motion_sessions (
       id, session_id, user_id, race_id, activity_id, kind, outcome,
       detected_value, goal_value, confidence, failed_rule_reason,
       started_at, ended_at, duration_ms, frame_count, schema_version,
       app_version, git_commit, verifier_version, model_version,
       object_key, metadata_json
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(session_id) DO UPDATE SET
       outcome = excluded.outcome,
       detected_value = excluded.detected_value,
       confidence = excluded.confidence,
       failed_rule_reason = excluded.failed_rule_reason,
       ended_at = excluded.ended_at,
       duration_ms = excluded.duration_ms,
       frame_count = excluded.frame_count,
       object_key = excluded.object_key,
       metadata_json = excluded.metadata_json`,
  )
    .bind(
      generateId(),
      sessionId,
      accountRef,
      meta.raceId == null ? null : String(meta.raceId),
      str(meta.activityId, 'unknown'),
      str(meta.kind, 'preset'),
      str(meta.outcome, 'incomplete'),
      num(meta.detectedValue),
      meta.goalValue == null ? null : num(meta.goalValue),
      typeof meta.confidence === 'number' ? meta.confidence : 0,
      str(meta.failedRuleReason),
      meta.startedAt == null ? null : String(meta.startedAt),
      meta.endedAt == null ? null : String(meta.endedAt),
      num(meta.durationMs),
      num(meta.frameCount),
      num(meta.schemaVersion, 1),
      str(meta.appVersion, 'unknown'),
      str(meta.gitCommit, 'unknown'),
      str(meta.verifierVersion, 'unknown'),
      str(meta.modelVersion, 'unknown'),
      objectKey,
      encryptedMetadata,
    )
    .run();

  // Index release-linked health asynchronously in the request lifecycle. The
  // raw artifact remains encrypted in R2 for replay.
  // Missing release metadata is allowed for older clients and is backfilled
  // when a linked verification session completes.
  await recordReleaseMetric(c.env.DB, {
    releaseId: typeof meta.verifierReleaseId === 'string' ? meta.verifierReleaseId : null,
    activityId: str(meta.activityId, 'unknown'),
    outcome: str(meta.outcome, 'incomplete'),
    failureReason: str(meta.failedRuleReason),
    detectedValue: num(meta.detectedValue),
    confidence: typeof meta.confidence === 'number' ? meta.confidence : 0,
  });

  return c.json({ ok: true, sessionId, stored: true });
});

motionSessionsRouter.post('/:sessionId/feedback', async (c) => {
  const sessionId = c.req.param('sessionId');
  const userId = c.get('userId');
  let accountRef: string;
  try {
    accountRef = await motionAccountRef(c.env.MOTION_DATA_MASTER_KEY!, userId);
  } catch {
    return c.json({ ok: false, error: 'Motion privacy storage is not configured.' }, 503);
  }
  const session = await c.env.DB.prepare(
    'SELECT session_id FROM motion_sessions WHERE session_id = ? AND user_id IN (?, ?) LIMIT 1',
  ).bind(sessionId, userId, accountRef).first<{ session_id: string }>();
  if (!session) return c.json({ ok: false, error: 'Motion session not found.' }, 404);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body as Record<string, unknown>;
  const label = typeof value.label === 'string' ? value.label.trim() : '';
  if (!['missed_count', 'false_count', 'camera_issue', 'worked'].includes(label)) {
    return c.json({ ok: false, error: 'Unsupported motion feedback label.' }, 400);
  }
  await recordFeedback(c.env.DB, {
    motionSessionId: sessionId,
    userId: accountRef,
    label,
    note: typeof value.note === 'string' ? value.note : null,
  });
  return c.json({ ok: true, stored: true });
});

motionRouter.post('/training/examples', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body as Record<string, unknown>;
  if (value.consentVersion !== 'motion-training-v1') return c.json({ ok: false, error: 'Training consent is required.' }, 403);
  if (typeof value.motionId !== 'string' || !Array.isArray(value.frames)) return c.json({ ok: false, error: 'motionId and frames are required.' }, 400);
  const request = validateMotionRequest({ schemaVersion: motionAnalysisSchemaVersion, motionId: value.motionId, frames: value.frames, durationMs: value.durationMs });
  const id = generateId();
  const userId = c.get('userId');
  let accountKey: Uint8Array;
  let accountRef: string;
  try {
    accountKey = await getOrCreateMotionDataKey(c.env.DB, c.env.MOTION_DATA_MASTER_KEY, userId);
    accountRef = await motionAccountRef(c.env.MOTION_DATA_MASTER_KEY!, userId);
  } catch (error) {
    console.error('[motion-privacy] training key unavailable:', error instanceof Error ? error.message : String(error));
    return c.json({ ok: false, error: 'Motion privacy storage is not configured.' }, 503);
  }
  const trainingPayload = JSON.stringify({
    schemaVersion: motionAnalysisSchemaVersion,
    motionId: request.motionId,
    frames: request.frames,
    durationMs: request.durationMs ?? null,
    label: typeof value.label === 'string' ? value.label : null,
  });
  const objectKey = `motion-training/${generateId()}.bin`;
  await c.env.PROFILE_PHOTOS.put(
    objectKey,
    await encryptMotionBytes(accountKey, new TextEncoder().encode(trainingPayload)),
    { httpMetadata: { contentType: 'application/octet-stream' } },
  );
  await c.env.DB.prepare(
    `INSERT INTO motion_training_examples (id, user_id, motion_id, object_key, label, review_status, consent_version, schema_version, metadata_json)
     VALUES (?, ?, ?, ?, ?, 'unreviewed', ?, ?, ?)`,
  ).bind(id, accountRef, request.motionId, objectKey, typeof value.label === 'string' ? value.label : null, 'motion-training-v1', motionAnalysisSchemaVersion, JSON.stringify({ frameCount: request.frames.length })).run();
  return c.json({ ok: true, exampleId: id, stored: true });
});
