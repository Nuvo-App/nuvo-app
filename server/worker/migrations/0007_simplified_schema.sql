-- Migration 0007: Simplified backend schema for Nuvo
--
-- Goal: Make the database easy to understand and edit directly in the
-- Cloudflare D1 visual editor while supporting MoveCheck-verified races.
--
-- Safety: This migration renames the existing race/proof tables to *_legacy
-- instead of dropping them. Data is preserved. Old auth/social tables remain
-- untouched. A follow-up migration (0008) will copy data into the new tables.
--
-- Rollback: Rename *_legacy tables back to their original names and drop the
-- new tables created here. Note that any writes that happened after this
-- migration would be lost on rollback.

-- Rename current race-related tables to legacy names so the new schema can use
-- the clean names requested in the architecture redo. SQLite automatically
-- updates foreign key references when the parent table is renamed.
ALTER TABLE races RENAME TO races_legacy;
ALTER TABLE race_participants RENAME TO race_participants_legacy;
ALTER TABLE proofs RENAME TO proofs_legacy;

-- Add media-tracking and demo flags to profiles.
ALTER TABLE profiles ADD COLUMN avatar_object_key TEXT;
ALTER TABLE profiles ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- New table: media_objects
-- Tracks every important R2 object inside D1 so media is not invisible URLs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS media_objects (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT,
  bucket TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  public_url TEXT,
  media_type TEXT NOT NULL DEFAULT 'image',        -- image | video
  purpose TEXT NOT NULL DEFAULT 'system_asset',    -- profile_avatar | race_cover | move_media | demo_avatar | system_asset
  status TEXT NOT NULL DEFAULT 'active',           -- active | replaced | deleted | orphaned
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  FOREIGN KEY(owner_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_media_objects_owner ON media_objects(owner_user_id, status);
CREATE INDEX IF NOT EXISTS idx_media_objects_purpose ON media_objects(purpose, status);
CREATE INDEX IF NOT EXISTS idx_media_objects_object_key ON media_objects(object_key);

-- ---------------------------------------------------------------------------
-- New table: races
-- Clean, human-editable race definition.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS races (
  id TEXT PRIMARY KEY,
  creator_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  race_type TEXT NOT NULL DEFAULT 'first_to_target',  -- first_to_target | most_in_time | daily_streak | habit_check
  movement_type TEXT,                                  -- pushups | squats | jumping_jacks | plank | lunges | custom
  verification_type TEXT NOT NULL DEFAULT 'manual',      -- movecheck | manual | photo | none
  target_value INTEGER,
  target_unit TEXT,                                      -- reps | seconds | minutes | days | count
  status TEXT NOT NULL DEFAULT 'draft',                  -- draft | active | completed | archived | cancelled
  visibility TEXT NOT NULL DEFAULT 'private',            -- private | crew_only | invite_code | public_demo
  start_at TEXT,
  end_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  FOREIGN KEY(creator_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_races_creator ON races(creator_id);
CREATE INDEX IF NOT EXISTS idx_races_status ON races(status);
CREATE INDEX IF NOT EXISTS idx_races_deleted_at ON races(deleted_at);
CREATE INDEX IF NOT EXISTS idx_races_visibility ON races(visibility, status);

-- ---------------------------------------------------------------------------
-- New table: race_members
-- Membership and roles for each race. No progress here.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS race_members (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'racer',     -- creator | racer | viewer
  status TEXT NOT NULL DEFAULT 'active',    -- active | left | removed
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cached_display_name TEXT,
  cached_avatar_url TEXT,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_members_race ON race_members(race_id, status);
CREATE INDEX IF NOT EXISTS idx_race_members_user ON race_members(user_id, status);

-- ---------------------------------------------------------------------------
-- New table: race_progress
-- Human-editable cache of current progress and leaderboard rank.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- New table: move_logs
-- Every submitted/verified move. Replaces proofs.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS move_logs (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  source TEXT NOT NULL,                        -- movecheck | manual | demo | import
  movement_type TEXT,
  value INTEGER,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'pending',      -- pending | verified | rejected | removed
  summary TEXT,
  media_object_key TEXT,
  validator_version TEXT,
  duration_ms INTEGER,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(media_object_key) REFERENCES media_objects(object_key)
);

CREATE INDEX IF NOT EXISTS idx_move_logs_race ON move_logs(race_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_move_logs_user ON move_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_move_logs_status ON move_logs(status);

-- Note: race_invites and crew_connections are kept as-is from earlier migrations.
-- Their schema already matches the target design.
