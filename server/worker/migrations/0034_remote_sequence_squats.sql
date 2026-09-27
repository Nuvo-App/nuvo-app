-- Migration 0034: second remote-only activity fixture — this one proves the
-- `sequence_match_v1` engine end to end. `0033_remote_test_motion` covered
-- alternating_rep_v1; this covers the phase-chain engine so every shipped
-- remote engine has a live control-plane activity.
--
-- `remote_seq_squats` ("Squat Jumps") exists ONLY as control-plane data — no
-- compiled Dart identity, no static catalog entry, no bundled release. The
-- release is spec-only (no package manifest, no binary assets): discovery,
-- checksum pinning, capability resolution, and runtime creation all run on
-- the declarative spec alone.
--
-- The phase chain is strict-linear per the engine contract:
--   standing (knees extended) → crouch (knees flexed) → airborne (extended
--   + ankles lifted) → complete. A rep fires only when all three phases hold
--   in order with dwell hysteresis.
--
-- checksum = sha256 of the canonical JSON.stringify(spec_json) — the same
-- convention the internal publish route uses, so the release is
-- byte-identical to a control-plane-published one.
--
-- Additive and reversible by disabling the channel pointer and the activity
-- row.

INSERT OR IGNORE INTO motion_activities
  (id, display_name, category, proof_label, measurement_type, metric,
   suggested_targets_json, supported_formats_json, icon_key, sort_priority,
   featured, availability, metadata_json)
VALUES (
  'remote_seq_squats',
  'Squat Jumps',
  'lower_body',
  'squat jumps',
  'repetitions',
  'reps',
  '[5,10,20,40]',
  '["first_to_goal","most_in_window","best_attempt"]',
  'sports_gymnastics',
  89,
  0,
  'supported',
  '{"cameraOrientation":"front","instructions":["Step back until your full body fits the frame.","Squat until your knees bend, then jump straight up.","Land softly and stand tall before the next rep."],"aliases":["squat jumps","jump squats","squat jump"]}'
);

INSERT OR IGNORE INTO verifier_releases
  (id, activity_id, semver, change_class, engine_type, spec_schema_version,
   spec_json, checksum, required_capabilities_json, minimum_app_build,
   compatibility_group, status, release_notes, published_at)
VALUES (
  'remote_seq_squats-2026.10.0',
  'remote_seq_squats',
  '2026.10.0',
  'minor',
  'sequence_match_v1',
  1,
  '{"specSchemaVersion":1,"releaseId":"remote_seq_squats-2026.10.0","activityId":"remote_seq_squats","engineType":"sequence_match_v1","measurementType":"repetitions","requiredCapabilities":["pose_landmarks_v1","derived_features_v1","sequence_match_v1"],"requiredLandmarks":["leftHip","leftKnee","leftAnkle","rightHip","rightKnee","rightAnkle"],"stableFrames":2,"repTimeoutMs":8000,"lostPoseMs":1500,"phases":[{"id":"standing","predicates":[{"kind":"angle","a":"leftHip","b":"leftKnee","c":"leftAnkle","operator":"gte","degrees":160},{"kind":"angle","a":"rightHip","b":"rightKnee","c":"rightAnkle","operator":"gte","degrees":160}],"next":"crouch"},{"id":"crouch","predicates":[{"kind":"angle","a":"leftHip","b":"leftKnee","c":"leftAnkle","operator":"lte","degrees":120},{"kind":"angle","a":"rightHip","b":"rightKnee","c":"rightAnkle","operator":"lte","degrees":120}],"next":"airborne"},{"id":"airborne","predicates":[{"kind":"angle","a":"leftHip","b":"leftKnee","c":"leftAnkle","operator":"gte","degrees":150},{"kind":"angle","a":"rightHip","b":"rightKnee","c":"rightAnkle","operator":"gte","degrees":150},{"kind":"landmark_axis","point":"leftAnkle","axis":"y","operator":"lt","threshold":0.88},{"kind":"landmark_axis","point":"rightAnkle","axis":"y","operator":"lt","threshold":0.88}],"next":"complete"}],"activity":{"displayName":"Squat Jumps","measurementType":"repetitions","defaultTarget":10,"preferredCameraView":"front","instructions":["Step back until your full body fits the frame.","Squat until your knees bend, then jump straight up.","Land softly and stand tall before the next rep."],"unit":"squat jumps","coachingTextActive":"Squat low, then explode up","coachingTextIncomplete":"Keep your whole body in frame"}}',
  'sha256:ed3ca2679aa84b785342dafce41e205606f4cd67a392401f9b1f6a69ffe29a20',
  '["pose_landmarks_v1","derived_features_v1","sequence_match_v1"]',
  'remote-runtime-v1',
  'remote_seq_squats-remote-v1',
  'stable',
  'Sequence-engine remote fixture; proves OTA motion delivery for phase chains.',
  CURRENT_TIMESTAMP
);

INSERT OR REPLACE INTO activity_channel_releases
  (activity_id, channel, release_id, rollout_percent)
VALUES
  ('remote_seq_squats', 'stable', 'remote_seq_squats-2026.10.0', 100);
