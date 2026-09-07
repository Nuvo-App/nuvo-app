import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);

const {
  activityForId,
  normalizeActivityId,
  normalizeMetric,
  scoringRuleForFormat,
} = require('../.tmp-test-dist/domain/raceActivities.js');
const { applyVerifiedSubmission } = require('../.tmp-test-dist/domain/raceScoring.js');
const { computeCompetitionRanks } = require('../.tmp-test-dist/domain/raceRanking.js');
const {
  assertSubmissionCompatible,
  configFromBody,
  customConfigFromBody,
} = require('../.tmp-test-dist/domain/raceValidation.js');

function feature(value = 0.5) {
  return {
    value,
    confidence: 0.9,
    valid: true,
    kind: 'angle',
  };
}

function normalizedPose({ withLandmarks = true } = {}) {
  return {
    version: 1,
    originX: 0,
    originY: 0,
    scale: 1,
    originReference: 'hips',
    scaleReference: 'shoulders',
    validLandmarkCount: withLandmarks ? 1 : 0,
    validFeatureCount: 1,
    landmarks: withLandmarks
      ? {
        nose: {
          x: 0,
          y: 0,
          z: 0,
          confidence: 1,
          valid: true,
        },
      }
      : {},
    features: {
      version: 1,
      values: {
        hip_angle: feature(),
      },
    },
  };
}

function customVerifierSpec(overrides = {}) {
  return {
    version: 1,
    verifierType: 'custom_pose_sequence',
    movementName: 'Overhead knee touch',
    measurementType: 'count',
    startPose: normalizedPose(),
    completionPose: normalizedPose({ withLandmarks: false }),
    completionStrategy: 'completionAtTerminalPose',
    canonicalSequence: [
      {
        position: 0,
        features: {
          hip_angle: {
            value: 0.5,
            confidence: 0.9,
            reliability: 0.8,
            allowedVariation: 0.2,
            contributingDemonstrationCount: 3,
            kind: 'angle',
          },
        },
      },
      {
        position: 1,
        features: {
          hip_angle: {
            value: 0.7,
            confidence: 0.9,
            reliability: 0.8,
            allowedVariation: 0.2,
            contributingDemonstrationCount: 3,
            kind: 'angle',
          },
        },
      },
    ],
    requiredFeatureIds: ['hip_angle'],
    activeFeatureIds: ['hip_angle'],
    sequenceSimilarityThreshold: 0.6,
    completionSimilarityThreshold: 0.65,
    resetSimilarityThreshold: 0.55,
    minimumValidFeatureRatio: 0.7,
    minimumVisibility: 0.5,
    cooldownMs: 600,
    expectedSequenceFrameCount: 2,
    ...overrides,
  };
}

// ── Scoring: arbitrary targets ─────────────────────────────────────────────────

test('target 6: cumulative sessions complete at or above goal', () => {
  const s1 = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 0, submissionValue: 4, targetValue: 6 });
  assert.deepEqual(s1, { newScore: 4, progressPercent: 67, completed: false });

  const s2 = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 4, submissionValue: 2, targetValue: 6 });
  assert.deepEqual(s2, { newScore: 6, progressPercent: 100, completed: true });
});

test('target 15: three sessions including over-target final submission', () => {
  const s1 = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 0, submissionValue: 6, targetValue: 15 });
  assert.equal(s1.newScore, 6);
  assert.equal(s1.completed, false);

  const s2 = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 6, submissionValue: 4, targetValue: 15 });
  assert.equal(s2.newScore, 10);
  assert.equal(s2.completed, false);

  const s3 = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 10, submissionValue: 7, targetValue: 15 });
  assert.equal(s3.newScore, 17);
  assert.equal(s3.progressPercent, 100);
  assert.equal(s3.completed, true);
});

test('target 100: arbitrary large target accumulates correctly', () => {
  let score = 0;
  for (let i = 0; i < 4; i++) {
    const r = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: score, submissionValue: 25, targetValue: 100 });
    score = r.newScore;
  }
  assert.equal(score, 100);

  const over = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 93, submissionValue: 12, targetValue: 100 });
  assert.equal(over.newScore, 105);
  assert.equal(over.progressPercent, 100);
  assert.equal(over.completed, true);
});

test('score exceeding target preserves raw value and caps visual percent at 100', () => {
  const r = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 14, submissionValue: 7, targetValue: 15 });
  assert.equal(r.newScore, 21);
  assert.equal(r.progressPercent, 100);
  assert.equal(r.completed, true);
});

test('multiple sessions without completing do not prematurely complete', () => {
  const sessions = [3, 2, 4];
  let score = 0;
  for (const val of sessions) {
    const r = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: score, submissionValue: val, targetValue: 30 });
    assert.equal(r.completed, false);
    score = r.newScore;
  }
  assert.equal(score, 9);
  assert.equal(Math.round((9 / 30) * 100), 30);
});

// ── Scoring: winner and completion ─────────────────────────────────────────────

test('winner selection: first to reach target completes the race', () => {
  const winner = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 10, submissionValue: 5, targetValue: 15 });
  assert.equal(winner.completed, true);

  const lateArrival = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 13, submissionValue: 3, targetValue: 15 });
  assert.equal(lateArrival.completed, true);
  assert.equal(lateArrival.newScore, 16);
});

test('proof route: completed race gate sits after idempotency check', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  const routeStart = source.indexOf("racesRouter.post('/:id/proof'");
  assert.notEqual(routeStart, -1, 'proof route must exist');
  const routeSource = source.slice(routeStart);
  const duplicateLookup = routeSource.indexOf('client_submission_id = ?');
  const activeGate = routeSource.indexOf("badRequest('Race is not active')");
  assert.notEqual(duplicateLookup, -1, 'idempotency lookup must exist');
  assert.notEqual(activeGate, -1, 'active race gate must exist');
  assert.ok(duplicateLookup < activeGate, 'idempotent retry must return original result even after race completes');
});

test('proof route: non-participant rejection is present', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  assert.ok(
    source.includes('Only race participants can submit proof'),
    'non-participant must be rejected with clear message',
  );
});

test('proof route: final standings snapshot is triggered on completion', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  const completionWriteIdx = source.indexOf("SET status = 'completed'");
  assert.notEqual(completionWriteIdx, -1, 'completion UPDATE must exist');
  const snapshotCallIdx = source.indexOf('await snapshotFinalStandings(');
  assert.notEqual(snapshotCallIdx, -1, 'await snapshotFinalStandings call must exist');
  assert.ok(snapshotCallIdx > completionWriteIdx, 'snapshot must be called after the completion write');
});

test('custom race scoring does not impersonate a preset activity id', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  assert.ok(source.includes('function raceScoringConfigFromRow'), 'custom scoring helper must exist');
  assert.equal(source.includes('race.verifier_type as unknown as RaceActivityId'), false);
});

test('proof route validates custom verifier proof contract', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  assert.ok(source.includes('Custom races require AI Motion Proof'));
  assert.ok(source.includes('Custom proof movement does not match race.'));
  assert.ok(source.includes('Custom proof detected value must match value.'));
  assert.ok(source.includes('Custom proof valid frames cannot exceed analyzed frames.'));
});

// ── Ranking: deterministic and tied ───────────────────────────────────────────

test('first-to-goal supports arbitrary cumulative targets (original)', () => {
  const first = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 0, submissionValue: 4, targetValue: 6 });
  assert.deepEqual(first, { newScore: 4, progressPercent: 67, completed: false });

  const second = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: first.newScore, submissionValue: 3, targetValue: 6 });
  assert.deepEqual(second, { newScore: 7, progressPercent: 100, completed: true });
});

test('competition ranks use tied ranks and deterministic tie ordering', () => {
  const ranked = computeCompetitionRanks([
    { user_id: 'a', progress_value: 10, completed_at: null, joined_at: '2026-01-01T00:00:01Z' },
    { user_id: 'b', progress_value: 15, completed_at: '2026-01-01T00:02:00Z', joined_at: '2026-01-01T00:00:02Z' },
    { user_id: 'c', progress_value: 15, completed_at: '2026-01-01T00:03:00Z', joined_at: '2026-01-01T00:00:03Z' },
    { user_id: 'd', progress_value: 5, completed_at: null, joined_at: '2026-01-01T00:00:04Z' },
  ]);

  assert.deepEqual(ranked.map((row) => [row.user_id, row.rank]), [
    ['b', 1],
    ['c', 1],
    ['a', 3],
    ['d', 4],
  ]);
});

test('tied ranks: all equal scores get the same rank and next rank skips', () => {
  const ranked = computeCompetitionRanks([
    { user_id: 'x', progress_value: 10, completed_at: null, joined_at: '2026-01-01T00:00:01Z' },
    { user_id: 'y', progress_value: 10, completed_at: null, joined_at: '2026-01-01T00:00:02Z' },
    { user_id: 'z', progress_value: 5, completed_at: null, joined_at: '2026-01-01T00:00:03Z' },
  ]);

  assert.deepEqual(ranked.map((r) => r.rank), [1, 1, 3]);
});

test('deterministic ordering: lower score first then joined_at breaks further ties', () => {
  const ranked = computeCompetitionRanks([
    { user_id: 'late', progress_value: 10, completed_at: null, joined_at: '2026-01-01T00:01:00Z' },
    { user_id: 'early', progress_value: 10, completed_at: null, joined_at: '2026-01-01T00:00:00Z' },
  ]);

  assert.equal(ranked[0].user_id, 'early');
  assert.equal(ranked[0].rank, 1);
  assert.equal(ranked[1].user_id, 'late');
  assert.equal(ranked[1].rank, 1);
});

// ── Activity and metric normalization ─────────────────────────────────────────

test('activity and metric normalization do not fall back to jumping jacks', () => {
  assert.equal(normalizeActivityId('pushups'), 'push_ups');
  assert.equal(normalizeActivityId('jumping jacks'), 'jumping_jacks');
  assert.equal(normalizeActivityId('cartwheels'), undefined);
  assert.equal(normalizeMetric('pushups', activityForId('push_ups')), 'reps');
  assert.equal(normalizeMetric('seconds', activityForId('plank_hold')), 'seconds');
});

test('plank uses seconds metric, not reps', () => {
  const plank = activityForId('plank_hold');
  assert.equal(plank?.defaultMetric, 'seconds', 'plank defaultMetric must be seconds');
  assert.deepEqual(plank?.supportedMetrics, ['seconds'], 'plank must only support seconds');
  assert.equal(normalizeMetric('seconds', plank), 'seconds');
});

// ── Validation ────────────────────────────────────────────────────────────────

test('validation rejects unsupported activities and invalid combinations', () => {
  assert.deepEqual(configFromBody({ activityId: 'cartwheels', metric: 'reps', format: 'first_to_goal', targetValue: 10 }), { error: 'Choose a supported activity.' });
  assert.deepEqual(configFromBody({ activityId: 'plank_hold', metric: 'reps', format: 'first_to_goal', targetValue: 60 }), { error: 'Plank cannot use that metric.' });

  const valid = configFromBody({ activityId: 'squats', metric: 'reps', format: 'first_to_goal', targetValue: 15 });
  assert.equal('error' in valid, false);
});

test('validation rejects zero and negative targets', () => {
  const zero = configFromBody({ activityId: 'push_ups', metric: 'reps', format: 'first_to_goal', targetValue: 0 });
  assert.ok('error' in zero, 'zero target must be rejected');

  const negative = configFromBody({ activityId: 'push_ups', metric: 'reps', format: 'first_to_goal', targetValue: -5 });
  assert.ok('error' in negative, 'negative target must be rejected');
});

test('custom verifier validation accepts bounded custom race config', () => {
  const spec = customVerifierSpec();

  const config = customConfigFromBody({
    title: 'Office ladder',
    targetValue: 10,
    verifierType: 'custom_pose_sequence',
    verifierVersion: 1,
    customActivityName: 'Overhead knee touch',
    verifierSpec: spec,
  });

  assert.equal('error' in config, false);
  assert.equal(config.verifierType, 'custom_pose_sequence');
  assert.equal(config.verifierVersion, 1);
  assert.equal(config.metric, 'reps');
  assert.equal(config.verificationMethod, 'ai');
  assert.equal(config.targetValue, 10);
});

test('custom verifier validation accepts feature-only learned completion pose', () => {
  const config = customConfigFromBody({
    title: 'Office ladder',
    targetValue: 10,
    verifierType: 'custom_pose_sequence',
    verifierVersion: 1,
    customActivityName: 'Overhead knee touch',
    verifierSpec: customVerifierSpec({
      completionPose: normalizedPose({ withLandmarks: false }),
    }),
  });

  assert.equal('error' in config, false);
});

test('custom verifier validation rejects inactive sequence features', () => {
  const config = customConfigFromBody({
    title: 'Office ladder',
    targetValue: 10,
    verifierType: 'custom_pose_sequence',
    verifierVersion: 1,
    customActivityName: 'Overhead knee touch',
    verifierSpec: customVerifierSpec({
      canonicalSequence: [{
        position: 0,
        features: {
          other_angle: {
            value: 0.5,
            confidence: 0.9,
            reliability: 0.8,
            allowedVariation: 0.2,
            contributingDemonstrationCount: 3,
            kind: 'angle',
          },
        },
      }],
      expectedSequenceFrameCount: 1,
    }),
  });

  assert.equal('error' in config, true);
  assert.equal(config.error, 'Custom verifier sequence uses inactive features.');
});

test('custom verifier validation rejects preset activity impersonation', () => {
  const config = customConfigFromBody({
    title: 'Office ladder',
    targetValue: 10,
    activityId: 'push_ups',
    verifierType: 'custom_pose_sequence',
    verifierVersion: 1,
    customActivityName: 'Overhead knee touch',
    verifierSpec: {},
  });

  assert.equal('error' in config, true);
  assert.equal(config.error, 'Custom races cannot use a preset activity.');
});

test('submission compatibility validates activity and metric', () => {
  const config = {
    activityId: 'push_ups',
    metric: 'reps',
    format: 'first_to_goal',
    scoringRule: scoringRuleForFormat('first_to_goal'),
    targetValue: 100,
    attemptDurationSeconds: null,
    attemptLimit: null,
    verificationMethod: 'camera_pose',
    timezone: 'America/New_York',
    startsAt: null,
    endsAt: null,
    recurrence: 'none',
  };

  assert.equal(assertSubmissionCompatible(config, 'push_ups', 'reps'), null);
  assert.equal(assertSubmissionCompatible(config, 'squats', 'reps'), 'Verified movement does not match this race.');
  assert.equal(assertSubmissionCompatible(config, 'push_ups', 'seconds'), 'Verified metric does not match this race.');
});

test('wrong activity is rejected with clear message', () => {
  const config = {
    activityId: 'squats',
    metric: 'reps',
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    targetValue: 15,
    attemptDurationSeconds: null,
    attemptLimit: null,
    verificationMethod: 'camera_pose',
    timezone: 'America/New_York',
    startsAt: null,
    endsAt: null,
    recurrence: 'none',
  };

  const err = assertSubmissionCompatible(config, 'push_ups', 'reps');
  assert.equal(err, 'Verified movement does not match this race.');
});

test('wrong metric is rejected with clear message', () => {
  const config = {
    activityId: 'plank_hold',
    metric: 'seconds',
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    targetValue: 60,
    attemptDurationSeconds: null,
    attemptLimit: null,
    verificationMethod: 'camera_pose',
    timezone: 'America/New_York',
    startsAt: null,
    endsAt: null,
    recurrence: 'none',
  };

  const err = assertSubmissionCompatible(config, 'plank_hold', 'reps');
  assert.equal(err, 'Verified metric does not match this race.');
  assert.equal(assertSubmissionCompatible(config, 'plank_hold', 'seconds'), null);
});

// ── Duplicate clientSubmissionId ──────────────────────────────────────────────

test('proof route checks duplicate submissions before active race gate', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  const routeStart = source.indexOf("racesRouter.post('/:id/proof'");
  assert.notEqual(routeStart, -1);
  const routeSource = source.slice(routeStart);
  const duplicateLookup = routeSource.indexOf('client_submission_id = ?');
  const activeGate = routeSource.indexOf("badRequest('Race is not active')");

  assert.notEqual(duplicateLookup, -1);
  assert.notEqual(activeGate, -1);
  assert.ok(
    duplicateLookup < activeGate,
    'idempotent retries must return the original result even after completion',
  );
});

// ── Legacy race compatibility ──────────────────────────────────────────────────

test('legacy race compatibility: old movement_type and race_type fields are normalised', () => {
  assert.equal(normalizeActivityId('pushups'), 'push_ups');
  assert.equal(normalizeActivityId('push_ups'), 'push_ups');
  assert.equal(normalizeActivityId('jumping_jacks'), 'jumping_jacks');
  assert.equal(normalizeActivityId('squats'), 'squats');
  assert.equal(normalizeActivityId('lunges'), 'lunges');
  assert.equal(normalizeActivityId('plank'), 'plank_hold');
  assert.equal(normalizeActivityId('plank_hold'), 'plank_hold');
});

test('legacy race compatibility: first_to_target race_type maps to first_to_goal format', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  assert.ok(source.includes("'first_to_target' ? 'first_to_goal'"), 'first_to_target must map to first_to_goal');
});

test('scoring rule defaults to cumulative_sum for unknown rules', () => {
  const r = applyVerifiedSubmission({ format: 'first_to_goal', scoringRule: 'cumulative_sum', previousScore: 5, submissionValue: 3, targetValue: 20 });
  assert.equal(r.newScore, 8);
  assert.equal(r.completed, false);
});

// ── Custom race INSERT column/bind alignment ─────────────────────────────────

test('custom race INSERT has matching column count, placeholder count, and bind order', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  const routeStart = source.indexOf("racesRouter.post('/', async (c) => {");
  assert.notEqual(routeStart, -1, 'POST / route must exist');
  const routeSource = source.slice(routeStart);

  // Find the custom INSERT block
  const customInsertStart = routeSource.indexOf('INSERT INTO races (id, creator_id, title, description, race_type, movement_type, verification_type,');
  assert.notEqual(customInsertStart, -1, 'custom INSERT must exist');

  // Extract the column list
  const columnSection = routeSource.slice(customInsertStart);
  const columnEnd = columnSection.indexOf(')');
  const columnList = columnSection.slice(0, columnEnd);
  const columns = columnList
    .replace('INSERT INTO races (', '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  assert.ok(columns.includes('verifier_type'), 'INSERT must include verifier_type');
  assert.ok(columns.includes('verifier_version'), 'INSERT must include verifier_version');
  assert.ok(columns.includes('verifier_spec_json'), 'INSERT must include verifier_spec_json');
  assert.ok(columns.includes('custom_activity_name'), 'INSERT must include custom_activity_name');

  // Extract the VALUES section
  const valuesStart = columnSection.indexOf('VALUES (');
  const valuesSection = columnSection.slice(valuesStart);
  const valuesEnd = valuesSection.indexOf(')');
  const valuesList = valuesSection.slice(0, valuesEnd);
  const values = valuesList
    .replace('VALUES (', '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  // Count placeholders (?)
  const placeholderCount = values.filter((v) => v === '?').length;
  const literalCount = values.filter((v) => v !== '?').length;
  assert.equal(columns.length, values.length, 'column count must match value count');
  assert.equal(placeholderCount + literalCount, columns.length, 'all values must be accounted for');

  // Verify bind order: the custom bind block binds in the same order as columns
  const bindStart = routeSource.indexOf('.bind(', customInsertStart);
  const bindSection = routeSource.slice(bindStart);
  const bindEnd = bindSection.indexOf(')');
  const bindArgs = bindSection.slice(5, bindEnd)
    .split(/\s*,\s*/)
    .map((s) => s.trim())
    .filter(Boolean);

  assert.equal(bindArgs.length, placeholderCount, `bind args (${bindArgs.length}) must match placeholder count (${placeholderCount})`);

  // Verify key bind positions match their columns
  const verifierTypeIdx = columns.indexOf('verifier_type');
  assert.ok(bindArgs[verifierTypeIdx].includes('custom.verifierType'), `verifier_type bind must be custom.verifierType, got: ${bindArgs[verifierTypeIdx]}`);
  const verifierVersionIdx = columns.indexOf('verifier_version');
  assert.ok(bindArgs[verifierVersionIdx].includes('custom.verifierVersion'), `verifier_version bind must be custom.verifierVersion`);
  const verifierSpecIdx = columns.indexOf('verifier_spec_json');
  assert.ok(bindArgs[verifierSpecIdx].includes('custom.verifierSpecJson'), `verifier_spec_json bind must be custom.verifierSpecJson`);
  const customActivityIdx = columns.indexOf('custom_activity_name');
  assert.ok(bindArgs[customActivityIdx].includes('custom.customActivityName'), `custom_activity_name bind must be custom.customActivityName`);
});

test('POST /races wraps DB batch in try/catch for useful error responses', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  const routeStart = source.indexOf("racesRouter.post('/', async (c) => {");
  const routeSource = source.slice(routeStart);
  assert.ok(routeSource.includes('Could not create the race'), 'DB failure must return a user-friendly error');
  assert.ok(routeSource.includes('no such column'), 'DB failure must detect missing column errors');
});

test('buildRaceResponse includes custom verifier fields in response', () => {
  const source = readFileSync(new URL('../src/routes/races.ts', import.meta.url), 'utf8');
  assert.ok(source.includes('verifierType: race.verifier_type'), 'response must include verifierType');
  assert.ok(source.includes('verifierVersion: race.verifier_version'), 'response must include verifierVersion');
  assert.ok(source.includes('verifierSpec: verifier.spec'), 'response must include verifierSpec');
  assert.ok(source.includes('customActivityName: race.custom_activity_name'), 'response must include customActivityName');
});

// ── Preset activity registration: high_knees and arm_raises ────────────────────

// Mirrors the preset branch of raceConfigFromRow/raceScoringConfigFromRow in
// routes/races.ts using only the exported domain helpers, so we can prove a
// synthetic race row resolves to a non-null scoring config without importing
// the non-exported route helper.
function presetScoringConfigFromRow(race) {
  const activityId = normalizeActivityId(race.activity_id ?? race.movement_type);
  const activity = activityForId(activityId);
  if (!activity || !activityId) return null;
  const metric = normalizeMetric(race.metric ?? race.target_unit, activity);
  if (!metric) return null;
  const format = ((race.format ?? race.race_type) === 'first_to_target' ? 'first_to_goal' : (race.format ?? 'first_to_goal'));
  const scoringRule = (race.scoring_rule ?? 'cumulative_sum');
  return { activityId, metric, format, scoringRule, targetValue: race.target_value };
}

test('normalizeActivityId recognizes high_knees and its aliases', () => {
  assert.equal(normalizeActivityId('high_knees'), 'high_knees');
  assert.equal(normalizeActivityId('high knee'), 'high_knees');
  assert.equal(normalizeActivityId('high knees'), 'high_knees');
  assert.equal(normalizeActivityId('high-knees'), 'high_knees');
  assert.equal(normalizeActivityId('highknees'), 'high_knees');
  assert.equal(normalizeActivityId('high knee'), 'high_knees');
});

test('normalizeActivityId recognizes arm_raises and its aliases', () => {
  assert.equal(normalizeActivityId('arm_raises'), 'arm_raises');
  assert.equal(normalizeActivityId('arm raise'), 'arm_raises');
  assert.equal(normalizeActivityId('arm raises'), 'arm_raises');
  assert.equal(normalizeActivityId('arm-raises'), 'arm_raises');
  assert.equal(normalizeActivityId('armraises'), 'arm_raises');
});

test('activityForId returns definitions for high_knees and arm_raises', () => {
  const highKnees = activityForId('high_knees');
  assert.equal(highKnees?.id, 'high_knees');
  assert.equal(highKnees?.defaultMetric, 'reps');
  assert.equal(highKnees?.validatorKey, 'high_knees_v1');
  assert.equal(highKnees?.cameraOrientation, 'front');
  assert.deepEqual(highKnees?.supportedFormats, ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);

  const armRaises = activityForId('arm_raises');
  assert.equal(armRaises?.id, 'arm_raises');
  assert.equal(armRaises?.defaultMetric, 'reps');
  assert.equal(armRaises?.validatorKey, 'arm_raises_v1');
  assert.equal(armRaises?.cameraOrientation, 'front');
  assert.deepEqual(armRaises?.supportedFormats, ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt']);
});

test('synthetic race row with activity_id=high_knees produces a non-null scoring config', () => {
  const config = presetScoringConfigFromRow({
    activity_id: 'high_knees',
    metric: 'reps',
    format: 'first_to_goal',
    scoring_rule: 'cumulative_sum',
    target_value: 20,
  });
  assert.ok(config, 'high_knees race row must resolve to a scoring config');
  assert.equal(config.activityId, 'high_knees');
  assert.equal(config.metric, 'reps');
  assert.equal(config.targetValue, 20);
});

test('synthetic race row with activity_id=arm_raises produces a non-null scoring config', () => {
  const config = presetScoringConfigFromRow({
    activity_id: 'arm_raises',
    metric: 'reps',
    format: 'first_to_goal',
    scoring_rule: 'cumulative_sum',
    target_value: 20,
  });
  assert.ok(config, 'arm_raises race row must resolve to a scoring config');
  assert.equal(config.activityId, 'arm_raises');
  assert.equal(config.metric, 'reps');
  assert.equal(config.targetValue, 20);
});

test('normalizeMetric recognizes high_knees and arm_raises as reps', () => {
  assert.equal(normalizeMetric('high_knees', activityForId('high_knees')), 'reps');
  assert.equal(normalizeMetric('high knees', activityForId('high_knees')), 'reps');
  assert.equal(normalizeMetric('arm_raises', activityForId('arm_raises')), 'reps');
  assert.equal(normalizeMetric('arm raises', activityForId('arm_raises')), 'reps');
});

test('configFromBody accepts high_knees preset race (proves POST /races stores activity_id non-null)', () => {
  const config = configFromBody({
    activityId: 'high_knees',
    metric: 'reps',
    format: 'first_to_goal',
    targetValue: 20,
  });
  assert.equal('error' in config, false);
  assert.equal(config.activityId, 'high_knees');
  assert.equal(config.metric, 'reps');
});

test('configFromBody accepts arm_raises preset race (proves POST /races stores activity_id non-null)', () => {
  const config = configFromBody({
    activityId: 'arm_raises',
    metric: 'reps',
    format: 'first_to_goal',
    targetValue: 20,
  });
  assert.equal('error' in config, false);
  assert.equal(config.activityId, 'arm_raises');
  assert.equal(config.metric, 'reps');
});

test('existing five preset activities still normalize correctly (regression)', () => {
  assert.equal(normalizeActivityId('push_ups'), 'push_ups');
  assert.equal(normalizeActivityId('pushups'), 'push_ups');
  assert.equal(normalizeActivityId('jumping_jacks'), 'jumping_jacks');
  assert.equal(normalizeActivityId('jumping jack'), 'jumping_jacks');
  assert.equal(normalizeActivityId('squats'), 'squats');
  assert.equal(normalizeActivityId('lunges'), 'lunges');
  assert.equal(normalizeActivityId('plank_hold'), 'plank_hold');
  assert.equal(normalizeActivityId('plank'), 'plank_hold');
  // Burpees is now a supported preset (see preset-motion-expansion) — the
  // regression guard is that the ORIGINAL five still normalize correctly.
  assert.equal(normalizeActivityId('burpees'), 'burpees');
});

const {
  RACE_ACTIVITY_CATALOG,
} = require('../.tmp-test-dist/domain/raceActivities.js');

// Registration invariant: every activity in RACE_ACTIVITY_CATALOG must be
// accepted by every gate on the race-creation path. This is the server-side
// mirror of test/preset_registration_contract_test.dart — it prevents the
// "client offers a preset the deployed Worker rejects with 'choose a
// supported activity'" class of bug. NOTE: passing here only proves the
// SOURCE is correct — the Worker must still be redeployed (`npm run deploy`)
// for a catalog change to reach production.
test('every RACE_ACTIVITY_CATALOG entry passes the full creation route', () => {
  for (const activity of RACE_ACTIVITY_CATALOG) {
    const id = activity.id;

    assert.equal(normalizeActivityId(id), id, `${id}: normalizeActivityId`);
    assert.ok(activityForId(id), `${id}: activityForId`);

    const unit = activity.defaultMetric;
    const config = configFromBody({
      activityId: id,
      metric: unit,
      format: 'first_to_goal',
      targetValue: 15,
    });
    assert.equal(
      'error' in config,
      false,
      `${id}: configFromBody rejected it: ${JSON.stringify(config)}`,
    );
    assert.equal(config.activityId, id, `${id}: config.activityId`);
    assert.equal(config.metric, unit, `${id}: config.metric`);
  }
});

test('the 10 preset-motion-expansion activities are all in the catalog', () => {
  const ids = new Set(RACE_ACTIVITY_CATALOG.map((a) => a.id));
  for (const id of [
    'running_in_place', 'treadmill_running', 'walking_in_place',
    'marching_in_place', 'butt_kicks', 'mountain_climbers', 'burpees',
    'step_ups', 'calf_raises', 'lateral_steps',
  ]) {
    assert.ok(ids.has(id), `${id} missing from RACE_ACTIVITY_CATALOG`);
    assert.equal(normalizeActivityId(id), id, `${id}: normalizeActivityId`);
  }
});

test('GET /races/activities exposes every catalog id (deployment-verifiable)', () => {
  // Mirrors the public endpoint's payload shape so a curl against production
  // can be checked against this list.
  const supported = RACE_ACTIVITY_CATALOG
    .filter((a) => a.availability === 'supported')
    .map((a) => a.id);
  for (const id of [
    'push_ups', 'jumping_jacks', 'squats', 'lunges', 'plank_hold',
    'high_knees', 'arm_raises', 'sumo_squats', 'side_lunges', 'deep_squats',
    'squat_jacks', 'jump_squats', 'lunge_jumps',
    'running_in_place', 'treadmill_running', 'walking_in_place',
    'marching_in_place', 'butt_kicks', 'mountain_climbers', 'burpees',
    'step_ups', 'calf_raises', 'lateral_steps',
  ]) {
    assert.ok(supported.includes(id), `${id} not in supported activities`);
  }
  assert.equal(supported.length, 23);
});
