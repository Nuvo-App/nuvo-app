-- Teach Nuvo telemetry — the observability half of the learned-motion loop.
--
-- One row per Teach Nuvo session (name -> 3 demos -> learn -> test -> use).
-- The row carries only searchable metadata; the full artifact (demo pose
-- landmarks, the V1 CustomPoseVerifierSpec the race will use, the V2 learned
-- spec + self-validation, live-test match trace, failure stage/reason) lives
-- encrypted in R2 under `object_key`, exactly like motion_sessions. Internal
-- tooling (teach-list / teach-get in scripts/nuvo-motion.mjs) reads these rows
-- and pulls the artifact so a session can be replayed offline.

CREATE TABLE IF NOT EXISTS motion_teach_sessions (
  id TEXT PRIMARY KEY,                    -- server row id
  session_id TEXT NOT NULL UNIQUE,        -- client-generated id (MV2-YYYYMMDD-XXXXXX)
  user_id TEXT NOT NULL,                  -- motion account ref (pseudonymous)
  movement_name TEXT NOT NULL DEFAULT '',
  outcome TEXT NOT NULL DEFAULT 'abandoned', -- used | learned | failed | abandoned
  engine TEXT NOT NULL DEFAULT 'v2',      -- matcher that ran the learn/test: v2 | v1_fallback | v1
  failure_stage TEXT,                     -- recording | v1_build | v2_learn | live_test | use
  failure_reason TEXT NOT NULL DEFAULT '',
  demo_count INTEGER NOT NULL DEFAULT 0,
  frame_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  learned INTEGER NOT NULL DEFAULT 0,     -- a usable V1 spec was produced
  v2_available INTEGER NOT NULL DEFAULT 1,-- the MotionBERT engine ran on this device
  v2_learned INTEGER NOT NULL DEFAULT 0,
  self_validation_passed INTEGER,         -- NULL when V2 never ran
  live_test_matched INTEGER,              -- NULL when no live test ran
  used_for_race INTEGER NOT NULL DEFAULT 0,
  schema_version INTEGER NOT NULL DEFAULT 1,
  app_version TEXT NOT NULL DEFAULT 'unknown',
  git_commit TEXT NOT NULL DEFAULT 'unknown',
  model_version TEXT NOT NULL DEFAULT 'unknown',   -- encoder release that produced the V2 spec
  matcher_version TEXT NOT NULL DEFAULT 'unknown', -- matcher/schema identifier
  object_key TEXT NOT NULL,               -- R2 key of the encrypted .json.gz artifact
  metadata_json TEXT,                     -- the client-sent searchable metadata blob, verbatim
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_teach_sessions_user_created
  ON motion_teach_sessions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_teach_sessions_outcome_created
  ON motion_teach_sessions(outcome, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_teach_sessions_movement_created
  ON motion_teach_sessions(movement_name, created_at DESC);
