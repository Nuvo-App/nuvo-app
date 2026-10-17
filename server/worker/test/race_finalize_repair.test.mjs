// Atomic race finalization + repair sweep, against the captured PROD schema.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { finalizeRaceIfEnded, repairCompletedRaces, sweepRaceLifecycle } = require('../.tmp-test-dist/domain/raceFinalize.js');

const root = new URL('..', import.meta.url);
const SCHEMA = [
  readFileSync(new URL('test/fixtures/prod_schema_2026-09-28.sql', root), 'utf8'),
  readFileSync(new URL('migrations/0043_proof_votes.sql', root), 'utf8'),
];

function d1(sqlite, hooks = {}) {
  const norm = (args) => args.map((v) => (v === undefined ? null : v));
  const stmt = (sql, args = []) => ({
    sql,
    bind: (...a) => stmt(sql, a),
    async first(col) {
      const row = sqlite.prepare(sql).get(...norm(args));
      if (!row) return null;
      return col ? row[col] : { ...row };
    },
    async all() {
      return { success: true, meta: {}, results: sqlite.prepare(sql).all(...norm(args)).map((r) => ({ ...r })) };
    },
    async run() {
      return this.runSync();
    },
    runSync() {
      const info = sqlite.prepare(sql).run(...norm(args));
      return { success: true, meta: { changes: Number(info.changes) } };
    },
  });
  return {
    prepare: (sql) => stmt(sql),
    async batch(stmts) {
      hooks.onBatch?.(stmts);
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

function world(hooks) {
  const sqlite = new DatabaseSync(':memory:');
  for (const sql of SCHEMA) sqlite.exec(sql);
  const db = d1(sqlite, hooks);
  const q = (sql, ...a) => sqlite.prepare(sql).all(...a).map((r) => ({ ...r }));
  const exec = (sql, ...a) => sqlite.prepare(sql).run(...a);
  const user = (id) => {
    exec("INSERT INTO users (id, primary_email, status, terms_accepted_at, created_at, updated_at) VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)", id, `${id}@example.com`);
    exec('INSERT INTO people (id, person_key, user_id, display_name) VALUES (?, ?, ?, ?)', `p-${id}`, `user-${id}`, id, id);
  };
  let n = 0;
  const member = (raceId, userId, value) => {
    exec(
      "INSERT INTO race_members (id, race_id, person_id, user_id, role, status, joined_at) VALUES (?, ?, ?, ?, 'racer', 'active', datetime('now', ?))",
      `rm-${raceId}-${userId}`, raceId, `p-${userId}`, userId, `-${1000 - ++n} seconds`,
    );
    exec('INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent) VALUES (?, ?, ?, ?, 0)', `rp-${raceId}-${userId}`, raceId, userId, value);
  };
  const race = (id, over = {}) => {
    const r = { status: 'active', end_at: '2026-01-02T00:00:00.000Z', completed_at: null, ...over };
    exec(
      `INSERT INTO races (id, creator_id, title, race_type, format, verification_type, status, visibility, public_join_enabled,
         scoring_rule, score_direction, target_value, target_unit, metric, verifier_type, proof_review_mode, start_at, end_at, completed_at,
         created_at, updated_at)
       VALUES (?, 'A', 'Race', 'most_in_window', 'most_in_window', 'manual', ?, 'public_demo', 1,
         'cumulative_sum', 'higher', NULL, 'pages', 'reps', 'manual_log', 'auto_accept', NULL, ?, ?,
         '2026-01-01T00:00:00Z', '2026-01-01 00:00:00')`,
      id, r.status, r.end_at, r.completed_at,
    );
  };
  return { sqlite, db, q, exec, user, member, race };
}

const NOW = new Date('2026-01-02T12:00:00.000Z');
const raceRow = (w, id) => w.q('SELECT * FROM races WHERE id = ?', id)[0];

function seedActive(w) {
  w.user('A'); w.user('B'); w.user('C');
  w.race('r1');
  w.member('r1', 'A', 10); w.member('r1', 'B', 30); w.member('r1', 'C', 20);
}

test('finalize writes claim, winner and standings together, then events once', async () => {
  const w = world();
  seedActive(w);
  const res = await finalizeRaceIfEnded(w.db, raceRow(w, 'r1'), NOW);
  assert.equal(res.finalized, true);
  assert.equal(res.winnerUserId, 'B');
  const r = raceRow(w, 'r1');
  assert.equal(r.status, 'completed');
  assert.equal(r.winner_user_id, 'B');
  const st = w.q('SELECT user_id, rank_position FROM race_final_standings WHERE race_id = ? ORDER BY rank_position', 'r1');
  assert.deepEqual(st.map((s) => s.user_id), ['B', 'C', 'A']);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'race_finished'").length, 1);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'winner_determined'").length, 1);
  // Second caller is a no-op.
  const again = await finalizeRaceIfEnded(w.db, raceRow(w, 'r1'), NOW);
  assert.equal(again.finalized, false);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'race_finished'").length, 1);
});

test('a failure inside the finalize batch leaves the race active (no half-completed state)', async () => {
  const w = world({
    onBatch: () => { throw new Error('simulated crash'); },
  });
  seedActive(w);
  await assert.rejects(() => finalizeRaceIfEnded(w.db, raceRow(w, 'r1'), NOW), /simulated crash/);
  assert.equal(raceRow(w, 'r1').status, 'active');
  assert.equal(w.q('SELECT id FROM race_final_standings').length, 0);
});

test('a batch rolled back midway (bad standings row) leaves claim undone', async () => {
  const w = world();
  seedActive(w);
  // Make a standings insert fail inside the batch.
  w.sqlite.exec('CREATE TRIGGER boom BEFORE INSERT ON race_final_standings BEGIN SELECT RAISE(ABORT, \'boom\'); END');
  await assert.rejects(() => finalizeRaceIfEnded(w.db, raceRow(w, 'r1'), NOW), /boom/);
  const r = raceRow(w, 'r1');
  assert.equal(r.status, 'active');
  assert.equal(r.winner_user_id, null);
});

test('repair: completed race missing standings/event is re-derived and notified once', async () => {
  const w = world();
  seedActive(w);
  // Footprint of the old crash: claimed but nothing else written.
  w.exec("UPDATE races SET status = 'completed', completed_at = end_at WHERE id = 'r1'");
  const first = await repairCompletedRaces(w.db, NOW);
  assert.equal(first.length, 1);
  assert.deepEqual(first[0].events.map((e) => e.type), ['race_finished', 'winner_determined']);
  assert.equal(raceRow(w, 'r1').winner_user_id, 'B');
  assert.equal(w.q('SELECT id FROM race_final_standings WHERE race_id = ?', 'r1').length, 3);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'race_finished'").length, 1);
  // Idempotent.
  const second = await repairCompletedRaces(w.db, NOW);
  assert.equal(second.length, 0);
  assert.equal(w.q('SELECT id FROM race_final_standings WHERE race_id = ?', 'r1').length, 3);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'race_finished'").length, 1);
});

test('repair: standings present but event missing only adds the event', async () => {
  const w = world();
  seedActive(w);
  const fin = await finalizeRaceIfEnded(w.db, raceRow(w, 'r1'), NOW);
  assert.equal(fin.finalized, true);
  w.exec("DELETE FROM race_events WHERE race_id = 'r1'");
  w.exec("UPDATE races SET updated_at = '2026-01-02 00:00:00' WHERE id = 'r1'"); // settled
  const ids = w.q('SELECT id FROM race_final_standings ORDER BY id').map((r) => r.id);
  const out = await repairCompletedRaces(w.db, NOW);
  assert.equal(out.length, 1);
  assert.deepEqual(w.q('SELECT id FROM race_final_standings ORDER BY id').map((r) => r.id), ids);
  assert.equal(w.q("SELECT id FROM race_events WHERE event_type = 'race_finished'").length, 1);
});

test('repair skips old, recently-touched, and healthy races; sweep runs it', async () => {
  const w = world();
  w.user('A'); w.user('B');
  w.race('old', { status: 'completed', end_at: '2025-01-02T00:00:00.000Z', completed_at: '2025-01-02T00:00:00.000Z' });
  w.member('old', 'A', 5);
  assert.equal((await repairCompletedRaces(w.db, NOW)).length, 0);
  // Recently touched (another request may be mid-write).
  w.race('fresh', { status: 'completed', completed_at: '2026-01-02T00:00:00.000Z' });
  w.member('fresh', 'A', 5);
  w.exec("UPDATE races SET updated_at = '2026-01-02 11:59:30' WHERE id = 'fresh'");
  assert.equal((await repairCompletedRaces(w.db, NOW)).length, 0);
  // Through the lifecycle sweep once settled.
  const later = new Date('2026-01-02T13:00:00.000Z');
  const transitions = await sweepRaceLifecycle(w.db, later);
  assert.equal(transitions.filter((t) => t.race.id === 'fresh').length, 1);
  assert.equal(w.q("SELECT id FROM race_events WHERE race_id = 'old'").length, 0);
});
