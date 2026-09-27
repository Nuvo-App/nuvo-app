import { Hono, type Context } from 'hono';
import type { AppEnv } from '../types';
import { readMotionCatalog, readMotionRelease } from '../domain/motionRegistry';
import { validateMotionVerifierSpec } from '../domain/motionSpec';
import { declaredPackageAssets, packageAssetKey } from '../domain/motionAssets';
import { adaptationRecommendation, decideEvaluation, parseEvaluationReport } from '../domain/motionEvaluation';
import { generateId, hashBytes, hashValue } from '../lib/crypto';
import {
  MODEL_CHANNELS,
  disableModelRelease,
  insertModelRelease,
  parseModelEvaluationReport,
  parseModelReleaseDraft,
  promoteModelRelease,
  publicModelRelease,
  recordModelEvaluation,
  rollbackModelChannel,
  type ModelChannel,
  type ModelReleaseRow,
} from '../domain/motionModels';
import {
  decryptMotionBytes,
  decryptMotionText,
  getMotionDataKeyByRef,
  isMotionEncryptionEnvelope,
  motionAccountRef,
} from '../lib/motion_privacy';

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

internalRouter.get('/motion/catalog', async (c) => {
  const channel = c.req.query('channel') ?? 'stable';
  if (!['internal', 'beta', 'stable'].includes(channel)) {
    return c.json({ ok: false, error: 'Unsupported motion channel.' }, 400);
  }
  return c.json({ ok: true, channel, ...(await readMotionCatalog(c.env.DB, channel)) });
});

internalRouter.get('/motion/releases/:releaseId', async (c) => {
  const release = await readMotionRelease(c.env.DB, c.req.param('releaseId'));
  if (!release) return c.json({ ok: false, error: 'Release not found.' }, 404);
  return c.json({ ok: true, release });
});

// ── Moderation review ────────────────────────────────────────────────────────
// Report triage lives ONLY on the internal surface — an ordinary user JWT must
// never read the global report queue or change moderation state.

internalRouter.get('/reports', async (c) => {
  const rows = await c.env.DB.prepare(
    `SELECT r.*, reporter.full_name as reporter_name, reporter.username as reporter_username
     FROM reports r
     LEFT JOIN profiles reporter ON reporter.user_id = r.reporter_user_id
     ORDER BY
       CASE r.status WHEN 'pending' THEN 0 ELSE 1 END,
       r.created_at DESC
     LIMIT 100`,
  ).all<import('../types').ReportRow & { reporter_name: string | null; reporter_username: string | null }>();

  return c.json({
    ok: true,
    reports: rows.results.map((row) => ({
      id: row.id,
      reporterUserId: row.reporter_user_id,
      reporterDisplayName: row.reporter_name ?? row.reporter_username ?? 'Nuvo member',
      targetType: row.target_type,
      targetId: row.target_id,
      reason: row.reason,
      status: row.status,
      reviewedBy: row.reviewed_by,
      notes: row.notes,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })),
  });
});

internalRouter.post('/reports/:id', async (c) => {
  const reportId = c.req.param('id');
  let body: Record<string, unknown>;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body' }, 400); }

  const status = typeof body.status === 'string' ? (body.status as string).trim() : '';
  const notes = typeof body.notes === 'string' ? (body.notes as string).trim() : null;
  if (!['pending', 'reviewed', 'resolved', 'dismissed'].includes(status)) {
    return c.json({ ok: false, error: 'status must be pending | reviewed | resolved | dismissed' }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE reports SET status = ?, notes = ?, reviewed_by = 'internal-operator', updated_at = CURRENT_TIMESTAMP WHERE id = ?`,
  ).bind(status, notes, reportId).run();

  return c.json({ ok: true });
});

function bodyString(body: Record<string, unknown>, key: string, fallback = ''): string {
  return typeof body[key] === 'string' ? String(body[key]).trim() : fallback;
}

function bodyInt(body: Record<string, unknown>, key: string, fallback: number): number {
  const value = body[key];
  return typeof value === 'number' && Number.isInteger(value) ? value : fallback;
}

function bodyActor(body: Record<string, unknown>): string {
  return bodyString(body, 'actorId', 'internal-operator').slice(0, 160);
}

async function audit(
  db: D1Database,
  input: { actorId: string; action: string; activityId?: string | null; releaseId?: string | null; previousReleaseId?: string | null; details?: Record<string, unknown> },
) {
  await db.prepare(
    `INSERT INTO verifier_audit_log
       (id, actor_id, action, activity_id, release_id, previous_release_id, details_json)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    generateId(), input.actorId, input.action, input.activityId ?? null,
    input.releaseId ?? null, input.previousReleaseId ?? null,
    JSON.stringify(input.details ?? {}),
  ).run();
}

// Aggregates are intentionally small and release-scoped. They identify a
// cluster worth replaying; they do not mutate a verifier or publish a fix.
internalRouter.get('/motion/adaptation/signals', async (c) => {
  const activityId = c.req.query('activityId');
  const releaseId = c.req.query('releaseId');
  const clauses = ['1 = 1'];
  const binds: string[] = [];
  if (activityId) { clauses.push('activity_id = ?'); binds.push(activityId); }
  if (releaseId) { clauses.push('release_id = ?'); binds.push(releaseId); }
  const rows = await c.env.DB.prepare(
    `SELECT release_id, activity_id, outcome, failure_reason, sample_count,
            total_detected, total_confidence, last_seen_at
       FROM motion_release_metrics WHERE ${clauses.join(' AND ')}
      ORDER BY sample_count DESC, last_seen_at DESC LIMIT 200`,
  ).bind(...binds).all<Record<string, unknown>>();
  return c.json({
    ok: true,
    signals: rows.results.map((row) => ({
      releaseId: row.release_id,
      activityId: row.activity_id,
      outcome: row.outcome,
      failureReason: row.failure_reason,
      sampleCount: row.sample_count,
      averageDetected: Number(row.sample_count) > 0 ? Number(row.total_detected) / Number(row.sample_count) : 0,
      averageConfidence: Number(row.sample_count) > 0 ? Number(row.total_confidence) / Number(row.sample_count) : 0,
      recommendation: adaptationRecommendation(String(row.failure_reason ?? ''), Number(row.sample_count ?? 0)),
      lastSeenAt: row.last_seen_at,
    })),
  });
});

// Draft creation is the handoff from telemetry analysis to release tooling.
// The caller supplies the proposed declarative spec; the Worker validates it,
// assigns a checksum, and keeps it unavailable to clients as `draft`.
internalRouter.post('/motion/releases/drafts', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return c.json({ ok: false, error: 'Invalid draft body.' }, 400);
  const value = body as Record<string, unknown>;
  const activityId = bodyString(value, 'activityId');
  const releaseId = bodyString(value, 'releaseId');
  const parentReleaseId = bodyString(value, 'parentReleaseId');
  const semver = bodyString(value, 'semver');
  const changeClass = bodyString(value, 'changeClass', 'patch');
  const spec = value.spec;
  if (!activityId || !releaseId || !parentReleaseId || !semver || !spec || typeof spec !== 'object' || Array.isArray(spec)) {
    return c.json({ ok: false, error: 'activityId, releaseId, parentReleaseId, semver, and spec are required.' }, 400);
  }
  if (!/^[a-z0-9][a-z0-9._-]{2,119}$/.test(releaseId)) return c.json({ ok: false, error: 'Invalid release ID.' }, 400);
  if (!['patch', 'minor', 'major'].includes(changeClass)) return c.json({ ok: false, error: 'Invalid change class.' }, 400);
  try { validateMotionVerifierSpec(spec, { releaseId, activityId }); }
  catch (error) { return c.json({ ok: false, code: 'invalid_spec', error: error instanceof Error ? error.message : 'Invalid verifier spec.' }, 400); }
  const parent = await c.env.DB.prepare(
    'SELECT id, activity_id, compatibility_group, minimum_app_build FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(parentReleaseId).first<{ id: string; activity_id: string; compatibility_group: string; minimum_app_build: string }>();
  if (!parent || parent.activity_id !== activityId) return c.json({ ok: false, error: 'Parent release does not match the activity.' }, 400);
  const checksum = `sha256:${await hashValue(JSON.stringify(spec))}`;
  const requiredCapabilities = Array.isArray((spec as Record<string, unknown>).requiredCapabilities)
    ? (spec as Record<string, unknown>).requiredCapabilities
    : [];
  const compatibilityGroup = bodyString(value, 'compatibilityGroup', parent.compatibility_group);
  const minimumAppBuild = bodyString(value, 'minimumAppBuild', parent.minimum_app_build);
  try {
    await c.env.DB.prepare(
      `INSERT INTO verifier_releases
         (id, activity_id, semver, change_class, engine_type, spec_schema_version,
          spec_json, checksum, required_capabilities_json, minimum_app_build,
          compatibility_group, status, release_notes, parent_release_id, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?, CURRENT_TIMESTAMP)`,
    ).bind(
      releaseId, activityId, semver, changeClass,
      String((spec as Record<string, unknown>).engineType),
      Number((spec as Record<string, unknown>).specSchemaVersion),
      JSON.stringify(spec), checksum, JSON.stringify(requiredCapabilities),
      minimumAppBuild, compatibilityGroup, bodyString(value, 'releaseNotes'), parentReleaseId,
    ).run();
  } catch {
    return c.json({ ok: false, error: 'Release ID or checksum already exists.' }, 409);
  }
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'release_drafted', activityId, releaseId,
    details: { parentReleaseId, changeClass, checksum },
  });
  return c.json({ ok: true, release: { id: releaseId, activityId, checksum, status: 'draft' } }, 201);
});

// Package asset upload — raw bytes in the request body. The bytes are hashed
// and byte-counted against the asset the release manifest declares before
// anything lands in R2: a release can never carry an asset whose content
// differs from its immutable spec. Stored under the content-bound key with
// the declared checksum as custom metadata so the public GET can refuse
// drifted objects.
internalRouter.post('/motion/releases/:releaseId/assets/:assetId', async (c) => {
  const releaseId = c.req.param('releaseId');
  const assetId = c.req.param('assetId');
  const release = await readMotionRelease(c.env.DB, releaseId);
  if (!release) return c.json({ ok: false, error: 'Verifier release not found.' }, 404);
  if (release.status === 'stable' || release.status === 'disabled') {
    return c.json({ ok: false, error: 'Assets are immutable once a release is stable.' }, 409);
  }
  const declared = declaredPackageAssets(release).find((a) => a.id === assetId);
  if (!declared) {
    return c.json({ ok: false, error: 'Asset is not declared by this release manifest.' }, 400);
  }
  const body = await c.req.arrayBuffer();
  if (body.byteLength !== declared.bytes) {
    return c.json({ ok: false, error: `Asset byte length ${body.byteLength} does not match declared ${declared.bytes}.` }, 400);
  }
  const sha = await hashBytes(body);
  if (sha !== declared.sha256) {
    return c.json({ ok: false, error: 'Asset checksum does not match the release manifest.' }, 400);
  }
  await c.env.PROFILE_PHOTOS.put(packageAssetKey(releaseId, assetId), body, {
    customMetadata: { sha256: declared.sha256, type: declared.type },
  });
  await audit(c.env.DB, {
    actorId: 'internal', action: 'package_asset_uploaded', activityId: release.activityId,
    releaseId, details: { assetId, type: declared.type, bytes: declared.bytes },
  });
  return c.json({ ok: true, releaseId, assetId, sha256: sha }, 201);
});

// Evaluation reports come from the deterministic replay runner. A report that
// fails a guardrail is retained as evidence but cannot validate a release.
internalRouter.post('/motion/evaluations', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) return c.json({ ok: false, error: 'Invalid evaluation body.' }, 400);
  const value = body as Record<string, unknown>;
  const releaseId = bodyString(value, 'releaseId');
  const release = await c.env.DB.prepare(
    'SELECT id, activity_id, status FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(releaseId).first<{ id: string; activity_id: string; status: string }>();
  if (!release) return c.json({ ok: false, error: 'Release not found.' }, 404);
  let report;
  try { report = parseEvaluationReport(value.report); }
  catch (error) { return c.json({ ok: false, code: 'invalid_evaluation', error: error instanceof Error ? error.message : 'Invalid evaluation.' }, 400); }
  const decision = decideEvaluation(report);
  const runId = generateId();
  await c.env.DB.prepare(
    `INSERT INTO verifier_evaluation_runs
       (id, release_id, dataset_snapshot_id, status, report_json, completed_at)
     VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
  ).bind(runId, releaseId, report.datasetSnapshotId, decision.status, JSON.stringify({ ...report, decision })).run();
  if (decision.status === 'passed') {
    await c.env.DB.prepare("UPDATE verifier_releases SET status = 'validated' WHERE id = ? AND status = 'draft'").bind(releaseId).run();
  }
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: `evaluation_${decision.status}`,
    activityId: release.activity_id, releaseId,
    details: { runId, datasetSnapshotId: report.datasetSnapshotId, blockers: decision.blockers },
  });
  return c.json({ ok: true, runId, decision });
});

internalRouter.post('/motion/releases/:releaseId/promote', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const releaseId = c.req.param('releaseId');
  const channel = bodyString(value, 'channel');
  const rolloutPercent = bodyInt(value, 'rolloutPercent', channel === 'stable' ? 100 : 0);
  if (!['internal', 'beta', 'stable'].includes(channel) || rolloutPercent < 0 || rolloutPercent > 100) {
    return c.json({ ok: false, error: 'Valid channel and rolloutPercent are required.' }, 400);
  }
  const release = await c.env.DB.prepare(
    'SELECT id, activity_id, status FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(releaseId).first<{ id: string; activity_id: string; status: string }>();
  if (!release) return c.json({ ok: false, error: 'Release not found.' }, 404);
  if (!['validated', 'internal', 'beta', 'stable'].includes(release.status)) return c.json({ ok: false, error: 'Release must pass evaluation before promotion.' }, 409);
  // A release already serving stable must not be demoted by a promotion
  // call — status drives resolution, so flipping stable→internal would kill
  // the activity until rollback. Pointer moves go through rollback/disable.
  if (release.status === 'stable' && channel !== 'stable') {
    return c.json({ ok: false, error: 'Cannot demote a stable release; use channel rollback or disable.' }, 409);
  }
  if (channel === 'stable') {
    const evaluation = await c.env.DB.prepare(
      "SELECT id FROM verifier_evaluation_runs WHERE release_id = ? AND status = 'passed' ORDER BY completed_at DESC LIMIT 1",
    ).bind(releaseId).first<{ id: string }>();
    if (!evaluation) return c.json({ ok: false, error: 'A passing evaluation is required for stable promotion.' }, 409);
  }
  const previous = await c.env.DB.prepare(
    'SELECT release_id FROM activity_channel_releases WHERE activity_id = ? AND channel = ? LIMIT 1',
  ).bind(release.activity_id, channel).first<{ release_id: string }>();
  await c.env.DB.prepare("UPDATE verifier_releases SET status = ?, published_at = COALESCE(published_at, CURRENT_TIMESTAMP), updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(channel, releaseId).run();
  await c.env.DB.prepare(
    `INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(activity_id, channel) DO UPDATE SET release_id = excluded.release_id,
       rollout_percent = excluded.rollout_percent, updated_at = CURRENT_TIMESTAMP`,
  ).bind(release.activity_id, channel, releaseId, rolloutPercent).run();
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'release_promoted', activityId: release.activity_id,
    releaseId, previousReleaseId: previous?.release_id ?? null,
    details: { channel, rolloutPercent },
  });
  return c.json({ ok: true, channel, releaseId, previousReleaseId: previous?.release_id ?? null });
});

internalRouter.post('/motion/channels/:activityId/:channel/rollback', async (c) => {
  const activityId = c.req.param('activityId');
  const channel = c.req.param('channel');
  if (!['internal', 'beta', 'stable'].includes(channel)) return c.json({ ok: false, error: 'Unsupported channel.' }, 400);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const releaseId = bodyString(value, 'releaseId');
  const target = await c.env.DB.prepare(
    'SELECT id, activity_id, status FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(releaseId).first<{ id: string; activity_id: string; status: string }>();
  if (!target || target.activity_id !== activityId || target.status === 'disabled') return c.json({ ok: false, error: 'Rollback release is unavailable for this activity.' }, 409);
  const previous = await c.env.DB.prepare(
    'SELECT release_id FROM activity_channel_releases WHERE activity_id = ? AND channel = ? LIMIT 1',
  ).bind(activityId, channel).first<{ release_id: string }>();
  await c.env.DB.prepare(
    `INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent)
     VALUES (?, ?, ?, 100)
     ON CONFLICT(activity_id, channel) DO UPDATE SET release_id = excluded.release_id,
       rollout_percent = 100, updated_at = CURRENT_TIMESTAMP`,
  ).bind(activityId, channel, releaseId).run();
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'channel_rollback', activityId,
    releaseId, previousReleaseId: previous?.release_id ?? null,
    details: { channel },
  });
  return c.json({ ok: true, channel, releaseId, previousReleaseId: previous?.release_id ?? null });
});

// Every release + channel pointer for one activity — the ops "what exists"
// view that precedes promote/rollback decisions.
internalRouter.get('/motion/activities/:activityId/releases', async (c) => {
  const activityId = c.req.param('activityId');
  const activity = await c.env.DB.prepare(
    'SELECT id, display_name, availability FROM motion_activities WHERE id = ? LIMIT 1',
  ).bind(activityId).first<{ id: string; display_name: string; availability: string }>();
  if (!activity) return c.json({ ok: false, error: 'Activity not found.' }, 404);
  const releases = await c.env.DB.prepare(
    `SELECT id, semver, change_class, engine_type, checksum, status,
            minimum_app_build, compatibility_group, parent_release_id,
            published_at, created_at, updated_at
       FROM verifier_releases WHERE activity_id = ?
       ORDER BY created_at DESC`,
  ).bind(activityId).all<Record<string, unknown>>();
  const channels = await c.env.DB.prepare(
    `SELECT channel, release_id, rollout_percent, updated_at
       FROM activity_channel_releases WHERE activity_id = ? ORDER BY channel`,
  ).bind(activityId).all<Record<string, unknown>>();
  return c.json({
    ok: true,
    activity: {
      id: activity.id,
      displayName: activity.display_name,
      availability: activity.availability,
    },
    releases: releases.results,
    channels: channels.results,
  });
});

// Kill switch. `status = 'disabled'` fails closed everywhere a release is
// resolved: stableReleaseForActivity requires 'stable', and session creation
// re-checks the assigned release's status, so a disabled release cannot start
// a new race or a new session. Existing sessions keep their pin — completion
// still validates against it, so a kill never bricks in-flight proofs.
// Channel pointers are left in place so rollback stays a pointer move.
internalRouter.post('/motion/releases/:releaseId/disable', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { body = {}; }
  const value = body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const releaseId = c.req.param('releaseId');
  const release = await c.env.DB.prepare(
    'SELECT id, activity_id, status FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(releaseId).first<{ id: string; activity_id: string; status: string }>();
  if (!release) return c.json({ ok: false, error: 'Release not found.' }, 404);
  if (release.status === 'disabled') {
    return c.json({ ok: true, releaseId, status: 'disabled', alreadyDisabled: true });
  }
  await c.env.DB.prepare(
    "UPDATE verifier_releases SET status = 'disabled', updated_at = CURRENT_TIMESTAMP WHERE id = ?",
  ).bind(releaseId).run();
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'release_disabled', activityId: release.activity_id,
    releaseId, details: { previousStatus: release.status },
  });
  return c.json({ ok: true, releaseId, status: 'disabled' });
});

// Catalog membership. The public catalog only serves rows with
// availability = 'supported'; flipping it removes/restores the motion for
// every installed app on its next catalog fetch. Existing races referencing a
// hidden activity keep their pinned release — hiding stops NEW adoption.
internalRouter.put('/motion/activities/:activityId/availability', async (c) => {
  const activityId = c.req.param('activityId');
  const activity = await c.env.DB.prepare(
    'SELECT id, availability FROM motion_activities WHERE id = ? LIMIT 1',
  ).bind(activityId).first<{ id: string; availability: string }>();
  if (!activity) return c.json({ ok: false, error: 'Activity not found.' }, 404);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body && typeof body === 'object' ? body as Record<string, unknown> : {};
  const availability = value.availability;
  if (!['supported', 'hidden'].includes(availability as string)) {
    return c.json({ ok: false, error: 'availability must be "supported" or "hidden".' }, 400);
  }
  await c.env.DB.prepare(
    'UPDATE motion_activities SET availability = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
  ).bind(availability, activityId).run();
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'activity_availability', activityId,
    details: { from: activity.availability, to: availability },
  });
  return c.json({ ok: true, activityId, availability });
});

// Inline preview update. previewSequence lives on the activity (metadata_json)
// and is read by the public catalog, so writing it ships a new decorative
// animation to every installed app on its next catalog fetch. It is
// activity-level data, not part of the immutable release spec — verification
// never reads it, and the client parser falls back to the bundled animation
// on any malformed shape. Validated here to that parser's contract anyway so
// the control plane only ever stores previews that will render.
internalRouter.put('/motion/activities/:activityId/preview', async (c) => {
  const activityId = c.req.param('activityId');
  const activity = await c.env.DB.prepare(
    'SELECT id, metadata_json FROM motion_activities WHERE id = ? LIMIT 1',
  ).bind(activityId).first<{ id: string; metadata_json: string | null }>();
  if (!activity) return c.json({ ok: false, error: 'Activity not found.' }, 404);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const value = body && typeof body === 'object' && !Array.isArray(body) ? body as Record<string, unknown> : {};
  const preview = value.preview;
  // `preview: null` clears the remote override (client falls back to bundled).
  if (preview !== null) {
    if (!preview || typeof preview !== 'object' || Array.isArray(preview)) {
      return c.json({ ok: false, error: 'preview object or null is required.' }, 400);
    }
    const p = preview as Record<string, unknown>;
    const rig = p.rig;
    const durationMs = p.durationMs;
    const keyframes = p.keyframes;
    if (rig !== 'front' && rig !== 'side') {
      return c.json({ ok: false, error: 'preview.rig must be "front" or "side".' }, 400);
    }
    if (typeof durationMs !== 'number' || !Number.isInteger(durationMs) || durationMs <= 0 || durationMs > 60000) {
      return c.json({ ok: false, error: 'preview.durationMs must be an integer between 1 and 60000.' }, 400);
    }
    if (!Array.isArray(keyframes) || keyframes.length < 2 || keyframes.length > 64
        || keyframes.some((k) => !k || typeof k !== 'object' || Array.isArray(k))) {
      return c.json({ ok: false, error: 'preview.keyframes must be 2-64 objects.' }, 400);
    }
  }
  let metadata: Record<string, unknown> = {};
  try { metadata = activity.metadata_json ? JSON.parse(activity.metadata_json) : {}; } catch { metadata = {}; }
  if (preview === null) delete metadata.previewSequence;
  else metadata.previewSequence = preview;
  await c.env.DB.prepare(
    'UPDATE motion_activities SET metadata_json = ? WHERE id = ?',
  ).bind(JSON.stringify(metadata), activityId).run();
  await audit(c.env.DB, {
    actorId: bodyActor(value), action: 'activity_preview_updated', activityId,
    details: { cleared: preview === null },
  });
  return c.json({ ok: true, activityId, previewCleared: preview === null });
});

// ── System B: model releases ───────────────────────────────────────────────
// The general motion-intelligence model is managed independently of verifier
// releases: immutable artifact + declared runtime contract → evaluation →
// channel pointer (internal/beta/stable, optional rollout %) → rollback or
// kill switch. Artifact bytes are verified against the registered checksum
// before a release can be promoted; the client verifies again after download.

function modelChannel(value: string | undefined): ModelChannel | null {
  return MODEL_CHANNELS.includes(value as ModelChannel) ? (value as ModelChannel) : null;
}

internalRouter.get('/motion/models', async (c) => {
  const family = c.req.query('family');
  const releases = await c.env.DB.prepare(
    `SELECT * FROM motion_model_releases
     ${family ? 'WHERE model_family = ?' : ''} ORDER BY created_at DESC`,
  ).bind(...(family ? [family] : [])).all<ModelReleaseRow>();
  const channels = await c.env.DB.prepare(
    `SELECT model_family, channel, release_id, previous_release_id, rollout_percent, updated_at
     FROM motion_model_channels ORDER BY model_family, channel`,
  ).all<Record<string, unknown>>();
  return c.json({
    ok: true,
    releases: releases.results.map((r) => ({ ...publicModelRelease(r), disabledAt: r.disabled_at })),
    channels: channels.results.map((p) => ({
      modelFamily: p.model_family, channel: p.channel, releaseId: p.release_id,
      previousReleaseId: p.previous_release_id, rolloutPercent: p.rollout_percent, updatedAt: p.updated_at,
    })),
  });
});

// Register an immutable draft release. The artifact is uploaded separately;
// registration is rejected if the model version already exists.
internalRouter.post('/motion/models', async (c) => {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  try {
    const draft = parseModelReleaseDraft(body);
    const existing = await c.env.DB.prepare(
      'SELECT id FROM motion_model_releases WHERE model_version = ? LIMIT 1',
    ).bind(draft.modelVersion).first<{ id: string }>();
    if (existing) return c.json({ ok: false, error: 'model_version_already_exists' }, 409);
    const { id } = await insertModelRelease(c.env.DB, draft);
    await audit(c.env.DB, {
      actorId: bodyActor(body as Record<string, unknown>), action: 'model_release_draft',
      releaseId: id,
      details: { modelVersion: draft.modelVersion, modelFamily: draft.modelFamily, runtimeFamily: draft.runtimeFamily },
    });
    const row = await c.env.DB.prepare('SELECT * FROM motion_model_releases WHERE id = ?').bind(id).first<ModelReleaseRow>();
    return c.json({ ok: true, release: row ? publicModelRelease(row) : null });
  } catch (error) {
    return c.json({ ok: false, error: error instanceof Error ? error.message : 'Invalid model release.' }, 400);
  }
});

// Upload the artifact bytes for a registered release. The release checksum is
// law: bytes that don't hash to artifact_sha256 are rejected and removed.
internalRouter.post('/motion/models/:releaseId/artifact', async (c) => {
  const releaseId = c.req.param('releaseId');
  const release = await c.env.DB.prepare(
    'SELECT id, artifact_key, artifact_sha256, artifact_size_bytes FROM motion_model_releases WHERE id = ?',
  ).bind(releaseId).first<ModelReleaseRow>();
  if (!release) return c.json({ ok: false, error: 'Model release not found.' }, 404);
  if (!release.artifact_sha256) return c.json({ ok: false, error: 'release_has_no_declared_checksum' }, 400);

  const bytes = new Uint8Array(await c.req.arrayBuffer());
  if (bytes.byteLength === 0) return c.json({ ok: false, error: 'Empty artifact body.' }, 400);
  if (bytes.byteLength > 400 * 1024 * 1024) {
    return c.json({ ok: false, error: 'Artifact too large.' }, 413);
  }
  const actual = await hashBytes(bytes);
  if (actual !== release.artifact_sha256.toLowerCase()) {
    return c.json({ ok: false, error: 'artifact_checksum_mismatch', expected: release.artifact_sha256, actual }, 422);
  }
  if (release.artifact_size_bytes != null && release.artifact_size_bytes !== bytes.byteLength) {
    return c.json({ ok: false, error: 'artifact_size_mismatch', expected: release.artifact_size_bytes, actual: bytes.byteLength }, 422);
  }
  const key = release.artifact_key ?? `motion-models/${release.id}.onnx`;
  await c.env.PROFILE_PHOTOS.put(key, bytes, { httpMetadata: { contentType: 'application/octet-stream' } });
  await c.env.DB.prepare(
    `UPDATE motion_model_releases
     SET artifact_key = ?, artifact_size_bytes = ?,
         status = CASE WHEN status = 'draft' THEN 'candidate' ELSE status END
     WHERE id = ?`,
  ).bind(key, bytes.byteLength, releaseId).run();
  await audit(c.env.DB, {
    actorId: 'internal-operator', action: 'model_artifact_uploaded', releaseId,
    details: { artifactKey: key, sizeBytes: bytes.byteLength, sha256: actual },
  });
  return c.json({ ok: true, releaseId, artifactKey: key, artifactSizeBytes: bytes.byteLength, sha256: actual });
});

// Record an evaluation run. `hardGatesPassed` must be true — the replay tool
// decides quality; this route only accepts/denies the report shape.
internalRouter.post('/motion/models/:releaseId/evaluations', async (c) => {
  const releaseId = c.req.param('releaseId');
  const release = await c.env.DB.prepare('SELECT id FROM motion_model_releases WHERE id = ?')
    .bind(releaseId).first<{ id: string }>();
  if (!release) return c.json({ ok: false, error: 'Model release not found.' }, 404);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  try {
    const report = parseModelEvaluationReport(body);
    const { evaluationId } = await recordModelEvaluation(
      c.env.DB, releaseId, report, bodyActor(body as Record<string, unknown>),
    );
    await audit(c.env.DB, {
      actorId: bodyActor(body as Record<string, unknown>), action: 'model_evaluated', releaseId,
      details: { evaluationId, corpusId: report.corpusId, sampleCount: report.sampleCount },
    });
    return c.json({ ok: true, releaseId, evaluationId });
  } catch (error) {
    return c.json({ ok: false, error: error instanceof Error ? error.message : 'Invalid evaluation.' }, 400);
  }
});

internalRouter.post('/motion/models/:releaseId/promote', async (c) => {
  const releaseId = c.req.param('releaseId');
  let body: unknown;
  try { body = await c.req.json(); } catch { body = {}; }
  const value = body && typeof body === 'object' ? body as Record<string, unknown> : {};
  const channel = modelChannel(typeof value.channel === 'string' ? value.channel : 'stable');
  if (!channel) return c.json({ ok: false, error: 'Unsupported model channel.' }, 400);
  const rollout = typeof value.rolloutPercent === 'number' ? value.rolloutPercent : 100;
  try {
    const { previousReleaseId } = await promoteModelRelease(c.env.DB, releaseId, channel, rollout);
    await audit(c.env.DB, {
      actorId: bodyActor(value), action: 'model_promoted', releaseId, previousReleaseId,
      details: { channel, rolloutPercent: rollout },
    });
    return c.json({ ok: true, releaseId, channel, rolloutPercent: rollout, previousReleaseId });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Promotion failed.';
    const status = message === 'model_release_not_found' ? 404 : 409;
    return c.json({ ok: false, error: message }, status);
  }
});

internalRouter.post('/motion/models/channels/:family/:channel/rollback', async (c) => {
  const family = c.req.param('family');
  const channel = modelChannel(c.req.param('channel'));
  if (!channel) return c.json({ ok: false, error: 'Unsupported model channel.' }, 400);
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ ok: false, error: 'Invalid JSON body.' }, 400); }
  const releaseId = (body as Record<string, unknown>).releaseId;
  if (typeof releaseId !== 'string' || !releaseId) {
    return c.json({ ok: false, error: 'releaseId is required.' }, 400);
  }
  try {
    const { previousReleaseId } = await rollbackModelChannel(c.env.DB, family, channel, releaseId);
    await audit(c.env.DB, {
      actorId: bodyActor(body as Record<string, unknown>), action: 'model_channel_rollback',
      releaseId, previousReleaseId, details: { modelFamily: family, channel },
    });
    return c.json({ ok: true, modelFamily: family, channel, releaseId, previousReleaseId });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Rollback failed.';
    return c.json({ ok: false, error: message }, message === 'model_channel_not_found' ? 404 : 409);
  }
});

// Kill switch. Disabling repoints every channel to its previous release (or
// clears the pointer so clients resolve to last-known-good/bundled).
internalRouter.post('/motion/models/:releaseId/disable', async (c) => {
  const releaseId = c.req.param('releaseId');
  let body: unknown;
  try { body = await c.req.json(); } catch { body = {}; }
  try {
    const result = await disableModelRelease(c.env.DB, releaseId);
    await audit(c.env.DB, {
      actorId: bodyActor(body as Record<string, unknown>), action: 'model_disabled', releaseId,
      details: result,
    });
    return c.json({ ok: true, releaseId, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Disable failed.';
    return c.json({ ok: false, error: message }, message === 'model_release_not_found' ? 404 : 409);
  }
});

// Audit trail — every control-plane mutation lands here via the shared
// `audit()` helper. Filter by activity/release/action for incident review.
internalRouter.get('/motion/audit', async (c) => {
  const clauses = ['1 = 1'];
  const binds: string[] = [];
  const activityId = c.req.query('activityId');
  const releaseId = c.req.query('releaseId');
  const action = c.req.query('action');
  if (activityId) { clauses.push('activity_id = ?'); binds.push(activityId); }
  if (releaseId) { clauses.push('release_id = ?'); binds.push(releaseId); }
  if (action) { clauses.push('action = ?'); binds.push(action); }
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 50), 1), 200);
  const rows = await c.env.DB.prepare(
    `SELECT id, actor_id, action, activity_id, release_id, previous_release_id,
            details_json, created_at
       FROM verifier_audit_log WHERE ${clauses.join(' AND ')}
       ORDER BY created_at DESC, rowid DESC LIMIT ?`,
  ).bind(...binds, limit).all<Record<string, unknown>>();
  return c.json({
    ok: true,
    count: rows.results.length,
    entries: rows.results.map((row) => ({
      id: row.id,
      actorId: row.actor_id,
      action: row.action,
      activityId: row.activity_id,
      releaseId: row.release_id,
      previousReleaseId: row.previous_release_id,
      details: (() => { try { return JSON.parse(String(row.details_json)); } catch { return {}; } })(),
      createdAt: row.created_at,
    })),
  });
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
  let metadata: unknown = null;
  if (obj) {
    try {
      let bytes = new Uint8Array(await obj.arrayBuffer());
      if (isMotionEncryptionEnvelope(bytes)) {
        const key = await getMotionDataKeyByRef(
          c.env.DB,
          c.env.MOTION_DATA_MASTER_KEY,
          String(row.user_id),
        );
        if (!key) throw new Error('Motion data key is unavailable.');
        const decrypted = await decryptMotionBytes(key, bytes);
        bytes = new Uint8Array(decrypted).slice();
      }
      const compressed = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
      const decompressed = await decompressGzip(compressed);
      artifact = JSON.parse(new TextDecoder().decode(decompressed));
      if (typeof row.metadata_json === 'string') {
        let metadataText = row.metadata_json;
        if (isMotionEncryptionEnvelope(new TextEncoder().encode(metadataText))) {
          const key = await getMotionDataKeyByRef(
            c.env.DB,
            c.env.MOTION_DATA_MASTER_KEY,
            String(row.user_id),
          );
          if (!key) throw new Error('Motion data key is unavailable.');
          metadataText = await decryptMotionText(key, metadataText);
        }
        metadata = JSON.parse(metadataText);
      }
    } catch (e) {
      artifact = { error: `Could not decode artifact: ${e instanceof Error ? e.message : String(e)}` };
    }
  }
  return {
    ok: true as const,
    session: sessionSummary(row),
    metadata,
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
  const accountRef = await motionAccountRef(c.env.MOTION_DATA_MASTER_KEY!, userId);
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 20), 1), 100);
  const activityId = c.req.query('activityId');
  const outcome = c.req.query('outcome');

  const clauses = ['user_id IN (?, ?)'];
  const binds: unknown[] = [userId, accountRef];
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
  const accountRef = await motionAccountRef(c.env.MOTION_DATA_MASTER_KEY!, userId);
  const activityId = c.req.query('activityId');
  const row = await c.env.DB.prepare(
    `SELECT ${SUMMARY_COLS}, metadata_json FROM motion_sessions
      WHERE user_id IN (?, ?)${activityId ? ' AND activity_id = ?' : ''}
      ORDER BY created_at DESC LIMIT 1`,
  ).bind(...(activityId ? [userId, accountRef, activityId] : [userId, accountRef])).first<SessionRow>();
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
