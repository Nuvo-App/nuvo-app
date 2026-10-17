import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { raceHasFinishLine, effectiveTargetValue } = require('../.tmp-test-dist/domain/raceTarget.js');
const { applyVerifiedSubmission } = require('../.tmp-test-dist/domain/raceScoring.js');

test('only a race to a goal has a finish line', () => {
  assert.equal(raceHasFinishLine('first_to_goal'), true);
  assert.equal(raceHasFinishLine('first_to_target'), true);
  assert.equal(raceHasFinishLine(null), true);
  assert.equal(raceHasFinishLine('most_in_window'), false);
  assert.equal(raceHasFinishLine('timed_attempt'), false);
  assert.equal(raceHasFinishLine('best_attempt'), false);
});

test('placeholder targets on window / attempt races are never exposed', () => {
  assert.equal(effectiveTargetValue('most_in_window', 60), null);
  assert.equal(effectiveTargetValue('timed_attempt', 1), null);
  assert.equal(effectiveTargetValue('first_to_goal', 60), 60);
  assert.equal(effectiveTargetValue('first_to_goal', 0), null);
  assert.equal(effectiveTargetValue('first_to_goal', null), null);
});

test('a most-in-window race has no progress percent and never completes at a stored target', () => {
  const out = applyVerifiedSubmission({
    format: 'most_in_window',
    scoringRule: 'cumulative_sum',
    previousScore: 55,
    submissionValue: 10,
    targetValue: 60,
  });
  assert.equal(out.newScore, 65);
  assert.equal(out.progressPercent, 0);
  assert.equal(out.completed, false);
});

test('first to goal still completes at the target', () => {
  const out = applyVerifiedSubmission({
    format: 'first_to_goal',
    scoringRule: 'cumulative_sum',
    previousScore: 55,
    submissionValue: 10,
    targetValue: 60,
  });
  assert.equal(out.progressPercent, 100);
  assert.equal(out.completed, true);
});

const { validateRaceWindow } = require('../.tmp-test-dist/domain/raceValidation.js');

test('finish line: most_in_window requires one; attempt races get a default instead of a refusal', () => {
  const now = new Date('2026-01-01T00:00:00.000Z');
  assert.equal(validateRaceWindow('most_in_window', null, null, now).endsAt, '2026-01-08T00:00:00.000Z');
  const timed = validateRaceWindow('timed_attempt', null, null, now);
  assert.equal(timed.endsAt, '2026-01-02T00:00:00.000Z');
  const best = validateRaceWindow('best_attempt', null, null, now);
  assert.equal(best.endsAt, '2026-01-08T00:00:00.000Z');
  // an explicit finish line still wins, and a past one is still refused
  assert.equal(validateRaceWindow('best_attempt', null, '2026-02-01T00:00:00Z', now).endsAt, '2026-02-01T00:00:00.000Z');
  assert.ok(validateRaceWindow('best_attempt', null, '2025-12-01T00:00:00Z', now).error);
  // first to goal has no window at all
  assert.equal(validateRaceWindow('first_to_goal', null, null, now).endsAt, null);
});
