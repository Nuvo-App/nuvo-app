import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  INVITE_KINDS,
  targetTypeForKind,
  inviteAvailability,
  statusForAvailability,
  generateInviteToken,
  looksLikeInviteToken,
  shareUrl,
  defaultExpirySeconds,
} = require('../.tmp-test-dist/lib/invites.js');

test('INVITE_KINDS maps to the right target type', () => {
  assert.deepEqual([...INVITE_KINDS].sort(), ['crew_connect', 'race_join', 'squad_join']);
  assert.equal(targetTypeForKind('race_join'), 'race');
  assert.equal(targetTypeForKind('crew_connect'), 'user');
  assert.equal(targetTypeForKind('squad_join'), 'squad');
});

test('inviteAvailability — the full lifecycle', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  assert.equal(inviteAvailability(null, now), 'not_found');
  assert.equal(
    inviteAvailability({ expires_at: null, revoked_at: null, max_uses: null, use_count: 0 }, now),
    'active',
  );
  assert.equal(
    inviteAvailability(
      { expires_at: null, revoked_at: '2025-12-01T00:00:00Z', max_uses: null, use_count: 0 },
      now,
    ),
    'revoked',
  );
  assert.equal(
    inviteAvailability(
      { expires_at: '2025-12-31T23:59:59Z', revoked_at: null, max_uses: null, use_count: 0 },
      now,
    ),
    'expired',
  );
  assert.equal(
    inviteAvailability(
      { expires_at: '2026-02-01T00:00:00Z', revoked_at: null, max_uses: null, use_count: 99 },
      now,
    ),
    'active',
  );
  assert.equal(
    inviteAvailability({ expires_at: null, revoked_at: null, max_uses: 3, use_count: 3 }, now),
    'used',
  );
  assert.equal(
    inviteAvailability({ expires_at: null, revoked_at: null, max_uses: 3, use_count: 2 }, now),
    'active',
  );
});

test('revoked wins over expired wins over used', () => {
  const now = new Date('2026-01-01T00:00:00Z');
  assert.equal(
    inviteAvailability(
      { expires_at: '2020-01-01T00:00:00Z', revoked_at: '2020-01-01T00:00:00Z', max_uses: 1, use_count: 5 },
      now,
    ),
    'revoked',
  );
});

test('statusForAvailability — not_found is 404, everything else 410', () => {
  assert.equal(statusForAvailability('not_found'), 404);
  assert.equal(statusForAvailability('expired'), 410);
  assert.equal(statusForAvailability('revoked'), 410);
  assert.equal(statusForAvailability('used'), 410);
});

test('generateInviteToken — 43 url-safe chars, unique, non-guessable', () => {
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const t = generateInviteToken();
    assert.match(t, /^[A-Za-z0-9_-]{43}$/);
    assert.ok(!seen.has(t), 'collision');
    seen.add(t);
    assert.ok(looksLikeInviteToken(t));
  }
});

test('looksLikeInviteToken rejects junk and short ids (enumeration guard)', () => {
  assert.equal(looksLikeInviteToken('12345'), false);
  assert.equal(looksLikeInviteToken('abcABC123-_'.repeat(3)), true); // shape ok, DB decides
  assert.equal(looksLikeInviteToken('has spaces'), false);
  assert.equal(looksLikeInviteToken('a'.repeat(200)), false);
  assert.equal(looksLikeInviteToken('drop/table'), false);
});

test('shareUrl builds a clean /j/ URL against the request origin', () => {
  assert.equal(
    shareUrl('https://nuvo-api.getnuvoapp.workers.dev', 'abc123'),
    'https://nuvo-api.getnuvoapp.workers.dev/j/abc123',
  );
  assert.equal(shareUrl('https://x.dev/', 'abc123'), 'https://x.dev/j/abc123');
});

test('defaultExpirySeconds — race + crew open-ended, squad 7 days', () => {
  assert.equal(defaultExpirySeconds('race_join'), null);
  assert.equal(defaultExpirySeconds('crew_connect'), null);
  assert.equal(defaultExpirySeconds('squad_join'), 7 * 24 * 3600);
});
