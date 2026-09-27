-- Migration 0033: fixture the first remote-only activity — a motion that has
-- no compiled identity anywhere in the iOS binary or the static race
-- catalog. This is the acceptance slice for the universal competition
-- engine: the activity exists ONLY as control-plane data.
--
-- `remote_test_motion` ("Reach Taps") runs on the existing alternating_rep_v1
-- engine — left/right wrist reach alternation — so the slice proves identity
-- resolution, package parsing, generic metadata, runtime selection, and proof
-- identity preservation without shipping a new engine.
--
-- The release spec carries an `activity` block (display name, camera hint,
-- instructions, measurement semantics) so the client can present and verify
-- the motion with zero compiled knowledge of it. Additive and reversible by
-- disabling the channel pointer and the activity row.

INSERT OR IGNORE INTO motion_activities
  (id, display_name, category, proof_label, measurement_type, metric,
   suggested_targets_json, supported_formats_json, icon_key, sort_priority,
   featured, availability, metadata_json)
VALUES (
  'remote_test_motion',
  'Reach Taps',
  'upper_body',
  'reach taps',
  'repetitions',
  'reps',
  '[5,10,20,40]',
  '["first_to_goal","most_in_window","best_attempt"]',
  'sports_gymnastics',
  90,
  0,
  'supported',
  '{"cameraOrientation":"front","instructions":["Stand facing the camera with your full body in frame.","Raise one hand overhead, then the other.","Alternate hands cleanly to count each rep."],"aliases":["reach taps","overhead reach taps"]}'
);

INSERT OR IGNORE INTO verifier_releases
  (id, activity_id, semver, change_class, engine_type, spec_schema_version,
   spec_json, checksum, required_capabilities_json, minimum_app_build,
   compatibility_group, status, release_notes, published_at)
VALUES (
  'remote_test_motion-2026.10.0',
  'remote_test_motion',
  '2026.10.0',
  'minor',
  'alternating_rep_v1',
  1,
  '{"specSchemaVersion":1,"releaseId":"remote_test_motion-2026.10.0","activityId":"remote_test_motion","engineType":"alternating_rep_v1","measurementType":"repetitions","requiredCapabilities":["pose_landmarks_v1","derived_features_v1","alternating_rep_v1"],"requiredLandmarks":["leftShoulder","rightShoulder","leftWrist","rightWrist"],"stableFrames":2,"leftRules":[{"point":"leftWrist","axis":"y","operator":"lt","threshold":0.35}],"rightRules":[{"point":"rightWrist","axis":"y","operator":"lt","threshold":0.35}],"activity":{"displayName":"Reach Taps","measurementType":"repetitions","defaultTarget":10,"preferredCameraView":"front","instructions":["Stand facing the camera with your full body in frame.","Raise one hand overhead, then the other.","Alternate hands cleanly to count each rep."],"unit":"reach taps","coachingTextActive":"Reach up with one hand, then the other","coachingTextIncomplete":"Keep both arms visible"}}',
  'sha256:b6930bb5f6e39ea923f44ee4ccd564e09243b1daa1e24d9118a8cff771209851',
  '["pose_landmarks_v1","derived_features_v1","alternating_rep_v1"]',
  'remote-runtime-v1',
  'remote_test_motion-remote-v1',
  'stable',
  'First remote-only activity fixture; proves OTA motion delivery end to end.',
  CURRENT_TIMESTAMP
);

INSERT OR REPLACE INTO activity_channel_releases
  (activity_id, channel, release_id, rollout_percent)
VALUES
  ('remote_test_motion', 'stable', 'remote_test_motion-2026.10.0', 100);
