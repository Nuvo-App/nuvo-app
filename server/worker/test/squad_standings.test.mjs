import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { computeSquadStandings, placementPoints } = require(
  '../.tmp-test-dist/domain/squadStandings.js',
);

const score = (user_id, progress_value, joined_at = '2026-01-01T00:00:00Z', completed_at = null) => ({
  user_id,
  progress_value,
  joined_at,
  completed_at,
});

test('placementPoints — podium then participation', () => {
  assert.deepEqual([1, 2, 3, 4, 9].map(placementPoints), [5, 3, 2, 1, 1]);
});

test('standings sum placement points across races', () => {
  const rows = computeSquadStandings(['a', 'b', 'c'], [
    { raceId: 'r1', direction: 'higher', scores: [score('a', 30), score('b', 20), score('c', 10)] },
    { raceId: 'r2', direction: 'higher', scores: [score('a', 1), score('b', 50), score('c', 5)] },
  ]);
  const byUser = Object.fromEntries(rows.map((r) => [r.user_id, r]));
  assert.equal(byUser.a.points, 5 + 2);
  assert.equal(byUser.b.points, 3 + 5);
  assert.equal(byUser.b.wins, 1);
  assert.equal(rows[0].user_id, 'b');
  assert.equal(rows[0].rank, 1);
});

test('members with no proof earn nothing but still appear', () => {
  const rows = computeSquadStandings(['a', 'b'], [
    { raceId: 'r1', direction: 'higher', scores: [score('a', 10), score('b', 0)] },
  ]);
  assert.equal(rows.find((r) => r.user_id === 'b').points, 0);
  assert.equal(rows.find((r) => r.user_id === 'b').races, 0);
});

test('lower-wins races rank the fastest first', () => {
  const rows = computeSquadStandings(['a', 'b'], [
    { raceId: 'r1', direction: 'lower', scores: [score('a', 90), score('b', 60)] },
  ]);
  assert.equal(rows.find((r) => r.user_id === 'b').wins, 1);
});

test('tied crew totals share a rank', () => {
  const rows = computeSquadStandings(['a', 'b'], []);
  assert.deepEqual(rows.map((r) => r.rank), [1, 1]);
});
