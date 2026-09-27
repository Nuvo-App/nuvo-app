-- Motion model control plane — System B (Nuvo Motion Intelligence releases).
--
-- `motion_model_releases` already existed as an immutable artifact registry for
-- the basketball object model. This migration generalizes it into the release
-- registry for ALL remote model families (object detectors + the general
-- motion encoder), adds channel pointers for internal/beta/stable rollout, and
-- adds the evaluation gate required before stable promotion.

ALTER TABLE motion_model_releases ADD COLUMN model_family TEXT NOT NULL DEFAULT 'auxiliary_object';
ALTER TABLE motion_model_releases ADD COLUMN runtime_family TEXT NOT NULL DEFAULT '';
ALTER TABLE motion_model_releases ADD COLUMN output_schema_version INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN preprocessing_version INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN normalization_version INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN embedding_schema_version INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN minimum_app_build INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN artifact_size_bytes INTEGER;
ALTER TABLE motion_model_releases ADD COLUMN evaluation_id TEXT;
ALTER TABLE motion_model_releases ADD COLUMN disabled_at TEXT;

-- The one pre-existing row is the basketball YOLOX object model.
UPDATE motion_model_releases
   SET model_family = 'basketball_yolox', runtime_family = 'yolox_800_v1'
 WHERE model_version = 'basketball-yolox-s-800';

-- Channel pointers: which release each (family, channel) resolves to.
-- Mirrors verifier release assignments — immutable releases, mutable pointers.
-- `rollout_percent` gates deterministic user bucketing; `previous_release_id`
-- gives an instant fallback target for rollout exclusion and rollback.
CREATE TABLE IF NOT EXISTS motion_model_channels (
  model_family TEXT NOT NULL,
  channel TEXT NOT NULL,
  release_id TEXT NOT NULL REFERENCES motion_model_releases(id),
  previous_release_id TEXT REFERENCES motion_model_releases(id),
  rollout_percent INTEGER NOT NULL DEFAULT 100,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (model_family, channel)
);

-- Evaluation gate records. A stable promotion requires a passing row.
CREATE TABLE IF NOT EXISTS motion_model_evaluations (
  id TEXT PRIMARY KEY,
  release_id TEXT NOT NULL REFERENCES motion_model_releases(id),
  corpus_id TEXT,
  sample_count INTEGER NOT NULL,
  passed INTEGER NOT NULL,
  metrics_json TEXT NOT NULL DEFAULT '{}',
  evaluator TEXT NOT NULL DEFAULT 'ops',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_motion_model_evaluations_release
  ON motion_model_evaluations(release_id, created_at DESC);

-- Keep the launch basketball artifact resolvable through the uniform
-- channel-pointer path.
INSERT OR IGNORE INTO motion_model_channels
  (model_family, channel, release_id, rollout_percent)
SELECT 'basketball_yolox', 'stable', id, 100
  FROM motion_model_releases
 WHERE model_version = 'basketball-yolox-s-800';
