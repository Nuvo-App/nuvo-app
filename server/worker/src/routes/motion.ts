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
