import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  manualConfigFromBody,
  configFromBody,
  MANUAL_VERIFIER_TYPE,
} = require('../.tmp-test-dist/domain/raceValidation.js');
const { applyVerifiedSubmission } = require('../.tmp-test-dist/domain/raceScoring.js');

// The client's _manualCreatePayload shape.
const manualBody = (over = {}) => ({
  title: 'Read 100 pages',
  goalType: 'first_to_goal',
  targetValue: 100,
  unit: 'pages',
  targetUnit: 'pages',
  metric: 'reps',
  format: 'first_to_goal',
  recurrence: 'none',
  proofRequirement: 'manual',
  proofMode: 'manual',
  visibility: 'private',
  ...over,
});

test('manualConfigFromBody accepts an honor-logged goal', () => {
  const c = manualConfigFromBody(manualBody());
  assert.ok(c && !('error' in c));
  assert.equal(c.verifierType, MANUAL_VERIFIER_TYPE);
  assert.equal(c.metric, 'reps'); // wire metric
  assert.equal(c.unit, 'pages'); // display unit preserved
  assert.equal(c.targetValue, 100);
  assert.equal(c.format, 'first_to_goal');
  assert.equal(c.scoringRule, 'cumulative_sum');
});

test('manualConfigFromBody requires a goal amount', () => {
  const c = manualConfigFromBody(manualBody({ targetValue: 0 }));
  assert.ok(c && 'error' in c);
});

test('manualConfigFromBody ignores a preset-activity body (returns null)', () => {
  assert.equal(
    manualConfigFromBody({ activityId: 'push_ups', proofRequirement: 'ai_check', targetValue: 25 }),
    null,
  );
});

test('manualConfigFromBody ignores a custom-verifier body (returns null)', () => {
  assert.equal(
    manualConfigFromBody({ verifierType: 'custom_pose_sequence', targetValue: 10, proofMode: 'manual' }),
    null,
  );
});

test('a preset body still routes to configFromBody, not manual', () => {
  assert.equal(manualConfigFromBody({ activityId: 'squats', proofRequirement: 'ai_check', targetValue: 20 }), null);
  const preset = configFromBody({ activityId: 'squats', metric: 'reps', format: 'first_to_goal', targetValue: 20 });
  assert.ok(!('error' in preset));
});

test('manual progress accumulates and completes at the goal', () => {
  const s1 = applyVerifiedSubmission({
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    previousScore: 0,
    submissionValue: 40,
    targetValue: 100,
  });
  assert.equal(s1.newScore, 40);
  assert.equal(s1.completed, false);
  const s2 = applyVerifiedSubmission({
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    previousScore: 40,
    submissionValue: 65,
    targetValue: 100,
  });
  assert.equal(s2.newScore, 105);
  assert.equal(s2.completed, true);
});

test('daily_check / note / link proof requirements also read as manual', () => {
  for (const proofRequirement of ['daily_check', 'note', 'link', 'photo_video']) {
    const c = manualConfigFromBody(manualBody({ proofRequirement, proofMode: proofRequirement }));
    assert.ok(c && !('error' in c), proofRequirement);
    assert.equal(c.verifierType, MANUAL_VERIFIER_TYPE);
  }
});
