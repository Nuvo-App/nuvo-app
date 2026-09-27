/**
 * Race lifecycle authority (docs/agents/21-race-system-v2-design.md §7–§10).
 *
 * This module is the ONLY place races transition to a finished state:
 * deadline finalization, winner/tie determination, final-standings
 * snapshots, and the domain events those transitions produce. Routes and
 * the cron sweep call into here; notification policy consumes the emitted
 * `race_events` — this module never calls notification code directly.
 */
import type { RaceRow } from '../types';
import { generateId } from '../lib/crypto';
import { computeCompetitionRanks } from './raceRanking';
import { effectiveRaceStatus } from './raceLifecycle';
import { recordRaceEvents, type RaceEventInput } from './raceEvents';

// ── Pure decision helpers (unit-testable without D1) ─────────────────────────

/** Grace for verified work captured before the deadline but processed after. */
export const DEADLINE_GRACE_MS = 24 * 60 * 60 * 1000;

export type DeadlineEligibility =
  | 'active' // inside the competition window — always eligible
  | 'grace' // window ended; captured before end_at, received within grace
  | 'closed'; // too late / not started

/**
 * Whether a submission at `receivedAt` is eligible, given the race window and
 * an optional client-reported `capturedAt` (the moment the work was done).
 * Server receive time is the authority; capturedAt only ever EXTENDS
 * eligibility into the grace window, never shortens it.
 */
export function deadlineEligibility(
  race: { status: string; start_at: string | null; end_at: string | null },
  capturedAt: Date | null,
  receivedAt: Date,
): DeadlineEligibility {
  const effective = effectiveRaceStatus(race.status, race.start_at, race.end_at, receivedAt);
  if (effective === 'active') return 'active';
  if (effective !== 'completed' || !race.end_at || !capturedAt) return 'closed';
  const end = new Date(race.end_at).getTime();
  const captured = capturedAt.getTime();
  // Bound client-clock manipulation: captured time must precede the deadline
  // and be within the grace window of the receive time.
  if (
    captured <= end &&
    captured <= receivedAt.getTime() &&
    receivedAt.getTime() <= end + DEADLINE_GRACE_MS
  ) {
    return 'grace';
  }
  return 'closed';
}

/**
 * Fields that define what the competition IS. Once the race is locked these
 * cannot change — creators cannot rewrite the competition after it starts.
 * Editable forever: title, description, visibility, status (cancel/archive),
 * public join toggle.
 */
export const LOCKED_RULE_FIELDS = [
  'targetValue',
  'unit',
  'targetUnit',
  'goalType',
  'aiActivityType',
  'proofRequirement',
  'startLineAt',
  'finishLineAt',
  'format',
  'metric',
  'scoringRule',
  'attemptDurationSeconds',
  'attemptLimit',
  'scoreDirection',
] as const;

/** Body keys (wire names) that touch a locked rule field. */
export function lockedFieldsPresent(body: Record<string, unknown>): string[] {
  return LOCKED_RULE_FIELDS.filter((k) => body[k] !== undefined);
}

/**
 * Whether a race's rules are locked:
 *  - any verified proof exists (competition has produced results), or
 *  - its scheduled start line has already passed.
 * A race with no start line stays editable until first verified proof so a
 * creator can fix setup mistakes before anyone has raced.
 */
export function rulesLocked(input: {
  startAt: string | null;
  hasVerifiedMoves: boolean;
  now: Date;
}): boolean {
  if (input.hasVerifiedMoves) return true;
  if (input.startAt && new Date(input.startAt).getTime() <= input.now.getTime()) return true;
  return false;
}

/** Sort direction for a race: 'higher' (most/best) or 'lower' (fastest). */
export function scoreDirectionFor(race: { score_direction?: string | null }): 'higher' | 'lower' {
  return race.score_direction === 'lower' ? 'lower' : 'higher';
}

/** Does this race format ever produce a winner via the deadline finalizer? */
export function formatFinalizesOnDeadline(format: string): boolean {
  return (
    format === 'most_in_window' ||
    format === 'best_attempt' ||
    format === 'timed_attempt' ||
    format === 'first_to_goal' // goal-by-deadline: ranked at close, not first-crossing
  );
}

// ── Finalization ─────────────────────────────────────────────────────────────

export interface FinalizeResult {
  finalized: boolean;
  alreadyCompleted: boolean;
  winnerUserId: string | null;
  tiedForFirst: boolean;
  events: RaceEventInput[];
}

/**
 * Structural subset of RaceRow the finalizer actually reads — lets batched
 * list queries (Arena, GET /races) pass lightweight rows without re-fetching.
 */
export interface FinalizableRace {
  id: string;
  title: string;
  status: string;
  race_type?: string | null;
  format?: string | null;
  end_at: string | null;
  winner_user_id?: string | null;
  score_direction?: string | null;
}

interface RankedStandingRow {
  user_id: string;
  joined_at: string;
  progress_value: number;
  completed_at: string | null;
  rank: number;
}

async function loadStandings(db: D1Database, raceId: string, direction: 'higher' | 'lower'): Promise<RankedStandingRow[]> {
  const rows = await db
    .prepare(
      `SELECT rm.user_id, rm.joined_at, rm.finished_at,
              COALESCE(rp.progress_value, 0) as progress_value, rp.completed_at
       FROM race_members rm
       LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
       WHERE rm.race_id = ? AND rm.status = 'active'`,
    )
    .bind(raceId)
    .all<{
      user_id: string;
      joined_at: string;
      finished_at: string | null;
      progress_value: number | null;
      completed_at: string | null;
    }>();
  return computeCompetitionRanks(
    rows.results.map((row) => ({
      user_id: row.user_id,
      joined_at: row.joined_at,
      progress_value: row.progress_value ?? 0,
      // finish ordering prefers the explicit member finished_at, falls back
      // to progress.completed_at (first_to_goal crossing stamp).
      completed_at: row.finished_at ?? row.completed_at,
    })),
    { direction: direction === 'lower' ? 'asc' : 'desc' },
  );
}

/**
 * Atomically finalize a race whose window has ended.
 *
 *   deadline reached → conditional UPDATE claims the race → standings
 *   computed → race_final_standings snapshot → winner/tie recorded →
 *   race_finished (+winner_determined) events → result immutable.
 *
 * Idempotent: the `WHERE status='active'` claim means concurrent cron +
 * lazy-read finalization can only succeed once.
 */
export async function finalizeRaceIfEnded(
  db: D1Database,
  race: FinalizableRace,
  now = new Date(),
): Promise<FinalizeResult> {
  const empty: FinalizeResult = { finalized: false, alreadyCompleted: false, winnerUserId: race.winner_user_id ?? null, tiedForFirst: false, events: [] };
  if (race.status !== 'active') {
    return { ...empty, alreadyCompleted: race.status === 'completed' };
  }
  if (!race.end_at || new Date(race.end_at).getTime() > now.getTime()) return empty;

  // Claim the finalization. Only one caller can transition active→completed.
  const completedAt = race.end_at; // the race ended AT the deadline
  const claim = await db
    .prepare(
      `UPDATE races SET status = 'completed', completed_at = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'active'`,
    )
    .bind(completedAt, race.id)
    .run();
  if ((claim.meta.changes ?? 0) === 0) {
    return { ...empty, alreadyCompleted: true };
  }

  const direction = scoreDirectionFor(race);
  const standings = await loadStandings(db, race.id, direction);
  const top = standings[0] ?? null;
  const leaders = standings.filter((s) => s.rank === 1);
  // A tied lead is a shared result, not a hidden tiebreaker (PRD §39).
  const tiedForFirst = leaders.length > 1;
  const winnerUserId = top && !tiedForFirst && top.progress_value > 0 ? top.user_id : null;

  if (winnerUserId) {
    await db
      .prepare('UPDATE races SET winner_user_id = ? WHERE id = ?')
      .bind(winnerUserId, race.id)
      .run();
  }

  if (standings.length > 0) {
    const stmts = standings.map((row) =>
      db
        .prepare(
          `INSERT OR REPLACE INTO race_final_standings
             (id, race_id, user_id, rank_position, score_value, completed_at, created_at)
           VALUES (
             COALESCE((SELECT id FROM race_final_standings WHERE race_id = ? AND user_id = ?), ?),
             ?, ?, ?, ?, ?, CURRENT_TIMESTAMP
           )`,
        )
        .bind(race.id, row.user_id, generateId(), race.id, row.user_id, row.rank, row.progress_value, row.completed_at),
    );
    await db.batch(stmts);
  }

  const events: RaceEventInput[] = [
    {
      type: 'race_finished',
      payload: {
        title: race.title,
        format: race.format ?? race.race_type,
        endAt: race.end_at,
        participantCount: standings.length,
        tiedForFirst,
        winnerUserId,
        topScore: top?.progress_value ?? 0,
      },
    },
  ];
  if (winnerUserId) {
    events.push({
      type: 'winner_determined',
      subjectUserId: winnerUserId,
      payload: { score: top!.progress_value, rank: 1, tied: false },
    });
  }
  await recordRaceEvents(db, race.id, events);
  return { finalized: true, alreadyCompleted: false, winnerUserId, tiedForFirst, events };
}

/**
 * Emit `race_started` exactly once when a scheduled race's start line passes.
 * Stored status stays 'active' — 'scheduled' is derived — so this is a
 * durable event, not a state change.
 */
export async function markRaceStartedIfDue(
  db: D1Database,
  race: RaceRow,
  now = new Date(),
): Promise<boolean> {
  if (race.status !== 'active' || !race.start_at) return false;
  if (new Date(race.start_at).getTime() > now.getTime()) return false;
  const existing = await db
    .prepare("SELECT id FROM race_events WHERE race_id = ? AND event_type = 'race_started' LIMIT 1")
    .bind(race.id)
    .first<{ id: string }>();
  if (existing) return false;
  const count = await db
    .prepare("SELECT COUNT(*) as n FROM race_members WHERE race_id = ? AND status = 'active'")
    .bind(race.id)
    .first<{ n: number }>();
  await recordRaceEvents(db, race.id, [
    {
      type: 'race_started',
      payload: { title: race.title, startAt: race.start_at, participantCount: count?.n ?? 0 },
    },
  ]);
  return true;
}

export interface LifecycleTransition {
  race: RaceRow;
  events: RaceEventInput[];
}

/**
 * Cron sweep — one indexed scan per lifecycle edge. Called from the worker
 * scheduled() handler; the same helpers run lazily on reads so correctness
 * never depends on cron cadence. Returns the transitions produced so the
 * caller can publish notifications — this module emits durable events only.
 */
export async function sweepRaceLifecycle(
  db: D1Database,
  now = new Date(),
): Promise<LifecycleTransition[]> {
  const iso = now.toISOString();
  const transitions: LifecycleTransition[] = [];

  const ended = await db
    .prepare(
      `SELECT * FROM races
       WHERE status = 'active' AND end_at IS NOT NULL AND end_at <= ? AND deleted_at IS NULL`,
    )
    .bind(iso)
    .all<RaceRow>();
  for (const race of ended.results) {
    const res = await finalizeRaceIfEnded(db, race, now);
    if (res.finalized) {
      transitions.push({
        race: { ...race, status: 'completed', winner_user_id: res.winnerUserId },
        events: res.events,
      });
    }
  }

  const due = await db
    .prepare(
      `SELECT r.* FROM races r
       WHERE r.status = 'active' AND r.start_at IS NOT NULL AND r.start_at <= ?
         AND r.deleted_at IS NULL
         AND NOT EXISTS (
           SELECT 1 FROM race_events e WHERE e.race_id = r.id AND e.event_type = 'race_started'
         )`,
    )
    .bind(iso)
    .all<RaceRow>();
  for (const race of due.results) {
    if (await markRaceStartedIfDue(db, race, now)) {
      transitions.push({
        race,
        events: [{ type: 'race_started', payload: { title: race.title, startAt: race.start_at } }],
      });
    }
  }
  return transitions;
}
