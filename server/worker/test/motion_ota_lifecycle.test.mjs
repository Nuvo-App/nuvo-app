// End-to-end proof that the motion control plane actually does what Nuvo
// needs after Apple submission: tune every shipped motion's verifier over
// the air and roll it back, swap the motion-intelligence model and roll it
// back, create a brand-new motion and remove it from the app again, and
// change a motion's preview animation — all through the real Hono app
// (`src/index.ts`) and real routes (`src/routes/internal.ts`), against a
// REAL SQLite schema (not a hand-written fake D1), the same way
// release_p0_sql.test.mjs proves P0 behavior.
//
// Every "confirm it changed for the app" assertion reads the exact public,
// unauthenticated endpoint the Flutter client calls: GET /races/activities.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
];

// ── D1-over-node:sqlite adapter, same shape as release_p0_sql.test.mjs ─────
function d1(sqlite) {
  const norm = (args) =>
    args.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v));
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    async first(col) {
      const row = sqlite.prepare(sql).get(...norm(args));
      if (!row) return null;
      const o = { ...row };
      return col ? o[col] : o;
    },
    async all() {
      return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
    },
    async run() {
      const info = sqlite.prepare(sql).run(...norm(args));
      return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
    },
  });
  return {
    prepare: (sql) => stmt(sql),
    async batch(stmts) {
      sqlite.exec('BEGIN');
      try {
        const out = [];
        for (const s of stmts) out.push(await s.run());
        sqlite.exec('COMMIT');
        return out;
      } catch (err) {
        sqlite.exec('ROLLBACK');
        throw err;
      }
    },
  };
}

function fakeR2() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, opts) { objects.set(key, { body, opts }); },
    async get(key) {
      const o = objects.get(key);
      return o ? { body: o.body, customMetadata: o.opts?.customMetadata ?? {}, writeHttpMetadata() {} } : null;
    },
    async delete(key) { objects.delete(key); },
  };
}

function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  sqlite.exec('PRAGMA foreign_keys = ON');
  const db = d1(sqlite);
  const r2 = fakeR2();
  const env = { DB: db, JWT_SECRET, PROFILE_PHOTOS: r2, INTERNAL_API_KEY: 'test-internal-key' };
  const ctx = { waitUntil: () => {}, passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);

  const req = async (method, path, body, { internal = true, userId } = {}) => {
    const headers = { 'Content-Type': 'application/json' };
    if (internal) headers['X-Internal-Key'] = env.INTERNAL_API_KEY;
    if (userId) headers.Authorization = `Bearer ${await signJwt({ sub: userId, iat: 0, exp: 9999999999 }, JWT_SECRET)}`;
    const res = await app.request(`${internal ? '/internal' : ''}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    }, env, ctx);
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* non-JSON */ }
    return { status: res.status, json, text };
  };
  // Raw-body internal POST, for the artifact-upload route (no JSON body).
  const reqBytes = async (path, bytes) => {
    const res = await app.request(`/internal${path}`, {
      method: 'POST',
      headers: { 'X-Internal-Key': env.INTERNAL_API_KEY },
      body: bytes,
    }, env, ctx);
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* non-JSON */ }
    return { status: res.status, json, text };
  };

  // Seed a motion exactly the way a production backfill would: the activity
  // row plus one already-stable release, bypassing the draft API (which
  // deliberately refuses to mint a *first* release for a compiled/native
  // engine — see internal.ts's "A new motion needs a data engine" guard).
  const seedShippedMotion = (spec, { availability = 'supported' } = {}) => {
    exec(
      `INSERT INTO motion_activities
         (id, display_name, category, proof_label, measurement_type, metric,
          suggested_targets_json, supported_formats_json, icon_key, sort_priority,
          featured, availability, metadata_json)
       VALUES (?, ?, ?, ?, ?, ?, '[10]', '["first_to_goal"]', 'fitness_center', 100, 0, ?, '{}')`,
      spec.activityId, spec.activityId, 'full_body', spec.activityId,
      spec.measurementType ?? 'repetitions', spec.measurementType === 'duration' ? 'seconds' : 'reps',
      availability,
    );
    const checksum = `sha256:${createHash('sha256').update(JSON.stringify(spec)).digest('hex')}`;
    exec(
      `INSERT INTO verifier_releases
         (id, activity_id, semver, change_class, engine_type, spec_schema_version,
          spec_json, checksum, required_capabilities_json, minimum_app_build,
          compatibility_group, status, release_notes, parent_release_id)
       VALUES (?, ?, '2026.09.0', 'patch', ?, 1, ?, ?, ?, 'remote-runtime-v1', ?, 'stable', 'baseline', NULL)`,
      spec.releaseId, spec.activityId, spec.engineType, JSON.stringify(spec), checksum,
      JSON.stringify(spec.requiredCapabilities ?? []), `${spec.activityId}-remote-v1`,
    );
    exec(
      `INSERT INTO activity_channel_releases (activity_id, channel, release_id, rollout_percent)
       VALUES (?, 'stable', ?, 100)`,
      spec.activityId, spec.releaseId,
    );
    return { releaseId: spec.releaseId, checksum };
  };

  const passingEvaluation = async (releaseId) => {
    const metrics = {
      validRepRecall: 0.95, falsePositiveRate: 0.01, readinessSuccessRate: 0.97,
      frameP95Ms: 12, unsupportedSpecRate: 0, proofMismatchRate: 0,
    };
    const res = await req('POST', '/motion/evaluations', {
      releaseId,
      report: { datasetSnapshotId: 'ds-1', sampleCount: 100, hardGatesPassed: true, baseline: metrics, candidate: metrics },
    });
    assert.equal(res.status, 200, res.text);
    assert.equal(res.json.decision.status, 'passed', JSON.stringify(res.json));
  };

  const activityFromCatalog = async (activityId) => {
    const res = await req('GET', '/races/activities', undefined, { internal: false });
    assert.equal(res.status, 200, res.text);
    return res.json.activities.find((a) => a.id === activityId) ?? null;
  };

  return { sqlite, db, r2, env, req, reqBytes, q, exec, seedShippedMotion, passingEvaluation, activityFromCatalog };
}

// ── Load every compiled motion's real production spec ──────────────────────
const specDir = new URL('motion_specs/', root);
const specFiles = readdirSync(specDir).filter((f) => f.endsWith('.json'));
assert.ok(specFiles.length > 0, 'expected at least one motion_specs/*.json fixture');

// stableFrames is a generic, engine-agnostic tunable (1-12, allowed on every
// engine type) — bumping it is a universal way to publish a *different*,
// still-valid release for literally any motion without needing per-engine
// knowledge of its thresholds.
function tuned(spec, releaseId) {
  const current = spec.stableFrames ?? 3;
  return { ...spec, releaseId, stableFrames: current >= 12 ? current - 1 : current + 1 };
}

for (const file of specFiles) {
  const activityId = file.replace(/\.json$/, '');
  test(`OTA tune round-trip: ${activityId}`, async () => {
    const w = world();
    const spec = JSON.parse(readFileSync(new URL(file, specDir), 'utf8'));
    assert.equal(spec.activityId, activityId, `${file} activityId must match its filename`);
    const baseline = w.seedShippedMotion(spec);

    // Baseline: the app sees exactly the shipped release.
    const before = await w.activityFromCatalog(activityId);
    assert.ok(before, `${activityId} missing from /races/activities`);
    assert.equal(before.currentReleaseId, baseline.releaseId);
    assert.equal(before.currentReleaseChecksum, baseline.checksum);

    // Publish a tuned release over the air.
    const newReleaseId = `${activityId}-ota-tune-1`;
    const candidateSpec = tuned(spec, newReleaseId);
    const draft = await w.req('POST', '/motion/releases/drafts', {
      activityId, releaseId: newReleaseId, parentReleaseId: baseline.releaseId,
      semver: '2026.10.1', changeClass: 'patch', spec: candidateSpec,
    });
    assert.equal(draft.status, 201, draft.text);
    await w.passingEvaluation(newReleaseId);
    const promote = await w.req('POST', `/motion/releases/${newReleaseId}/promote`, { channel: 'stable' });
    assert.equal(promote.status, 200, promote.text);

    // Confirm the app-visible catalog changed to the tuned release.
    const afterTune = await w.activityFromCatalog(activityId);
    assert.equal(afterTune.currentReleaseId, newReleaseId);
    assert.notEqual(afterTune.currentReleaseChecksum, baseline.checksum, 'checksum must change after a tune');

    // Roll back.
    const rollback = await w.req('POST', `/motion/channels/${activityId}/stable/rollback`, { releaseId: baseline.releaseId });
    assert.equal(rollback.status, 200, rollback.text);

    // Confirm the app-visible catalog reverted exactly to the baseline.
    const afterRollback = await w.activityFromCatalog(activityId);
    assert.equal(afterRollback.currentReleaseId, baseline.releaseId);
    assert.equal(afterRollback.currentReleaseChecksum, baseline.checksum, 'rollback must restore the original checksum');
  });
}

// ── Swap the AI model (System B) and roll it back ───────────────────────────
test('model swap round-trip: the app-visible current model changes and rolls back', async () => {
  const w = world();
  const userId = 'user-model-swap';
  const family = 'nuvo_motion_intelligence';
  const runtimeFamily = 'motionbert_rep_v1';

  const registerAndPromote = async (modelVersion) => {
    const bytes = Buffer.from(`fake-onnx-weights-${modelVersion}`);
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const register = await w.req('POST', '/motion/models', {
      modelVersion, modelFamily: family, runtimeFamily,
      inputSchemaVersion: 1, artifactSha256: sha256, artifactSizeBytes: bytes.byteLength,
    });
    assert.equal(register.status, 200, register.text);
    const releaseId = register.json.release.modelReleaseId;
    const upload = await w.reqBytes(`/motion/models/${releaseId}/artifact`, bytes);
    assert.equal(upload.status, 200, upload.text);
    const evaluate = await w.req('POST', `/motion/models/${releaseId}/evaluations`, {
      corpusId: 'corpus-1', sampleCount: 100, hardGatesPassed: true, metrics: {},
    });
    assert.equal(evaluate.status, 200, evaluate.text);
    const promote = await w.req('POST', `/motion/models/${releaseId}/promote`, { channel: 'stable' });
    assert.equal(promote.status, 200, promote.text);
    return { releaseId, modelVersion };
  };

  const currentModel = async () => {
    const res = await w.req('GET', `/motion/models/current?family=${family}&channel=stable`, undefined, { internal: false, userId });
    assert.equal(res.status, 200, res.text);
    return res.json.model;
  };

  const modelA = await registerAndPromote('2026.10.0');
  assert.equal((await currentModel()).modelVersion, modelA.modelVersion);

  // Swap to a different model release — confirm the app-visible model changed.
  const modelB = await registerAndPromote('2026.10.1');
  assert.equal((await currentModel()).modelVersion, modelB.modelVersion);
  assert.notEqual(modelB.modelVersion, modelA.modelVersion);

  // Roll the channel back — confirm it changed back.
  const rollback = await w.req('POST', `/motion/models/channels/${family}/stable/rollback`, { releaseId: modelA.releaseId });
  assert.equal(rollback.status, 200, rollback.text);
  assert.equal((await currentModel()).modelVersion, modelA.modelVersion);
});

// ── Create a brand-new motion, then remove it from the app again ───────────
test('create and remove a motion without an app update', async () => {
  const w = world();
  const activityId = 'side_reaches_e2e';

  // Does not exist yet.
  assert.equal(await w.activityFromCatalog(activityId), null);

  const create = await w.req('POST', '/motion/activities', {
    id: activityId, displayName: 'Side Reaches', category: 'upper_body', proofLabel: 'side reaches',
    measurementType: 'repetitions', suggestedTargets: [10, 20], supportedFormats: ['first_to_goal'],
    iconKey: 'fitness_center',
  });
  assert.equal(create.status, 201, create.text);
  assert.equal(create.json.availability, 'hidden');

  // Hidden by default: the public stable catalog (what the app fetches)
  // omits a hidden activity entirely, not just from its `supported` list.
  assert.equal(await w.activityFromCatalog(activityId), null);
  const supportedBefore = (await w.req('GET', '/races/activities', undefined, { internal: false })).json.supported;
  assert.ok(!supportedBefore.includes(activityId));

  // Give it a first release on a generic data engine.
  const spec = {
    specSchemaVersion: 1, releaseId: `${activityId}-2026.10.0`, activityId, engineType: 'state_machine_v1',
    measurementType: 'repetitions', requiredCapabilities: ['pose_landmarks_v1', 'derived_features_v1', 'state_machine_v1'],
    requiredLandmarks: ['leftWrist', 'leftShoulder'],
    startRules: [{ point: 'leftWrist', axis: 'y', operator: 'lt', threshold: 0.5 }],
    activeRules: [{ point: 'leftWrist', axis: 'y', operator: 'gt', threshold: 0.5 }],
    activity: { displayName: 'Side Reaches', measurementType: 'repetitions' },
  };
  const draft = await w.req('POST', '/motion/releases/drafts', {
    activityId, releaseId: spec.releaseId, semver: '2026.10.0', changeClass: 'minor', spec,
  });
  assert.equal(draft.status, 201, draft.text);
  await w.passingEvaluation(spec.releaseId);
  const promote = await w.req('POST', `/motion/releases/${spec.releaseId}/promote`, { channel: 'stable' });
  assert.equal(promote.status, 200, promote.text);

  // Switch visibility on: now it is in the app.
  const show = await w.req('PUT', `/motion/activities/${activityId}/availability`, { availability: 'supported' });
  assert.equal(show.status, 200, show.text);
  const supportedAfterShow = (await w.req('GET', '/races/activities', undefined, { internal: false })).json.supported;
  assert.ok(supportedAfterShow.includes(activityId), 'motion should now be app-visible');
  const shownEntry = await w.activityFromCatalog(activityId);
  assert.equal(shownEntry.currentReleaseId, spec.releaseId);

  // Remove it from the app again (the control plane's "delete" is hide —
  // there is no hard-delete endpoint, which is intentional: historical races
  // and sessions must keep referring to a real activity row).
  const hide = await w.req('PUT', `/motion/activities/${activityId}/availability`, { availability: 'hidden' });
  assert.equal(hide.status, 200, hide.text);
  const supportedAfterHide = (await w.req('GET', '/races/activities', undefined, { internal: false })).json.supported;
  assert.ok(!supportedAfterHide.includes(activityId), 'motion should be gone from the app-visible set again');
});

// ── Modify a motion's preview animation and confirm it changed, then clear it ─
test('motion preview change round-trip', async () => {
  const w = world();
  const spec = JSON.parse(readFileSync(new URL(specFiles[0], specDir), 'utf8'));
  const activityId = spec.activityId;
  w.seedShippedMotion(spec);

  const before = await w.activityFromCatalog(activityId);
  assert.equal(before.previewSequence, null);

  const preview = {
    rig: 'front', durationMs: 1200,
    keyframes: [{ t: 0, pose: 'start' }, { t: 1200, pose: 'end' }],
  };
  const set = await w.req('PUT', `/motion/activities/${activityId}/preview`, { preview });
  assert.equal(set.status, 200, set.text);
  assert.equal(set.json.previewCleared, false);

  const afterSet = await w.activityFromCatalog(activityId);
  assert.deepEqual(afterSet.previewSequence, preview);

  const clear = await w.req('PUT', `/motion/activities/${activityId}/preview`, { preview: null });
  assert.equal(clear.status, 200, clear.text);
  assert.equal(clear.json.previewCleared, true);

  const afterClear = await w.activityFromCatalog(activityId);
  assert.equal(afterClear.previewSequence, null, 'clearing the preview must fall back to the bundled animation');
});
