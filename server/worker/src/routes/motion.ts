import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import { analyzeMotion, motionAnalysisSchemaVersion, motionModelVersion, motionValidatorVersion, validateMotionRequest } from '../domain/motionAnalysis';

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

  const objectKey = `motion-sessions/${userId}/${sessionId}.json.gz`;
  await c.env.PROFILE_PHOTOS.put(objectKey, body, {
    httpMetadata: { contentType: 'application/gzip' },
  });

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
      userId,
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
      JSON.stringify(meta),
    )
    .run();

  return c.json({ ok: true, sessionId, stored: true });
});

motionRouter.post('/training/examples', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body as Record<string, unknown>;
  if (value.consentVersion !== 'motion-training-v1') return c.json({ ok: false, error: 'Training consent is required.' }, 403);
  if (typeof value.motionId !== 'string' || !Array.isArray(value.frames)) return c.json({ ok: false, error: 'motionId and frames are required.' }, 400);
  const request = validateMotionRequest({ schemaVersion: motionAnalysisSchemaVersion, motionId: value.motionId, frames: value.frames, durationMs: value.durationMs });
  const id = generateId();
  const objectKey = `motion-training/${c.get('userId')}/${id}.json`;
  await c.env.PROFILE_PHOTOS.put(objectKey, JSON.stringify({
    schemaVersion: motionAnalysisSchemaVersion,
    motionId: request.motionId,
    frames: request.frames,
    durationMs: request.durationMs ?? null,
    label: typeof value.label === 'string' ? value.label : null,
  }), { httpMetadata: { contentType: 'application/json' } });
  await c.env.DB.prepare(
    `INSERT INTO motion_training_examples (id, user_id, motion_id, object_key, label, review_status, consent_version, schema_version, metadata_json)
     VALUES (?, ?, ?, ?, ?, 'unreviewed', ?, ?, ?)`,
  ).bind(id, c.get('userId'), request.motionId, objectKey, typeof value.label === 'string' ? value.label : null, 'motion-training-v1', motionAnalysisSchemaVersion, JSON.stringify({ frameCount: request.frames.length })).run();
  return c.json({ ok: true, exampleId: id, stored: true });
});
