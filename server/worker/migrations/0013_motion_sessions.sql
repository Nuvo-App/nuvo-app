-- Motion Intelligence — Motion Session telemetry (PRD Phases 1–3).
--
-- Every dev/beta preset verification attempt uploads a self-contained
-- `.json.gz` artifact (landmark stream + verifier decision trace + result) to
-- R2. This table is the searchable index over those blobs: an internal tool
-- resolves a user, finds their latest / a specific / recent failed session,
-- then pulls the full artifact from R2 by `object_key`.

CREATE TABLE IF NOT EXISTS motion_sessions (
  id TEXT PRIMARY KEY,                    -- server row id
  session_id TEXT NOT NULL UNIQUE,        -- client-generated MotionSessionRecorder id (ms_...)
  user_id TEXT NOT NULL,
  race_id TEXT,
  activity_id TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'preset',    -- preset | custom
  outcome TEXT NOT NULL DEFAULT 'incomplete', -- verified | failed | incomplete
  detected_value INTEGER NOT NULL DEFAULT 0,
  goal_value INTEGER,
  confidence REAL NOT NULL DEFAULT 0,
  failed_rule_reason TEXT NOT NULL DEFAULT '',
  started_at TEXT,
  ended_at TEXT,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  frame_count INTEGER NOT NULL DEFAULT 0,
  schema_version INTEGER NOT NULL DEFAULT 1,
  app_version TEXT NOT NULL DEFAULT 'unknown',
  git_commit TEXT NOT NULL DEFAULT 'unknown',
  verifier_version TEXT NOT NULL DEFAULT 'unknown',
  model_version TEXT NOT NULL DEFAULT 'unknown',
  object_key TEXT NOT NULL,               -- R2 key of the .json.gz artifact
  metadata_json TEXT,                     -- the client-sent searchable metadata blob, verbatim
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_motion_sessions_user_created
  ON motion_sessions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_motion_sessions_user_activity_created
  ON motion_sessions(user_id, activity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_motion_sessions_activity_created
  ON motion_sessions(activity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_motion_sessions_outcome_created
  ON motion_sessions(outcome, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_motion_sessions_race
  ON motion_sessions(race_id, created_at DESC);
