-- 0047: reconcile production with what the Worker code expects.
-- Additive and idempotent: safe to run on production and on a migrated DB.
--
-- Audit (docs/prod_schema.json vs migrations + src):
--   * `reports` never reached production (0010 was only partly applied), so
--     user / content reporting failed there.
--   * race_members had UNIQUE(race_id, person_id) but no UNIQUE(race_id,
--     user_id); joins that dedupe on (race_id, user_id) need it.
--   * Hot-path indexes the code relies on were missing.

CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  reporter_user_id TEXT NOT NULL,
  target_type TEXT NOT NULL,          -- user | race | content
  target_id TEXT NOT NULL,            -- user id, race id, or move log id
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | reviewed | resolved | dismissed
  reviewed_by TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(reporter_user_id) REFERENCES users(id),
  FOREIGN KEY(reviewed_by) REFERENCES users(id)
);
CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_user_id, status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_type, target_id, status);

-- One active row per (race, user). NULL user_id rows (demo people) are exempt.
CREATE UNIQUE INDEX IF NOT EXISTS uq_race_members_race_user ON race_members(race_id, user_id);

-- Nightly / sweep finalisation: WHERE status = 'active' AND end_at <= ?
CREATE INDEX IF NOT EXISTS idx_races_status_end ON races(status, end_at);
CREATE INDEX IF NOT EXISTS idx_races_visibility_status ON races(visibility, status);
-- Proof recomputation and standings: WHERE race_id = ? AND user_id = ? AND status = 'verified'
CREATE INDEX IF NOT EXISTS idx_move_logs_race_user_status ON move_logs(race_id, user_id, status);
