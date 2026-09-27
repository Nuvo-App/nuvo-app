import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);

const {
  DEADLINE_GRACE_MS,
  deadlineEligibility,
  lockedFieldsPresent,
  rulesLocked,
  formatFinalizesOnDeadline,
  scoreDirectionFor,
} = require('../.tmp-test-dist/domain/raceFinalize.js');
const { computeCompetitionRanks } = require('../.tmp-test-dist/domain/raceRanking.js');
const { computeViewerContext } = require('../.tmp-test-dist/domain/raceContext.js');
const { formatUsesAttempts, ATTEMPT_SUBMIT_GRACE_MS } = require('../.tmp-test-dist/domain/raceAttempts.js');

// ── deadlineEligibility ──────────────────────────────────────────────────────

test('submission inside the window is always eligible', () => {
  const race = { status: 'active', start_at: '2026-09-20T00:00:00Z', end_at: '2026-09-30T00:00:00Z' };
  const received = new Date('2026-09-25T00:00:00Z');
  assert.equal(deadlineEligibility(race, null, received), 'active');
  assert.equal(deadlineEligibility(race, new Date('2026-09-24T00:00:00Z'), received), 'active');
});

test('scheduled race rejects submissions before the start line', () => {
  const race = { status: 'active', start_at: '2026-09-26T00:00:00Z', end_at: null };
  const received = new Date('2026-09-25T00:00:00Z');
  assert.equal(deadlineEligibility(race, null, received), 'closed');
});

test('proof captured before the deadline survives inside the grace window', () => {
  const race = { status: 'active', start_at: null, end_at: '2026-09-25T00:00:00Z' };
  const captured = new Date('2026-09-24T23:59:00Z');
  const received = new Date('2026-09-25T02:00:00Z'); // 2h after deadline
  assert.equal(deadlineEligibility(race, captured, received), 'grace');
});

test('late proof without a capture timestamp is closed', () => {
  const race = { status: 'active', start_at: null, end_at: '2026-09-25T00:00:00Z' };
  const received = new Date('2026-09-25T02:00:00Z');
  assert.equal(deadlineEligibility(race, null, received), 'closed');
});

test('capture timestamp cannot be forged beyond the grace window', () => {
  const race = { status: 'active', start_at: null, end_at: '2026-09-25T00:00:00Z' };
  const captured = new Date('2026-09-24T23:00:00Z');
  const received = new Date('2026-09-27T00:00:01Z'); // past end + 24h
  assert.equal(deadlineEligibility(race, captured, received), 'closed');
});

test('capturedAt after receive time is rejected (clock forgery)', () => {
  const race = { status: 'active', start_at: null, end_at: '2026-09-25T00:00:00Z' };
  const captured = new Date('2026-09-26T00:00:00Z');
  const received = new Date('2026-09-25T01:00:00Z');
  assert.equal(deadlineEligibility(race, captured, received), 'closed');
});

// ── rulesLocked / lockedFieldsPresent ────────────────────────────────────────

test('rules lock once any verified proof exists', () => {
  assert.equal(
    rulesLocked({ startAt: null, hasVerifiedMoves: true, now: new Date('2026-09-24') }),
    true,
  );
});

test('rules lock when a scheduled start line has passed', () => {
  assert.equal(
    rulesLocked({ startAt: '2026-09-20T00:00:00Z', hasVerifiedMoves: false, now: new Date('2026-09-24') }),
    true,
  );
});

test('rules stay editable for a future start line with no proof', () => {
  assert.equal(
    rulesLocked({ startAt: '2026-09-30T00:00:00Z', hasVerifiedMoves: false, now: new Date('2026-09-24') }),
    false,
  );
});

test('rules stay editable pre-proof for an unscheduled race', () => {
  assert.equal(
    rulesLocked({ startAt: null, hasVerifiedMoves: false, now: new Date('2026-09-24') }),
    false,
  );
});

test('locked field detection matches wire names the PATCH accepts', () => {
  assert.deepEqual(lockedFieldsPresent({ targetValue: 100, title: 'ok' }), ['targetValue']);
  assert.deepEqual(lockedFieldsPresent({ finishLineAt: 'x', startLineAt: 'y' }), ['startLineAt', 'finishLineAt']);
  assert.deepEqual(lockedFieldsPresent({ title: 'x', description: 'y', visibility: 'crew_only' }), []);
});

// ── format helpers ───────────────────────────────────────────────────────────

test('attempt formats are exactly best_attempt and timed_attempt', () => {
  assert.equal(formatUsesAttempts('best_attempt'), true);
  assert.equal(formatUsesAttempts('timed_attempt'), true);
  assert.equal(formatUsesAttempts('first_to_goal'), false);
  assert.equal(formatUsesAttempts('most_in_window'), false);
});

test('deadline finalization applies to windowed + attempt + first-to-goal formats', () => {
  assert.equal(formatFinalizesOnDeadline('most_in_window'), true);
  assert.equal(formatFinalizesOnDeadline('best_attempt'), true);
  assert.equal(formatFinalizesOnDeadline('timed_attempt'), true);
  assert.equal(formatFinalizesOnDeadline('first_to_goal'), true);
});

test('score direction defaults to higher unless explicitly lower', () => {
  assert.equal(scoreDirectionFor({ score_direction: 'lower' }), 'lower');
  assert.equal(scoreDirectionFor({ score_direction: 'higher' }), 'higher');
  assert.equal(scoreDirectionFor({}), 'higher');
});

// ── computeCompetitionRanks direction ────────────────────────────────────────

test('desc ranking: highest score wins, ties share rank', () => {
  const ranked = computeCompetitionRanks([
    { user_id: 'a', progress_value: 80, completed_at: null, joined_at: '2026-01-01' },
    { user_id: 'b', progress_value: 80, completed_at: null, joined_at: '2026-01-02' },
    { user_id: 'c', progress_value: 40, completed_at: null, joined_at: '2026-01-03' },
  ]);
  assert.deepEqual(
    ranked.map((r) => [r.user_id, r.rank]),
    [['a', 1], ['b', 1], ['c', 3]],
  );
});

test('asc ranking: lowest nonzero wins; zero scores rank last', () => {
  const ranked = computeCompetitionRanks(
    [
      { user_id: 'fast', progress_value: 382, completed_at: null, joined_at: '2026-01-01' },
      { user_id: 'slow', progress_value: 450, completed_at: null, joined_at: '2026-01-02' },
      { user_id: 'unplayed', progress_value: 0, completed_at: null, joined_at: '2026-01-03' },
    ],
    { direction: 'asc' },
  );
  assert.deepEqual(
    ranked.map((r) => [r.user_id, r.rank]),
    [['fast', 1], ['slow', 2], ['unplayed', 3]],
  );
});

// ── computeViewerContext ─────────────────────────────────────────────────────

function ctxInput(overrides = {}) {
  return {
    raceId: 'r1',
    format: 'most_in_window',
    targetValue: null,
    startAt: null,
    endAt: '2026-09-28T00:00:00Z',
    storedStatus: 'active',
    winnerUserId: null,
    scoreDirection: 'higher',
    attemptLimit: null,
    attemptDurationSeconds: null,
    standings: [
      { userId: 'riley', score: 82, rank: 1 },
      { userId: 'me', score: 67, rank: 2 },
      { userId: 'maya', score: 41, rank: 3 },
    ],
    attemptsUsed: 0,
    openAttemptId: null,
    viewerUserId: 'me',
    now: new Date('2026-09-24T20:00:00Z'),
    ...overrides,
  };
}

test('viewer context reports rank, gaps, and leader', () => {
  const ctx = computeViewerContext(ctxInput());
  assert.equal(ctx.rank, 2);
  assert.equal(ctx.gapToLeader, 15);
  assert.equal(ctx.gapToNextRank, 15);
  assert.equal(ctx.leaderUserId, 'riley');
  assert.equal(ctx.isLeading, false);
  assert.equal(ctx.isMember, true);
  assert.equal(ctx.isSpectator, false);
});

test('leader sees isLeading and zero gap', () => {
  const ctx = computeViewerContext(ctxInput({ viewerUserId: 'riley' }));
  assert.equal(ctx.isLeading, true);
  assert.equal(ctx.gapToLeader, null);
  assert.equal(ctx.gapToNextRank, null);
});

test('goal remaining counts down toward the target', () => {
  const ctx = computeViewerContext(ctxInput({ format: 'first_to_goal', targetValue: 100 }));
  assert.equal(ctx.goalRemaining, 33);
  assert.equal(ctx.isFinished, false);
});

test('viewer past the goal is finished', () => {
  const ctx = computeViewerContext(
    ctxInput({
      format: 'first_to_goal',
      targetValue: 60,
      viewerUserId: 'me',
    }),
  );
  assert.equal(ctx.isFinished, true);
  assert.equal(ctx.goalRemaining, 0);
});

test('time remaining and starts-in derive from server timestamps', () => {
  const ctx = computeViewerContext(ctxInput());
  assert.equal(ctx.timeRemainingSeconds, 3 * 24 * 3600 + 4 * 3600);
  const scheduled = computeViewerContext(
    ctxInput({ startAt: '2026-09-25T00:00:00Z', endAt: null }),
  );
  assert.equal(scheduled.startsInSeconds, 4 * 3600);
  assert.equal(scheduled.status, 'scheduled');
});

test('attempt fields flow through for attempt races', () => {
  const ctx = computeViewerContext(
    ctxInput({ format: 'timed_attempt', attemptLimit: 3, attemptsUsed: 2, openAttemptId: 'a1' }),
  );
  assert.equal(ctx.attemptsUsed, 2);
  assert.equal(ctx.attemptsRemaining, 1);
  assert.equal(ctx.openAttemptId, 'a1');
});

test('spectator viewer is flagged without membership', () => {
  const ctx = computeViewerContext(ctxInput({ viewerUserId: 'outsider' }));
  assert.equal(ctx.isMember, false);
  assert.equal(ctx.isSpectator, true);
  assert.equal(ctx.rank, null);
});

test('tied scores flag isTied', () => {
  const ctx = computeViewerContext(
    ctxInput({
      standings: [
        { userId: 'riley', score: 67, rank: 1 },
        { userId: 'me', score: 67, rank: 1 },
      ],
    }),
  );
  assert.equal(ctx.isTied, true);
});

test('constants are sane', () => {
  assert.ok(DEADLINE_GRACE_MS > 0);
  assert.ok(ATTEMPT_SUBMIT_GRACE_MS > 0);
});
