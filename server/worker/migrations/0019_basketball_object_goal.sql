-- Migration 0019: internal basketball object-interaction goal.
-- This is intentionally internal-only until an object-dot producer and
-- physical replay gate are available. No raw video is stored or required.

INSERT OR IGNORE INTO motion_activities
  (id, display_name, category, proof_label, measurement_type, metric,
   suggested_targets_json, supported_formats_json, icon_key, sort_priority,
   featured, availability, metadata_json)
VALUES
  ('basketball_shot', 'Basketball Shot', 'object_interaction', 'made basketball shots',
   'repetitions', 'reps', '[1,3,5,10]',
   '["first_to_goal","most_in_window","best_attempt"]', 'sports_basketball',
   4, 0, 'internal',
   '{"verifierMode":"object_composition","objectKinds":["ball","hoop"],"rawVideo":false}');

INSERT OR IGNORE INTO verifier_releases
  (id, activity_id, semver, change_class, engine_type, spec_schema_version,
   spec_json, checksum, required_capabilities_json, minimum_app_build,
   compatibility_group, status, release_notes)
VALUES
  ('basketball_shot-composition-2026.09.1', 'basketball_shot', '2026.09.1',
   'minor', 'object_composition_v1', 1,
   '{"specSchemaVersion":1,"releaseId":"basketball_shot-composition-2026.09.1","activityId":"basketball_shot","engineType":"object_composition_v1","measurementType":"repetitions","requiredCapabilities":["pose_landmarks_v1","object_dots_v1","object_composition_v1"],"requiredLandmarks":["leftWrist","rightWrist"],"requiredObjects":[{"id":"ball","kind":"ball","minLikelihood":0.45},{"id":"hoop","kind":"hoop","minLikelihood":0.55}],"model":{"modelVersion":"basketball-yolox-s-800","inputSchemaVersion":1,"artifactSha256":"dc5a5afe11ac75ba9c80f1975cb1f7dc8bc738a6a37a8a4ecfb78fa196b3b425","inputSize":800},"composition":{"states":["ready","released","ascending","descending","made","missed"],"transitions":[{"from":"ready","to":"released","event":"ball_released"},{"from":"released","to":"ascending","event":"ball_ascending"},{"from":"ascending","to":"descending","event":"ball_descending"},{"from":"descending","to":"made","event":"ball_through_hoop"},{"from":"ascending","to":"missed","event":"shot_timeout"},{"from":"descending","to":"missed","event":"shot_timeout"}],"startState":"ready","terminalStates":["made","missed"],"ballObjectId":"ball","hoopObjectId":"hoop","stableFrames":2,"maxShotMs":8000,"controlDistance":0.22,"releaseDistance":0.16,"minUpwardVelocity":0.06,"minDownwardVelocity":0.04,"hoopPlaneTolerance":0.08,"madeRadius":0.18}}',
   '740ade0dbf1bccf1b233ae1de81a63db109233e80bb6c90ed98414afa439ad4a',
   '["pose_landmarks_v1","object_dots_v1","object_composition_v1"]',
   'object-runtime-v1', 'basketball-object-composition-v1', 'internal',
   'Initial dot-only basketball composition candidate; requires object tracking and replay validation.');

INSERT OR REPLACE INTO activity_channel_releases
  (activity_id, channel, release_id, rollout_percent)
VALUES ('basketball_shot', 'internal', 'basketball_shot-composition-2026.09.1', 0);
