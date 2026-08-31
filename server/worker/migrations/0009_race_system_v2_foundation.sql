-- Migration 0009: Race System V2 foundation
--
-- Non-destructive additions for structured race configuration, idempotent
-- verified submissions, backend-owned scores, and final standings.

ALTER TABLE races ADD COLUMN activity_id TEXT;
ALTER TABLE races ADD COLUMN metric TEXT;
ALTER TABLE races ADD COLUMN format TEXT NOT NULL DEFAULT 'first_to_goal';
ALTER TABLE races ADD COLUMN scoring_rule TEXT NOT NULL DEFAULT 'cumulative_sum';
ALTER TABLE races ADD COLUMN attempt_duration_seconds INTEGER;
ALTER TABLE races ADD COLUMN attempt_limit INTEGER;
ALTER TABLE races ADD COLUMN verification_method TEXT NOT NULL DEFAULT 'camera_pose';
ALTER TABLE races ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/New_York';
ALTER TABLE races ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none';
ALTER TABLE races ADD COLUMN winner_user_id TEXT;
ALTER TABLE races ADD COLUMN completed_at TEXT;

UPDATE races
SET
  activity_id = CASE
    WHEN movement_type = 'pushups' THEN 'push_ups'
    WHEN movement_type = 'push_ups' THEN 'push_ups'
    WHEN movement_type = 'jumping_jacks' THEN 'jumping_jacks'
    WHEN movement_type = 'squats' THEN 'squats'
    WHEN movement_type = 'lunges' THEN 'lunges'
    WHEN movement_type = 'plank' THEN 'plank_hold'
    WHEN movement_type = 'plank_hold' THEN 'plank_hold'
    ELSE movement_type
  END,
  metric = CASE
    WHEN target_unit = 'seconds' THEN 'seconds'
    ELSE 'reps'
  END,
  format = CASE
    WHEN race_type = 'first_to_goal' THEN 'first_to_goal'
    WHEN race_type = 'first_to_target' THEN 'first_to_goal'
    ELSE 'first_to_goal'
  END,
  scoring_rule = 'cumulative_sum',
  verification_method = CASE
    WHEN verification_type = 'movecheck' THEN 'camera_pose'
    ELSE verification_type
  END
WHERE activity_id IS NULL OR metric IS NULL;

ALTER TABLE move_logs ADD COLUMN client_submission_id TEXT;
ALTER TABLE move_logs ADD COLUMN activity_id TEXT;
ALTER TABLE move_logs ADD COLUMN metric TEXT;
ALTER TABLE move_logs ADD COLUMN previous_score INTEGER;
ALTER TABLE move_logs ADD COLUMN new_score INTEGER;
ALTER TABLE move_logs ADD COLUMN previous_rank INTEGER;
ALTER TABLE move_logs ADD COLUMN new_rank INTEGER;
ALTER TABLE move_logs ADD COLUMN race_completed INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_move_logs_client_submission
  ON move_logs(race_id, user_id, client_submission_id)
  WHERE client_submission_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS race_final_standings (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  rank_position INTEGER NOT NULL,
  score_value INTEGER NOT NULL,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_final_standings_race
  ON race_final_standings(race_id, rank_position);
