/**
 * Community proof veto — race-truth enforcement, not cosmetic reporting.
 *
 * A veto vote says "this proof should not count in THIS race". Votes are
 * durable audit rows (never deleted) and consensus is deterministic:
 *
 *   eligible voters = active race members excluding the proof submitter
 *   threshold       = floor(eligible / 2) + 1   (majority of eligible others)
 *   1v1 race        → eligible = 1 → threshold = 1 — the sole opponent's
 *                     veto IS consensus; nobody else exists to vote.
 *
 * States: none → disputed (votes > 0, below threshold) → vetoed (consensus).
 * Consensus transitions the proof to vetoed — the route layer then removes
 * it from race truth (progress, winner, XP) and stamps move_logs.vetoed_at.
 */
import type { D1Database } from '@cloudflare/workers-types';
import { generateId } from '../lib/crypto';

export const VETO_REASONS = [
  'not_shown',     // doesn't show the result
  'wrong_result',  // evidence contradicts the entered value
  'stale_proof',   // old or unrelated proof
  'other',
] as const;
export type VetoReason = (typeof VETO_REASONS)[number];
export const VETO_REASON_SET: ReadonlySet<string> = new Set(VETO_REASONS);

/** Majority of eligible OTHER participants — the 1v1 case falls out for free. */
export function vetoThreshold(eligibleVoters: number): number {
  return Math.floor(eligibleVoters / 2) + 1;
}

export interface VetoOutcome {
  /** This voter already had an active vote on the proof (idempotent re-cast). */
  alreadyVoted: boolean;
  voteCount: number;
  eligibleVoters: number;
  threshold: number;
  state: 'none' | 'disputed' | 'vetoed';
  /** This vote opened the dispute (first vote on the proof). */
  firstVote: boolean;
  /** This vote crossed consensus — caller must invalidate race truth. */
  justVetoed: boolean;
}

/**
 * Record one participant's veto and evaluate consensus.
 *
 * Idempotent per (proof, voter) — a repeat call returns the current outcome
 * without double-counting. Eligibility (active member, not the submitter) is
 * enforced by the caller; this function is the pure consensus step.
 */
export async function castProofVote(
  db: D1Database,
  input: {
    raceId: string;
    moveId: string;
    submitterId: string;
    voterId: string;
    reason: VetoReason;
    /** move_logs.vetoed_at — set when the proof is already vetoed. */
    alreadyVetoed: boolean;
  },
): Promise<VetoOutcome> {
  const eligible = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM race_members
       WHERE race_id = ? AND status = 'active' AND user_id != ?`,
    )
    .bind(input.raceId, input.submitterId)
    .first<{ n: number }>();
  const eligibleVoters = eligible?.n ?? 0;

  const prior = await db
    .prepare('SELECT id FROM proof_votes WHERE move_log_id = ? AND voter_user_id = ?')
    .bind(input.moveId, input.voterId)
    .first<{ id: string }>();
  const alreadyVoted = prior != null;
  if (!alreadyVoted) {
    await db
      .prepare(
        `INSERT INTO proof_votes (id, move_log_id, race_id, voter_user_id, reason, created_at)
         VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), input.moveId, input.raceId, input.voterId, input.reason)
      .run();
  }

  const count = await db
    .prepare('SELECT COUNT(*) AS n FROM proof_votes WHERE move_log_id = ?')
    .bind(input.moveId)
    .first<{ n: number }>();
  const voteCount = count?.n ?? 0;
  const threshold = vetoThreshold(eligibleVoters);

  const state: VetoOutcome['state'] =
    input.alreadyVetoed || voteCount >= threshold ? 'vetoed' : voteCount > 0 ? 'disputed' : 'none';

  return {
    alreadyVoted,
    voteCount,
    eligibleVoters,
    threshold,
    state,
    firstVote: voteCount === 1 && !alreadyVoted,
    justVetoed: state === 'vetoed' && !input.alreadyVetoed,
  };
}
