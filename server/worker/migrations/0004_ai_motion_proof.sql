ALTER TABLE proofs ADD COLUMN ai_activity_type TEXT;
ALTER TABLE proofs ADD COLUMN detected_value INTEGER;
ALTER TABLE proofs ADD COLUMN target_value INTEGER;
ALTER TABLE proofs ADD COLUMN confidence REAL;
ALTER TABLE proofs ADD COLUMN validator_version TEXT;
ALTER TABLE proofs ADD COLUMN frames_analyzed INTEGER;
ALTER TABLE proofs ADD COLUMN valid_pose_frames INTEGER;
ALTER TABLE proofs ADD COLUMN duration_ms INTEGER;
