-- 0043_proof_votes.sql
-- Community proof veto + evidence reversal.
--
-- proof_votes: one row per (proof, voter) — a participant's dispute that the
-- proof should count in THIS race. Consensus among the other active racers
-- vetoes the proof; rows are never deleted so the audit trail survives.
--
-- move_logs.vetoed_at: set when community consensus vetoed the proof. The
-- status field ('rejected') is what scoring reads; vetoed_at distinguishes a
-- participant veto from a creator/verifier rejection in the UI.
--
-- race_events.move_log_id / voided_at: links each scoring event to the proof
-- that produced it so a veto can void exactly those events — progression
-- (xp_events, stats, unlocks) reconciles from still-valid history.

CREATE TABLE IF NOT EXISTS proof_votes (
  id TEXT PRIMARY KEY,
  move_log_id TEXT NOT NULL REFERENCES move_logs(id),
  race_id TEXT NOT NULL REFERENCES races(id),
  voter_user_id TEXT NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL,                          -- not_shown | wrong_result | stale_proof | other
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (move_log_id, voter_user_id)
);

CREATE INDEX IF NOT EXISTS idx_proof_votes_move ON proof_votes(move_log_id);
CREATE INDEX IF NOT EXISTS idx_proof_votes_race ON proof_votes(race_id);

ALTER TABLE move_logs ADD COLUMN vetoed_at TEXT;
ALTER TABLE race_events ADD COLUMN move_log_id TEXT;
ALTER TABLE race_events ADD COLUMN voided_at TEXT;

CREATE INDEX IF NOT EXISTS idx_race_events_move ON race_events(move_log_id);
