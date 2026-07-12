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
} = require('../.tmp-test-dist/domain/raceValidation.js');

test('first-to-goal supports arbitrary cumulative targets', () => {
  const first = applyVerifiedSubmission({
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    previousScore: 0,
    submissionValue: 4,
    targetValue: 6,
  });
  assert.deepEqual(first, {
    newScore: 4,
    progressPercent: 67,
    completed: false,
  });

  const second = applyVerifiedSubmission({
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    previousScore: first.newScore,
    submissionValue: 3,
    targetValue: 6,
  });
  assert.deepEqual(second, {
    newScore: 7,
    progressPercent: 100,
    completed: true,
  });
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

test('activity and metric normalization do not fall back to jumping jacks', () => {
  assert.equal(normalizeActivityId('pushups'), 'push_ups');
  assert.equal(normalizeActivityId('jumping jacks'), 'jumping_jacks');
  assert.equal(normalizeActivityId('burpees'), undefined);
  assert.equal(normalizeMetric('pushups', activityForId('push_ups')), 'reps');
  assert.equal(normalizeMetric('seconds', activityForId('plank_hold')), 'seconds');
});

test('validation rejects unsupported activities and invalid combinations', () => {
  assert.deepEqual(configFromBody({
    activityId: 'burpees',
    metric: 'reps',
    format: 'first_to_goal',
    targetValue: 10,
  }), { error: 'Choose a supported activity.' });

  assert.deepEqual(configFromBody({
    activityId: 'plank_hold',
    metric: 'reps',
    format: 'first_to_goal',
    targetValue: 60,
  }), { error: 'Plank cannot use that metric.' });

  const valid = configFromBody({
    activityId: 'squats',
    metric: 'reps',
    format: 'first_to_goal',
    targetValue: 15,
  });
  assert.equal('error' in valid, false);
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
  assert.equal(
    assertSubmissionCompatible(config, 'squats', 'reps'),
    'Verified movement does not match this race.',
  );
  assert.equal(
    assertSubmissionCompatible(config, 'push_ups', 'seconds'),
    'Verified metric does not match this race.',
  );
});

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
