-- One-time live D1 compatibility patch.
--
-- The remote database has the older admin/demo tables recorded as migrations
-- 0007/0008, while the deployed Worker expects the simplified race schema in
-- the local migrations. This patch only adds missing columns/tables; it does
-- not rename or drop live tables.

ALTER TABLE users ADD COLUMN terms_accepted_at TEXT;

ALTER TABLE profiles ADD COLUMN avatar_object_key TEXT;
ALTER TABLE profiles ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS media_objects (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT,
  bucket TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  public_url TEXT,
  media_type TEXT NOT NULL DEFAULT 'image',
  purpose TEXT NOT NULL DEFAULT 'system_asset',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  FOREIGN KEY(owner_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_media_objects_owner ON media_objects(owner_user_id, status);
CREATE INDEX IF NOT EXISTS idx_media_objects_purpose ON media_objects(purpose, status);
CREATE INDEX IF NOT EXISTS idx_media_objects_object_key ON media_objects(object_key);

ALTER TABLE races ADD COLUMN movement_type TEXT;
ALTER TABLE races ADD COLUMN verification_type TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE races ADD COLUMN start_at TEXT;
ALTER TABLE races ADD COLUMN end_at TEXT;
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
ALTER TABLE races ADD COLUMN public_join_enabled INTEGER NOT NULL DEFAULT 1;

ALTER TABLE race_members ADD COLUMN user_id TEXT;
ALTER TABLE race_members ADD COLUMN role TEXT NOT NULL DEFAULT 'racer';
ALTER TABLE race_members ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE race_members ADD COLUMN cached_display_name TEXT;
ALTER TABLE race_members ADD COLUMN cached_avatar_url TEXT;

CREATE INDEX IF NOT EXISTS idx_race_members_race_compat ON race_members(race_id, status);
CREATE INDEX IF NOT EXISTS idx_race_members_user_compat ON race_members(user_id, status);

CREATE TABLE IF NOT EXISTS race_progress (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  progress_value INTEGER NOT NULL DEFAULT 0,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  rank_cache INTEGER,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_progress_race ON race_progress(race_id, progress_percent DESC, progress_value DESC);
CREATE INDEX IF NOT EXISTS idx_race_progress_user ON race_progress(user_id);

CREATE TABLE IF NOT EXISTS move_logs (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  source TEXT NOT NULL,
  movement_type TEXT,
  value INTEGER,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  summary TEXT,
  media_object_key TEXT,
  validator_version TEXT,
  duration_ms INTEGER,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  client_submission_id TEXT,
  activity_id TEXT,
  metric TEXT,
  previous_score INTEGER,
  new_score INTEGER,
  previous_rank INTEGER,
  new_rank INTEGER,
  race_completed INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(media_object_key) REFERENCES media_objects(object_key)
);

CREATE INDEX IF NOT EXISTS idx_move_logs_race ON move_logs(race_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_move_logs_user ON move_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_move_logs_status ON move_logs(status);
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

CREATE TABLE IF NOT EXISTS blocked_users (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(blocked_user_id) REFERENCES users(id),
  UNIQUE(user_id, blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_user ON blocked_users(user_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON blocked_users(blocked_user_id);
