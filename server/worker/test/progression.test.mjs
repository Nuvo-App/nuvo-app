import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  XP_AWARDS,
  xpForLevel,
  levelForXp,
  categoryFor,
  statValue,
  reconcileProgression,
  readProgression,
  readBadgeCollection,
  readRaceXp,
  setFeaturedBadges,
  markLevelSeen,
  publicLevelFor,
  publicIdentityFor,
  publicProfileProgressionFor,
  featuredSlotsFor,
} = require('../.tmp-test-dist/domain/progression.js');

// ── In-memory D1 double covering every statement progression.ts runs ────────
const DEFS = [
  // Capability ladder slice
  { id: 'cap-badge-slot-2', required_level: 2, unlock_type: 'badge_slot', unlock_key: 'slot_2', name: 'Second badge slot', description: null, metadata_json: null, category: null, icon_key: 'slot', requirement_kind: 'level', stat_key: null, threshold: 2, sort_order: 10 },
  { id: 'cap-accent-ember', required_level: 3, unlock_type: 'accent', unlock_key: 'ember', name: 'Ember accent', description: null, metadata_json: null, category: null, icon_key: 'accent', requirement_kind: 'level', stat_key: null, threshold: 3, sort_order: 20 },
  { id: 'cap-badge-slot-3', required_level: 7, unlock_type: 'badge_slot', unlock_key: 'slot_3', name: 'Third badge slot', description: null, metadata_json: null, category: null, icon_key: 'slot', requirement_kind: 'level', stat_key: null, threshold: 7, sort_order: 30 },
  // Achievements
  { id: 'ach-first-move', required_level: 0, unlock_type: 'achievement', unlock_key: 'first_move', name: 'First Move', description: 'Submit your first accepted progress.', metadata_json: null, category: 'racing', icon_key: 'arrow_forward', requirement_kind: 'stat', stat_key: 'progresses_accepted', threshold: 1, sort_order: 10 },
  { id: 'ach-on-the-board', required_level: 0, unlock_type: 'achievement', unlock_key: 'on_the_board', name: 'On the Board', description: 'Finish your first race.', metadata_json: null, category: 'racing', icon_key: 'flag', requirement_kind: 'stat', stat_key: 'races_finished', threshold: 1, sort_order: 20 },
  { id: 'ach-five-deep', required_level: 0, unlock_type: 'achievement', unlock_key: 'five_deep', name: 'Five Deep', description: 'Finish 5 races.', metadata_json: null, category: 'racing', icon_key: 'flags_5', requirement_kind: 'stat', stat_key: 'races_finished', threshold: 5, sort_order: 30 },
  { id: 'ach-first-w', required_level: 0, unlock_type: 'achievement', unlock_key: 'first_w', name: 'First W', description: 'Win your first race.', metadata_json: null, category: 'winning', icon_key: 'trophy_1', requirement_kind: 'stat', stat_key: 'races_won', threshold: 1, sort_order: 10 },
  { id: 'ach-hat-trick', required_level: 0, unlock_type: 'achievement', unlock_key: 'hat_trick', name: 'Hat Trick', description: 'Win 3 races.', metadata_json: null, category: 'winning', icon_key: 'trophy_3', requirement_kind: 'stat', stat_key: 'races_won', threshold: 3, sort_order: 20 },
  { id: 'ach-race-maker', required_level: 0, unlock_type: 'achievement', unlock_key: 'race_maker', name: 'Race Maker', description: 'Create 3 races.', metadata_json: null, category: 'creation', icon_key: 'flag_plus', requirement_kind: 'stat', stat_key: 'races_created', threshold: 3, sort_order: 10 },
  { id: 'ach-personal-best', required_level: 0, unlock_type: 'achievement', unlock_key: 'personal_best', name: 'Personal Best', description: 'Set your first personal best.', metadata_json: null, category: 'performance', icon_key: 'spark_up', requirement_kind: 'stat', stat_key: 'pbs_set', threshold: 1, sort_order: 10 },
  { id: 'ach-comeback', required_level: 0, unlock_type: 'achievement', unlock_key: 'comeback', name: 'Comeback', description: 'Win a race after trailing.', metadata_json: null, category: 'performance', icon_key: 'arrow_curve', requirement_kind: 'stat', stat_key: 'comebacks', threshold: 1, sort_order: 30 },
  { id: 'ach-wire-to-wire', required_level: 0, unlock_type: 'achievement', unlock_key: 'wire_to_wire', name: 'Wire to Wire', description: 'Lead from first result to the finish.', metadata_json: null, category: 'performance', icon_key: 'crown_line', requirement_kind: 'stat', stat_key: 'wire_to_wires', threshold: 1, sort_order: 40 },
  { id: 'ach-crewmate', required_level: 0, unlock_type: 'achievement', unlock_key: 'crewmate', name: 'Crewmate', description: 'Finish 5 races with other people.', metadata_json: null, category: 'social', icon_key: 'people', requirement_kind: 'stat', stat_key: 'social_finished', threshold: 5, sort_order: 10 },
  { id: 'ach-crowd-favorite', required_level: 0, unlock_type: 'achievement', unlock_key: 'crowd_favorite', name: 'Crowd Favorite', description: 'Finish a race with 10+ racers.', metadata_json: null, category: 'social', icon_key: 'people_flag', requirement_kind: 'stat', stat_key: 'big_race_finished', threshold: 1, sort_order: 20 },
  { id: 'ach-rivalry', required_level: 0, unlock_type: 'achievement', unlock_key: 'rivalry', name: 'Rivalry', description: 'Finish 5 races against the same racer.', metadata_json: null, category: 'social', icon_key: 'crossed_flags', requirement_kind: 'stat', stat_key: 'rivalry_max', threshold: 5, sort_order: 30 },
  { id: 'ach-variety-pack', required_level: 0, unlock_type: 'achievement', unlock_key: 'variety_pack', name: 'Variety Pack', description: 'Finish races in 4 categories.', metadata_json: null, category: 'variety', icon_key: 'tiles_4', requirement_kind: 'stat', stat_key: 'distinct_categories', threshold: 4, sort_order: 10 },
  { id: 'ach-motion-rookie', required_level: 0, unlock_type: 'achievement', unlock_key: 'motion_rookie', name: 'Movement Rookie', description: 'Finish your first motion race.', metadata_json: null, category: 'motion', icon_key: 'motion_figure', requirement_kind: 'stat', stat_key: 'motion_finished', threshold: 1, sort_order: 10 },
  { id: 'ach-photo-finish', required_level: 0, unlock_type: 'achievement', unlock_key: 'photo_finish', name: 'Photo Finish', description: 'Finish your first photo-proof race.', metadata_json: null, category: 'proof', icon_key: 'camera', requirement_kind: 'stat', stat_key: 'photo_finished', threshold: 1, sort_order: 10 },
  { id: 'ach-proof-collector', required_level: 0, unlock_type: 'achievement', unlock_key: 'proof_collector', name: 'Proof Collector', description: 'Get 10 accepted photo proofs.', metadata_json: null, category: 'proof', icon_key: 'camera_check', requirement_kind: 'stat', stat_key: 'photo_proofs', threshold: 10, sort_order: 20 },
  { id: 'ach-time-trial', required_level: 0, unlock_type: 'achievement', unlock_key: 'time_trial', name: 'Time Trial', description: 'Finish your first timed race.', metadata_json: null, category: 'proof', icon_key: 'stopwatch', requirement_kind: 'stat', stat_key: 'timed_finished', threshold: 1, sort_order: 30 },
  { id: 'ach-book-it', required_level: 0, unlock_type: 'achievement', unlock_key: 'book_it', name: 'Book It', description: 'Finish your first reading race.', metadata_json: '{"categoryAliases":["books","novel","pages"]}', category: 'category', icon_key: 'book', requirement_kind: 'stat', stat_key: 'category:reading', threshold: 1, sort_order: 10 },
  { id: 'ach-on-the-green', required_level: 0, unlock_type: 'achievement', unlock_key: 'on_the_green', name: 'On the Green', description: 'Finish your first golf race.', metadata_json: '{"categoryAliases":["putting","driving_range"]}', category: 'category', icon_key: 'flag_golf', requirement_kind: 'stat', stat_key: 'category:golf', threshold: 1, sort_order: 50 },
  { id: 'ach-level-5', required_level: 5, unlock_type: 'achievement', unlock_key: 'level_5', name: 'Level 5', description: 'Reach Level 5.', metadata_json: null, category: 'level', icon_key: 'num_5', requirement_kind: 'level', stat_key: null, threshold: 5, sort_order: 10 },
];

function fakeDb() {
  const raceEvents = []; // {id, race_id, event_type, actor, subject, payload, meta, created_at}
  const xpEvents = new Map(); // 'user|type|sourceId' -> row
  const progression = new Map(); // user -> row
  const defs = DEFS.map((d) => ({ ...d }));
  const unlocks = new Map(); // 'user|unlockId' -> {unlocked_at}
  const featured = new Map(); // 'user|position' -> unlockId
  const members = new Map(); // raceId -> Set<userId>
  const races = new Map(); // raceId -> {id,title,status,winner_user_id,completed_at}
  const leadEvents = []; // {race_id, payload_json}

  let idc = 0;
  const nextId = () => `id-${++idc}`;

  const unlockKey = (user, unlockId) => `${user}|${unlockId}`;
  function ownedRows(user) {
    const out = [];
    for (const [k] of unlocks) {
      if (!k.startsWith(`${user}|`)) continue;
      const d = defs.find((x) => x.id === k.slice(user.length + 1));
      if (d) out.push(d);
    }
    return out;
  }
  function featuredEntries(user) {
    return [...featured.entries()]
      .filter(([k]) => k.startsWith(`${user}|`))
      .map(([k, unlockId]) => ({ position: Number(k.split('|')[1]), unlockId }))
      .sort((a, b) => a.position - b.position);
  }
  function statsOf(user) {
    const row = progression.get(user);
    return row?.stats_json ? JSON.parse(row.stats_json) : null;
  }

  return {
    raceEvents,
    xpEvents,
    progression,
    unlocks,
    featured,
    members,
    addEvent(type, subject, raceId = 'r1', opts = {}) {
      raceEvents.push({
        id: nextId(),
        race_id: raceId,
        event_type: type,
        actor_user_id: opts.actor ?? (type === 'race_created' ? subject : null),
        subject_user_id: subject,
        payload_json: opts.payload ? JSON.stringify(opts.payload) : null,
        created_at: new Date().toISOString(),
        activity_id: opts.activityId ?? 'push_ups',
        custom_activity_name: opts.customName ?? null,
        verification_type: opts.verification ?? 'camera_pose',
        format: opts.format ?? 'first_to_goal',
      });
    },
    addMembers(raceId, userIds) {
      members.set(raceId, new Set(userIds));
    },
    addRace(raceId, opts = {}) {
      races.set(raceId, {
        id: raceId,
        title: opts.title ?? 'Race',
        status: opts.status ?? 'completed',
        winner_user_id: opts.winnerUserId ?? null,
        completed_at: opts.completedAt ?? new Date().toISOString(),
      });
    },
    addLeadChange(raceId, newLeader) {
      leadEvents.push({ race_id: raceId, payload_json: JSON.stringify({ newLeaderUserId: newLeader }) });
    },
    prepare(sql) {
      const stmt = { _a: [] };
      stmt.bind = (...a) => {
        stmt._a = a;
        return stmt;
      };
      stmt.first = async () => {
        if (sql.includes('SELECT level FROM user_progression')) {
          const p = progression.get(stmt._a[0]);
          return p ? { level: p.level } : null;
        }
        if (sql.includes('SELECT total_xp FROM user_progression')) {
          const p = progression.get(stmt._a[0]);
          return p ? { total_xp: p.total_xp } : null;
        }
        if (sql.includes('COUNT(*) AS n FROM unlock_definitions')) {
          return { n: defs.filter((d) => d.unlock_type === 'achievement').length };
        }
        if (sql.includes('FROM xp_events') && sql.includes('SUM(')) {
          const u = stmt._a[0];
          let total = 0;
          for (const [k, r] of xpEvents) if (k.startsWith(`${u}|`)) total += r.xp_amount;
          return { total };
        }
        if (sql.includes('SELECT stats_json FROM user_progression')) {
          const p = progression.get(stmt._a[0]);
          return p ? { stats_json: p.stats_json ?? null } : null;
        }
        if (sql.includes('SELECT user_id, total_xp, level, last_seen_level')) {
          return progression.get(stmt._a[0]) ?? null;
        }
        if (sql.includes('FROM unlock_definitions') && sql.includes('required_level >') && sql.includes('NOT IN')) {
          const [level, user] = stmt._a;
          const def = defs
            .filter((d) => d.requirement_kind === 'level' && d.required_level > level && !unlocks.has(unlockKey(user, d.id)))
            .sort((a, b) => a.required_level - b.required_level || a.sort_order - b.sort_order)[0];
          return def ?? null;
        }
        if (sql.includes('FROM user_unlocks u') && sql.includes('d.required_level = ?')) {
          const [user, level] = stmt._a;
          const d = ownedRows(user).find((x) => x.required_level === level);
          return d ? { ...d, owned_at: unlocks.get(unlockKey(user, d.id))?.unlocked_at ?? null } : null;
        }
        if (sql.includes('COUNT(*) AS n FROM user_unlocks')) {
          const n = ownedRows(stmt._a[0]).filter((d) => d.unlock_type === 'achievement').length;
          return { n };
        }
        return null;
      };
      stmt.all = async () => {
        // publicProfileProgressionFor — grouped racing stats
        if (sql.includes('COUNT(*) AS n FROM race_events') && sql.includes('GROUP BY event_type')) {
          const user = stmt._a[0];
          const counts = new Map();
          for (const e of raceEvents) {
            if (e.subject_user_id !== user) continue;
            if (!['participant_finished', 'winner_determined'].includes(e.event_type)) continue;
            counts.set(e.event_type, (counts.get(e.event_type) ?? 0) + 1);
          }
          return { results: [...counts.entries()].map(([event_type, n]) => ({ event_type, n })) };
        }
        // publicProfileProgressionFor — earned achievement rows
        if (sql.includes('FROM user_unlocks u') && sql.includes("d.unlock_type = 'achievement'") && sql.includes('d.active = 1')) {
          const user = stmt._a[0];
          return {
            results: ownedRows(user)
              .filter((d) => d.unlock_type === 'achievement')
              .map((d) => ({ ...d, owned_at: unlocks.get(unlockKey(user, d.id))?.unlocked_at ?? null })),
          };
        }
        // publicProfileProgressionFor — shared completed races (bind: target, viewer)
        if (sql.includes('FROM race_members a') && sql.includes('JOIN races r')) {
          const [target, viewer] = stmt._a;
          const out = [];
          for (const [raceId, set] of members) {
            if (!set.has(target) || !set.has(viewer)) continue;
            const r = races.get(raceId);
            if (!r || r.status !== 'completed') continue;
            out.push({ id: r.id, title: r.title, winner_user_id: r.winner_user_id, completed_at: r.completed_at });
          }
          out.sort((a, b) => String(b.completed_at).localeCompare(String(a.completed_at)));
          return { results: out };
        }
        // reconcileProgression XP scan — event_type IN (...)
        if (sql.includes('FROM race_events') && sql.includes('event_type IN (')) {
          const [user, ...types] = stmt._a;
          return {
            results: raceEvents
              .filter((e) => e.subject_user_id === user && types.includes(e.event_type))
              .map((e) => ({ id: e.id, event_type: e.event_type, race_id: e.race_id, created_at: e.created_at, activity_id: e.activity_id, custom_activity_name: e.custom_activity_name })),
          };
        }
        // computeUserStats — subject OR actor, joined race meta
        if (sql.includes('FROM race_events') && sql.includes('actor_user_id')) {
          const user = stmt._a[0];
          return {
            results: raceEvents.filter(
              (e) => e.subject_user_id === user || e.actor_user_id === user,
            ),
          };
        }
        // lead history for won races
        if (sql.includes('FROM race_events') && sql.includes("event_type = 'lead_changed'")) {
          const ids = stmt._a;
          return {
            results: leadEvents.filter((e) => ids.includes(e.race_id)),
          };
        }
        if (sql.includes('FROM race_members')) {
          const ids = stmt._a;
          const out = [];
          for (const [raceId, set] of members) {
            if (ids.includes(raceId)) for (const uid of set) out.push({ race_id: raceId, user_id: uid });
          }
          return { results: out };
        }
        if (sql.includes('SELECT * FROM unlock_definitions WHERE active = 1')) {
          return { results: defs.map((d) => ({ ...d })) };
        }
        if (sql.includes('FROM user_featured_badges f') && sql.includes('LIMIT')) {
          const [user, limit] = stmt._a;
          return {
            results: featuredEntries(user)
              .slice(0, limit)
              .map(({ unlockId }) => {
                const d = defs.find((x) => x.id === unlockId);
                return d ? { id: d.id, unlock_key: d.unlock_key, name: d.name, icon_key: d.icon_key } : null;
              })
              .filter(Boolean),
          };
        }
        if (sql.includes('FROM user_featured_badges f')) {
          const user = stmt._a[0];
          return {
            results: featuredEntries(user).map(({ position, unlockId }) => {
              const d = defs.find((x) => x.id === unlockId);
              return { ...d, position, owned_at: unlocks.get(unlockKey(user, unlockId))?.unlocked_at ?? null };
            }),
          };
        }
        // readProgression owned unlocks (type,key only)
        if (sql.includes('FROM user_unlocks u') && sql.includes('unlock_type AS type') && !sql.includes('u.unlock_id')) {
          const user = stmt._a[0];
          return {
            results: ownedRows(user).map((d) => ({ type: d.unlock_type, key: d.unlock_key })),
          };
        }
        // setFeaturedBadges owned check (with unlock_id)
        if (sql.includes('FROM user_unlocks u') && sql.includes('u.unlock_id')) {
          const user = stmt._a[0];
          return {
            results: ownedRows(user).map((d) => ({ type: d.unlock_type, key: d.unlock_key, unlock_id: d.id })),
          };
        }
        // readProgression achievements list
        if (sql.includes('FROM unlock_definitions d') && sql.includes("unlock_type = 'achievement'") && sql.includes('LEFT JOIN user_unlocks')) {
          const user = stmt._a[0];
          return {
            results: defs
              .filter((d) => d.unlock_type === 'achievement')
              .map((d) => ({ ...d, owned_at: unlocks.get(unlockKey(user, d.id))?.unlocked_at ?? null })),
          };
        }
        // readBadgeCollection — all defs + featured positions
        if (sql.includes('FROM unlock_definitions d') && sql.includes('LEFT JOIN user_unlocks')) {
          const user = stmt._a[0];
          return {
            results: defs.map((d) => ({
              ...d,
              owned_at: unlocks.get(unlockKey(user, d.id))?.unlocked_at ?? null,
              featured_position: featuredEntries(user).find((f) => f.unlockId === d.id)?.position ?? null,
            })),
          };
        }
        // readRaceXp — grouped xp rows
        if (sql.includes('FROM xp_events') && sql.includes('GROUP BY source_type')) {
          const [user, raceId] = stmt._a;
          const sums = new Map();
          for (const [, r] of xpEvents) {
            if (r.user_id === user && r.race_id === raceId) {
              sums.set(r.source_type, (sums.get(r.source_type) ?? 0) + r.xp_amount);
            }
          }
          return { results: [...sums.entries()].map(([source_type, xp]) => ({ source_type, xp })) };
        }
        return { results: [] };
      };
      stmt.run = async () => {
        if (sql.includes('INSERT OR IGNORE INTO xp_events')) {
          const [id, user, type, sourceId, raceId, amount] = stmt._a;
          const key = `${user}|${type}|${sourceId}`;
          if (xpEvents.has(key)) return { meta: { changes: 0 } };
          xpEvents.set(key, { id, user_id: user, source_type: type, source_id: sourceId, race_id: raceId, xp_amount: amount });
          return { meta: { changes: 1 } };
        }
        if (sql.includes('INSERT INTO user_progression')) {
          const [user, totalXp, level, statsJson] = stmt._a;
          const existing = progression.get(user);
          progression.set(user, {
            user_id: user,
            total_xp: totalXp,
            level,
            last_seen_level: existing?.last_seen_level ?? 1,
            stats_json: statsJson ?? null,
          });
          return { meta: { changes: 1 } };
        }
        if (sql.includes('INSERT OR IGNORE INTO user_unlocks')) {
          const [id, user, unlockId] = stmt._a;
          const key = unlockKey(user, unlockId);
          if (unlocks.has(key)) return { meta: { changes: 0 } };
          unlocks.set(key, { unlocked_at: new Date().toISOString() });
          return { meta: { changes: 1 } };
        }
        if (sql.includes('UPDATE user_progression SET last_seen_level')) {
          const p = progression.get(stmt._a[0]);
          if (p) p.last_seen_level = p.level;
          return { meta: { changes: 1 } };
        }
        if (sql.includes('DELETE FROM user_featured_badges')) {
          for (const k of [...featured.keys()]) if (k.startsWith(`${stmt._a[0]}|`)) featured.delete(k);
          return { meta: { changes: 1 } };
        }
        if (sql.includes('INSERT INTO user_featured_badges')) {
          const [user, unlockId, position] = stmt._a;
          featured.set(`${user}|${position}`, unlockId);
          return { meta: { changes: 1 } };
        }
        return { meta: { changes: 0 } };
      };
      return stmt;
    },
    async batch(stmts) {
      const out = [];
      for (const s of stmts) out.push(await s.run());
      return out;
    },
    statsOf,
  };
}

// Convenience — a finish event on a race the user is a member of.
function finishRace(db, user, raceId, opts = {}) {
  db.addEvent('participant_finished', user, raceId, opts);
}

// ── Level curve ──────────────────────────────────────────────────────────────

test('level 1 starts at zero XP; early levels arrive quickly', () => {
  assert.equal(xpForLevel(1), 0);
  assert.equal(xpForLevel(2), 60);
  assert.equal(xpForLevel(3), 180);
  assert.ok(xpForLevel(11) - xpForLevel(10) > xpForLevel(3) - xpForLevel(2));
  assert.ok(xpForLevel(30) / xpForLevel(10) < 20);
});

test('levelForXp boundaries land exactly on thresholds', () => {
  assert.equal(levelForXp(0).level, 1);
  assert.equal(levelForXp(59).level, 1);
  assert.equal(levelForXp(60).level, 2);
  assert.equal(levelForXp(180).level, 3);
  const p = levelForXp(100);
  assert.equal(p.level, 2);
  assert.equal(p.currentLevelXp, 40);
  assert.equal(p.nextLevelXp, 120);
});

// ── Category derivation ──────────────────────────────────────────────────────

test('canonical categories come from race metadata, never titles', () => {
  assert.equal(categoryFor({ activity_id: 'push_ups', custom_activity_name: null }), 'push_ups');
  assert.equal(categoryFor({ activity_id: 'custom:Reading', custom_activity_name: 'Reading' }), 'reading');
  assert.equal(categoryFor({ activity_id: null, custom_activity_name: 'Mini Golf!' }), 'mini_golf');
  assert.equal(categoryFor({ activity_id: 'manual:reps', custom_activity_name: null }), 'other');
});

// ── Reconcile / XP awards ────────────────────────────────────────────────────

test('new user reconciles to level 1 with zero XP', async () => {
  const db = fakeDb();
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
  assert.equal(r.level, 1);
});

test('canonical events award the v2 schedule', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  db.addEvent('participant_finished', 'u1');
  db.addEvent('winner_determined', 'u1');
  db.addEvent('personal_best', 'u1');
  const r = await reconcileProgression(db, 'u1');
  // +10 progress +25 finish +15 win bonus +5 PB +5 discovery (first category)
  assert.equal(r.totalXp, 10 + 25 + 15 + 5 + 5);
});

test('discovery bonus pays once per canonical category', async () => {
  const db = fakeDb();
  // two progress events in the same category → one bonus
  db.addEvent('progress_accepted', 'u1', 'r1', { activityId: 'push_ups' });
  db.addEvent('progress_accepted', 'u1', 'r2', { activityId: 'push_ups' });
  // a new category → second bonus
  db.addEvent('progress_accepted', 'u1', 'r3', { activityId: 'custom:Reading', customName: 'Reading' });
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 10 * 3 + 5 * 2);
});

test('non-XP actions earn nothing', async () => {
  const db = fakeDb();
  db.addEvent('race_created', 'u1');
  db.addEvent('race_joined', 'u1');
  db.addEvent('rank_changed', 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
});

test('events about OTHER users do not award', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u2');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
});

test('reconcile is idempotent — retries cannot double-award XP', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  await reconcileProgression(db, 'u1');
  const again = await reconcileProgression(db, 'u1');
  const third = await reconcileProgression(db, 'u1');
  // +10 progress +5 discovery — exactly once across three reconciles
  assert.equal(again.totalXp, 15);
  assert.equal(third.totalXp, 15);
  assert.equal(db.xpEvents.size, 2);
});

test('loser still levels: completion XP without win bonus', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  db.addEvent('participant_finished', 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 10 + 25 + 5);
});

test('multi-level jump: enough XP crosses several thresholds at once', async () => {
  const db = fakeDb();
  for (let i = 0; i < 20; i++) db.addEvent('participant_finished', 'u1', `r${i}`);
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 500);
  assert.equal(r.level, levelForXp(500).level);
  assert.ok(r.level >= 4);
  assert.equal(r.previousLevel, 1);
});

// ── Canonical stats → stat achievements ──────────────────────────────────────

test('first accepted progress earns First Move', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-first-move'));
  assert.ok(db.unlocks.has('u1|ach-first-move'));
});

test('finish thresholds grant the racing ladder', async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) finishRace(db, 'u1', `r${i}`);
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-on-the-board'));
  assert.ok(r.newUnlockIds.includes('ach-five-deep'));
  assert.equal(db.statsOf('u1').racesFinished, 5);
});

test('race creation counts toward achievements, not XP', async () => {
  const db = fakeDb();
  for (let i = 0; i < 3; i++) db.addEvent('race_created', 'u1', `r${i}`);
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
  assert.ok(r.newUnlockIds.includes('ach-race-maker'));
});

test('wins and PBs feed their families', async () => {
  const db = fakeDb();
  db.addEvent('winner_determined', 'u1', 'r1');
  db.addEvent('personal_best', 'u1', 'r1');
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-first-w'));
  assert.ok(r.newUnlockIds.includes('ach-personal-best'));
});

test('social stats: racing with others and crowds', async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) {
    finishRace(db, 'u1', `r${i}`);
    db.addMembers(`r${i}`, ['u1', `other-${i}`]);
  }
  db.addEvent('participant_finished', 'u1', 'big');
  db.addMembers('big', ['u1', ...Array.from({ length: 10 }, (_, i) => `p${i}`)]);
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-crewmate'));
  assert.ok(r.newUnlockIds.includes('ach-crowd-favorite'));
});

test('rivalry counts races against the same opponent', async () => {
  const db = fakeDb();
  for (let i = 0; i < 5; i++) {
    finishRace(db, 'u1', `r${i}`);
    db.addMembers(`r${i}`, ['u1', 'rival-1']);
  }
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-rivalry'));
  assert.equal(db.statsOf('u1').rivalryMax, 5);
});

test('variety counts distinct canonical categories', async () => {
  const db = fakeDb();
  const cats = ['push_ups', 'squats', 'custom:Reading', 'custom:Golf'];
  for (let i = 0; i < 4; i++) {
    finishRace(db, 'u1', `r${i}`, {
      activityId: cats[i],
      customName: cats[i].startsWith('custom:') ? cats[i].slice(7) : null,
    });
  }
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-variety-pack'));
  assert.equal(db.statsOf('u1').distinctCategories, 4);
});

test('category families resolve via aliases', async () => {
  const db = fakeDb();
  finishRace(db, 'u1', 'r1', { activityId: 'custom:Books', customName: 'Books' });
  finishRace(db, 'u1', 'r2', { activityId: 'custom:Golf', customName: 'Golf' });
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-book-it')); // 'books' alias → reading family
  assert.ok(r.newUnlockIds.includes('ach-on-the-green'));
});

test('proof families: motion, photo, timed', async () => {
  const db = fakeDb();
  finishRace(db, 'u1', 'r1', { verification: 'camera_pose' });
  finishRace(db, 'u1', 'r2', { verification: 'photo' });
  finishRace(db, 'u1', 'r3', { format: 'timed_attempt' });
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-motion-rookie'));
  assert.ok(r.newUnlockIds.includes('ach-photo-finish'));
  assert.ok(r.newUnlockIds.includes('ach-time-trial'));
});

test('comeback: winning after someone else led', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1', 'r1', { payload: { newRank: 2 } });
  db.addLeadChange('r1', 'other-user');
  db.addEvent('participant_finished', 'u1', 'r1');
  db.addEvent('winner_determined', 'u1', 'r1');
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-comeback'));
  assert.ok(!r.newUnlockIds.includes('ach-wire-to-wire'));
});

test('wire to wire: led from first result through the win', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1', 'r1', { payload: { newRank: 1 } });
  db.addEvent('progress_accepted', 'u1', 'r1', { payload: { newRank: 1 } });
  db.addEvent('participant_finished', 'u1', 'r1');
  db.addEvent('winner_determined', 'u1', 'r1');
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('ach-wire-to-wire'));
  assert.ok(!r.newUnlockIds.includes('ach-comeback'));
});

test('level milestones grant on the same reconcile', async () => {
  const db = fakeDb();
  for (let i = 0; i < 20; i++) db.addEvent('participant_finished', 'u1', `r${i}`); // 500 XP → L4
  const r = await reconcileProgression(db, 'u1');
  assert.ok(r.newUnlockIds.includes('cap-badge-slot-2'));
  assert.ok(r.newUnlockIds.includes('cap-accent-ember'));
  assert.ok(!r.newUnlockIds.includes('ach-level-5')); // needs level 5
});

test('achievement grants are idempotent', async () => {
  const db = fakeDb();
  db.addEvent('participant_finished', 'u1');
  await reconcileProgression(db, 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.newUnlockIds.length, 0);
});

// ── Read payload ─────────────────────────────────────────────────────────────

test('readProgression returns level, progress, slots, achievement counts', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1'); // 10 + 5 discovery = 15 XP
  const p = await readProgression(db, 'u1');
  assert.equal(p.level, 1);
  assert.equal(p.totalXp, 15);
  assert.equal(p.xpToNext, 45);
  assert.equal(p.featuredSlots, 1); // base slot — ladder not climbed yet
  assert.equal(p.nextUnlock.unlockId, 'cap-badge-slot-2');
  assert.equal(p.achievementsEarned, 1); // first_move granted
  assert.equal(p.achievementsTotal, DEFS.filter((d) => d.unlock_type === 'achievement').length);
});

test('next unlock skips earned level defs', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1'); // 60 XP → L2
  const p = await readProgression(db, 'u1');
  assert.equal(p.nextUnlock.unlockId, 'cap-accent-ember');
  assert.equal(p.nextUnlock.level, 3);
  assert.equal(p.featuredSlots, 2); // slot_2 unlock landed
});

test('next achievement is the locked goal closest to done', async () => {
  const db = fakeDb();
  for (let i = 0; i < 4; i++) finishRace(db, 'u1', `r${i}`); // 4/5 → Five Deep
  const p = await readProgression(db, 'u1');
  assert.equal(p.nextAchievement.unlockId, 'ach-five-deep');
  assert.equal(p.nextAchievement.progressValue, 4);
  assert.equal(p.nextAchievement.threshold, 5);
});

test('next achievement falls back to the easiest goal for new racers', async () => {
  const db = fakeDb();
  const p = await readProgression(db, 'u1');
  assert.equal(p.nextAchievement.threshold, 1);
});

test('level-up arrives only once via last_seen_level', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  let p = await readProgression(db, 'u1');
  assert.equal(p.level, 2);
  assert.equal(p.lastSeenLevel, 1);
  await markLevelSeen(db, 'u1');
  p = await readProgression(db, 'u1');
  assert.equal(p.lastSeenLevel, 2);
});

// ── Collection ───────────────────────────────────────────────────────────────

test('collection carries category, icon, threshold, live progress', async () => {
  const db = fakeDb();
  for (let i = 0; i < 3; i++) finishRace(db, 'u1', `r${i}`);
  const badges = await readBadgeCollection(db, 'u1');
  const fiveDeep = badges.find((b) => b.unlockId === 'ach-five-deep');
  assert.equal(fiveDeep.unlocked, false);
  assert.equal(fiveDeep.progressValue, 3);
  assert.equal(fiveDeep.threshold, 5);
  assert.equal(fiveDeep.category, 'racing');
  assert.equal(fiveDeep.iconKey, 'flags_5');
  const onBoard = badges.find((b) => b.unlockId === 'ach-on-the-board');
  assert.equal(onBoard.unlocked, true);
  assert.ok(onBoard.unlockedAt);
});

// ── Featured badges ──────────────────────────────────────────────────────────

test('locked achievement cannot be featured', async () => {
  const db = fakeDb();
  const r = await setFeaturedBadges(db, 'u1', ['ach-first-move']);
  assert.equal(r.ok, false);
});

test('earned achievement can be featured', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  const r = await setFeaturedBadges(db, 'u1', ['ach-first-move']);
  assert.equal(r.ok, true);
  const p = await readProgression(db, 'u1');
  assert.equal(p.featuredBadges.length, 1);
  assert.equal(p.featuredBadges[0].unlockId, 'ach-first-move');
});

test('featured slots come from the unlock ladder, not a constant', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1'); // earns first_move → 1 slot
  const denied = await setFeaturedBadges(db, 'u1', ['ach-first-move', 'ach-on-the-board']);
  assert.equal(denied.ok, false);
});

test('duplicate featured entries are rejected', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1'); // L2 → 2 slots
  const r = await setFeaturedBadges(db, 'u1', ['ach-first-move', 'ach-first-move']);
  assert.equal(r.ok, false);
});

test('non-achievement unlocks cannot be featured', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1'); // owns cap-badge-slot-2
  const r = await setFeaturedBadges(db, 'u1', ['cap-badge-slot-2']);
  assert.equal(r.ok, false);
});

// ── Race XP breakdown ────────────────────────────────────────────────────────

test('race XP breakdown shows what one race paid', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1', 'r1');
  db.addEvent('participant_finished', 'u1', 'r1');
  db.addEvent('winner_determined', 'u1', 'r1');
  db.addEvent('personal_best', 'u1', 'r1');
  db.addEvent('progress_accepted', 'u1', 'r2'); // other race — excluded
  const xp = await readRaceXp(db, 'u1', 'r1');
  assert.equal(xp.totalXp, 10 + 25 + 15 + 5 + 5); // + discovery (first category)
  const labels = xp.lines.map((l) => l.label);
  assert.ok(labels.includes('Finish'));
  assert.ok(labels.includes('Win bonus'));
});

// ── Public identity ──────────────────────────────────────────────────────────

test('publicIdentityFor exposes level, earned count, featured icons', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  await reconcileProgression(db, 'u1');
  await setFeaturedBadges(db, 'u1', ['ach-first-move']);
  const id = await publicIdentityFor(db, 'u1');
  assert.equal(id.level, 2);
  assert.equal(id.achievementsEarned, 1);
  assert.equal(id.featured[0].name, 'First Move');
});

test('publicLevelFor reads cached level without reconciling', async () => {
  const db = fakeDb();
  assert.equal(await publicLevelFor(db, 'u1'), 1);
  db.addEvent('progress_accepted', 'u1');
  assert.equal(await publicLevelFor(db, 'u1'), 1);
  await reconcileProgression(db, 'u1');
  assert.equal(await publicLevelFor(db, 'u1'), 1);
});

// ── statValue unit checks ────────────────────────────────────────────────────

test('statValue resolves category families through aliases', () => {
  const stats = { categories: { books: 2, reading: 1, push_ups: 4 } };
  assert.equal(statValue(stats, 'category:reading', ['books', 'novel']), 3);
  assert.equal(statValue(stats, 'category:golf', ['putting']), 0);
  assert.equal(statValue(stats, 'races_finished'), 0);
});

test('featuredSlotsFor counts slot unlocks over the base slot', () => {
  assert.equal(featuredSlotsFor([]), 1);
  assert.equal(featuredSlotsFor([{ type: 'badge_slot', key: 'slot_2' }]), 2);
  assert.equal(
    featuredSlotsFor([
      { type: 'badge_slot', key: 'slot_2' },
      { type: 'accent', key: 'ember' },
      { type: 'badge_slot', key: 'slot_3' },
    ]),
    3,
  );
});

// ── Public profile progression (another member's identity) ──────────────────

test('public bundle carries level + fraction, never absolute XP', async () => {
  const db = fakeDb();
  finishRace(db, 'them', 'r1');
  db.addMembers('r1', ['them', 'me']);
  await reconcileProgression(db, 'them');

  const pub = await publicProfileProgressionFor(db, 'me', 'them');
  assert.equal(pub.level, 1);
  assert.equal(typeof pub.levelProgress, 'number');
  assert.ok(pub.levelProgress >= 0 && pub.levelProgress <= 1);
  assert.equal(pub.totalXp, undefined, 'public payload must not expose XP');
  assert.equal(pub.stats.races, 1);
  assert.equal(pub.stats.wins, 0);
});

test('public bundle reports earned achievements only', async () => {
  const db = fakeDb();
  finishRace(db, 'them', 'r1');
  db.addMembers('r1', ['them']);
  await reconcileProgression(db, 'them');

  const pub = await publicProfileProgressionFor(db, 'me', 'them');
  assert.equal(pub.achievementsEarned, pub.earned.length);
  assert.ok(pub.earned.length > 0);
  assert.ok(pub.earned.every((a) => a.unlocked === true));
  // Locked defs (hat trick at 0/3, five deep at 1/5) never surface publicly.
  assert.ok(!pub.earned.some((a) => a.key === 'hat_trick'));
  assert.ok(pub.achievementsTotal >= pub.achievementsEarned);
});

test('public bundle computes races-with-you from canonical rosters', async () => {
  const db = fakeDb();
  // Two shared finished races: viewer won one, target won one.
  db.addRace('shared-1', { title: 'Pushup Battle', winnerUserId: 'me', completedAt: '2026-09-15T10:00:00Z' });
  db.addRace('shared-2', { title: 'Squat Race', winnerUserId: 'them', completedAt: '2026-09-14T10:00:00Z' });
  db.addMembers('shared-1', ['me', 'them']);
  db.addMembers('shared-2', ['me', 'them']);
  // A race they finished without the viewer — not shared.
  db.addRace('theirs-only', { title: 'Solo Race', winnerUserId: 'them', completedAt: '2026-09-13T10:00:00Z' });
  db.addMembers('theirs-only', ['them']);
  // A shared race still running — not a finished shared result.
  db.addRace('still-live', { title: 'Live Race', status: 'active' });
  db.addMembers('still-live', ['me', 'them']);

  const pub = await publicProfileProgressionFor(db, 'me', 'them');
  assert.equal(pub.racesWithYou.total, 2);
  assert.equal(pub.racesWithYou.viewerWins, 1);
  assert.equal(pub.racesWithYou.targetWins, 1);
  assert.equal(pub.racesWithYou.recent.length, 2);
  assert.equal(pub.racesWithYou.recent[0].title, 'Pushup Battle');
});

test('public bundle marks featured achievements on the earned list', async () => {
  const db = fakeDb();
  finishRace(db, 'them', 'r1');
  db.addMembers('r1', ['them']);
  await reconcileProgression(db, 'them');
  await setFeaturedBadges(db, 'them', ['ach-on-the-board']);

  const pub = await publicProfileProgressionFor(db, 'me', 'them');
  assert.equal(pub.featured.length, 1);
  assert.equal(pub.featured[0].key, 'on_the_board');
  const firstMove = pub.earned.find((a) => a.key === 'on_the_board');
  assert.equal(firstMove.featured, true);
});
