import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  decryptMotionBytes,
  encryptMotionBytes,
  isMotionEncryptionEnvelope,
  motionAccountRef,
} = require('../.tmp-test-dist/lib/motion_privacy.js');

test('motion account references are keyed and do not expose the account id', async () => {
  const first = await motionAccountRef('master-secret', 'user-42');
  const repeat = await motionAccountRef('master-secret', 'user-42');
  const other = await motionAccountRef('master-secret', 'user-43');
  assert.equal(first, repeat);
  assert.notEqual(first, other);
  assert.equal(first.includes('user-42'), false);
});

test('motion artifacts are encrypted and round-trip with the account key', async () => {
  const key = new Uint8Array(32).fill(7);
  const plaintext = new TextEncoder().encode('normalized body landmark stream');
  const envelope = await encryptMotionBytes(key, plaintext);

  assert.equal(isMotionEncryptionEnvelope(envelope), true);
  assert.notDeepEqual(Array.from(envelope), Array.from(plaintext));
  assert.deepEqual(
    Array.from(await decryptMotionBytes(key, envelope)),
    Array.from(plaintext),
  );
});

test('motion envelopes cannot be decrypted with another account key', async () => {
  const envelope = await encryptMotionBytes(
    new Uint8Array(32).fill(1),
    new TextEncoder().encode('private motion data'),
  );
  await assert.rejects(
    decryptMotionBytes(new Uint8Array(32).fill(2), envelope),
  );
});
