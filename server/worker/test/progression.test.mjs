import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  XP_AWARDS,
  xpForLevel,
  levelForXp,
  reconcileProgression,
  readProgression,
  readBadgeCollection,
  setFeaturedBadges,
  markLevelSeen,
  publicLevelFor,
  FEATURED_BADGE_SLOTS,
} = require('../.tmp-test-dist/domain/progression.js');

// ── In-memory D1 double covering every statement progression.ts runs ────────
const DEFS = [
  { id: 'bdg-off-the-line', required_level: 2, unlock_type: 'badge', unlock_key: 'off_the_line', name: 'Off the Line', description: null, metadata_json: '{"icon":"flag","rarity":"standard"}' },
  { id: 'bdg-in-motion', required_level: 3, unlock_type: 'badge', unlock_key: 'in_motion', name: 'In Motion', description: null, metadata_json: '{"icon":"bolt","rarity":"standard"}' },
  { id: 'bdg-five-deep', required_level: 5, unlock_type: 'badge', unlock_key: 'five_deep', name: 'Five Deep', description: null, metadata_json: '{"icon":"flame","rarity":"milestone"}' },
  { id: 'bdg-locked-in', required_level: 7, unlock_type: 'badge', unlock_key: 'locked_in', name: 'Locked In', description: null, metadata_json: '{"icon":"target","rarity":"standard"}' },
  { id: 'bdg-double-digits', required_level: 10, unlock_type: 'badge', unlock_key: 'double_digits', name: 'Double Digits', description: null, metadata_json: '{"icon":"medal","rarity":"milestone"}' },
];

function fakeDb() {
  const raceEvents = []; // {id, race_id, event_type, subject_user_id, created_at}
  const xpEvents = new Map(); // 'user|type|sourceId' -> row
  const progression = new Map(); // user -> {user_id,total_xp,level,last_seen_level}
  const defs = DEFS.map((d) => ({ ...d }));
  const unlocks = new Map(); // 'user|unlockId' -> {unlocked_at}
  const featured = new Map(); // 'user|position' -> unlockId  (+dup check map)

  let idc = 0;
  const nextId = () => `id-${++idc}`;

  function unlockKey(user, unlockId) {
    return `${user}|${unlockId}`;
  }
  function ownedBadge(user, unlockId) {
    const def = defs.find((d) => d.id === unlockId);
    return unlocks.has(unlockKey(user, unlockId)) && def?.unlock_type === 'badge';
  }
  function featuredEntries(user) {
    return [...featured.entries()]
      .filter(([k]) => k.startsWith(`${user}|`))
      .map(([k, unlockId]) => ({ position: Number(k.split('|')[1]), unlockId }))
      .sort((a, b) => a.position - b.position);
  }

  return {
    raceEvents,
    xpEvents,
    progression,
    unlocks,
    featured,
    addEvent(type, subject, raceId = 'r1') {
      raceEvents.push({
        id: nextId(),
        race_id: raceId,
        event_type: type,
        subject_user_id: subject,
        created_at: new Date().toISOString(),
      });
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
        if (sql.includes('FROM xp_events') && sql.includes('SUM(')) {
          const u = stmt._a[0];
          let total = 0;
          for (const [k, r] of xpEvents) if (k.startsWith(`${u}|`)) total += r.xp_amount;
          return { total };
        }
        if (sql.includes('SELECT user_id, total_xp, level, last_seen_level FROM user_progression')) {
          return progression.get(stmt._a[0]) ?? null;
        }
        if (sql.includes('FROM unlock_definitions') && sql.includes('required_level >') && sql.includes('NOT IN')) {
          const [level, user] = stmt._a;
          const def = defs
            .filter((d) => d.required_level > level && !unlocks.has(unlockKey(user, d.id)))
            .sort((a, b) => a.required_level - b.required_level)[0];
          return def ?? null;
        }
        if (sql.includes('FROM user_unlocks u') && sql.includes("unlock_type = 'badge'")) {
          const [user, unlockId] = stmt._a;
          return ownedBadge(user, unlockId) ? { yes: 1 } : null;
        }
        return null;
      };
      stmt.all = async () => {
        if (sql.includes('FROM race_events') && sql.includes('subject_user_id')) {
          const [user, ...types] = stmt._a;
          return {
            results: raceEvents
              .filter((e) => e.subject_user_id === user && types.includes(e.event_type)),
          };
        }
        if (sql.includes('SELECT id FROM unlock_definitions')) {
          return {
            results: defs.filter((d) => d.required_level <= stmt._a[0]).map((d) => ({ id: d.id })),
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
        if (sql.includes('FROM unlock_definitions d') && sql.includes('LEFT JOIN user_unlocks')) {
          const user = stmt._a[0];
          return {
            results: defs.map((d) => ({
              ...d,
              owned_at: unlocks.get(unlockKey(user, d.id))?.unlocked_at ?? null,
              featured_position:
                featuredEntries(user).find((f) => f.unlockId === d.id)?.position ?? null,
            })),
          };
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
          const [user, totalXp, level] = stmt._a;
          const existing = progression.get(user);
          progression.set(user, {
            user_id: user,
            total_xp: totalXp,
            level,
            last_seen_level: existing?.last_seen_level ?? 1,
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
  };
}

// ── Level curve ──────────────────────────────────────────────────────────────

test('level 1 starts at zero XP; early levels arrive quickly', () => {
  assert.equal(xpForLevel(1), 0);
  assert.equal(xpForLevel(2), 60);
  assert.equal(xpForLevel(3), 180);
  // Later levels cost progressively more, not exponentially.
  assert.ok(xpForLevel(11) - xpForLevel(10) > xpForLevel(3) - xpForLevel(2));
  assert.ok(xpForLevel(30) / xpForLevel(10) < 20);
});

test('levelForXp boundaries land exactly on thresholds', () => {
  assert.equal(levelForXp(0).level, 1);
  assert.equal(levelForXp(59).level, 1);
  assert.equal(levelForXp(60).level, 2);
  assert.equal(levelForXp(179).level, 2);
  assert.equal(levelForXp(180).level, 3);
  const p = levelForXp(100);
  assert.equal(p.level, 2);
  assert.equal(p.currentLevelXp, 40);
  assert.equal(p.nextLevelXp, 120);
});

// ── Reconcile / XP awards ────────────────────────────────────────────────────

test('new user reconciles to level 1 with zero XP', async () => {
  const db = fakeDb();
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
  assert.equal(r.level, 1);
});

test('canonical events award their configured XP', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  db.addEvent('participant_finished', 'u1');
  db.addEvent('winner_determined', 'u1');
  db.addEvent('personal_best', 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 10 + 25 + 10 + 5);
});

test('non-XP event types are ignored', async () => {
  const db = fakeDb();
  db.addEvent('race_joined', 'u1');
  db.addEvent('rank_changed', 'u1');
  db.addEvent('lead_changed', 'u1');
  db.addEvent('attempt_completed', 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
});

test('events about OTHER users do not award', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u2');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 0);
});

test('reconcile is idempotent — retries cannot double-award', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  await reconcileProgression(db, 'u1');
  const again = await reconcileProgression(db, 'u1');
  const third = await reconcileProgression(db, 'u1');
  assert.equal(again.totalXp, 10);
  assert.equal(third.totalXp, 10);
  assert.equal(db.xpEvents.size, 1);
});

test('loser still levels: completion XP without winner bonus', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1');
  db.addEvent('participant_finished', 'u1'); // finished but did not win
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 35);
});

test('multi-level jump: enough XP crosses several thresholds at once', async () => {
  const db = fakeDb();
  for (let i = 0; i < 20; i++) db.addEvent('participant_finished', 'u1', `r${i}`); // 500 XP
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.totalXp, 500);
  assert.equal(r.level, levelForXp(500).level); // level 4 — multi-level jump
  assert.ok(r.level >= 4, `expected level >= 4, got ${r.level}`);
  assert.equal(r.previousLevel, 1);
});

// ── Unlocks ──────────────────────────────────────────────────────────────────

test('crossing a badge level grants the unlock', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1'); // 60 XP → level 2
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.level, 2);
  assert.ok(r.newUnlockIds.includes('bdg-off-the-line'));
  assert.ok(db.unlocks.has('u1|bdg-off-the-line'));
});

test('unlock grants are idempotent', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  await reconcileProgression(db, 'u1');
  const r = await reconcileProgression(db, 'u1');
  assert.equal(r.newUnlockIds.length, 0);
});

test('level-up arrives only once via last_seen_level', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  let p = await readProgression(db, 'u1');
  assert.equal(p.level, 2);
  assert.equal(p.lastSeenLevel, 1); // unseen → client should present
  await markLevelSeen(db, 'u1');
  p = await readProgression(db, 'u1');
  assert.equal(p.lastSeenLevel, 2); // acknowledged → no replay
});

// ── Read payload ─────────────────────────────────────────────────────────────

test('readProgression returns level, progress, and next unlock', async () => {
  const db = fakeDb();
  db.addEvent('progress_accepted', 'u1'); // 10 XP → level 1, 50 to level 2
  const p = await readProgression(db, 'u1');
  assert.equal(p.level, 1);
  assert.equal(p.totalXp, 10);
  assert.equal(p.xpToNext, 50);
  assert.equal(p.nextUnlock.unlockId, 'bdg-off-the-line');
  assert.equal(p.nextUnlock.level, 2);
});

test('next unlock skips already-earned definitions', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1'); // level 2, owns L2 badge
  const p = await readProgression(db, 'u1');
  assert.equal(p.nextUnlock.unlockId, 'bdg-in-motion');
  assert.equal(p.nextUnlock.level, 3);
});

test('badge collection lists locked badges with requirements', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  const badges = await readBadgeCollection(db, 'u1');
  const offLine = badges.find((b) => b.unlockId === 'bdg-off-the-line');
  const locked = badges.find((b) => b.unlockId === 'bdg-double-digits');
  assert.equal(offLine.unlocked, true);
  assert.equal(locked.unlocked, false);
  assert.equal(locked.requiredLevel, 10);
});

// ── Featured badges ──────────────────────────────────────────────────────────

test('locked badge cannot be featured', async () => {
  const db = fakeDb();
  const r = await setFeaturedBadges(db, 'u1', ['bdg-off-the-line']);
  assert.equal(r.ok, false);
});

test('owned badge can be featured', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  const r = await setFeaturedBadges(db, 'u1', ['bdg-off-the-line']);
  assert.equal(r.ok, true);
  const p = await readProgression(db, 'u1');
  assert.equal(p.featuredBadges.length, 1);
  assert.equal(p.featuredBadges[0].unlockId, 'bdg-off-the-line');
});

test('duplicate featured badges are rejected', async () => {
  const db = fakeDb();
  for (let i = 0; i < 6; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  const r = await setFeaturedBadges(db, 'u1', ['bdg-off-the-line', 'bdg-off-the-line']);
  assert.equal(r.ok, false);
});

test('more than the slot count is rejected', async () => {
  const db = fakeDb();
  const ids = Array.from({ length: FEATURED_BADGE_SLOTS + 1 }, (_, i) => `x${i}`);
  const r = await setFeaturedBadges(db, 'u1', ids);
  assert.equal(r.ok, false);
});

test('replacing featured set clears the old one', async () => {
  const db = fakeDb();
  for (let i = 0; i < 12; i++) db.addEvent('participant_finished', 'u1', `r${i}`); // 300 XP → L3
  await reconcileProgression(db, 'u1');
  await setFeaturedBadges(db, 'u1', ['bdg-off-the-line']);
  await setFeaturedBadges(db, 'u1', ['bdg-in-motion']);
  const p = await readProgression(db, 'u1');
  assert.equal(p.featuredBadges.length, 1);
  assert.equal(p.featuredBadges[0].unlockId, 'bdg-in-motion');
});

// ── Public level ─────────────────────────────────────────────────────────────

test('publicLevelFor reads cached level without reconciling', async () => {
  const db = fakeDb();
  assert.equal(await publicLevelFor(db, 'u1'), 1); // never played
  db.addEvent('progress_accepted', 'u1');
  assert.equal(await publicLevelFor(db, 'u1'), 1); // cached row not written yet
  await reconcileProgression(db, 'u1');
  // still level 1 — bump to level 2
  for (let i = 0; i < 5; i++) db.addEvent('progress_accepted', 'u1', 'r1');
  await reconcileProgression(db, 'u1');
  assert.equal(await publicLevelFor(db, 'u1'), 2);
});

// ── Award map sanity ─────────────────────────────────────────────────────────

test('award map covers the XP-bearing event types only', () => {
  assert.deepEqual(
    Object.keys(XP_AWARDS).sort(),
    ['participant_finished', 'personal_best', 'progress_accepted', 'winner_determined'],
  );
  assert.ok(XP_AWARDS.winner_determined < XP_AWARDS.participant_finished);
});
