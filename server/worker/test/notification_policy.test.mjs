import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {
  notifyEvent,
  notifyRaceEvents,
  notifyLifecycleTransitions,
  runNotificationJob,
} = require('../.tmp-test-dist/domain/notificationPolicy.js');
const { scheduleRaceStartingSoon, jobStillRelevant, claimDueJobs } = require(
  '../.tmp-test-dist/domain/notificationJobs.js',
);

// ── In-memory D1 double covering every statement the policy runs ────────────
function fakeDb() {
  const prefs = new Map(); // 'user|cat' -> {in_app, push}
  const notifications = []; // {id,user,category,title,body,dedupe,createdMs,aggregateCount}
  const dedupe = new Map(); // 'user|key' -> row
  const raceEvents = []; // {type, actor, subject, createdMs}
  const crew = new Set(); // 'a|b'
  const blocked = new Set(); // 'a|b' (either direction checked)
  const ranks = new Map(); // 'race|user' -> rank
  const races = new Map(); // id -> race row
  const membersByRace = new Map(); // id -> [{user_id, display_name}]
  const jobs = [];
  let idc = 0;
  const nowMs = () => Date.now();
  const iso = (ms) => new Date(ms).toISOString();

  const findRow = (user, key) => dedupe.get(`${user}|${key}`);

  function notifCount(user, cats, sinceMs, entityId = null) {
    return notifications.filter(
      (n) =>
        n.user === user &&
        cats.includes(n.category) &&
        n.createdMs > sinceMs &&
        (entityId === null || n.entityId === entityId),
    ).length;
  }

  return {
    prefs,
    notifications,
    raceEvents,
    crew,
    blocked,
    ranks,
    races,
    membersByRace,
    jobs,
    prepare(sql) {
      const stmt = { _a: [] };
      stmt.bind = (...a) => {
        stmt._a = a;
        return stmt;
      };
      stmt.first = async () => {
        if (sql.includes('FROM notification_preferences')) {
          const [u, cat] = stmt._a;
          return prefs.get(`${u}|${cat}`) ?? null;
        }
        if (sql.includes('FROM notifications') && sql.includes('dedupe_key')) {
          const [u, key] = stmt._a;
          const r = findRow(u, key);
          return r ? { id: r.id, aggregate_count: r.aggregateCount } : null;
        }
        if (sql.includes('rank_cache FROM race_progress')) {
          const [race, u] = stmt._a;
          const v = ranks.get(`${race}|${u}`);
          return v == null ? null : { rank_cache: v };
        }
        if (sql.includes('FROM crew_connections')) {
          const [a, b] = stmt._a;
          return crew.has(`${a}|${b}`) ? { id: 'c' } : null;
        }
        if (sql.includes('FROM blocked_users')) {
          const [a, b] = stmt._a;
          return blocked.has(`${a}|${b}`) ? { id: 'x' } : null;
        }
        if (sql.includes('FROM race_events') && sql.includes('COUNT')) {
          const [race, a1, s1, a2, s2] = stmt._a;
          const n = raceEvents.filter(
            (e) =>
              e.type === 'lead_changed' &&
              e.createdMs > nowMs() - 24 * 3600e3 &&
              ((e.actor === a1 && e.subject === s1) ||
                (e.actor === a2 && e.subject === s2)),
          ).length;
          return { n };
        }
        if (sql.includes('FROM notifications') && sql.includes('SUM(')) {
          const [u, ...cats] = stmt._a;
          const h = notifCount(u, cats, nowMs() - 3600e3);
          const d = notifCount(u, cats, nowMs() - 24 * 3600e3);
          return { h, d };
        }
        if (sql.includes('FROM notifications') && sql.includes('COUNT')) {
          const [u, , entityId] = stmt._a;
          return {
            n: notifCount(
              u,
              ['passed_on_leaderboard'],
              nowMs() - 3600e3,
              entityId,
            ),
          };
        }
        if (sql.trimStart().startsWith('SELECT * FROM races')) {
          const r = races.get(stmt._a[0]);
          return r ?? null;
        }
        if (sql.includes('FROM notification_jobs') && sql.includes('LIMIT')) {
          return null;
        }
        return null;
      };
      stmt.all = async () => {
        if (sql.includes('FROM device_tokens')) return { results: [] };
        if (sql.includes('FROM race_members')) {
          return { results: membersByRace.get(stmt._a[0]) ?? [] };
        }
        if (sql.includes('FROM notification_jobs')) {
          const [runAt, limit] = stmt._a;
          return {
            results: jobs
              .filter((j) => j.status === 'pending' && j.run_at <= runAt)
              .slice(0, limit),
          };
        }
        return { results: [] };
      };
      stmt.run = async () => {
        if (sql.includes('INSERT OR IGNORE INTO notifications')) {
          const [id, user, category, actor, title, body, dt, di, dc, et, ei, key] =
            stmt._a;
          const k = `${user}|${key}`;
          if (dedupe.has(k)) return { meta: { changes: 0 } };
          const row = {
            id,
            user,
            category,
            actor,
            title,
            body,
            dest: { type: dt, id: di, context: dc },
            entityId: ei,
            dedupe: key,
            aggregateCount: 1,
            createdMs: nowMs(),
          };
          dedupe.set(k, row);
          notifications.push(row);
          return { meta: { changes: 1 } };
        }
        if (sql.includes('UPDATE notifications SET title')) {
          const [title, body, actor, id] = stmt._a;
          const row = notifications.find((n) => n.id === id);
          if (!row) return { meta: { changes: 0 } };
          row.title = title;
          row.body = body;
          row.actor = actor;
          row.aggregateCount += 1;
          return { meta: { changes: 1 } };
        }
        if (sql.includes('INSERT OR IGNORE INTO notification_jobs')) {
          const [id, entityId, key, runAt] = stmt._a;
          if (jobs.some((j) => j.dedupe_key === key))
            return { meta: { changes: 0 } };
          jobs.push({
            id,
            kind: 'race_starting_soon',
            entity_type: 'race',
            entity_id: entityId,
            dedupe_key: key,
            run_at: runAt,
            status: 'pending',
          });
          return { meta: { changes: 1 } };
        }
        if (sql.includes('UPDATE notification_jobs SET status')) {
          // claimDueJobs binds (id) with 'claimed' literal; markJobDone binds (status, id).
          const [status, id] =
            stmt._a.length === 1 ? ["'claimed'", stmt._a[0]] : stmt._a;
          const j = jobs.find((x) => x.id === id);
          if (!j || (sql.includes("'pending'") && j.status !== 'pending'))
            return { meta: { changes: 0 } };
          j.status = status.replaceAll("'", '');
          return { meta: { changes: 1 } };
        }
        return { meta: { changes: 0 } };
      };
      return stmt;
    },
  };
}

const env = (db) => ({ DB: db }); // no FCM secrets → sendPush is dormant
const race = { id: 'r1', title: 'Morning Run', status: 'active' };
const NAMES = { u1: 'Riley', u2: 'Maya', u3: 'Jules', u5: 'Sam', u9: 'Kai', creator: 'Alex' };
const members = (ids) =>
  ids.map((id) => ({ user_id: id, display_name: NAMES[id] ?? id }));

// ── race_finished ───────────────────────────────────────────────────────────

test('race_finished: every member gets a row; winner gets the win copy', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 1);
  db.ranks.set('r1|u2', 2);
  db.ranks.set('r1|u3', 3);
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'race_finished', payload: { winnerUserId: 'u1', topScore: 42 } }],
    members(['u1', 'u2', 'u3']),
  );
  assert.equal(out.length, 3);
  assert.ok(out.every((o) => o.decision === 'push' || o.decision === 'inbox'));
  const win = db.notifications.find((n) => n.user === 'u1');
  const lose = db.notifications.find((n) => n.user === 'u2');
  assert.match(win.title, /You won Morning Run/);
  assert.match(lose.title, /Riley won Morning Run/);
  assert.match(lose.body, /#2/);
});

test('race_finished: duplicate event dedupes per recipient', async () => {
  const db = fakeDb();
  const evt = [{ type: 'race_finished', payload: { winnerUserId: 'u1' } }];
  await notifyRaceEvents(env(db), undefined, race, evt, members(['u1', 'u2']));
  const out = await notifyRaceEvents(env(db), undefined, race, evt, members(['u1', 'u2']));
  assert.ok(out.every((o) => o.decision === 'suppress'));
  assert.equal(db.notifications.length, 2); // still one row each
});

// ── lead_changed / overtake ─────────────────────────────────────────────────

test('lead_changed: only the displaced leader is interrupted', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2', 'u3']),
  );
  assert.equal(out.length, 1);
  assert.equal(out[0].userId, 'u1');
  assert.equal(out[0].decision, 'push');
  assert.match(db.notifications[0].title, /Maya just passed you/);
});

test('rank_changed: overtaken member on podium gets pushed, backmarker suppressed', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u2', 2); // podium — eligible
  db.ranks.set('r1|u9', 9); // out of contention — not
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [
      {
        type: 'rank_changed',
        actorUserId: 'u1',
        subjectUserId: 'u1',
        payload: { previousRank: 9, newRank: 1, overtakenUserIds: ['u2', 'u9'] },
      },
    ],
    members(['u1', 'u2', 'u9']),
  );
  const byUser = Object.fromEntries(out.map((o) => [o.userId, o]));
  assert.equal(byUser.u2.decision, 'push');
  assert.equal(byUser.u9.decision, 'suppress');
  assert.equal(byUser.u9.reason, 'not_in_contention');
});

test('rank_changed: crew member is eligible even outside the podium', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u5', 5);
  db.crew.add('u5|u1');
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [
      {
        type: 'rank_changed',
        actorUserId: 'u1',
        subjectUserId: 'u1',
        payload: { previousRank: 6, newRank: 4, overtakenUserIds: ['u5'] },
      },
    ],
    members(['u1', 'u5']),
  );
  assert.equal(out[0].decision, 'push');
});

test('overtake: directed-pair cooldown — same pass twice in the window no-ops', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  const evt = [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }];
  await notifyRaceEvents(env(db), undefined, race, evt, members(['u1', 'u2']));
  const out = await notifyRaceEvents(env(db), undefined, race, evt, members(['u1', 'u2']));
  assert.equal(out[0].decision, 'suppress');
  assert.equal(db.notifications.length, 1);
});

test('lead oscillation: third same-pair trade rolls up into a battle row', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  // Two prior trades between the pair already logged.
  db.raceEvents.push(
    { type: 'lead_changed', actor: 'u2', subject: 'u1', createdMs: Date.now() - 2000 },
    { type: 'lead_changed', actor: 'u1', subject: 'u2', createdMs: Date.now() - 1000 },
    // The event being published is already durable when policy runs.
    { type: 'lead_changed', actor: 'u2', subject: 'u1', createdMs: Date.now() - 10 },
  );
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2']),
  );
  assert.equal(out[0].decision, 'push');
  assert.match(db.notifications[0].title, /keep trading the lead/);
  // A fourth trade in the same direction: battle row dedupes → silence.
  const out2 = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2']),
  );
  assert.equal(out2[0].decision, 'suppress');
});

test('overtake: blocked relationship suppresses entirely', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  db.blocked.add('u1|u2');
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2']),
  );
  assert.equal(out.length, 0);
  assert.equal(db.notifications.length, 0);
});

// ── budgets ─────────────────────────────────────────────────────────────────

test('engagement budget: second overtake push within the hour degrades to inbox', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2', 'u3']),
  );
  // Different actor, same race, same hour → budget exhausted → inbox only.
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u3', subjectUserId: 'u1' }],
    members(['u1', 'u2', 'u3']),
  );
  assert.equal(out[0].decision, 'inbox');
  assert.equal(db.notifications.length, 2); // row still exists — budget gates push, not record
});

test('functional notifications bypass the engagement budget', async () => {
  const db = fakeDb();
  db.ranks.set('r1|u1', 2);
  await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'lead_changed', actorUserId: 'u2', subjectUserId: 'u1' }],
    members(['u1', 'u2']),
  );
  const out = await notifyEvent(env(db), undefined, {
    type: 'proof_reviewed',
    userId: 'u1',
    actorUserId: 'u2',
    raceId: 'r1',
    raceTitle: 'Morning Run',
    moveId: 'm1',
    outcome: 'rejected',
  });
  assert.equal(out[0].decision, 'push'); // proof results are earned, not budgeted
});

// ── preferences ─────────────────────────────────────────────────────────────

test('in-app preference off suppresses the row entirely', async () => {
  const db = fakeDb();
  db.prefs.set('u1|race_completed', { in_app: 0, push: 1 });
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'race_finished', payload: { winnerUserId: 'u2' } }],
    members(['u1', 'u2']),
  );
  const u1 = out.find((o) => o.userId === 'u1');
  assert.equal(u1.decision, 'suppress');
  assert.equal(db.notifications.filter((n) => n.user === 'u1').length, 0);
});

test('push preference off still writes the inbox row', async () => {
  const db = fakeDb();
  db.prefs.set('u1|race_completed', { in_app: 1, push: 0 });
  const out = await notifyRaceEvents(
    env(db),
    undefined,
    race,
    [{ type: 'race_finished', payload: { winnerUserId: 'u2' } }],
    members(['u1', 'u2']),
  );
  const u1 = out.find((o) => o.userId === 'u1');
  assert.equal(u1.decision, 'inbox');
  assert.equal(db.notifications.filter((n) => n.user === 'u1').length, 1);
});

// ── aggregation ─────────────────────────────────────────────────────────────

test('race_member_joined: joins roll up into one row, push only on first', async () => {
  const db = fakeDb();
  const join = (actor) =>
    notifyEvent(env(db), undefined, {
      type: 'race_member_joined',
      userId: 'creator',
      actorUserId: actor,
      actorName: actor,
      raceId: 'r1',
      raceTitle: 'Morning Run',
    });
  const first = await join('Maya');
  const second = await join('Jules');
  assert.equal(first[0].decision, 'push');
  assert.equal(second[0].decision, 'aggregate');
  assert.equal(db.notifications.length, 1);
  const row = db.notifications[0];
  assert.equal(row.aggregateCount, 2);
  assert.match(row.title, /Jules and 1 other joined Morning Run/);
});

// ── non-race events ─────────────────────────────────────────────────────────

test('race_invited: direct invite pushes with actor in the copy', async () => {
  const db = fakeDb();
  const out = await notifyEvent(env(db), undefined, {
    type: 'race_invited',
    userId: 'u1',
    actorUserId: 'u2',
    actorName: 'Riley',
    raceId: 'r1',
    raceTitle: 'Morning Run',
  });
  assert.equal(out[0].decision, 'push');
  assert.match(db.notifications[0].title, /Riley added you to Morning Run/);
});

test('proof_reviewed: verified carries the earned value in the body', async () => {
  const db = fakeDb();
  await notifyEvent(env(db), undefined, {
    type: 'proof_reviewed',
    userId: 'u1',
    actorUserId: 'u2',
    raceId: 'r1',
    raceTitle: 'Morning Run',
    moveId: 'm1',
    outcome: 'verified',
    value: 25,
    unit: 'pushups',
  });
  assert.match(db.notifications[0].title, /Proof verified/);
  assert.match(db.notifications[0].body, /\+25 pushups/);
});

// ── scheduled jobs ──────────────────────────────────────────────────────────

test('scheduleRaceStartingSoon: arms a job 30 min before the start line', async () => {
  const db = fakeDb();
  const start = new Date(Date.now() + 2 * 3600e3).toISOString();
  await scheduleRaceStartingSoon(db, 'r1', start);
  assert.equal(db.jobs.length, 1);
  const job = db.jobs[0];
  assert.equal(job.kind, 'race_starting_soon');
  const expected = new Date(start).getTime() - 30 * 60 * 1000;
  assert.equal(new Date(job.run_at).getTime(), expected);
  // Re-scheduling the same start is idempotent; a new start arms a new job.
  await scheduleRaceStartingSoon(db, 'r1', start);
  assert.equal(db.jobs.length, 1);
  const moved = new Date(Date.now() + 3 * 3600e3).toISOString();
  await scheduleRaceStartingSoon(db, 'r1', moved);
  assert.equal(db.jobs.length, 2);
});

test('jobStillRelevant: cancels jobs whose start line moved or already passed', async () => {
  const db = fakeDb();
  const future = new Date(Date.now() + 3600e3).toISOString();
  await scheduleRaceStartingSoon(db, 'r1', future);
  const job = db.jobs[0];
  assert.equal(jobStillRelevant(job, { id: 'r1', status: 'active', start_at: future }), true);
  // Start moved → the old reminder no longer matches the race.
  const moved = new Date(Date.now() + 2 * 3600e3).toISOString();
  assert.equal(jobStillRelevant(job, { id: 'r1', status: 'active', start_at: moved }), false);
  // Started already / cancelled → nothing to remind about.
  const past = new Date(Date.now() - 3600e3).toISOString();
  assert.equal(jobStillRelevant(job, { id: 'r1', status: 'active', start_at: past }), false);
  assert.equal(jobStillRelevant(job, { id: 'r1', status: 'cancelled', start_at: future }), false);
  assert.equal(jobStillRelevant(job, null), false);
});

test('runNotificationJob: reminds members, then marks the job sent', async () => {
  const db = fakeDb();
  // Start 10 min out → the -30min reminder job is already due and aligned.
  const start = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  db.races.set('r1', { id: 'r1', title: 'Morning Run', status: 'active', start_at: start, deleted_at: null });
  db.membersByRace.set('r1', [
    { user_id: 'u1', display_name: 'Riley Kim' },
    { user_id: 'u2', display_name: 'Maya Lee' },
  ]);
  // Schedule at -30min so the job is due and aligned with start_at.
  const runAt = new Date(new Date(start).getTime() - 30 * 60 * 1000).toISOString();
  db.jobs.push({
    id: 'j1',
    kind: 'race_starting_soon',
    entity_type: 'race',
    entity_id: 'r1',
    dedupe_key: 'job:race_starting_soon:r1:' + start,
    run_at: runAt,
    status: 'pending',
  });
  const claimed = await claimDueJobs(db);
  assert.equal(claimed.length, 1);
  const out = await runNotificationJob(env(db), undefined, claimed[0]);
  assert.equal(out.length, 2);
  assert.ok(out.every((o) => o.decision === 'push'));
  assert.match(db.notifications[0].title, /starts in 30 min/);
  assert.match(db.notifications[0].body, /Riley and Maya/);
  assert.equal(db.jobs[0].status, 'sent');
});

// ── reactions ─────────────────────────────────────────────────────────────

test('reaction_added: lands as an inbox row, never pushes by default', async () => {
  const db = fakeDb();
  const out = await notifyEvent(env(db), undefined, {
    type: 'reaction_added',
    userId: 'u1',
    actorUserId: 'u2',
    actorName: 'Riley',
    emoji: 'fire',
    entityType: 'race_event',
    entityId: 'evt1',
    raceId: 'r1',
    context: 'Morning Run',
  });
  assert.equal(out[0].decision, 'inbox');
  assert.match(db.notifications[0].title, /Riley reacted 🔥 to Morning Run/);
});

test('reaction_added: same entity rolls up into one aggregated row', async () => {
  const db = fakeDb();
  const react = (actor, name) =>
    notifyEvent(env(db), undefined, {
      type: 'reaction_added',
      userId: 'u1',
      actorUserId: actor,
      actorName: name,
      emoji: 'muscle',
      entityType: 'race_event',
      entityId: 'evt1',
      raceId: 'r1',
      context: 'Morning Run',
    });
  const first = await react('u2', 'Riley');
  const second = await react('u3', 'Jules');
  assert.equal(first[0].decision, 'inbox');
  assert.equal(second[0].decision, 'aggregate');
  assert.equal(db.notifications.length, 1);
  assert.equal(db.notifications[0].aggregateCount, 2);
  assert.match(db.notifications[0].title, /Jules and 1 other reacted 💪/);
});

// ── lazy lifecycle transitions ────────────────────────────────────────────

test('notifyLifecycleTransitions: a read-finalized race still reaches members', async () => {
  const db = fakeDb();
  db.membersByRace.set('r1', members(['u1', 'u2']));
  db.ranks.set('r1|u1', 1);
  db.ranks.set('r1|u2', 2);
  const out = await notifyLifecycleTransitions(env(db), undefined, [
    {
      race,
      events: [
        { type: 'race_finished', payload: { winnerUserId: 'u1', topScore: 42 } },
      ],
    },
  ]);
  assert.equal(out.length, 2);
  assert.match(
    db.notifications.find((n) => n.user === 'u1').title,
    /You won Morning Run/,
  );
});

test('runNotificationJob: a stale job (race already started) emits nothing', async () => {
  const db = fakeDb();
  const past = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  db.races.set('r1', { id: 'r1', title: 'Morning Run', status: 'active', start_at: past, deleted_at: null });
  db.membersByRace.set('r1', [{ user_id: 'u1', display_name: 'Riley' }]);
  db.jobs.push({
    id: 'j1',
    kind: 'race_starting_soon',
    entity_type: 'race',
    entity_id: 'r1',
    dedupe_key: 'k',
    run_at: past,
    status: 'claimed',
  });
  const out = await runNotificationJob(env(db), undefined, db.jobs[0]);
  assert.equal(out.length, 0);
  assert.equal(db.notifications.length, 0);
  assert.equal(db.jobs[0].status, 'sent'); // completed silently
});
