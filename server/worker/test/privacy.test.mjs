import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { resolveRaceMemberVisibility } = require('../.tmp-test-dist/lib/privacy.js');

const empty = { crewIds: new Set(), blockedEitherWay: new Set(), coRacerIds: new Set() };
const target = (over = {}) => ({
  userId: 'u2',
  displayName: 'Riley Chen',
  username: 'riley',
  profilePhotoUrl: 'https://x/p.jpg',
  ...over,
});

test('public user shows real name + photo', () => {
  const v = resolveRaceMemberVisibility('u1', target(), empty);
  assert.equal(v.displayName, 'Riley Chen');
  assert.equal(v.profilePhotoUrl, 'https://x/p.jpg');
  assert.equal(v.anonymized, false);
});

test('a stranger with no shared context shows real name + photo (no private profiles)', () => {
  const v = resolveRaceMemberVisibility('u1', target(), empty);
  assert.equal(v.displayName, 'Riley Chen');
  assert.equal(v.profilePhotoUrl, 'https://x/p.jpg');
  assert.equal(v.anonymized, false);
});

test('a legacy privateProfile flag on the target is ignored', () => {
  const v = resolveRaceMemberVisibility('u1', target(), empty);
  assert.equal(v.displayName, 'Riley Chen');
  assert.equal(v.anonymized, false);
});

test('a CO-RACER shows race identity', () => {
  const v = resolveRaceMemberVisibility('u1', target(), {
    ...empty,
    coRacerIds: new Set(['u2']),
  });
  assert.equal(v.displayName, 'Riley Chen');
  assert.equal(v.profilePhotoUrl, 'https://x/p.jpg');
  assert.equal(v.anonymized, false);
});

test('a CREW member shows race identity', () => {
  const v = resolveRaceMemberVisibility('u1', target(), {
    ...empty,
    crewIds: new Set(['u2']),
  });
  assert.equal(v.displayName, 'Riley Chen');
});

test('blocked is anonymized even with no other context', () => {
  const v = resolveRaceMemberVisibility('u1', target(), { ...empty, blockedEitherWay: new Set(['u2']) });
  assert.equal(v.displayName, 'Private User');
  assert.equal(v.profilePhotoUrl, null);
  assert.equal(v.anonymized, true);
});

test('blocked wins over co-racer', () => {
  const v = resolveRaceMemberVisibility('u1', target(), {
    ...empty,
    coRacerIds: new Set(['u2']),
    blockedEitherWay: new Set(['u2']),
  });
  assert.equal(v.displayName, 'Private User');
  assert.equal(v.anonymized, true);
});

test('self is never anonymized', () => {
  const v = resolveRaceMemberVisibility('u2', target(), empty);
  assert.equal(v.displayName, 'Riley Chen');
});

test('no viewer (public list) shows real name', () => {
  const v = resolveRaceMemberVisibility(undefined, target(), empty);
  assert.equal(v.displayName, 'Riley Chen');
});

test('missing name falls back to username, then Nuvo member', () => {
  assert.equal(
    resolveRaceMemberVisibility('u1', target({ displayName: null }), empty).displayName,
    'riley',
  );
  assert.equal(
    resolveRaceMemberVisibility('u1', target({ displayName: 'Unknown', username: null }), empty)
      .displayName,
    'Nuvo member',
  );
});
