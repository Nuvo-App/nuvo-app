import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const KEY = 'internal-test-key';

// In-memory D1 for just the tables the motion admin routes touch.
function makeEnv() {
  const activities = new Map();
  const releases = [];
  const DB = {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let a = [];
      return {
        bind(...x) { a = x; return this; },
        async run() {
          if (q.startsWith('INSERT INTO motion_activities')) {
            const [id, display_name, category, proof_label, measurement_type, metric, targets, formats, icon, sort, featured, metadata] = a;
            activities.set(id, { id, display_name, category, proof_label, measurement_type, metric,
              suggested_targets_json: targets, supported_formats_json: formats, icon_key: icon,
              sort_priority: sort, featured, availability: 'hidden', metadata_json: metadata });
          } else if (q.startsWith('UPDATE motion_activities SET display_name')) {
            const id = a[a.length - 1];
            const row = activities.get(id);
            const [name, cat, proof, targets, formats, icon, sort, featured, metadata] = a;
            if (name !== null) row.display_name = name;
            if (cat !== null) row.category = cat;
            if (proof !== null) row.proof_label = proof;
            if (targets !== null) row.suggested_targets_json = targets;
            if (formats !== null) row.supported_formats_json = formats;
            if (icon !== null) row.icon_key = icon;
            if (sort !== null) row.sort_priority = sort;
            if (featured !== null) row.featured = featured;
            row.metadata_json = metadata;
          } else if (q.startsWith('INSERT INTO verifier_releases')) {
            const [id, activity_id, semver, change_class, engine_type, , spec_json, checksum, , minimum_app_build, compatibility_group, notes, parent] = a;
            if (releases.some((r) => r.id === id || r.checksum === checksum)) throw new Error('UNIQUE');
            releases.push({ id, activity_id, semver, change_class, engine_type, spec_json, checksum, minimum_app_build, compatibility_group, parent_release_id: parent, status: 'draft' });
          }
          return { success: true };
        },
        async first() {
          if (q.startsWith('SELECT id FROM motion_activities')) return activities.get(a[0]) ?? null;
          if (q.startsWith('SELECT id, metadata_json FROM motion_activities')) return activities.get(a[0]) ?? null;
          if (q.startsWith('SELECT COUNT(*) AS n FROM verifier_releases')) return { n: releases.filter((r) => r.activity_id === a[0]).length };
          if (q.startsWith('SELECT id, activity_id, compatibility_group')) return releases.find((r) => r.id === a[0]) ?? null;
          return null;
        },
        async all() { return { results: [] }; },
      };
    },
  };
  return { DB, INTERNAL_API_KEY: KEY, JWT_SECRET: 's', __activities: activities, __releases: releases };
}

const call = (env, method, path, body) =>
  app.request(`/internal${path}`, {
    method,
    headers: { 'X-Internal-Key': KEY, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  }, env);

const NEW = {
  id: 'side_reaches', displayName: 'Side Reaches', category: 'upper_body', proofLabel: 'side reaches',
  measurementType: 'repetitions', suggestedTargets: [10, 20], supportedFormats: ['first_to_goal'],
  iconKey: 'fitness_center', instructions: ['Face the camera.'], aliases: ['side reach'],
  cameraOrientation: 'front',
};

const SPEC = (extra = {}) => ({
  specSchemaVersion: 1, releaseId: 'side_reaches-2026.10.0', activityId: 'side_reaches',
  engineType: 'alternating_rep_v1', measurementType: 'repetitions',
  requiredCapabilities: ['pose_landmarks_v1', 'alternating_rep_v1'],
  requiredLandmarks: ['leftShoulder', 'rightShoulder', 'leftWrist', 'rightWrist'], stableFrames: 2,
  leftRules: [{ point: 'leftWrist', axis: 'y', operator: 'lt', threshold: 0.35 }],
  rightRules: [{ point: 'rightWrist', axis: 'y', operator: 'lt', threshold: 0.35 }],
  activity: { displayName: 'Side Reaches', measurementType: 'repetitions', defaultTarget: 10, preferredCameraView: 'front' },
  ...extra,
});

test('create a motion: starts hidden, metric derived, duplicates and bad input refused', async () => {
  const env = makeEnv();
  let res = await call(env, 'POST', '/motion/activities', NEW);
  assert.equal(res.status, 201);
  assert.equal(env.__activities.get('side_reaches').availability, 'hidden');
  assert.equal(env.__activities.get('side_reaches').metric, 'reps');
  assert.deepEqual(JSON.parse(env.__activities.get('side_reaches').metadata_json),
    { instructions: ['Face the camera.'], aliases: ['side reach'], cameraOrientation: 'front' });

  assert.equal((await call(env, 'POST', '/motion/activities', NEW)).status, 409);
  assert.equal((await call(env, 'POST', '/motion/activities', { ...NEW, id: 'Bad Id' })).status, 400);
  assert.equal((await call(env, 'POST', '/motion/activities', { ...NEW, id: 'x_one', measurementType: 'distance' })).status, 400);
  assert.equal((await call(env, 'POST', '/motion/activities', { ...NEW, id: 'x_two', suggestedTargets: [0] })).status, 400);
  assert.equal((await call(env, 'POST', '/motion/activities', { ...NEW, id: 'x_three', supportedFormats: ['bogus'] })).status, 400);

  const plank = await call(env, 'POST', '/motion/activities', { ...NEW, id: 'new_hold', measurementType: 'duration' });
  assert.equal(plank.status, 201);
  assert.equal(env.__activities.get('new_hold').metric, 'seconds');
});

test('update display fields; identity fields are locked', async () => {
  const env = makeEnv();
  await call(env, 'POST', '/motion/activities', NEW);
  const res = await call(env, 'PUT', '/motion/activities/side_reaches', {
    displayName: 'Side Reach Taps', suggestedTargets: [15, 30], aliases: ['taps'],
  });
  assert.equal(res.status, 200);
  const row = env.__activities.get('side_reaches');
  assert.equal(row.display_name, 'Side Reach Taps');
  assert.equal(row.category, 'upper_body');
  assert.deepEqual(JSON.parse(row.suggested_targets_json), [15, 30]);
  assert.deepEqual(JSON.parse(row.metadata_json).aliases, ['taps']);
  assert.deepEqual(JSON.parse(row.metadata_json).instructions, ['Face the camera.']);

  assert.equal((await call(env, 'PUT', '/motion/activities/side_reaches', { measurementType: 'duration' })).status, 400);
  assert.equal((await call(env, 'PUT', '/motion/activities/side_reaches', { metric: 'seconds' })).status, 400);
  assert.equal((await call(env, 'PUT', '/motion/activities/missing_one', { displayName: 'X' })).status, 404);
});

test('first release needs no parent; later releases do; native engines refused for new motions', async () => {
  const env = makeEnv();
  const draft = (spec, extra = {}) => call(env, 'POST', '/motion/releases/drafts', {
    activityId: 'side_reaches', releaseId: spec.releaseId, semver: '2026.10.0', spec, ...extra,
  });

  // activity must exist first
  assert.equal((await draft(SPEC())).status, 404);
  await call(env, 'POST', '/motion/activities', NEW);

  assert.equal((await draft(SPEC({ engineType: 'native_v1' }))).status, 400);
  const noBlock = SPEC(); delete noBlock.activity;
  assert.equal((await draft(noBlock)).status, 400);

  const first = await draft(SPEC());
  assert.equal(first.status, 201);
  const row = env.__releases[0];
  assert.equal(row.parent_release_id, null);
  assert.equal(row.compatibility_group, 'side_reaches-remote-v1');

  const second = SPEC({ releaseId: 'side_reaches-2026.10.1', stableFrames: 3 });
  assert.equal((await draft(second)).status, 400); // parent required now
  const ok = await draft(second, { parentReleaseId: 'side_reaches-2026.10.0' });
  assert.equal(ok.status, 201);
  assert.equal(env.__releases[1].compatibility_group, 'side_reaches-remote-v1');
});
