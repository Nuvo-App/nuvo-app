/**
 * Notification policy — THE seam between domain events and delivery
 * (docs/agents/21-notification-reengagement-plan.md §2–6). Replaces
 * domain/raceNotify.ts: race code emits canonical `race_events` (and routes
 * emit structured non-race events); this module owns EVERYTHING about who
 * gets told, what it says, whether it interrupts, and how duplicates /
 * oscillation / storms collapse.
 *
 *   domain event → recipients → eligibility → priority → copy
 *     → dedupe/cooldown → aggregate? → durable inbox row → push?
 *
 * Decisions are returned as `PolicyOutcome`s so policy is unit-testable
 * without D1 semantics and observable in logs. Race correctness never
 * depends on this module — it reads `races`/`race_members`/`race_progress`/
 * `race_events` but only writes `notifications`/`notification_jobs` state.
 */
import type { AppEnv } from '../types';
import type { RaceRow } from '../types';
import {
  emitNotification,
  pushEligible,
  type EmitOptions,
  type NotificationCategory,
} from './notifications';
import { sendPush } from './push';
import { isBlocked } from '../lib/privacy';
import type { RaceEventInput } from './raceEvents';
import {
  jobStillRelevant,
  markJobDone,
  type NotificationJobRow,
} from './notificationJobs';

type Env = AppEnv['Bindings'];
type WaitUntil = ((p: Promise<unknown>) => void) | undefined;

export type PolicyDecision = 'push' | 'inbox' | 'aggregate' | 'suppress';
export interface PolicyOutcome {
  userId: string;
  category: string;
  decision: PolicyDecision;
  notificationId?: string | null;
  reason?: string;
}

export interface MemberLite {
  user_id: string;
  display_name?: string | null;
}

interface Intent extends EmitOptions {
  /** false → inbox row only by design (feed-level events). */
  push?: boolean;
  /** engagement categories count against the user's interruption budget. */
  budgeted?: boolean;
  /** rolled-up copy for the (n+1)th event in an aggregation window. */
  aggregateCopy?: (count: number) => { title: string; body?: string };
}

// ── Policy constants ─────────────────────────────────────────────────────────

/** Categories that count against the user's engagement push budget. */
const ENGAGEMENT_BUDGETED = new Set<NotificationCategory>([
  'passed_on_leaderboard',
  'race_joined',
]);

/** Per-recipient engagement interruptions: 1/hour, 4/day across categories. */
const ENGAGEMENT_PER_HOUR = 1;
const ENGAGEMENT_PER_DAY = 4;
/** A single race may interrupt one user at most this often for overtakes. */
const OVERTAKE_PER_RACE_PER_HOUR = 2;
/** A directed A-passes-B push can't repeat inside this window. */
const PAIR_COOLDOWN_MS = 30 * 60 * 1000;
/** Lead trades ≥ this inside a day roll up into one "battle" row. */
const LEAD_BATTLE_THRESHOLD = 3;
/** Overtake pushes only when the target is on/near the podium — or crew. */
const PODIUM_NOTIFY_RANK = 3;

const halfHourBucket = () => Math.floor(Date.now() / PAIR_COOLDOWN_MS);
const dayBucket = () => new Date().toISOString().slice(0, 10);

/** Wire code → glyph for reaction copy. */
const REACTION_GLYPHS: Record<string, string> = {
  fire: '🔥',
  clap: '👏',
  muscle: '💪',
};

function firstName(name: string | null | undefined): string {
  if (!name) return 'Someone';
  return name.trim().split(/\s+/)[0] || 'Someone';
}

/** "Riley, Maya and Jules" / "Riley, Maya +3" — capped display lists. */
function nameList(names: string[], cap = 3): string {
  const first = names.map(firstName).filter((n) => n !== 'Someone');
  if (first.length === 0) return 'Your crew';
  if (first.length <= cap) {
    if (first.length === 1) return first[0];
    return `${first.slice(0, -1).join(', ')} and ${first[first.length - 1]}`;
  }
  return `${first.slice(0, cap - 1).join(', ')} +${first.length - (cap - 1)}`;
}

// ── Eligibility + budget gates ───────────────────────────────────────────────

async function isBlockedEitherWay(db: D1Database, a: string, b: string): Promise<boolean> {
  return (await isBlocked(db, a, b)) || (await isBlocked(db, b, a));
}

async function isCrewmate(db: D1Database, userId: string, otherId: string): Promise<boolean> {
  const row = await db
    .prepare(
      "SELECT id FROM crew_connections WHERE user_id = ? AND crew_user_id = ? AND status = 'active'",
    )
    .bind(userId, otherId)
    .first<{ id: string }>();
  return Boolean(row);
}

/** Count lead_changed events between a pair (either direction) in 24h. */
async function countLeadTrades(
  db: D1Database,
  raceId: string,
  a: string,
  b: string,
): Promise<number> {
  const row = await db
    .prepare(
      `SELECT COUNT(*) as n FROM race_events
       WHERE race_id = ? AND event_type = 'lead_changed'
         AND created_at > datetime('now', '-24 hours')
         AND ((actor_user_id = ? AND subject_user_id = ?)
           OR (actor_user_id = ? AND subject_user_id = ?))`,
    )
    .bind(raceId, a, b, b, a)
    .first<{ n: number }>();
  return row?.n ?? 0;
}

/**
 * The interruption budget. Evaluated BEFORE the row exists, so it counts
 * prior interruptions only. Budgeted categories are capped; direct/
 * functional categories (invites, requests, proof results, race results)
 * are exempt — they are always earned.
 */
async function engagementBudgetOk(
  db: D1Database,
  userId: string,
  category: NotificationCategory,
  raceId: string | null,
): Promise<boolean> {
  if (!ENGAGEMENT_BUDGETED.has(category)) return true;

  if (category === 'passed_on_leaderboard' && raceId) {
    const perRace = await db
      .prepare(
        `SELECT COUNT(*) as n FROM notifications
         WHERE user_id = ? AND category = 'passed_on_leaderboard'
           AND entity_id = ? AND created_at > datetime('now', '-1 hour')`,
      )
      .bind(userId, raceId)
      .first<{ n: number }>();
    if ((perRace?.n ?? 0) >= OVERTAKE_PER_RACE_PER_HOUR) return false;
  }

  const cats = [...ENGAGEMENT_BUDGETED].map(() => '?').join(',');
  const recent = await db
    .prepare(
      `SELECT
         SUM(CASE WHEN created_at > datetime('now', '-1 hour') THEN 1 ELSE 0 END) as h,
         COUNT(*) as d
       FROM notifications
       WHERE user_id = ? AND category IN (${cats})
         AND created_at > datetime('now', '-24 hours')`,
    )
    .bind(userId, ...ENGAGEMENT_BUDGETED)
    .first<{ h: number | null; d: number }>();
  if ((recent?.h ?? 0) >= ENGAGEMENT_PER_HOUR) return false;
  if ((recent?.d ?? 0) >= ENGAGEMENT_PER_DAY) return false;
  return true;
}

// ── The delivery gate ────────────────────────────────────────────────────────

/**
 * One intent → one durable row (or a rolled-up row) → maybe a push. Push
 * requires: intent.push, the user's push pref, and — for engagement
 * categories — remaining budget. The inbox row is the truth: a suppressed
 * push never erases it, and a suppressed event still records the row when
 * in-app is on.
 */
async function deliver(
  env: Env,
  waitUntil: WaitUntil,
  intent: Intent,
): Promise<PolicyOutcome> {
  const db = env.DB;
  const base: Omit<PolicyOutcome, 'decision'> = {
    userId: intent.userId,
    category: intent.category,
  };
  try {
    if (intent.aggregate) {
      // Rolled-up copy needs the post-update count; the update itself bumps
      // aggregate_count inside emitNotification.
      const existing = await db
        .prepare(
          'SELECT aggregate_count FROM notifications WHERE user_id = ? AND dedupe_key = ?',
        )
        .bind(intent.userId, intent.dedupeKey ?? '')
        .first<{ aggregate_count: number }>();
      if (existing && intent.aggregateCopy) {
        const rolled = intent.aggregateCopy(existing.aggregate_count + 1);
        intent = { ...intent, title: rolled.title, body: rolled.body };
      }
    }

    const pushWanted =
      intent.push !== false &&
      (!intent.budgeted ||
        (await engagementBudgetOk(
          db,
          intent.userId,
          intent.category,
          intent.entityType === 'race' ? (intent.entityId ?? null) : null,
        )));

    const id = await emitNotification(db, intent);
    if (!id) {
      return {
        ...base,
        decision: intent.aggregate ? 'aggregate' : 'suppress',
        reason: intent.aggregate ? 'rolled_into_existing' : 'deduped_or_pref_off',
      };
    }

    const pref = await db
      .prepare('SELECT in_app, push FROM notification_preferences WHERE user_id = ? AND category = ?')
      .bind(intent.userId, intent.category)
      .first<{ in_app: number; push: number }>();
    const pushOk = pushWanted && pushEligible(pref, intent.category);
    if (!pushOk) return { ...base, decision: 'inbox', notificationId: id };

    const deliverPush = sendPush(env, intent.userId, {
      title: intent.title,
      body: intent.body,
      category: intent.category,
      dest: intent.dest,
      notificationId: id,
    });
    if (waitUntil) waitUntil(deliverPush);
    else await deliverPush;
    return { ...base, decision: 'push', notificationId: id };
  } catch (err) {
    console.error('[policy] deliver failed:', (err as Error).message, intent.category);
    return { ...base, decision: 'suppress', reason: 'error' };
  }
}

// ── Race events (canonical race_events → delivery) ───────────────────────────

/**
 * Consumes Agent 3's canonical `race_events` — same signature/role as the
 * old `publishRaceTransitions`, so call sites swap one import. Events with
 * no notification category stay feed-only (Crew/analytics read race_events).
 */
/** The race fields notification copy needs — a structural subset so callers
 *  with partial rows (Arena's LightRaceRow) can publish transitions. */
export interface RaceNotifyContext {
  id: string;
  title: string;
  metric?: string | null;
  target_unit?: string | null;
}

/** One lifecycle edge that needs notification processing — produced by
 *  `finalizeRaceIfEnded`/`markRaceStartedIfDue` whether they run inside the
 *  cron sweep or lazily on a read. */
export interface LifecycleTransitionLike {
  race: RaceNotifyContext;
  events: RaceEventInput[];
}

export async function notifyRaceEvents(
  env: Env,
  waitUntil: WaitUntil,
  race: RaceNotifyContext,
  events: RaceEventInput[],
  members: MemberLite[],
): Promise<PolicyOutcome[]> {
  const db = env.DB;
  const outcomes: PolicyOutcome[] = [];
  const dest = { type: 'race' as const, id: race.id };
  const memberIds = new Set(members.map((m) => m.user_id));
  const nameOf = (id: string | null | undefined) =>
    firstName(members.find((m) => m.user_id === id)?.display_name);
  const rankCache = async (userId: string): Promise<number | null> =>
    (
      await db
        .prepare('SELECT rank_cache FROM race_progress WHERE race_id = ? AND user_id = ?')
        .bind(race.id, userId)
        .first<{ rank_cache: number | null }>()
    )?.rank_cache ?? null;

  const overtakeIntent = (
    targetId: string,
    actorId: string,
    rank: number | null,
  ): Intent => ({
    userId: targetId,
    category: 'passed_on_leaderboard',
    priority: 'high',
    title: `${nameOf(actorId)} just passed you in ${race.title}`,
    body: rank ? `You're #${rank}.` : undefined,
    actorUserId: actorId,
    dest: { ...dest, context: 'leaderboard' },
    entityType: 'race',
    entityId: race.id,
    dedupeKey: `overtake:${race.id}:${actorId}:${targetId}:${halfHourBucket()}`,
    budgeted: true,
  });

  for (const event of events) {
    switch (event.type) {
      case 'race_started': {
        const n = (event.payload?.participantCount as number | undefined) ?? members.length;
        for (const m of members) {
          outcomes.push(
            await deliver(env, waitUntil, {
              userId: m.user_id,
              category: 'race_starting',
              priority: 'high',
              title: `${race.title} starts now`,
              body: `${n} ${n === 1 ? 'racer is' : 'racers are'} in.`,
              dest,
              entityType: 'race',
              entityId: race.id,
              dedupeKey: `race_starting:${race.id}:${m.user_id}`,
            }),
          );
        }
        break;
      }

      case 'race_finished': {
        const winnerId = (event.payload?.winnerUserId as string | undefined) ?? null;
        const topScore = event.payload?.topScore as number | undefined;
        const winnerName = winnerId ? nameOf(winnerId) : null;
        const unit = race.metric ?? race.target_unit ?? 'pts';
        for (const m of members) {
          const won = winnerId != null && m.user_id === winnerId;
          const rank = won ? 1 : await rankCache(m.user_id);
          const title = won
            ? `You won ${race.title} 🏆`
            : winnerName
              ? `${winnerName} won ${race.title}`
              : `${race.title} finished 🏁`;
          const body = won
            ? `${topScore != null ? `${topScore} ${unit}. ` : ''}First place.`
            : winnerName
              ? rank
                ? `You finished #${rank}.`
                : 'See where everyone landed.'
              : 'See where everyone landed.';
          outcomes.push(
            await deliver(env, waitUntil, {
              userId: m.user_id,
              category: 'race_completed',
              priority: 'high',
              title,
              body,
              actorUserId: winnerId ?? undefined,
              dest,
              entityType: 'race',
              entityId: race.id,
              dedupeKey: `race_completed:${race.id}:${m.user_id}`,
            }),
          );
        }
        break;
      }

      case 'lead_changed': {
        // The displaced leader is the only one interrupted — everyone else
        // sees it in Crew/feed. ≥3 same-pair trades/day → one battle row.
        const displaced = event.subjectUserId;
        const actor = event.actorUserId;
        if (!displaced || !actor || displaced === actor || !memberIds.has(displaced)) break;
        if (await isBlockedEitherWay(db, displaced, actor)) break;

        const trades = await countLeadTrades(db, race.id, actor, displaced);
        const rank = await rankCache(displaced);
        if (trades >= LEAD_BATTLE_THRESHOLD) {
          outcomes.push(
            await deliver(env, waitUntil, {
              userId: displaced,
              category: 'passed_on_leaderboard',
              priority: 'medium',
              title: `You and ${nameOf(actor)} keep trading the lead 🔥`,
              body: `${nameOf(actor)} is currently ahead.`,
              actorUserId: actor,
              dest: { ...dest, context: 'leaderboard' },
              entityType: 'race',
              entityId: race.id,
              dedupeKey: `lead_battle:${race.id}:${actor}:${displaced}:${dayBucket()}`,
              budgeted: true,
            }),
          );
        } else {
          outcomes.push(await deliver(env, waitUntil, overtakeIntent(displaced, actor, rank)));
        }
        break;
      }

      case 'rank_changed': {
        // The submitter moved; members they passed MAY deserve a push —
        // only when they're in podium contention or crew with the actor.
        const actor = event.actorUserId;
        if (!actor) break;
        const overtaken = (event.payload?.overtakenUserIds as string[] | undefined) ?? [];
        for (const targetId of overtaken) {
          if (targetId === actor || !memberIds.has(targetId)) continue;
          if (await isBlockedEitherWay(db, targetId, actor)) {
            outcomes.push({
              userId: targetId,
              category: 'passed_on_leaderboard',
              decision: 'suppress',
              reason: 'blocked',
            });
            continue;
          }
          const rank = await rankCache(targetId);
          const inContention = rank !== null && rank <= PODIUM_NOTIFY_RANK;
          const crew = inContention ? false : await isCrewmate(db, targetId, actor);
          if (!inContention && !crew) {
            outcomes.push({
              userId: targetId,
              category: 'passed_on_leaderboard',
              decision: 'suppress',
              reason: 'not_in_contention',
            });
            continue;
          }
          outcomes.push(await deliver(env, waitUntil, overtakeIntent(targetId, actor, rank)));
        }
        break;
      }

      // Feed-only: participant_finished, progress_accepted, personal_best,
      // attempt_*, race_created, race_joined, winner_determined (covered by
      // race_finished), rematch_requested — Crew/analytics read race_events.
      default:
        break;
    }
  }
  return outcomes;
}

/**
 * Publish lifecycle transitions — the members fetch + notifyRaceEvents loop
 * shared by the cron sweep and every lazy-read finalization site. Without
 * this, a race that finalizes on a read (before cron runs) would land
 * race_finished in race_events but never produce race_completed rows: the
 * sweep only scans still-active races, so the edge would be lost forever.
 * Same for a start line crossed on a read and race_starting.
 */
export async function notifyLifecycleTransitions(
  env: Env,
  waitUntil: WaitUntil,
  transitions: LifecycleTransitionLike[],
): Promise<PolicyOutcome[]> {
  const outcomes: PolicyOutcome[] = [];
  for (const t of transitions) {
    const members = await env.DB
      .prepare(
        `SELECT rm.user_id, COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name
         FROM race_members rm LEFT JOIN profiles p ON p.user_id = rm.user_id
         WHERE rm.race_id = ? AND rm.status = 'active'`,
      )
      .bind(t.race.id)
      .all<MemberLite>();
    outcomes.push(
      ...(await notifyRaceEvents(env, waitUntil, t.race, t.events, members.results)),
    );
  }
  return outcomes;
}

// ── Non-race domain events (invites, joins, proof review) ────────────────────

export type NuvoDomainEvent =
  | {
      type: 'race_invited';
      userId: string;
      actorUserId: string;
      actorName?: string | null;
      raceId: string;
      raceTitle: string;
      rematch?: boolean;
    }
  | {
      type: 'race_member_joined';
      userId: string; // the race creator being told
      actorUserId: string;
      actorName?: string | null;
      raceId: string;
      raceTitle: string;
    }
  | {
      type: 'proof_reviewed';
      userId: string; // the submitter
      actorUserId: string; // the reviewer
      raceId: string;
      raceTitle: string;
      moveId: string;
      outcome: 'verified' | 'rejected';
      value?: number | null;
      unit?: string | null;
    }
  | {
      type: 'reaction_added';
      userId: string; // the person whose activity was reacted to
      actorUserId: string; // the reactor
      actorName?: string | null;
      emoji: string; // wire code: fire | clap | muscle
      entityType: string; // 'race_event' | 'move_log' | 'crew' | 'race'
      entityId: string;
      raceId?: string | null; // deep-link target when the entity has one
      context?: string | null; // display context, e.g. the race title
    }
  | {
      type: 'proof_vetoed';
      userId: string; // the proof submitter whose result stopped counting
      raceId: string;
      raceTitle: string;
      moveId: string;
    }
  | {
      type: 'proof_disputed';
      userId: string; // the proof submitter
      actorUserId: string; // the first veto voter
      raceId: string;
      raceTitle: string;
      moveId: string;
    };

export async function notifyEvent(
  env: Env,
  waitUntil: WaitUntil,
  event: NuvoDomainEvent,
): Promise<PolicyOutcome[]> {
  switch (event.type) {
    case 'race_invited': {
      const title = event.rematch
        ? `Rematch: ${event.actorName ?? 'Someone'} wants another run at ${event.raceTitle}`
        : `${event.actorName ?? 'Someone'} added you to ${event.raceTitle}`;
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: 'race_invite',
          priority: 'high',
          title,
          actorUserId: event.actorUserId,
          dest: { type: 'race', id: event.raceId },
          entityType: 'race',
          entityId: event.raceId,
          dedupeKey: `${event.rematch ? 'rematch_invite' : 'race_invite'}:${event.raceId}:${event.userId}`,
        }),
      ];
    }

    case 'race_member_joined': {
      // One push per join storms the creator on big races — joins roll up
      // per race per day: first pushes, rest update the same inbox row.
      const joiner = event.actorName ?? 'Someone';
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: 'race_joined',
          priority: 'medium',
          title: `${joiner} joined ${event.raceTitle}`,
          actorUserId: event.actorUserId,
          dest: { type: 'race', id: event.raceId },
          entityType: 'race',
          entityId: event.raceId,
          dedupeKey: `race_joined:${event.raceId}:${event.userId}:${dayBucket()}`,
          aggregate: true,
          budgeted: true,
          aggregateCopy: (n) => ({
            title: `${joiner} and ${n - 1} ${n - 1 === 1 ? 'other' : 'others'} joined ${event.raceTitle}`,
            body: `${n} people joined today.`,
          }),
        }),
      ];
    }

    case 'proof_reviewed': {
      const verified = event.outcome === 'verified';
      const unit = event.unit ?? 'reps';
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: verified ? 'proof_accepted' : 'proof_rejected',
          priority: 'high',
          title: verified ? 'Proof verified ✓' : "We couldn't verify that proof",
          body: verified
            ? event.value != null
              ? `+${event.value} ${unit} added to ${event.raceTitle}.`
              : `Added to ${event.raceTitle}.`
            : 'Review it and try again.',
          actorUserId: event.actorUserId,
          dest: { type: 'race', id: event.raceId },
          entityType: 'move_log',
          entityId: event.moveId,
          dedupeKey: `proof_review:${event.moveId}:${event.outcome}`,
        }),
      ];
    }

    case 'proof_vetoed': {
      // Consensus reached — the proof no longer counts. Uses the
      // proof_rejected category so push prefs for review outcomes apply.
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: 'proof_rejected',
          priority: 'high',
          title: 'Your proof was vetoed',
          body: `Racers in ${event.raceTitle} disputed it — it no longer counts. Submit new proof.`,
          dest: { type: 'race', id: event.raceId },
          entityType: 'move_log',
          entityId: event.moveId,
          dedupeKey: `proof_vetoed:${event.moveId}`,
        }),
      ];
    }

    case 'proof_disputed': {
      // First veto opens the dispute — one inbox row, deduped per proof so
      // later votes never re-notify.
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: 'proof_disputed',
          priority: 'medium',
          title: 'Your proof was challenged',
          body: `A racer in ${event.raceTitle} disputes your proof. If enough agree, it stops counting.`,
          actorUserId: event.actorUserId,
          dest: { type: 'race', id: event.raceId },
          entityType: 'move_log',
          entityId: event.moveId,
          push: false,
          dedupeKey: `proof_disputed:${event.moveId}`,
        }),
      ];
    }

    case 'reaction_added': {
      // Reactions are an inbox-level signal by default — the durable row is
      // the point, and they never interrupt unless a user opts into push for
      // the category. Multiple reactors on the same entity roll up into one
      // row per day ("Riley and 2 others reacted 💪 to Morning Run").
      const who = firstName(event.actorName);
      const glyph = REACTION_GLYPHS[event.emoji] ?? '👏';
      const on = event.context ? ` to ${event.context}` : ' to your activity';
      return [
        await deliver(env, waitUntil, {
          userId: event.userId,
          category: 'reaction',
          priority: 'feed',
          title: `${who} reacted ${glyph}${on}`,
          actorUserId: event.actorUserId,
          dest: event.raceId
            ? { type: 'race', id: event.raceId }
            : event.entityType === 'crew'
              ? { type: 'crew' }
              : undefined,
          entityType: event.entityType,
          entityId: event.entityId,
          push: false,
          dedupeKey: `reaction:${event.entityType}:${event.entityId}:${dayBucket()}`,
          aggregate: true,
          aggregateCopy: (n) => ({
            title: `${who} and ${n - 1} ${n - 1 === 1 ? 'other' : 'others'} reacted ${glyph}${on}`,
          }),
        }),
      ];
    }
  }
}

// ── Scheduled reminder jobs ──────────────────────────────────────────────────

/**
 * Claim-time handler for notification_jobs. Re-validates the domain before
 * emitting — a job that outlived its meaning (race started/cancelled,
 * member left) completes silently. Returns outcomes for observability.
 */
export async function runNotificationJob(
  env: Env,
  waitUntil: WaitUntil,
  job: NotificationJobRow,
): Promise<PolicyOutcome[]> {
  const db = env.DB;
  try {
    if (job.kind === 'race_starting_soon') {
      const race = await db
        .prepare('SELECT * FROM races WHERE id = ?')
        .bind(job.entity_id)
        .first<RaceRow>();
      if (!jobStillRelevant(job, race ?? null)) {
        await markJobDone(db, job.id, 'sent');
        return [];
      }
      const members = await db
        .prepare(
          `SELECT rm.user_id, COALESCE(rm.cached_display_name, p.full_name, 'Unknown') as display_name
           FROM race_members rm LEFT JOIN profiles p ON p.user_id = rm.user_id
           WHERE rm.race_id = ? AND rm.status = 'active'`,
        )
        .bind(job.entity_id)
        .all<{ user_id: string; display_name: string }>();
      const names = nameList(members.results.map((m) => m.display_name));
      const outcomes: PolicyOutcome[] = [];
      for (const m of members.results) {
        outcomes.push(
          await deliver(env, waitUntil, {
            userId: m.user_id,
            category: 'race_starting',
            priority: 'high',
            title: `${race!.title} starts in 30 min`,
            body: `${names} ${members.results.length === 1 ? 'is' : 'are'} in.`,
            dest: { type: 'race', id: race!.id },
            entityType: 'race',
            entityId: race!.id,
            dedupeKey: `race_starting_soon:${race!.id}:${m.user_id}`,
          }),
        );
      }
      await markJobDone(db, job.id, 'sent');
      return outcomes;
    }
    await markJobDone(db, job.id, 'sent'); // unknown kind — don't retry forever
    return [];
  } catch (err) {
    console.error('[policy] job failed:', (err as Error).message, job.kind);
    await markJobDone(db, job.id, 'pending'); // retry next sweep
    return [];
  }
}
