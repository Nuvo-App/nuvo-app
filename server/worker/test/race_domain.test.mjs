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
  assert.equal(normalizeActivityId('burpees'), undefined);
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
  assert.deepEqual(configFromBody({ activityId: 'burpees', metric: 'reps', format: 'first_to_goal', targetValue: 10 }), { error: 'Choose a supported activity.' });
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
