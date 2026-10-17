import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { weakEtag, etagMatches, stalenessBucket } = require('../.tmp-test-dist/lib/etag.js');

test('weakEtag joins parts and tolerates null/undefined', () => {
  assert.equal(weakEtag('races', 7, null, undefined, 'x'), 'W/"races:7:::x"');
});

test('etagMatches — exact, weak/strong mix, lists, star, absent', () => {
  const tag = weakEtag('a', 1);
  assert.equal(etagMatches(tag, tag), true);
  assert.equal(etagMatches('"a:1"', tag), true); // strong form of the same opaque tag
  assert.equal(etagMatches(`W/"zzz", ${tag}`, tag), true);
  assert.equal(etagMatches('*', tag), true);
  assert.equal(etagMatches(weakEtag('a', 2), tag), false);
  assert.equal(etagMatches(undefined, tag), false);
  assert.equal(etagMatches('', tag), false);
});

test('stalenessBucket changes at the boundary and only there', () => {
  const m = 5 * 60_000;
  assert.equal(stalenessBucket(0), 0);
  assert.equal(stalenessBucket(m - 1), 0);
  assert.equal(stalenessBucket(m), 1);
});
