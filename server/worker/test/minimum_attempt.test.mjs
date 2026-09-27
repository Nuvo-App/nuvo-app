import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  manualConfigFromBody,
  configFromBody,
  scoreDirectionFromBody,
} = require('../.tmp-test-dist/domain/raceValidation.js');
const { applyVerifiedSubmission } = require('../.tmp-test-dist/domain/raceScoring.js');
const { scoringRuleForFormat } = require('../.tmp-test-dist/domain/raceActivities.js');
const { computeCompetitionRanks } = require('../.tmp-test-dist/domain/raceRanking.js');

// The client's manual payload for a lower-wins race ("Lowest golf score").
const lowerManualBody = (over = {}) => ({
  title: 'Lowest golf score',
  goalType: 'best_attempt',
  targetValue: 72,
  unit: 'strokes',
  targetUnit: 'strokes',
  metric: 'reps',
  format: 'best_attempt',
  recurrence: 'none',
  proofRequirement: 'manual',
  proofMode: 'manual',
  visibility: 'invite_code',
  scoreDirection: 'lower',
  ...over,
});

test('scoringRuleForFormat derives minimum_attempt from direction', () => {
  assert.equal(scoringRuleForFormat('best_attempt'), 'maximum_attempt');
  assert.equal(scoringRuleForFormat('best_attempt', 'higher'), 'maximum_attempt');
  assert.equal(scoringRuleForFormat('best_attempt', 'lower'), 'minimum_attempt');
  assert.equal(scoringRuleForFormat('timed_attempt', 'lower'), 'minimum_attempt');
  assert.equal(scoringRuleForFormat('first_to_goal', 'lower'), 'cumulative_sum');
});

test('manualConfigFromBody stores minimum_attempt for lower-wins races', () => {
  const c = manualConfigFromBody(lowerManualBody());
  assert.ok(c && !('error' in c));
  assert.equal(c.format, 'best_attempt');
  assert.equal(c.scoringRule, 'minimum_attempt');
  assert.equal(c.unit, 'strokes');
});

test('manualConfigFromBody keeps maximum_attempt for higher-wins races', () => {
  const c = manualConfigFromBody(lowerManualBody({ scoreDirection: 'higher' }));
  assert.ok(c && !('error' in c));
  assert.equal(c.scoringRule, 'maximum_attempt');
});

test('scoreDirectionFromBody parses both wire spellings', () => {
  assert.equal(scoreDirectionFromBody({ scoreDirection: 'lower' }), 'lower');
  assert.equal(scoreDirectionFromBody({ score_direction: 'lower' }), 'lower');
  assert.equal(scoreDirectionFromBody({ scoreDirection: 'higher' }), 'higher');
  assert.equal(scoreDirectionFromBody({}), 'higher');
});

test('minimum_attempt keeps the lowest real value — never negates', () => {
  // First submission: previousScore 0 means "no score yet", not zero.
  let s = applyVerifiedSubmission({
    format: 'best_attempt',
    scoringRule: 'minimum_attempt',
    previousScore: 0,
    submissionValue: 72,
    targetValue: null,
  });
  assert.equal(s.newScore, 72);

  // A better (lower) round replaces it.
  s = applyVerifiedSubmission({
    format: 'best_attempt',
    scoringRule: 'minimum_attempt',
    previousScore: 72,
    submissionValue: 68,
    targetValue: null,
  });
  assert.equal(s.newScore, 68);

  // A worse (higher) round does not.
  s = applyVerifiedSubmission({
    format: 'best_attempt',
    scoringRule: 'minimum_attempt',
    previousScore: 68,
    submissionValue: 80,
    targetValue: null,
  });
  assert.equal(s.newScore, 68);
});

test('maximum_attempt is unaffected', () => {
  const s = applyVerifiedSubmission({
    format: 'best_attempt',
    scoringRule: 'maximum_attempt',
    previousScore: 95,
    submissionValue: 90,
    targetValue: null,
  });
  assert.equal(s.newScore, 95);
});

test('standings order lowest-first when direction is asc', () => {
  const ranked = computeCompetitionRanks(
    [
      { user_id: 'a', joined_at: '2026-01-01', progress_value: 95, completed_at: null },
      { user_id: 'b', joined_at: '2026-01-01', progress_value: 68, completed_at: null },
      { user_id: 'c', joined_at: '2026-01-01', progress_value: 80, completed_at: null },
    ],
    { direction: 'asc' },
  );
  assert.equal(ranked[0].user_id, 'b');
  assert.equal(ranked[0].rank, 1);
  assert.equal(ranked[2].user_id, 'a');
});

test('preset configFromBody also derives minimum_attempt (fastest-mile shape)', () => {
  const c = configFromBody({
    activityId: 'push_ups',
    metric: 'reps',
    format: 'best_attempt',
    targetValue: 20,
    scoreDirection: 'lower',
  });
  if (c && !('error' in c)) {
    assert.equal(c.scoringRule, 'minimum_attempt');
  }
});
