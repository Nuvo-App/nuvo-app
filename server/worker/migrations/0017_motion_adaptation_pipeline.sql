-- Motion adaptation pipeline.
-- Additive only. Rollback is a forward fix: disable pointers and preserve
-- telemetry, evaluation, and audit records.

CREATE TABLE IF NOT EXISTS motion_release_metrics (
  release_id TEXT NOT NULL,
  activity_id TEXT NOT NULL,
  outcome TEXT NOT NULL,
  failure_reason TEXT NOT NULL DEFAULT '',
  sample_count INTEGER NOT NULL DEFAULT 0,
  total_detected INTEGER NOT NULL DEFAULT 0,
  total_confidence REAL NOT NULL DEFAULT 0,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (release_id, activity_id, outcome, failure_reason),
  FOREIGN KEY (release_id) REFERENCES verifier_releases(id),
  FOREIGN KEY (activity_id) REFERENCES motion_activities(id)
);

CREATE INDEX IF NOT EXISTS idx_motion_release_metrics_activity
  ON motion_release_metrics(activity_id, release_id, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS motion_feedback_labels (
  id TEXT PRIMARY KEY,
  motion_session_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  label TEXT NOT NULL CHECK (label IN ('missed_count', 'false_count', 'camera_issue', 'worked')),
  note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (motion_session_id, user_id, label)
);

CREATE INDEX IF NOT EXISTS idx_motion_feedback_session
  ON motion_feedback_labels(motion_session_id, created_at DESC);

CREATE TABLE IF NOT EXISTS verifier_audit_log (
  id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  activity_id TEXT,
  release_id TEXT,
  previous_release_id TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_verifier_audit_release
  ON verifier_audit_log(release_id, created_at DESC);
