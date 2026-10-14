import { Hono } from 'hono';
import type { AppEnv } from '../types';
import { requireAuth } from '../lib/jwt';
import { generateId } from '../lib/crypto';
import {
  encryptMotionBytes,
  encryptMotionText,
  getOrCreateMotionDataKey,
  motionAccountRef,
} from '../lib/motion_privacy';
import { hasMotionConsent } from './motion';

// ── Teach Nuvo session telemetry ingest ─────────────────────────────────────
//
// Mounted at `/teach-sessions` (see index.ts). Same transport contract as the
// motion-session ingest: the gzip'd diagnostic artifact is the raw body and
// the searchable metadata travels as base64 JSON in the `X-Teach-Session`
// header, so the Worker can index a session without unpacking the blob.
//
// The artifact is the full NuvoMotionDiagnosticSession (schema 2): the three
// teaching demos, the V1 spec that race verification will actually use, the
// V2 learned spec + self-validation, the live-test match trace, and where the
// flow ended (used / learned / failed / abandoned + failure stage). This is
// the data the offline evaluator replays to compare matchers and model
// releases — it only exists when the user opted in to motion contribution.

export const teachSessionsRouter = new Hono<AppEnv>();
teachSessionsRouter.use('*', requireAuth);

const TEACH_OUTCOMES = new Set(['used', 'learned', 'failed', 'abandoned']);
const TEACH_ENGINES = new Set(['v2', 'v1', 'v1_fallback']);
const TEACH_FAILURE_STAGES = new Set([
  'recording',
  'v1_build',
  'v2_learn',
  'live_test',
  'use',
]);

function num(v: unknown, fallback = 0): number {
  const n = typeof v === 'string' ? Number(v) : (v as number);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}
function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' && v.length > 0 ? v : fallback;
}
function flag(v: unknown): number | null {
  if (v === true || v === 1) return 1;
  if (v === false || v === 0) return 0;
  return null;
}
function capped(v: unknown, allowed: Set<string>, fallback: string): string {
  const s = str(v);
  return allowed.has(s) ? s : fallback;
}

teachSessionsRouter.post('/', async (c) => {
  const userId = c.get('userId');
  // Consent gate — no landmark artifact is retained for a non-consenting
  // account. Return a stored:false success (not an error) so the client's
  // upload queue drains instead of retrying forever.
  if (!(await hasMotionConsent(c.env.DB, userId))) {
    return c.json({ ok: true, stored: false, reason: 'motion_consent_off' });
  }
  const header = c.req.header('X-Teach-Session');
  if (!header) return c.json({ ok: false, error: 'Missing X-Teach-Session metadata header.' }, 400);

  let meta: Record<string, unknown>;
  try {
    meta = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(header), (ch) => ch.charCodeAt(0))));
  } catch {
    return c.json({ ok: false, error: 'X-Teach-Session header is not valid base64 JSON.' }, 400);
  }

  const sessionId = str(meta.sessionId);
  if (!sessionId || !/^[A-Za-z0-9][A-Za-z0-9_-]{5,63}$/.test(sessionId)) {
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
    console.error('[motion-privacy] teach key unavailable:', error instanceof Error ? error.message : String(error));
    return c.json({ ok: false, error: 'Motion privacy storage is not configured.' }, 503);
  }

  const encryptedBody = await encryptMotionBytes(accountKey, new Uint8Array(body));
  const objectKey = `teach-sessions/${generateId()}.bin`;
  await c.env.PROFILE_PHOTOS.put(objectKey, encryptedBody, {
    httpMetadata: { contentType: 'application/octet-stream' },
  });
  const encryptedMetadata = await encryptMotionText(accountKey, JSON.stringify(meta));

  const outcome = capped(meta.outcome, TEACH_OUTCOMES, 'abandoned');
  const engine = capped(meta.engine, TEACH_ENGINES, 'v2');
  const failureStage = meta.failureStage == null
    ? null
    : capped(meta.failureStage, TEACH_FAILURE_STAGES, '');

  await c.env.DB.prepare(
    `INSERT INTO motion_teach_sessions (
       id, session_id, user_id, movement_name, outcome, engine,
       failure_stage, failure_reason, demo_count, frame_count, duration_ms,
       learned, v2_available, v2_learned, self_validation_passed,
       live_test_matched, used_for_race, schema_version,
       app_version, git_commit, model_version, matcher_version,
       object_key, metadata_json
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(session_id) DO UPDATE SET
       outcome = excluded.outcome,
       engine = excluded.engine,
       failure_stage = excluded.failure_stage,
       failure_reason = excluded.failure_reason,
       demo_count = excluded.demo_count,
       frame_count = excluded.frame_count,
       duration_ms = excluded.duration_ms,
       learned = excluded.learned,
       v2_available = excluded.v2_available,
       v2_learned = excluded.v2_learned,
       self_validation_passed = excluded.self_validation_passed,
       live_test_matched = excluded.live_test_matched,
       used_for_race = excluded.used_for_race,
       object_key = excluded.object_key,
       metadata_json = excluded.metadata_json`,
  )
    .bind(
      generateId(),
      sessionId,
      accountRef,
      str(meta.movementName, 'unknown').slice(0, 120),
      outcome,
      engine,
      failureStage,
      str(meta.failureReason).slice(0, 500),
      num(meta.demoCount),
      num(meta.frameCount),
      num(meta.durationMs),
      flag(meta.learned) ?? 0,
      flag(meta.v2Available) ?? 1,
      flag(meta.v2Learned) ?? 0,
      flag(meta.selfValidationPassed),
      flag(meta.liveTestMatched),
      flag(meta.usedForRace) ?? 0,
      num(meta.schemaVersion, 1),
      str(meta.appVersion, 'unknown'),
      str(meta.gitCommit, 'unknown'),
      str(meta.modelVersion, 'unknown'),
      str(meta.matcherVersion, 'unknown'),
      objectKey,
      encryptedMetadata,
    )
    .run();

  return c.json({ ok: true, sessionId, stored: true });
});
