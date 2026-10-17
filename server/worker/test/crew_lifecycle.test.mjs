import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { crewConnectionStatus, canSeeIdentity, connectResult } = require(
  '../.tmp-test-dist/domain/crewLifecycle.js',
);

const ME = 'me';
const YOU = 'you';

test('crewConnectionStatus — the lifecycle', () => {
  assert.equal(crewConnectionStatus(ME, ME, null), 'connected'); // self
  assert.equal(crewConnectionStatus(ME, YOU, null), 'none');
  assert.equal(crewConnectionStatus(ME, YOU, { status: 'active', requested_by: YOU }), 'connected');
  assert.equal(
    crewConnectionStatus(ME, YOU, { status: 'pending', requested_by: ME }),
    'pending_outgoing',
  );
  assert.equal(
    crewConnectionStatus(ME, YOU, { status: 'pending', requested_by: YOU }),
    'pending_incoming',
  );
  assert.equal(crewConnectionStatus(ME, YOU, { status: 'removed', requested_by: ME }), 'none');
  assert.equal(crewConnectionStatus(ME, YOU, { status: 'declined', requested_by: YOU }), 'none');
});

test('canSeeIdentity — everyone is visible (no private profiles)', () => {
  assert.equal(canSeeIdentity(ME, ME, false, 'connected'), true); // self always
  assert.equal(canSeeIdentity(ME, YOU, false, 'none'), true);
  assert.equal(canSeeIdentity(ME, YOU, true, 'none'), true); // legacy flag ignored
  assert.equal(canSeeIdentity(ME, YOU, true, 'pending_incoming'), true);
  assert.equal(canSeeIdentity(ME, YOU, true, 'connected'), true);
});

test('connectResult — every add is a pending request on both sides', () => {
  const pending = { mine: 'pending', theirs: 'pending', outcome: 'pending' };
  assert.deepEqual(connectResult(), pending);
  assert.deepEqual(connectResult(false), pending);
  assert.deepEqual(connectResult(true), pending);
});
