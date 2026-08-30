CREATE TABLE IF NOT EXISTS motion_definitions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1,
  definition_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS motion_analysis_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  motion_id TEXT NOT NULL,
  status TEXT NOT NULL,
  request_schema_version INTEGER NOT NULL,
  model_version TEXT NOT NULL,
  validator_version TEXT NOT NULL,
  result_json TEXT,
  frame_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_motion_analysis_jobs_user_created
  ON motion_analysis_jobs(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS motion_training_examples (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  motion_id TEXT NOT NULL,
  object_key TEXT,
  label TEXT,
  review_status TEXT NOT NULL DEFAULT 'unreviewed',
  consent_version TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT
);

CREATE TABLE IF NOT EXISTS motion_model_releases (
  id TEXT PRIMARY KEY,
  model_version TEXT NOT NULL UNIQUE,
  input_schema_version INTEGER NOT NULL,
  artifact_key TEXT,
  artifact_sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'candidate',
  supported_motion_ids_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  promoted_at TEXT
);
