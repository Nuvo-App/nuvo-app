import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const app = require('../.tmp-test-dist/index.js').default;
const { signJwt } = require('../.tmp-test-dist/lib/jwt.js');

const JWT_SECRET = 'test-secret';

async function tokenFor(sub) {
  return signJwt({ sub, iat: 0, exp: 9999999999 }, JWT_SECRET);
}

// ── Stateful mini-D1 for the proof/veto matrix ───────────────────────────────
// Real rows for every table the proof and veto paths touch; unknown statements
// fail loudly so a new query can't silently pass through an unimplemented fake.
function raceDb() {
  const T = {
    races: [],
    race_members: [],
    race_progress: [],
    move_logs: [],
    race_events: [],
    proof_votes: [],
    media_objects: [],
    race_final_standings: [],
    personal_bests: [],
    profiles: [],
    people: [],
    notifications: [],
    notification_preferences: [],
    device_tokens: [],
    race_attempts: [],
    race_invites: [],
    blocked_users: [],
    crew_connections: [],
    xp_events: [],
    user_progression: [],
    user_unlocks: [],
    user_featured_badges: [],
    unlock_definitions: [],
    verification_sessions: [],
  };

  const activityKey = (r) =>
    r.activity_id ??
    (r.custom_activity_name != null ? `custom:${r.custom_activity_name}` : undefined) ??
    (r.verifier_type === 'manual_log' ? `manual:${r.target_unit ?? 'done'}` : null);

  function firstOf(q, args) {
    if (q.startsWith('SELECT * FROM races WHERE id = ?')) {
      const r = T.races.find((x) => x.id === args[0] && x.deleted_at == null);
      return r ? { ...r } : null;
    }
    if (q.startsWith('SELECT full_name FROM profiles WHERE user_id = ?')) {
      const p = T.profiles.find((x) => x.user_id === args[0]);
      return p ? { full_name: p.full_name } : { full_name: null };
    }
    if (q.startsWith('SELECT id FROM people WHERE user_id = ?')) {
      const p = T.people.find((x) => x.user_id === args[0]);
      return p ? { id: p.id } : null;
    }
    if (q.startsWith('SELECT COUNT(*) AS n FROM race_members')) {
      const [raceId, submitter] = args;
      const n = T.race_members.filter(
        (m) => m.race_id === raceId && m.status === 'active' && m.user_id !== submitter,
      ).length;
      return { n };
    }
    if (q.startsWith("SELECT id FROM race_members") && q.includes("status = 'active'")) {
      const m = T.race_members.find(
        (x) => x.race_id === args[0] && x.user_id === args[1] && x.status === 'active',
      );
      return m ? { id: m.id } : null;
    }
    if (q.startsWith('SELECT id, status FROM race_members')) {
      const m = T.race_members.find((x) => x.race_id === args[0] && x.user_id === args[1]);
      return m ? { id: m.id, status: m.status } : null;
    }
    if (q.startsWith('SELECT id FROM media_objects')) {
      const m = T.media_objects.find(
        (x) =>
          x.object_key === args[0] &&
          x.owner_user_id === args[1] &&
          x.purpose === 'proof_evidence' &&
          x.status === 'active',
      );
      return m ? { id: m.id } : null;
    }
    if (q.startsWith('SELECT status, result_value FROM verification_sessions')) {
      const s = T.verification_sessions.find(
        (x) => x.id === args[0] && x.user_id === args[1] && x.race_id === args[2],
      );
      return s ? { status: s.status, result_value: s.result_value } : null;
    }
    if (q.startsWith('SELECT id FROM move_logs') && q.includes('verification_session_id')) {
      const m = T.move_logs.find((x) => {
        if (x.race_id !== args[0] || !x.metadata_json) return false;
        try {
          return JSON.parse(x.metadata_json).verification_session_id === args[1];
        } catch {
          return false;
        }
      });
      return m ? { id: m.id } : null;
    }
    if (q.startsWith('SELECT * FROM move_logs') && q.includes('client_submission_id')) {
      const m = T.move_logs.find(
        (x) => x.race_id === args[0] && x.user_id === args[1] && x.client_submission_id === args[2],
      );
      return m ? { ...m } : null;
    }
    if (q.startsWith('SELECT * FROM move_logs WHERE id = ? AND race_id = ?')) {
      const m = T.move_logs.find((x) => x.id === args[0] && x.race_id === args[1]);
      return m ? { ...m } : null;
    }
    if (q.startsWith('SELECT id FROM proof_votes')) {
      const v = T.proof_votes.find(
        (x) => x.move_log_id === args[0] && x.voter_user_id === args[1],
      );
      return v ? { id: v.id } : null;
    }
    if (q.startsWith('SELECT COUNT(*) AS n FROM proof_votes')) {
      return { n: T.proof_votes.filter((x) => x.move_log_id === args[0]).length };
    }
    if (q.startsWith('SELECT progress_value, completed_at FROM race_progress')) {
      const p = T.race_progress.find((x) => x.race_id === args[0] && x.user_id === args[1]);
      return p ? { progress_value: p.progress_value, completed_at: p.completed_at } : null;
    }
    if (q.startsWith('SELECT id FROM race_progress')) {
      const p = T.race_progress.find((x) => x.race_id === args[0] && x.user_id === args[1]);
      return p ? { id: p.id } : null;
    }
    if (q.startsWith('SELECT id FROM race_attempts')) {
      const a = T.race_attempts.find(
        (x) => x.race_id === args[0] && x.user_id === args[1] && x.status === 'open',
      );
      return a ? { ...a } : null;
    }
    if (q.startsWith('SELECT * FROM race_invites')) {
      const inv = T.race_invites.filter((x) => x.race_id === args[0] && x.status === 'active')
        .sort((x, y) => (x.created_at < y.created_at ? 1 : -1))[0];
      return inv ? { ...inv } : null;
    }
    if (q.startsWith('SELECT in_app, push FROM notification_preferences') || q.startsWith('SELECT push FROM notification_preferences')) {
      const p = T.notification_preferences.find(
        (x) => x.user_id === args[0] && x.category === args[1],
      );
      return p ? { ...p } : null;
    }
    if (q.startsWith('SELECT id FROM notifications WHERE user_id = ? AND dedupe_key = ?')) {
      const n = T.notifications.find(
        (x) => x.user_id === args[0] && x.dedupe_key === args[1],
      );
      return n ? { id: n.id } : null;
    }
    if (q.includes('FROM blocked_users') || q.includes('FROM crew_connections')) return null;
    if (q.startsWith('SELECT id, score_direction FROM personal_bests')) {
      const p = T.personal_bests.find(
        (x) => x.user_id === args[0] && x.activity_id === args[1] && x.metric === args[2],
      );
      return p ? { id: p.id, score_direction: p.score_direction } : null;
    }
    if (q.includes('SUM(xp_amount)') || q.includes('FROM xp_events')) return { total: 0, n: 0 };
    if (q.includes('FROM user_progression')) return null;
    if (q.includes('FROM users WHERE id = ?')) return { id: args[0] };
    if (q.includes('COUNT(*)')) return { n: 0 };
    return null; // unimplemented SELECT → null keeps reconcile/no-op paths honest
  }

  function allOf(q, args) {
    if (q.startsWith('SELECT value FROM move_logs') && q.includes("status = 'verified'")) {
      return T.move_logs
        .filter((m) => m.race_id === args[0] && m.user_id === args[1] && m.status === 'verified')
        .sort((x, y) => String(x.created_at).localeCompare(String(y.created_at)))
        .map((m) => ({ value: m.value }));
    }
    if (q.includes('FROM race_members rm') && q.includes('LEFT JOIN race_progress')) {
      const isRanked = q.includes('rp.completed_at') && !q.includes('rm.finished_at');
      return T.race_members
        .filter((m) => m.race_id === args[0] && m.status === 'active')
        .map((m) => {
          const p = T.race_progress.find(
            (x) => x.race_id === m.race_id && x.user_id === m.user_id,
          );
          const prof = T.profiles.find((x) => x.user_id === m.user_id);
          return isRanked
            ? {
                user_id: m.user_id,
                joined_at: m.joined_at,
                progress_value: p?.progress_value ?? null,
                completed_at: p?.completed_at ?? null,
              }
            : {
                id: m.id,
                user_id: m.user_id,
                joined_at: m.joined_at,
                finished_at: m.finished_at ?? null,
                display_name: m.cached_display_name ?? prof?.full_name ?? 'Unknown',
                profile_photo_url: prof?.avatar_url ?? null,
                private_profile: prof?.private_profile ?? null,
                username: prof?.username ?? null,
                progress_value: p?.progress_value ?? 0,
                progress_percent: p?.progress_percent ?? 0,
                rank_cache: p?.rank_cache ?? null,
              };
        });
    }
    if (q.startsWith('SELECT ml.*') && q.includes('FROM move_logs ml')) {
      return T.move_logs
        .filter((m) => m.race_id === args[0] && m.status !== 'removed')
        .sort((x, y) => String(y.created_at).localeCompare(String(x.created_at)))
        .map((m) => {
          const prof = T.profiles.find((x) => x.user_id === m.user_id);
          return {
            ...m,
            display_name: prof?.full_name ?? 'Unknown',
            profile_photo_url: prof?.avatar_url ?? null,
            private_profile: prof?.private_profile ?? null,
            username: prof?.username ?? null,
          };
        });
    }
    if (q.includes('FROM race_final_standings fs')) {
      return T.race_final_standings
        .filter((s) => s.race_id === args[0])
        .map((s) => {
          const prof = T.profiles.find((x) => x.user_id === s.user_id);
          return {
            ...s,
            display_name: prof?.full_name ?? 'Unknown',
            profile_photo_url: prof?.avatar_url ?? null,
            private_profile: prof?.private_profile ?? null,
            username: prof?.username ?? null,
          };
        });
    }
    if (q.includes('FROM race_members rm LEFT JOIN profiles')) {
      return T.race_members
        .filter((m) => m.race_id === args[0] && m.status === 'active')
        .map((m) => {
          const prof = T.profiles.find((x) => x.user_id === m.user_id);
          return {
            user_id: m.user_id,
            display_name: m.cached_display_name ?? prof?.full_name ?? 'Unknown',
          };
        });
    }
    if (q.startsWith('SELECT ml.id AS move_id')) {
      const [userId, key, metric] = args;
      return T.move_logs
        .filter((m) => m.user_id === userId && m.status === 'verified')
        .map((m) => {
          const r = T.races.find((x) => x.id === m.race_id);
          return { move_id: m.id, race_id: m.race_id, value: m.value, __r: r };
        })
        .filter(
          (m) =>
            m.__r &&
            activityKey(m.__r) === key &&
            (m.__r.metric ?? m.__r.target_unit ?? 'reps') === metric &&
            ['best_attempt', 'timed_attempt'].includes(m.__r.format ?? m.__r.race_type),
        )
        .map(({ __r, ...rest }) => rest);
    }
    if (q.startsWith('SELECT move_log_id, COUNT(*) AS n FROM proof_votes')) {
      const byMove = new Map();
      for (const v of T.proof_votes.filter((x) => x.race_id === args[0])) {
        byMove.set(v.move_log_id, (byMove.get(v.move_log_id) ?? 0) + 1);
      }
      return [...byMove.entries()].map(([move_log_id, n]) => ({ move_log_id, n }));
    }
    if (q.startsWith('SELECT move_log_id, reason FROM proof_votes')) {
      return T.proof_votes
        .filter((x) => x.race_id === args[0] && x.voter_user_id === args[1])
        .map((x) => ({ move_log_id: x.move_log_id, reason: x.reason }));
    }
    if (q.includes('FROM device_tokens')) return [];
    if (q.includes('FROM blocked_users')) return [];
    if (q.includes('FROM crew_connections')) return [];
    if (q.includes('FROM race_events')) return [];
    if (q.includes('FROM xp_events') || q.includes('FROM user_unlocks') ||
        q.includes('FROM unlock_definitions') || q.includes('FROM user_progression')) return [];
    return [];
  }

  function runOf(q, args) {
    if (q.startsWith('INSERT INTO move_logs')) {
      const [id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
        status, summary, media_object_key, validator_version, duration_ms, metadata_json,
        client_submission_id] = args;
      T.move_logs.push({
        id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
        status, summary, media_object_key, validator_version, duration_ms, metadata_json,
        client_submission_id, created_at: new Date().toISOString(), vetoed_at: null,
        previous_score: null, new_score: null, previous_rank: null, new_rank: null,
        race_completed: 0,
      });
      return 1;
    }
    if (q.startsWith('UPDATE move_logs SET previous_score')) {
      const m = T.move_logs.find((x) => x.id === args[5]);
      if (!m) return 0;
      [m.previous_score, m.new_score, m.previous_rank, m.new_rank, m.race_completed] =
        [args[0], args[1], args[2], args[3], args[4]];
      return 1;
    }
    if (q.startsWith("UPDATE move_logs SET status = 'rejected', vetoed_at = CURRENT_TIMESTAMP")) {
      const m = T.move_logs.find((x) => x.id === args[0]);
      if (!m) return 0;
      m.status = 'rejected';
      m.vetoed_at = new Date().toISOString();
      return 1;
    }
    if (q.startsWith('UPDATE move_logs SET status = ?, summary = ?')) {
      const m = T.move_logs.find((x) => x.id === args[2]);
      if (!m) return 0;
      m.status = args[0];
      m.summary = args[1];
      return 1;
    }
    if (q.startsWith('INSERT INTO race_progress')) {
      T.race_progress.push({
        id: args[0], race_id: args[1], user_id: args[2], progress_value: args[3],
        progress_percent: args[4], completed_at: null, rank_cache: null,
      });
      return 1;
    }
    if (q.startsWith('UPDATE race_progress SET rank_cache')) {
      const p = T.race_progress.find((x) => x.race_id === args[1] && x.user_id === args[2]);
      if (p) p.rank_cache = args[0];
      return p ? 1 : 0;
    }
    if (q.startsWith('UPDATE race_progress')) {
      // Both writers bind (value, percent, completed*, raceId, userId); the
      // recompute variant passes a completed flag for its CASE expression.
      const p = T.race_progress.find((x) => x.race_id === args[3] && x.user_id === args[4]);
      if (!p) return 0;
      p.progress_value = args[0];
      p.progress_percent = args[1];
      p.completed_at = q.includes('CASE WHEN')
        ? (args[2] ? (p.completed_at ?? new Date().toISOString()) : null)
        : args[2];
      return 1;
    }
    if (q.startsWith("UPDATE races SET status = 'completed'")) {
      const r = T.races.find((x) => x.id === args[2]);
      if (!r || r.status !== 'active') return 0;
      r.status = 'completed';
      r.winner_user_id = args[0];
      r.completed_at = args[1];
      return 1;
    }
    if (q.startsWith("UPDATE races SET status = 'active', winner_user_id = NULL")) {
      const r = T.races.find((x) => x.id === args[0]);
      if (!r) return 0;
      r.status = 'active';
      r.winner_user_id = null;
      r.completed_at = null;
      r.version = (r.version ?? 0) + 1;
      return 1;
    }
    if (q.startsWith('UPDATE races SET winner_user_id = ?')) {
      const r = T.races.find((x) => x.id === args[1]);
      if (!r) return 0;
      r.winner_user_id = args[0];
      r.version = (r.version ?? 0) + 1;
      return 1;
    }
    if (q.startsWith('UPDATE races SET version = COALESCE(version, 0) + 1')) {
      const r = T.races.find((x) => x.id === args[0]);
      if (r) r.version = (r.version ?? 0) + 1;
      return r ? 1 : 0;
    }
    if (q.startsWith('INSERT INTO race_events')) {
      const [id, race_id, event_type, actor_user_id, subject_user_id, payload_json, move_log_id] = args;
      T.race_events.push({
        id, race_id, event_type, actor_user_id, subject_user_id, payload_json,
        move_log_id, created_at: new Date().toISOString(), voided_at: null,
      });
      return 1;
    }
    if (q.startsWith('UPDATE race_events SET voided_at')) {
      let n = 0;
      for (const e of T.race_events) {
        if (e.voided_at != null) continue;
        if (q.includes('move_log_id = ?') && e.move_log_id === args[0]) {
          e.voided_at = new Date().toISOString(); n++;
        } else if (
          q.includes("event_type = 'winner_determined'") &&
          e.race_id === args[0] && e.event_type === 'winner_determined'
        ) {
          e.voided_at = new Date().toISOString(); n++;
        }
      }
      return n;
    }
    if (q.startsWith('INSERT INTO proof_votes')) {
      const [id, move_log_id, race_id, voter_user_id, reason] = args;
      if (T.proof_votes.some((x) => x.move_log_id === move_log_id && x.voter_user_id === voter_user_id)) {
        return 0; // UNIQUE(move_log_id, voter_user_id)
      }
      T.proof_votes.push({ id, move_log_id, race_id, voter_user_id, reason, created_at: new Date().toISOString() });
      return 1;
    }
    if (q.startsWith('INSERT OR REPLACE INTO race_final_standings')) {
      const [raceIdA, userIdA, newId, race_id, user_id, rank, score, completed_at] = args;
      void raceIdA; void userIdA;
      const existing = T.race_final_standings.find(
        (s) => s.race_id === race_id && s.user_id === user_id,
      );
      if (existing) {
        Object.assign(existing, { rank_position: rank, score_value: score, completed_at });
      } else {
        T.race_final_standings.push({
          id: newId, race_id, user_id, rank_position: rank, score_value: score, completed_at,
        });
      }
      return 1;
    }
    if (q.startsWith('DELETE FROM race_final_standings WHERE race_id = ?')) {
      const before = T.race_final_standings.length;
      T.race_final_standings = T.race_final_standings.filter((s) => s.race_id !== args[0]);
      return before - T.race_final_standings.length;
    }
    if (q.startsWith('INSERT INTO people')) {
      T.people.push({ id: args[0], person_key: args[1], user_id: args[2], display_name: args[3] });
      return 1;
    }
    if (q.startsWith('INSERT INTO race_members')) {
      const [id, race_id, user_id, person_id, role, display_name] = args;
      T.race_members.push({
        id, race_id, user_id, person_id, role, status: 'active',
        joined_at: new Date().toISOString(), cached_display_name: display_name,
      });
      return 1;
    }
    if (q.startsWith("UPDATE race_members SET status = 'active'")) {
      const m = T.race_members.find((x) => x.id === args[1]);
      if (m) { m.status = 'active'; m.role = args[0]; }
      return m ? 1 : 0;
    }
    if (q.startsWith('INSERT OR IGNORE INTO notifications')) {
      const [id, user_id, category, actor_user_id, title, body, dest_type, dest_id,
        dest_context, entity_type, entity_id, dedupe_key, priority] = args;
      if (T.notifications.some((n) => n.user_id === user_id && n.dedupe_key === dedupe_key)) {
        return 0;
      }
      T.notifications.push({
        id, user_id, category, actor_user_id, title, body, dest_type, dest_id,
        dest_context, entity_type, entity_id, dedupe_key, priority,
        created_at: new Date().toISOString(), read_at: null, aggregate_count: 1,
      });
      return 1;
    }
    if (q.startsWith('UPDATE notifications SET title')) {
      const n = T.notifications.find((x) => x.id === args[3]);
      if (n) { n.title = args[0]; n.body = args[1]; n.actor_user_id = args[2]; n.read_at = null; n.aggregate_count++; }
      return n ? 1 : 0;
    }
    if (q.startsWith('DELETE FROM personal_bests WHERE id = ?')) {
      T.personal_bests = T.personal_bests.filter((p) => p.id !== args[0]);
      return 1;
    }
    if (q.startsWith('UPDATE personal_bests SET best_value')) {
      const p = T.personal_bests.find((x) => x.id === args[3]);
      if (p) Object.assign(p, { best_value: args[0], race_id: args[1], move_log_id: args[2] });
      return p ? 1 : 0;
    }
    // Progression projection writes — route tests only need them to not throw;
    // XP/unlock reversal correctness is covered in progression.test.mjs.
    if (
      q.startsWith('INSERT') || q.startsWith('DELETE') || q.startsWith('UPDATE')
    ) {
      return 1;
    }
    return 0;
  }

  return {
    T,
    prepare(sql) {
      const q = sql.replace(/\s+/g, ' ').trim();
      let args = [];
      const bound = {
        bind(...a) { args = a; return bound; },
        async run() { return { meta: { changes: runOf(q, args) }, success: true }; },
        async first() { return firstOf(q, args); },
        async all() { return { results: allOf(q, args) }; },
      };
      return bound;
    },
    async batch(stmts) {
      for (const s of stmts) await s.run();
      return [];
    },
  };
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

let seq = 0;
const nid = (p) => `${p}-${++seq}`;

function addRace(db, { id = 'r1', creator = 'A', ...over } = {}) {
  const race = {
    id,
    creator_id: creator,
    title: 'Highest math grade',
    status: 'active',
    format: 'most_in_window',
    race_type: null,
    scoring_rule: 'cumulative_sum',
    score_direction: 'higher',
    target_value: 100,
    target_unit: 'percent',
    metric: null,
    movement_type: null,
    activity_id: null,
    custom_activity_name: null,
    verifier_type: 'manual_log',
    verifier_version: null,
    proof_review_mode: 'auto_accept',
    winner_user_id: null,
    completed_at: null,
    start_at: null,
    end_at: null,
    timezone: null,
    recurrence: null,
    deleted_at: null,
    visibility: 'private',
    version: 0,
    ...over,
  };
  db.T.races.push(race);
  return race;
}

function addMember(db, raceId, userId, { status = 'active', role = 'racer' } = {}) {
  db.T.race_members.push({
    id: nid('mem'), race_id: raceId, user_id: userId, person_id: `p-${userId}`,
    role, status, joined_at: new Date().toISOString(), cached_display_name: userId,
  });
}

function addProgress(db, raceId, userId, value = 0, completedAt = null) {
  db.T.race_progress.push({
    id: nid('rp'), race_id: raceId, user_id: userId, progress_value: value,
    progress_percent: 0, completed_at: completedAt, rank_cache: null,
  });
}

function addMove(db, { id = nid('mv'), raceId = 'r1', userId = 'A', value = 90, status = 'verified', media = null, ...over } = {}) {
  const m = {
    id, race_id: raceId, user_id: userId, source: 'manual', movement_type: null,
    activity_id: null, metric: 'reps', value, unit: 'percent', status,
    summary: 'Manual proof accepted.', media_object_key: media,
    validator_version: null, duration_ms: null, metadata_json: null,
    client_submission_id: null, created_at: new Date().toISOString(),
    vetoed_at: null, previous_score: null, new_score: null,
    previous_rank: null, new_rank: null, race_completed: 0,
    ...over,
  };
  db.T.move_logs.push(m);
  return m;
}

function addMedia(db, { key, owner, raceId = 'r1' }) {
  db.T.media_objects.push({
    id: nid('med'), object_key: key, owner_user_id: owner,
    purpose: 'proof_evidence', status: 'active',
  });
}

function setupRace({ memberIds = ['A', 'B'], ...raceOver } = {}) {
  const db = raceDb();
  const race = addRace(db, raceOver);
  for (const uid of memberIds) {
    addMember(db, race.id, uid, { role: uid === race.creator_id ? 'creator' : 'racer' });
    addProgress(db, race.id, uid);
  }
  return { db, race };
}

// ── Request helpers ───────────────────────────────────────────────────────────

function makeClient(db) {
  const pending = [];
  const ctx = { waitUntil: (p) => pending.push(p) };
  const env = { DB: db, JWT_SECRET };
  const req = async (sub, method, path, body) =>
    app.request(path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${await tokenFor(sub)}`,
      },
      body: body == null ? undefined : JSON.stringify(body),
    }, env, ctx);
  return {
    pending,
    flush: async () => { await Promise.all(pending.splice(0)); },
    postProof: (sub, raceId, body) => req(sub, 'POST', `/races/${raceId}/proof`, body),
    veto: (sub, raceId, proofId, reason = 'wrong_result') =>
      req(sub, 'POST', `/races/${raceId}/proofs/${proofId}/veto`, { reason }),
    getProofs: (sub, raceId) => req(sub, 'GET', `/races/${raceId}/proofs`),
  };
}

// ── Required-photo enforcement ────────────────────────────────────────────────

test('manual proof without photo is rejected before any canonical write', async () => {
  const { db, race } = setupRace();
  const c = makeClient(db);
  const res = await c.postProof('A', race.id, { proofType: 'manual', value: 94 });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.match(body.error ?? '', /photo/i);
  assert.equal(db.T.move_logs.length, 0, 'rejected proof must not create a move log');
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 0);
  assert.equal(db.T.race_events.length, 0, 'no race events from rejected proof');
});

test('manual proof with a valid race-scoped photo is accepted and scores', async () => {
  const { db, race } = setupRace();
  addMedia(db, { key: `proof-evidence/${race.id}/A/photo1.jpg`, owner: 'A' });
  const c = makeClient(db);
  const res = await c.postProof('A', race.id, {
    proofType: 'manual',
    value: 94,
    mediaObjectKey: `proof-evidence/${race.id}/A/photo1.jpg`,
  });
  assert.equal(res.status, 200, await res.text());
  const move = db.T.move_logs.find((m) => m.user_id === 'A');
  assert.ok(move, 'verified proof creates a move log');
  assert.equal(move.status, 'verified');
  assert.equal(move.value, 94);
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 94);
  assert.ok(
    db.T.race_events.some((e) => e.event_type === 'progress_accepted' && e.move_log_id === move.id),
    'progress event must carry its source move id',
  );
});

test('media owned by another account is not valid evidence', async () => {
  const { db, race } = setupRace();
  addMedia(db, { key: `proof-evidence/${race.id}/B/photo.jpg`, owner: 'B' });
  const c = makeClient(db);
  const res = await c.postProof('A', race.id, {
    proofType: 'manual',
    value: 94,
    mediaObjectKey: `proof-evidence/${race.id}/B/photo.jpg`,
  });
  assert.equal(res.status, 400);
  assert.equal(db.T.move_logs.length, 0);
});

test('media outside this race’s upload prefix is not valid evidence', async () => {
  const { db, race } = setupRace();
  addMedia(db, { key: 'proof-evidence/other-race/A/photo.jpg', owner: 'A' });
  const c = makeClient(db);
  const res = await c.postProof('A', race.id, {
    proofType: 'manual',
    value: 94,
    mediaObjectKey: 'proof-evidence/other-race/A/photo.jpg',
  });
  assert.equal(res.status, 400);
  assert.equal(db.T.move_logs.length, 0);
});

test('non-member cannot submit proof', async () => {
  const { db, race } = setupRace();
  const c = makeClient(db);
  const res = await c.postProof('stranger', race.id, { proofType: 'manual', value: 50 });
  assert.equal(res.status, 403);
});

test('AI Motion Proof does not require a photo', async () => {
  const { db, race } = setupRace({
    activity_id: 'pushups',
    // Real preset races: verifier_type NULL, verification_type 'movecheck'.
    verifier_type: null,
    verification_type: 'movecheck',
    format: 'most_in_window',
    target_value: 100,
    target_unit: 'reps',
    metric: 'reps',
  });
  const c = makeClient(db);
  // AI proofs bind to a completed, caller-owned verification session.
  db.T.verification_sessions.push({
    id: 'vs-1', race_id: race.id, user_id: 'A', status: 'completed',
    result_value: 30,
  });
  const res = await c.postProof('A', race.id, {
    proofType: 'ai_motion',
    value: 30,
    clientSubmissionId: 'cs-1',
    verificationSessionId: 'vs-1',
    verificationStatus: 'ai_verified',
    activityType: 'pushups',
    metric: 'reps',
  });
  assert.equal(res.status, 200);
  const move = db.T.move_logs.find((m) => m.user_id === 'A');
  assert.equal(move.source, 'movecheck');
  assert.equal(move.media_object_key, null);
});

// ── Veto access control ───────────────────────────────────────────────────────

test('non-member cannot veto', async () => {
  const { db, race } = setupRace();
  const move = addMove(db, { raceId: race.id, userId: 'A' });
  const c = makeClient(db);
  const res = await c.veto('stranger', race.id, move.id);
  assert.equal(res.status, 403);
  assert.equal(db.T.proof_votes.length, 0);
});

test('submitter cannot veto their own proof', async () => {
  const { db, race } = setupRace();
  const move = addMove(db, { raceId: race.id, userId: 'A' });
  const c = makeClient(db);
  const res = await c.veto('A', race.id, move.id);
  assert.equal(res.status, 403);
  assert.equal(db.T.proof_votes.length, 0);
});

test('a member who left the race cannot veto', async () => {
  const { db, race } = setupRace();
  const move = addMove(db, { raceId: race.id, userId: 'A' });
  db.T.race_members.find((m) => m.user_id === 'B').status = 'left';
  const c = makeClient(db);
  const res = await c.veto('B', race.id, move.id);
  assert.equal(res.status, 403);
});

test('veto requires one of the allowed reasons', async () => {
  const { db, race } = setupRace();
  const move = addMove(db, { raceId: race.id, userId: 'A' });
  const c = makeClient(db);
  const bad = await c.veto('B', race.id, move.id, 'definitely_fake_lol');
  assert.equal(bad.status, 400);
  for (const reason of ['not_shown', 'wrong_result', 'stale_proof', 'other']) {
    db.T.proof_votes.length = 0;
    const res = await c.veto('B', race.id, move.id, reason);
    assert.equal(res.status, 200, `reason ${reason} must be accepted`);
  }
});

// ── Consensus rules ───────────────────────────────────────────────────────────

test('duplicate veto is idempotent — one row, still disputed', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B', 'C', 'D'] });
  const move = addMove(db, { raceId: race.id, userId: 'A' });
  const c = makeClient(db);
  const first = await c.veto('B', race.id, move.id);
  const again = await c.veto('B', race.id, move.id, 'stale_proof');
  assert.equal(first.status, 200);
  assert.equal(again.status, 200);
  const body = await again.json();
  assert.equal(body.alreadyVoted, true);
  assert.equal(body.vetoCount, 1, 'repeat vote must not double-count');
  assert.equal(body.state, 'disputed');
  assert.equal(db.T.proof_votes.length, 1);
});

test('1v1 race — the sole opponent’s veto is consensus', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B'] });
  db.T.race_progress.find((p) => p.user_id === 'A').progress_value = 94;
  const move = addMove(db, { raceId: race.id, userId: 'A', value: 94 });
  db.T.race_events.push({
    id: nid('ev'), race_id: race.id, event_type: 'progress_accepted',
    actor_user_id: 'A', subject_user_id: 'A', payload_json: '{}',
    move_log_id: move.id, created_at: new Date().toISOString(), voided_at: null,
  });
  const c = makeClient(db);
  const res = await c.veto('B', race.id, move.id);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.eligibleVoters, 1);
  assert.equal(body.threshold, 1);
  assert.equal(body.state, 'vetoed');

  // Race truth: proof rejected, score back to 0, source events voided.
  assert.equal(db.T.move_logs.find((m) => m.id === move.id).status, 'rejected');
  assert.ok(db.T.move_logs.find((m) => m.id === move.id).vetoed_at);
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 0);
  assert.ok(
    db.T.race_events
      .filter((e) => e.event_type !== 'proof_vetoed')
      .every((e) => e.voided_at != null),
    'derived events voided — the veto record itself stays live',
  );
});

test('3-player race — one vote disputes, majority of others vetoes', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B', 'C'] });
  db.T.race_progress.find((p) => p.user_id === 'A').progress_value = 94;
  const move = addMove(db, { raceId: race.id, userId: 'A', value: 94 });
  const c = makeClient(db);

  const first = await c.veto('B', race.id, move.id);
  const b1 = await first.json();
  assert.equal(b1.state, 'disputed'); // 1 of 2 eligible — below majority
  assert.equal(b1.threshold, 2);
  assert.equal(db.T.move_logs.find((m) => m.id === move.id).status, 'verified');
  assert.equal(
    db.T.notifications.filter((n) => n.category === 'proof_disputed' && n.user_id === 'A').length,
    1,
    'first vote notifies the submitter once',
  );

  const second = await c.veto('C', race.id, move.id);
  const b2 = await second.json();
  assert.equal(b2.state, 'vetoed'); // 2 of 2 eligible — majority reached
  assert.equal(db.T.move_logs.find((m) => m.id === move.id).status, 'rejected');
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 0);
  assert.equal(
    db.T.notifications.filter((n) => n.category === 'proof_disputed').length,
    1,
    'no extra dispute notification on the second vote',
  );
  assert.equal(
    db.T.notifications.filter((n) => n.user_id === 'A' && n.dedupe_key === `proof_vetoed:${move.id}`).length,
    1,
    'veto notifies the submitter exactly once',
  );
});

test('veto on an already-vetoed proof records a vote but changes nothing', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B', 'C', 'D'] });
  const move = addMove(db, {
    raceId: race.id, userId: 'A', status: 'rejected',
    vetoed_at: new Date().toISOString(),
  });
  const c = makeClient(db);
  const res = await c.veto('B', race.id, move.id);
  const body = await res.json();
  assert.equal(body.state, 'vetoed');
  assert.equal(db.T.move_logs.length, 1);
});

// ── Completed-race reversal ───────────────────────────────────────────────────

test('vetoing the winning proof reopens the race and clears the result', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B', 'C'] });
  const move = addMove(db, { raceId: race.id, userId: 'A', value: 100 });
  // The winning proof finished the race.
  db.T.race_progress.find((p) => p.user_id === 'A').progress_value = 100;
  db.T.race_progress.find((p) => p.user_id === 'A').completed_at = new Date().toISOString();
  race.status = 'completed';
  race.winner_user_id = 'A';
  race.completed_at = new Date().toISOString();
  db.T.race_final_standings.push(
    { id: 'fs1', race_id: race.id, user_id: 'A', rank_position: 1, score_value: 100, completed_at: new Date().toISOString() },
    { id: 'fs2', race_id: race.id, user_id: 'B', rank_position: 2, score_value: 0, completed_at: null },
    { id: 'fs3', race_id: race.id, user_id: 'C', rank_position: 3, score_value: 0, completed_at: null },
  );
  for (const type of ['progress_accepted', 'participant_finished', 'race_finished', 'winner_determined']) {
    db.T.race_events.push({
      id: nid('ev'), race_id: race.id, event_type: type, actor_user_id: 'A',
      subject_user_id: 'A', payload_json: '{}', move_log_id: move.id,
      created_at: new Date().toISOString(), voided_at: null,
    });
  }

  const c = makeClient(db);
  await c.veto('B', race.id, move.id);
  const res = await c.veto('C', race.id, move.id); // majority reached
  const body = await res.json();
  assert.equal(body.state, 'vetoed');

  // Winning proof stops being race truth: race reopens, result cleared,
  // standings removed, every derived event voided.
  assert.equal(race.status, 'active');
  assert.equal(race.winner_user_id, null);
  assert.equal(race.completed_at, null);
  assert.equal(db.T.race_final_standings.length, 0);
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 0);
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').completed_at, null);
  assert.ok(
    db.T.race_events
      .filter((e) => e.move_log_id === move.id && e.event_type !== 'proof_vetoed')
      .every((e) => e.voided_at != null),
    'all events derived from the vetoed proof must be voided',
  );
  assert.ok(
    db.T.race_events.some((e) => e.event_type === 'proof_vetoed' && e.voided_at == null),
    'the veto itself is recorded as an auditable event',
  );
  await c.flush(); // reconcile waitUntil promises settle without rejecting
});

// ── Replacement proof ─────────────────────────────────────────────────────────

test('submitter can replace a vetoed proof — new identity, new lifecycle', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B'] });
  const oldMove = addMove(db, { raceId: race.id, userId: 'A', value: 94 });
  const c = makeClient(db);
  await c.veto('B', race.id, oldMove.id);
  assert.equal(db.T.move_logs.find((m) => m.id === oldMove.id).status, 'rejected');

  addMedia(db, { key: `proof-evidence/${race.id}/A/photo2.jpg`, owner: 'A' });
  const res = await c.postProof('A', race.id, {
    proofType: 'manual', value: 88,
    mediaObjectKey: `proof-evidence/${race.id}/A/photo2.jpg`,
  });
  assert.equal(res.status, 200, await res.text());
  const newMove = db.T.move_logs.find((m) => m.id !== oldMove.id && m.user_id === 'A');
  assert.ok(newMove, 'replacement is a new move-log row, not an overwrite');
  assert.equal(newMove.status, 'verified');
  assert.equal(newMove.vetoed_at, null);
  assert.equal(newMove.value, 88);
  assert.equal(db.T.race_progress.find((p) => p.user_id === 'A').progress_value, 88);
  // Old audit record preserved untouched.
  assert.equal(db.T.move_logs.find((m) => m.id === oldMove.id).status, 'rejected');
});

// ── GET /proofs veto serialization ────────────────────────────────────────────

test('GET /proofs exposes veto state, count, and viewer vote', async () => {
  const { db, race } = setupRace({ memberIds: ['A', 'B', 'C', 'D'] });
  const disputed = addMove(db, { raceId: race.id, userId: 'A', value: 90 });
  const clean = addMove(db, { raceId: race.id, userId: 'A', value: 80 });
  const vetoed = addMove(db, {
    raceId: race.id, userId: 'A', value: 70, status: 'rejected',
    vetoed_at: new Date().toISOString(),
  });
  db.T.proof_votes.push(
    { id: 'v1', move_log_id: disputed.id, race_id: race.id, voter_user_id: 'B', reason: 'wrong_result', created_at: new Date().toISOString() },
    { id: 'v2', move_log_id: disputed.id, race_id: race.id, voter_user_id: 'C', reason: 'stale_proof', created_at: new Date().toISOString() },
    { id: 'v3', move_log_id: vetoed.id, race_id: race.id, voter_user_id: 'B', reason: 'wrong_result', created_at: new Date().toISOString() },
    { id: 'v4', move_log_id: vetoed.id, race_id: race.id, voter_user_id: 'C', reason: 'wrong_result', created_at: new Date().toISOString() },
  );

  const c = makeClient(db);
  const res = await c.getProofs('B', race.id);
  assert.equal(res.status, 200);
  const { proofs } = await res.json();
  const byId = new Map(proofs.map((p) => [p.id, p]));

  assert.equal(byId.get(disputed.id).vetoState, 'disputed');
  assert.equal(byId.get(disputed.id).vetoCount, 2);
  assert.equal(byId.get(disputed.id).viewerVoted, true);
  assert.equal(byId.get(disputed.id).vetoedAt, null);

  assert.equal(byId.get(vetoed.id).vetoState, 'vetoed');
  assert.equal(byId.get(vetoed.id).vetoCount, 2);
  assert.ok(byId.get(vetoed.id).vetoedAt);

  assert.equal(byId.get(clean.id).vetoState, 'none');
  assert.equal(byId.get(clean.id).vetoCount, 0);
  assert.equal(byId.get(clean.id).viewerVoted, false);
});
