import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  appleServiceConfig,
  buildAppleClientSecret,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
  revokeAppleCredentialForUser,
  retryPendingAppleRevocations,
} = require('../.tmp-test-dist/lib/apple.js');

function b64urlDecode(s) {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
}

async function makeKeyPair() {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const pem =
    '-----BEGIN PRIVATE KEY-----\n' +
    Buffer.from(pkcs8).toString('base64') +
    '\n-----END PRIVATE KEY-----';
  return { pair, pem };
}

const ENV_CFG = {
  APPLE_BUNDLE_ID: 'net.getnuvo.app',
  APPLE_TEAM_ID: 'TEAM123456',
  APPLE_KEY_ID: 'KEY1234567',
};

async function makeConfig(pem) {
  return {
    clientId: ENV_CFG.APPLE_BUNDLE_ID,
    teamId: ENV_CFG.APPLE_TEAM_ID,
    keyId: ENV_CFG.APPLE_KEY_ID,
    privateKey: pem,
  };
}

function fakeDb({ identity = null, pending = [] } = {}) {
  const calls = [];
  const bound = (sql, args) => {
    calls.push({ sql, args });
    return {
      async first() {
        if (sql.includes("provider = 'apple'") && sql.includes('user_id')) {
          return identity;
        }
        return null;
      },
      async all() {
        if (sql.includes('provider_user_id IS NULL')) {
          return { results: pending };
        }
        return { results: [] };
      },
      async run() {
        return { meta: { changes: 1 } };
      },
    };
  };
  return {
    calls,
    prepare(sql) {
      return {
        bind(...args) {
          return bound(sql, args);
        },
        async first() {
          return bound(sql).first();
        },
        async all() {
          return bound(sql).all();
        },
        async run() {
          return bound(sql).run();
        },
      };
    },
  };
}

function recordingFetch({ status = 200, json = {} } = {}) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push({ url, init });
    return new Response(JSON.stringify(json), { status });
  };
  impl.calls = calls;
  return impl;
}

test('appleServiceConfig requires all Apple service secrets', () => {
  assert.equal(appleServiceConfig({}), undefined);
  assert.equal(
    appleServiceConfig({ APPLE_BUNDLE_ID: 'x', APPLE_TEAM_ID: 't' }),
    undefined,
  );
  const cfg = appleServiceConfig({ ...ENV_CFG, APPLE_PRIVATE_KEY: 'k' });
  assert.equal(cfg.clientId, 'net.getnuvo.app');
  assert.equal(cfg.teamId, 'TEAM123456');
  assert.equal(cfg.keyId, 'KEY1234567');
});

test('buildAppleClientSecret produces a verifiable ES256 JWT', async () => {
  const { pair, pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const secret = await buildAppleClientSecret(cfg, new Date('2026-01-01T00:00:00Z'));
  const [h, p, sig] = secret.split('.');
  assert.deepEqual(JSON.parse(b64urlDecode(h)), {
    alg: 'ES256',
    kid: 'KEY1234567',
  });
  const payload = JSON.parse(b64urlDecode(p));
  assert.equal(payload.iss, 'TEAM123456');
  assert.equal(payload.sub, 'net.getnuvo.app');
  assert.equal(payload.aud, 'https://appleid.apple.com');
  assert.equal(payload.iat, 1767225600);
  assert.equal(payload.exp - payload.iat, 180 * 24 * 60 * 60);

  const signature = Uint8Array.from(
    Buffer.from(sig.replace(/-/g, '+').replace(/_/g, '/'), 'base64'),
  );
  const valid = await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' },
    pair.publicKey,
    signature,
    new TextEncoder().encode(`${h}.${p}`),
  );
  assert.equal(valid, true);
});

test('exchange posts the authorization-code grant and returns the refresh token', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch({ json: { refresh_token: 'rt-1' } });
  const res = await exchangeAppleAuthorizationCode(cfg, 'code-abc', fetchImpl);
  assert.equal(res.refreshToken, 'rt-1');
  const call = fetchImpl.calls[0];
  assert.equal(call.url, 'https://appleid.apple.com/auth/token');
  const form = new URLSearchParams(call.init.body);
  assert.equal(form.get('client_id'), 'net.getnuvo.app');
  assert.equal(form.get('code'), 'code-abc');
  assert.equal(form.get('grant_type'), 'authorization_code');
  assert.ok(form.get('client_secret')?.split('.').length === 3);
});

test('exchange without a refresh token in the response returns null', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch({ json: { access_token: 'at-only' } });
  const res = await exchangeAppleAuthorizationCode(cfg, 'code-abc', fetchImpl);
  assert.equal(res.refreshToken, null);
});

test('exchange throws on an Apple error response', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch({ status: 400, json: { error: 'invalid_grant' } });
  await assert.rejects(
    () => exchangeAppleAuthorizationCode(cfg, 'bad-code', fetchImpl),
    /HTTP 400/,
  );
});

test('revoke posts to Apple revoke endpoint with the refresh-token hint', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch();
  await revokeAppleRefreshToken(cfg, 'rt-9', fetchImpl);
  const call = fetchImpl.calls[0];
  assert.equal(call.url, 'https://appleid.apple.com/auth/revoke');
  const form = new URLSearchParams(call.init.body);
  assert.equal(form.get('token'), 'rt-9');
  assert.equal(form.get('token_type_hint'), 'refresh_token');
  assert.equal(form.get('client_id'), 'net.getnuvo.app');
});

test('revokeAppleCredentialForUser — no apple identity or token is a no-op', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch();
  assert.equal(
    await revokeAppleCredentialForUser(fakeDb(), cfg, 'u1', fetchImpl),
    'none',
  );
  // Identity exists but no stored refresh token (legacy beta account).
  const db2 = fakeDb({ identity: { id: 'ai-1', provider_refresh_token: null } });
  assert.equal(
    await revokeAppleCredentialForUser(db2, cfg, 'u1', fetchImpl),
    'none',
  );
  assert.equal(fetchImpl.calls.length, 0);
});

test('revokeAppleCredentialForUser — success deletes the identity row', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch();
  const db = fakeDb({
    identity: { id: 'ai-1', provider_refresh_token: 'rt-1' },
  });
  assert.equal(
    await revokeAppleCredentialForUser(db, cfg, 'u1', fetchImpl),
    'revoked',
  );
  assert.equal(fetchImpl.calls.length, 1);
  assert.ok(
    db.calls.some((c) => c.sql.includes('DELETE FROM auth_identities') && c.args[0] === 'ai-1'),
  );
});

test('revokeAppleCredentialForUser — apple failure anonymizes but keeps the token', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch({ status: 500 });
  const db = fakeDb({
    identity: { id: 'ai-1', provider_refresh_token: 'rt-1' },
  });
  assert.equal(
    await revokeAppleCredentialForUser(db, cfg, 'u1', fetchImpl),
    'pending',
  );
  const anon = db.calls.find((c) => c.sql.includes('UPDATE auth_identities'));
  assert.ok(anon);
  assert.ok(anon.sql.includes('provider_user_id = NULL'));
  assert.ok(!db.calls.some((c) => c.sql.includes('DELETE FROM auth_identities')));
});

test('revokeAppleCredentialForUser — missing config keeps the credential pending', async () => {
  const db = fakeDb({
    identity: { id: 'ai-1', provider_refresh_token: 'rt-1' },
  });
  const fetchImpl = recordingFetch();
  assert.equal(
    await revokeAppleCredentialForUser(db, undefined, 'u1', fetchImpl),
    'pending',
  );
  assert.equal(fetchImpl.calls.length, 0);
});

test('retryPendingAppleRevocations drains anonymized credential rows', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch();
  const db = fakeDb({
    pending: [
      { id: 'ai-1', provider_refresh_token: 'rt-1' },
      { id: 'ai-2', provider_refresh_token: 'rt-2' },
    ],
  });
  await retryPendingAppleRevocations(db, cfg, fetchImpl);
  assert.equal(fetchImpl.calls.length, 2);
  const deletes = db.calls.filter((c) => c.sql.includes('DELETE FROM auth_identities'));
  assert.equal(deletes.length, 2);
});

test('retryPendingAppleRevocations keeps the row when Apple still fails', async () => {
  const { pem } = await makeKeyPair();
  const cfg = await makeConfig(pem);
  const fetchImpl = recordingFetch({ status: 503 });
  const db = fakeDb({
    pending: [{ id: 'ai-1', provider_refresh_token: 'rt-1' }],
  });
  await retryPendingAppleRevocations(db, cfg, fetchImpl);
  assert.equal(
    db.calls.filter((c) => c.sql.includes('DELETE FROM auth_identities')).length,
    0,
  );
});
