import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { decideSessionAction, parseInlineSessionResult, inlineResultIsValid } =
  require('../.tmp-test-dist/domain/proofSession.js');

const rel = { releaseId: 'r1', releaseChecksum: 'c1' };
const inline = (o = {}) => ({ releaseId: 'r1', releaseChecksum: 'c1', resultValue: 5, confidence: null, motionSessionId: null, ...o });
const base = (o = {}) => ({
  sessionStatus: 'completed', sessionResultValue: 5, increment: 5,
  existingLogFound: false, existingLogClientSubmissionId: null,
  requestClientSubmissionId: 'a', inlineResult: null, sessionRelease: rel, ...o,
});

test('no session row is not_found', () => {
  assert.equal(decideSessionAction(base({ sessionStatus: null })), 'not_found');
});
test('completed session covering the claim is ok', () => {
  assert.equal(decideSessionAction(base()), 'ok');
  assert.equal(decideSessionAction(base({ sessionResultValue: 9 })), 'ok');
});
test('completed session below the claim is mismatch', () => {
  assert.equal(decideSessionAction(base({ sessionResultValue: 4 })), 'mismatch');
  assert.equal(decideSessionAction(base({ sessionResultValue: null })), 'mismatch');
});
test('created/running without inline result is mismatch (legacy behaviour)', () => {
  assert.equal(decideSessionAction(base({ sessionStatus: 'created' })), 'mismatch');
  assert.equal(decideSessionAction(base({ sessionStatus: 'running' })), 'mismatch');
  assert.equal(decideSessionAction(base({ sessionStatus: 'failed' })), 'mismatch');
});
test('valid inline result completes created and running sessions', () => {
  for (const sessionStatus of ['created', 'running']) {
    assert.equal(decideSessionAction(base({ sessionStatus, sessionResultValue: null, inlineResult: inline() })), 'complete_inline');
  }
  assert.equal(decideSessionAction(base({ sessionStatus: 'created', sessionResultValue: null, inlineResult: inline({ resultValue: 8 }) })), 'complete_inline');
});
test('invalid inline results fall back to mismatch', () => {
  const s = { sessionStatus: 'created', sessionResultValue: null };
  for (const bad of [
    inline({ releaseId: 'other' }),
    inline({ releaseChecksum: 'other' }),
    inline({ resultValue: 4 }),
    inline({ resultValue: 5.5 }),
    inline({ resultValue: NaN }),
    inline({ resultValue: Infinity }),
  ]) {
    assert.equal(decideSessionAction(base({ ...s, inlineResult: bad })), 'mismatch');
  }
});
test('inline result never overwrites a completed or failed session', () => {
  assert.equal(decideSessionAction(base({ sessionResultValue: 3, inlineResult: inline({ resultValue: 50 }) })), 'mismatch');
  assert.equal(decideSessionAction(base({ sessionStatus: 'failed', inlineResult: inline() })), 'mismatch');
  assert.equal(decideSessionAction(base({ inlineResult: inline() })), 'ok');
});
test('used session with same clientSubmissionId replays', () => {
  assert.equal(decideSessionAction(base({ existingLogFound: true, existingLogClientSubmissionId: 'a' })), 'replay');
});
test('used session with different or missing clientSubmissionId stays reused', () => {
  assert.equal(decideSessionAction(base({ existingLogFound: true, existingLogClientSubmissionId: 'b' })), 'reused');
  assert.equal(decideSessionAction(base({ existingLogFound: true, existingLogClientSubmissionId: null })), 'reused');
  assert.equal(decideSessionAction(base({ existingLogFound: true, existingLogClientSubmissionId: 'a', requestClientSubmissionId: null })), 'reused');
});
test('parseInlineSessionResult shape handling', () => {
  assert.equal(parseInlineSessionResult(undefined), null);
  assert.equal(parseInlineSessionResult([]), null);
  assert.equal(parseInlineSessionResult({ releaseId: 'r1' }), null);
  assert.equal(parseInlineSessionResult({ releaseId: 'r1', releaseChecksum: 'c1', resultValue: '5' }), null);
  const p = parseInlineSessionResult({ releaseId: ' r1 ', releaseChecksum: 'c1', resultValue: 5, confidence: 2, motionSessionId: 'm' });
  assert.deepEqual(p, { releaseId: 'r1', releaseChecksum: 'c1', resultValue: 5, confidence: 1, motionSessionId: 'm' });
  assert.equal(inlineResultIsValid(p, rel, 5), true);
  assert.equal(inlineResultIsValid(null, rel, 5), false);
});
