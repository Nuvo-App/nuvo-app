-- Migration 0021: register the verified basketball detector artifact.
-- The ONNX bytes live in R2; this row makes the immutable model identity
-- discoverable through the existing motion-model transport endpoint.

INSERT INTO motion_model_releases
  (id, model_version, input_schema_version, artifact_key, artifact_sha256,
   status, supported_motion_ids_json, metadata_json, promoted_at)
VALUES
  ('basketball-yolox-s-800-2026.09.1', 'basketball-yolox-s-800', 1,
   'motion-models/basketball-yolox-s-800.onnx',
   'dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425',
   'production', '["basketball_shot"]',
   '{"source":"ortizeg/basketball-yolox-s-800","license":"Apache-2.0","inputSize":800,"outputShape":[1,13125,15]}',
   CURRENT_TIMESTAMP)
ON CONFLICT(model_version) DO UPDATE SET
  artifact_key = excluded.artifact_key,
  artifact_sha256 = excluded.artifact_sha256,
  status = 'production',
  supported_motion_ids_json = excluded.supported_motion_ids_json,
  metadata_json = excluded.metadata_json,
  promoted_at = CURRENT_TIMESTAMP;
