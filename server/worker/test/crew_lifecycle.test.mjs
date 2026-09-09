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

test('canSeeIdentity — private profile hidden until connected', () => {
  assert.equal(canSeeIdentity(ME, ME, true, 'connected'), true); // self always
  assert.equal(canSeeIdentity(ME, YOU, false, 'none'), true); // public
  assert.equal(canSeeIdentity(ME, YOU, true, 'none'), false); // private stranger
  assert.equal(canSeeIdentity(ME, YOU, true, 'pending_incoming'), false); // still hidden
  assert.equal(canSeeIdentity(ME, YOU, true, 'connected'), true); // now visible
});

test('connectResult — public = immediate active, private = pending both sides', () => {
  assert.deepEqual(connectResult(false), { mine: 'active', theirs: 'active', outcome: 'active' });
  assert.deepEqual(connectResult(true), { mine: 'pending', theirs: 'pending', outcome: 'pending' });
});
