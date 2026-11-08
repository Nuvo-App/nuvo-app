// V0 wire-compatibility pin for the race rules_version staging (S0).
//
// Existing rows and old app builds are rules_version = 0. These tests prove:
//   - the V0 request aliases (goalType, proofRequirement, aiActivityType,
//     proofMode, mediaUrl, unit) still create/score exactly as before;
//   - every legacy response key still ships, alongside the new rulesVersion;
//   - the retired write endpoints keep their 410/404 answers;
//   - rules_version defaults to 0, stamps 1 on opt-in, echoes back, copies to
//     rematches, and cannot be PATCHed.
// If a future diff breaks any of these, old production clients break.

import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';
// Test-only credential for /auth/reviewer — never a real review password.
const REVIEWER_PASSWORD = 'test-review-pass';
const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0042_achievements.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0044_custom_verifier_seed.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0046_squads.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0047_reconcile_prod.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0050_race_rules_version.sql', root), 'utf8'),
];

// ── D1 adapter over node:sqlite ──────────────────────────────────────────────
function d1(sqlite) {
  const norm = (args) =>
    args.map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v));
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    async first(col) {
      const row = sqlite.prepare(sql).get(...norm(args));
      if (!row) return null;
      const o = { ...row };
      return col ? o[col] : o;
    },
    async all() {
      return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
    },
    async run() {
      return this.runSync();
    },
    runSync() {
      if (/^\s*(SELECT|WITH)\b/i.test(sql)) {
        return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
      }
      const info = sqlite.prepare(sql).run(...norm(args));
      return { success: true, meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) } };
    },
  });
  return {
    prepare: (sql) => stmt(sql),
    async batch(stmts) {
      sqlite.exec('BEGIN');
      try {
        const out = stmts.map((s) => s.runSync());
        sqlite.exec('COMMIT');
        return out;
      } catch (err) {
        sqlite.exec('ROLLBACK');
        throw err;
      }
    },
  };
}

function fakeR2() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, opts) { objects.set(key, { body, opts }); },
    async get(key) {
      const o = objects.get(key);
      return o ? { body: 'bytes', customMetadata: o.opts?.customMetadata ?? {}, writeHttpMetadata() {} } : null;
    },
    async delete(key) { objects.delete(key); },
  };
}

function world() {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  sqlite.exec('PRAGMA foreign_keys = ON');
  const db = d1(sqlite);
  const r2 = fakeR2();
  const pending = [];
  const env = {
    DB: db,
    JWT_SECRET,
    PROFILE_PHOTOS: r2,
    APPLE_BUNDLE_ID: 'net.getnuvo.app',
    REVIEWER_PASSWORD_HASH: createHash('sha256').update(REVIEWER_PASSWORD).digest('hex'),
  };
  const ctx = { waitUntil: (p) => pending.push(p), passThroughOnException() {} };
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const one = (sql, ...a) => q(sql, ...a)[0];
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);

  const req = async (sub, method, path, body) => {
    const headers = { 'Content-Type': 'application/json' };
    if (sub) headers.Authorization = `Bearer ${await signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET)}`;
    const res = await app.request(path, {
      method,
      headers,
      body: body == null ? undefined : JSON.stringify(body),
    }, env, ctx);
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* non-JSON */ }
    return { status: res.status, json, text };
  };

  const user = (id, { email = `${id}@example.com`, name = id } = {}) => {
    exec("INSERT INTO users (id, primary_email, status, terms_accepted_at, created_at, updated_at) VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", id, email);
    exec('INSERT INTO profiles (user_id, full_name) VALUES (?, ?)', id, name);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, name);
  };
  const member = (raceId, userId, role = 'racer', status = 'active') => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, role, status,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, 0, 0)', `rp-${raceId}-${userId}`, raceId, userId);
  };
  let mediaN = 0;
  const photo = (raceId, owner) => {
    const key = `proof-evidence/${raceId}/${owner}/${++mediaN}.jpg`;
    exec("INSERT INTO media_objects (id, owner_user_id, bucket, object_key, media_type, purpose, status) VALUES (?, ?, 'nuvor2', ?, 'image', 'proof_evidence', 'active')", `mo-${mediaN}`, owner, key);
    r2.objects.set(key, { body: 'jpg' });
    return key;
  };
  const progress = (raceId, userId) => one('SELECT progress_value FROM race_progress WHERE race_id = ? AND user_id = ?', raceId, userId).progress_value;
  const flush = async () => { await Promise.all(pending.splice(0)); };

  return { sqlite, db, r2, env, req, q, one, exec, user, member, photo, progress, flush };
}

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const HOUR = 3600_000;

// A create body shaped exactly like the old build sends: V0 aliases only —
// goalType/proofRequirement/proofMode/unit/finishLineAt — plus fields the
// Worker has always silently ignored (category, rules, note).
function v0ManualBody(over = {}) {
  return {
    title: 'Pages Read',
    description: 'read the most pages',
    goalType: 'manual',
    targetValue: 100,
    unit: 'pages',
    targetUnit: 'pages',
    proofRequirement: 'photo_video',
    proofMode: 'photo_video',
    finishLineAt: iso(48 * HOUR),
    visibility: 'crew_only',
    rules: 'no skim reading',
    category: 'mind',
    ...over,
  };
}

// ── tests ────────────────────────────────────────────────────────────────────

test('test_gap4_v0_create_roundtrip', async () => {
  const w = world();
  w.user('A');

  // V0 manual create — old aliases only, no rulesVersion field.
  const manual = await w.req('A', 'POST', '/races', v0ManualBody());
  assert.equal(manual.status, 201, manual.text);
  const manualRace = manual.json.race;
  assert.equal(manualRace.goalType, 'first_to_goal', 'goalType echoes the stored race_type');
  assert.equal(manualRace.targetValue, 100);
  assert.equal(manualRace.unit, 'pages', 'unit alias echoes back');
  assert.equal(manualRace.proofMode, 'photo_video', 'proofMode alias echoes back');
  assert.equal(manualRace.proofRequirement, 'photo_video');
  const manualRow = w.one('SELECT * FROM races WHERE id = ?', manualRace.id);
  assert.equal(manualRow.format, 'first_to_goal');
  assert.equal(manualRow.race_type, 'first_to_goal');
  assert.equal(manualRow.verification_type, 'photo');
  assert.equal(manualRow.target_unit, 'pages');
  assert.ok(manualRow.end_at, 'finishLineAt lands as end_at');

  // V0 preset create — aiActivityType + verificationMethod aliases.
  const preset = await w.req('A', 'POST', '/races', {
    title: 'Pushup Sprint',
    goalType: 'first_to_goal',
    targetValue: 50,
    aiActivityType: 'push_ups',
    proofRequirement: 'ai_check',
    proofMode: 'ai_check',
    verificationMethod: 'ai',
    startLineAt: iso(HOUR),
  });
  assert.equal(preset.status, 201, preset.text);
  const presetRow = w.one('SELECT * FROM races WHERE id = ?', preset.json.race.id);
  assert.equal(presetRow.format, 'first_to_goal');
  assert.equal(presetRow.activity_id, 'push_ups');
  assert.equal(presetRow.metric, 'reps');
  assert.equal(presetRow.target_value, 50);
  assert.equal(preset.json.race.aiActivityType, 'push_ups', 'aiActivityType alias echoes back');
});

test('test_gap4_v0_proof_roundtrip', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  const created = await w.req('A', 'POST', '/races', v0ManualBody());
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');

  // V0 manual proof — proofType + value + verificationSummary + mediaObjectKey.
  const proof = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'manual',
    value: 25,
    verificationSummary: 'Great set of chapters',
    mediaObjectKey: w.photo(raceId, 'B'),
  });
  assert.equal(proof.status, 200, proof.text);
  assert.equal(w.progress(raceId, 'B'), 25, 'auto-accept proof scores');

  // The proofs list still answers with the V0 field shape.
  const list = await w.req('A', 'GET', `/races/${raceId}/proofs`);
  assert.equal(list.status, 200, list.text);
  const entry = (list.json.proofs ?? []).find((p) => p.userId === 'B');
  assert.ok(entry, 'B proof is listed');
  assert.equal(entry.proofType, 'manual');
  assert.equal(entry.note, 'Great set of chapters', 'note echoes the stored summary');
  assert.equal(entry.verificationSummary, 'Great set of chapters');
  assert.equal(entry.value, 25);
  assert.equal(entry.verificationStatus, 'accepted');
  assert.ok(entry.mediaUrl, 'proof exposes the stored media to a member');
  assert.ok(entry.createdAt, 'createdAt key present');

  // mediaUrl alone is no longer sufficient — non-AI proofs require stored
  // media (recorded compat hole, preserved deliberately).
  const noMedia = await w.req('B', 'POST', `/races/${raceId}/proof`, {
    proofType: 'manual',
    value: 10,
    mediaUrl: 'https://cdn.example.com/photo.jpg',
  });
  assert.equal(noMedia.status, 400, noMedia.text);
});

test('test_gap4_legacy_response_keys', async () => {
  const w = world();
  w.user('A');
  const created = await w.req('A', 'POST', '/races', v0ManualBody());
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;

  const got = await w.req('A', 'GET', `/races/${raceId}`);
  assert.equal(got.status, 200, got.text);
  const race = got.json.race;
  // Every V0 key the old build reads, still present.
  for (const key of [
    'id', 'title', 'description', 'category', 'goalType', 'activityId',
    'targetValue', 'unit', 'targetUnit', 'aiActivityType', 'proofMode',
    'proofRequirement', 'verificationMethod', 'startLineAt', 'finishLineAt',
    'visibility', 'status', 'inviteCode', 'creatorId', 'createdAt',
    'updatedAt', 'participants', 'recentProofs', 'viewerContext', 'rules',
    'version',
  ]) {
    assert.ok(key in race, `legacy key "${key}" missing from race response`);
  }
  // V2 keys shipped alongside (additive, never renamed).
  for (const key of ['format', 'metric', 'scoringRule', 'scoreDirection', 'proofReviewMode', 'rulesVersion']) {
    assert.ok(key in race, `key "${key}" missing from race response`);
  }
});

test('test_gap4_410_endpoints_for_old_writes', async () => {
  const w = world();
  w.user('A');
  const created = await w.req('A', 'POST', '/races', v0ManualBody());
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;

  // Retired write paths keep their stable error contract — old builds see a
  // hard failure, not silent acceptance.
  const moveLog = await w.req('A', 'POST', `/races/${raceId}/move-log`, { value: 5 });
  assert.equal(moveLog.status, 410, `move-log: ${moveLog.text}`);
  const progress = await w.req('A', 'PATCH', `/races/${raceId}/progress/A`, { value: 5 });
  assert.equal(progress.status, 410, `progress: ${progress.text}`);
  const moves = await w.req('A', 'POST', `/races/${raceId}/moves`, { value: 5 });
  assert.equal(moves.status, 404, `moves: ${moves.text}`);
});

test('test_rules_version_defaults_to_zero', async () => {
  const w = world();
  w.user('A');
  const created = await w.req('A', 'POST', '/races', v0ManualBody());
  assert.equal(created.status, 201, created.text);
  assert.equal(
    w.one('SELECT rules_version FROM races WHERE id = ?', created.json.race.id).rules_version,
    0,
    'missing rulesVersion defaults to 0',
  );
  assert.equal(created.json.race.rulesVersion, 0, 'response echoes rulesVersion: 0');

  // A legacy row (inserted without the column) also reads as v0.
  w.exec(
    "INSERT INTO races (id, creator_id, title, race_type, verification_type, target_value, status, visibility) VALUES ('legacy-1', 'A', 'Old', 'first_to_goal', 'manual', 10, 'active', 'crew_only')",
  );
  const got = await w.req('A', 'GET', '/races/legacy-1');
  assert.equal(got.status, 200, got.text);
  assert.equal(got.json.race.rulesVersion, 0, 'legacy row echoes rulesVersion: 0');
});

test('test_rules_version_stamped_from_create_body', async () => {
  const w = world();
  w.user('A');

  const camel = await w.req('A', 'POST', '/races', v0ManualBody({ rulesVersion: 1 }));
  assert.equal(camel.status, 201, camel.text);
  assert.equal(w.one('SELECT rules_version FROM races WHERE id = ?', camel.json.race.id).rules_version, 1);
  assert.equal(camel.json.race.rulesVersion, 1);

  const snake = await w.req('A', 'POST', '/races', v0ManualBody({ rules_version: 1 }));
  assert.equal(snake.status, 201, snake.text);
  assert.equal(w.one('SELECT rules_version FROM races WHERE id = ?', snake.json.race.id).rules_version, 1);

  // Garbage / future revisions normalise to 0 — never stricter than asked.
  for (const bad of [2, 'yes', true, { v: 1 }]) {
    const res = await w.req('A', 'POST', '/races', v0ManualBody({ rulesVersion: bad }));
    assert.equal(res.status, 201, res.text);
    assert.equal(w.one('SELECT rules_version FROM races WHERE id = ?', res.json.race.id).rules_version, 0, `rulesVersion=${JSON.stringify(bad)} normalises to 0`);
  }
});

test('test_rules_version_not_patchable_and_copied_to_rematch', async () => {
  const w = world();
  w.user('A');
  w.user('B');
  const created = await w.req('A', 'POST', '/races', v0ManualBody({ rulesVersion: 1 }));
  assert.equal(created.status, 201, created.text);
  const raceId = created.json.race.id;
  w.member(raceId, 'B');

  // PATCH cannot move a race's rules revision — the field is locked.
  const patched = await w.req('A', 'PATCH', `/races/${raceId}`, { rulesVersion: 0, rules_version: 0 });
  assert.equal(patched.status, 200, patched.text);
  assert.equal(w.one('SELECT rules_version FROM races WHERE id = ?', raceId).rules_version, 1, 'rules_version survives PATCH');

  // Rematch inherits the source race's rules revision.
  const rematch = await w.req('B', 'POST', `/races/${raceId}/rematch`, {});
  assert.equal(rematch.status, 201, rematch.text);
  const rematchId = rematch.json.race.id;
  assert.equal(w.one('SELECT rules_version FROM races WHERE id = ?', rematchId).rules_version, 1, 'rematch copies rules_version');
  assert.equal(rematch.json.race.rulesVersion, 1, 'rematch response echoes rulesVersion');
});
