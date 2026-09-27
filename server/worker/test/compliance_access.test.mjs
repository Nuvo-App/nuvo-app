import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);

const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');
const { resolveRaceAccess, checkRaceJoinEligibility } =
  require('../.tmp-test-dist/lib/raceAccess.js');

const JWT_SECRET = 'test-secret';
const INTERNAL_KEY = 'internal-test-key';

async function tokenFor(sub) {
  return signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET);
}

// ── Tiny D1 stub for the access-policy matrix ─────────────────────────────────
// members: Set of "raceId|userId" active membership keys
// crews:   Set of "a>b" active crew edges (checked both directions)
// blocks:  Set of "a>b" block edges (checked both directions)
function accessDb({ members = new Set(), crews = new Set(), blocks = new Set() } = {}) {
  return {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ');
      let args = [];
      return {
        bind(...a) { args = a; return this; },
        async first() {
          if (q.includes('FROM race_members')) {
            return members.has(`${args[0]}|${args[1]}`) ? { id: 'm' } : null;
          }
          if (q.includes('FROM blocked_users')) {
            return blocks.has(`${args[0]}>${args[1]}`) || blocks.has(`${args[2]}>${args[3]}`)
              ? { id: 'b' } : null;
          }
          if (q.includes('FROM crew_connections')) {
            return crews.has(`${args[0]}>${args[1]}`) || crews.has(`${args[2]}>${args[3]}`)
              ? { id: 'c' } : null;
          }
          return null;
        },
        async run() { return { success: true }; },
        async all() { return { results: [] }; },
      };
    },
  };
}

const race = (visibility, creator = 'creator', extra = {}) =>
  ({ id: 'r1', creator_id: creator, visibility, status: 'active', public_join_enabled: 0, ...extra });

// ── resolveRaceAccess matrix ──────────────────────────────────────────────────

test('race access: owner reads with insider rights', async () => {
  const a = await resolveRaceAccess(accessDb(), race('private'), 'creator');
  assert.equal(a.level, 'owner');
  assert.ok(a.canRead && a.isInsider && a.isOwner);
});

test('race access: active member reads with insider rights', async () => {
  const db = accessDb({ members: new Set(['r1|m1']) });
  const a = await resolveRaceAccess(db, race('private'), 'm1');
  assert.equal(a.level, 'member');
  assert.ok(a.canRead && a.isInsider && a.isMember);
});

test('race access: stranger is denied a private race entirely', async () => {
  const a = await resolveRaceAccess(accessDb(), race('private'), 'stranger');
  assert.equal(a.level, 'denied');
  assert.ok(!a.canRead && !a.isInsider);
});

test('race access: stranger is denied an invite_code race', async () => {
  const a = await resolveRaceAccess(accessDb(), race('invite_code'), 'stranger');
  assert.equal(a.level, 'denied');
});

test('race access: crew member reads a crew_only race but is not an insider', async () => {
  const db = accessDb({ crews: new Set(['viewer>creator']) });
  const a = await resolveRaceAccess(db, race('crew_only'), 'viewer');
  assert.equal(a.level, 'crew');
  assert.ok(a.canRead);
  // Crew readers never receive the invite code — that is insider data.
  assert.ok(!a.isInsider);
});

test('race access: stranger is denied a crew_only race', async () => {
  const a = await resolveRaceAccess(accessDb(), race('crew_only'), 'stranger');
  assert.equal(a.level, 'denied');
});

test('race access: any signed-in user reads a public_demo race', async () => {
  const a = await resolveRaceAccess(accessDb(), race('public_demo'), 'stranger');
  assert.equal(a.level, 'public');
  assert.ok(a.canRead && !a.isInsider);
});

test('race access: a block with the creator closes even a public race', async () => {
  const db = accessDb({ blocks: new Set(['blocked>creator']) });
  const a = await resolveRaceAccess(db, race('public_demo'), 'blocked');
  assert.equal(a.level, 'denied');
});

test('join eligibility: private race demands the invite-code flow', async () => {
  const e = await checkRaceJoinEligibility(accessDb(), race('private'), 'stranger');
  assert.equal(e.ok, false);
  assert.equal(e.status, 403);
});

test('join eligibility: blocked user can never join', async () => {
  const db = accessDb({ blocks: new Set(['blocked>creator']) });
  const e = await checkRaceJoinEligibility(
    db, race('public_demo', 'creator', { public_join_enabled: 1 }), 'blocked');
  assert.equal(e.ok, false);
  assert.equal(e.status, 403);
});

test('join eligibility: crew member may join a crew_only race', async () => {
  const db = accessDb({ crews: new Set(['viewer>creator']) });
  const e = await checkRaceJoinEligibility(db, race('crew_only'), 'viewer');
  assert.equal(e.ok, true);
});

test('join eligibility: public join must be explicitly enabled', async () => {
  const off = await checkRaceJoinEligibility(accessDb(), race('public_demo'), 'stranger');
  assert.equal(off.ok, false);
  const on = await checkRaceJoinEligibility(
    accessDb(), race('public_demo', 'creator', { public_join_enabled: 1 }), 'stranger');
  assert.equal(on.ok, true);
});

// ── Recording env for route-level checks ─────────────────────────────────────

function recordingEnv({ withInternalKey = true, usersRow = {} } = {}) {
  const calls = [];
  const objects = new Map();
  const rowState = { ...usersRow };
  const DB = {
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let args = [];
      return {
        bind(...a) { args = a; return this; },
        async run() {
          calls.push({ q, args });
          // Keep the consent columns honest so PUT → read-back round-trips.
          if (q.startsWith('UPDATE users') && q.includes('motion_training_consent = ?')) {
            rowState.motion_training_consent = args[0];
          }
          return { success: true };
        },
        async first() {
          if (q.includes('FROM users')) {
            return { id: args[0], primary_email: 'a@b.com', status: 'active', ...rowState };
          }
          return null;
        },
        async all() { return { results: [] }; },
      };
    },
  };
  return {
    DB,
    PROFILE_PHOTOS: {
      async put(key) { objects.set(key, true); },
      async get() { return null; },
      async delete(key) { objects.delete(key); calls.push({ q: `R2.delete ${key}`, args: [] }); },
    },
    JWT_SECRET,
    INTERNAL_API_KEY: withInternalKey ? INTERNAL_KEY : undefined,
    GOOGLE_IOS_CLIENT_ID: '', APPLE_BUNDLE_ID: '', RESEND_API_KEY: '',
    RESEND_FROM_EMAIL: '', API_BASE_URL: '',
    __calls: calls,
    __objects: objects,
  };
}

// ── Report admin authorization ────────────────────────────────────────────────

test('report triage is NOT reachable through the user reports router', async () => {
  const env = recordingEnv();
  const res = await app.request('/reports/admin', {
    headers: { Authorization: `Bearer ${await tokenFor('user-1')}` },
  }, env);
  assert.equal(res.status, 404);
});

test('internal reports: an ordinary user JWT is denied', async () => {
  const env = recordingEnv();
  const res = await app.request('/internal/reports', {
    headers: { Authorization: `Bearer ${await tokenFor('user-1')}` },
  }, env);
  assert.equal(res.status, 403);
});

test('internal reports: no credentials at all is denied', async () => {
  const env = recordingEnv();
  const res = await app.request('/internal/reports', {}, env);
  assert.equal(res.status, 403);
});

test('internal reports: the operator key is allowed', async () => {
  const env = recordingEnv();
  const res = await app.request('/internal/reports', {
    headers: { 'X-Internal-Key': INTERNAL_KEY },
  }, env);
  assert.equal(res.status, 200);
});

// ── Motion consent + age gate ─────────────────────────────────────────────────

test('PUT /motion/consent: consent cannot be granted before age attestation', async () => {
  const env = recordingEnv({ usersRow: { age_attested_at: null } });
  const res = await app.request('/motion/consent', {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${await tokenFor('user-1')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ consented: true }),
  }, env);
  assert.equal(res.status, 403);
});

test('PUT /motion/consent: attested user can grant and revoke', async () => {
  const env = recordingEnv({ usersRow: { age_attested_at: '2026-01-01' } });
  const grant = await app.request('/motion/consent', {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${await tokenFor('user-1')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ consented: true }),
  }, env);
  assert.equal(grant.status, 200);
  const granted = await grant.json();
  assert.equal(granted.consent.consented, true);
  const revoke = await app.request('/motion/consent', {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${await tokenFor('user-1')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ consented: false }),
  }, env);
  assert.equal(revoke.status, 200);
});

test('legacy member: consent defaults off, attestation required before opt-in, revocation stops uploads', async () => {
  // 0038 state: terms grandfathered as 'legacy', NO attestation stamp,
  // motion_training_consent = 0.
  const env = recordingEnv({
    usersRow: {
      terms_version: 'legacy',
      terms_accepted_at: '2025-01-01',
      age_attested_at: null,
      motion_training_consent: 0,
    },
  });
  const token = await tokenFor('legacy-user');
  const authed = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

  const state = await app.request('/motion/consent', { headers: authed }, env);
  const s = await state.json();
  assert.equal(s.consent.consented, false);
  assert.equal(s.consent.ageAttested, false);

  // Opt-in refused until the member attests — ordinary features unaffected.
  const blocked = await app.request('/motion/consent', {
    method: 'PUT', headers: authed, body: JSON.stringify({ consented: true }),
  }, env);
  assert.equal(blocked.status, 403);

  // Attest, then opt in — now uploads may store.
  const attest = await app.request('/auth/age-attestation', {
    method: 'POST', headers: authed, body: '{}',
  }, env);
  assert.equal(attest.status, 200);
  // The fake does not model age_attested_at mutation; simulate post-attest.
  const env2 = recordingEnv({
    usersRow: {
      terms_version: 'legacy', terms_accepted_at: '2025-01-01',
      age_attested_at: '2026-09-27', motion_training_consent: 0,
    },
  });
  const grant = await app.request('/motion/consent', {
    method: 'PUT', headers: authed, body: JSON.stringify({ consented: true }),
  }, env2);
  assert.equal(grant.status, 200);
  assert.equal((await grant.json()).consent.consented, true);

  // Revocation flips the row back — subsequent uploads store nothing.
  const revoke = await app.request('/motion/consent', {
    method: 'PUT', headers: authed, body: JSON.stringify({ consented: false }),
  }, env2);
  assert.equal(revoke.status, 200);
  assert.equal((await revoke.json()).consent.consented, false);
});

// ── Account deletion coverage ─────────────────────────────────────────────────

test('DELETE /auth/account succeeds without MOTION_DATA_MASTER_KEY and covers every user-linked table', async () => {
  const env = recordingEnv(); // NOTE: no MOTION_DATA_MASTER_KEY set — the production bug.
  const res = await app.request('/auth/account', {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${await tokenFor('user-del')}` },
  }, env);
  assert.equal(res.status, 200);

  const sql = env.__calls.map((c) => c.q);
  const has = (needle) => sql.some((s) => s.includes(needle));

  // Every table the audit found orphaned must now be touched.
  const required = [
    'DELETE FROM device_tokens',
    'DELETE FROM notifications',
    'UPDATE notifications SET actor_user_id = NULL',
    'DELETE FROM notification_preferences',
    'DELETE FROM notification_jobs',
    'DELETE FROM activity_reactions',
    'DELETE FROM personal_bests',
    'DELETE FROM race_attempts',
    'DELETE FROM verification_sessions',
    'DELETE FROM proofs',
    'DELETE FROM race_participants',
    // people is tombstoned, not deleted — race_members.person_id is NOT NULL
    // with an FK to people, so surviving shared-race memberships still need a
    // valid row. The anonymize strips identity and frees the unique username.
    'UPDATE people',
    'DELETE FROM invites',
    'DELETE FROM invite_uses',
    'UPDATE race_events SET actor_user_id = NULL',
    'UPDATE race_events SET subject_user_id = NULL',
    'DELETE FROM motion_sessions',
    'DELETE FROM motion_training_examples',
    'DELETE FROM motion_feedback_labels',
    'DELETE FROM motion_analysis_jobs',
    'DELETE FROM sessions',
    'DELETE FROM email_codes',
    'DELETE FROM crew_connections',
    'DELETE FROM member_passes',
    'DELETE FROM profiles',
    'DELETE FROM blocked_users',
    'DELETE FROM media_objects',
  ];
  for (const needle of required) {
    assert.ok(has(needle), `missing cleanup statement: ${needle}`);
  }
  assert.ok(has('UPDATE users'), 'deleted account must be marked on the users row');
});
