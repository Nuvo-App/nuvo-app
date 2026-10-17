import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { computeRecord } = require('../.tmp-test-dist/domain/profileRecord.js');

const U = 'u1';
const row = (status, winnerUserId = null, hasRankOne = false) => ({ status, winnerUserId, hasRankOne });

test('empty', () => {
  assert.deepEqual(computeRecord([], U), { active: 0, finished: 0, wins: 0, winRatePercent: null });
});

test('only active races: null win rate', () => {
  assert.deepEqual(computeRecord([row('active'), row('active'), row('scheduled')], U), {
    active: 2, finished: 0, wins: 0, winRatePercent: null,
  });
});

test('mixed finished with wins', () => {
  const r = computeRecord([row('completed', U), row('completed', 'other'), row('active'), row('archived', U)], U);
  assert.deepEqual(r, { active: 1, finished: 3, wins: 2, winRatePercent: 67 });
});

test('tied for first: winner null but rank 1 is a win', () => {
  const r = computeRecord([row('completed', null, true)], U);
  assert.deepEqual(r, { active: 0, finished: 1, wins: 1, winRatePercent: 100 });
});

test('cancelled races never count as wins (still finished, like the client)', () => {
  const r = computeRecord([row('cancelled', U, true), row('completed', U)], U);
  assert.deepEqual(r, { active: 0, finished: 2, wins: 1, winRatePercent: 50 });
});

test('rounding', () => {
  assert.equal(computeRecord([row('completed', U), row('completed'), row('completed')], U).winRatePercent, 33);
  assert.equal(
    computeRecord([row('completed', U), row('completed', U), row('completed')], U).winRatePercent,
    67,
  );
});
