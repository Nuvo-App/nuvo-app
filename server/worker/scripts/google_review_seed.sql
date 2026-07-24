-- Google Play / App Store review seed.
--
-- Remote run:
--   wrangler d1 execute nuvo_db --remote --file=./scripts/google_review_seed.sql
--
-- This script keeps the reviewer user keyed by email so it is safe if the
-- account was already created through the reviewer auth route.

DELETE FROM race_invites
WHERE race_id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM race_final_standings
WHERE race_id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM move_logs
WHERE race_id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM race_progress
WHERE race_id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM race_members
WHERE race_id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM races
WHERE id IN (
  'review-race-pushups',
  'review-race-squats',
  'review-race-plank',
  'review-race-lunges'
);

DELETE FROM crew_connections
WHERE user_id IN (
  SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'
  UNION SELECT 'review-crew-riley'
  UNION SELECT 'review-crew-maya'
  UNION SELECT 'review-crew-jules'
)
OR crew_user_id IN (
  SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'
  UNION SELECT 'review-crew-riley'
  UNION SELECT 'review-crew-maya'
  UNION SELECT 'review-crew-jules'
);

DELETE FROM auth_identities
WHERE provider = 'reviewer' AND provider_user_id = 'testing@getnuvo.net';

DELETE FROM sessions
WHERE user_id IN (
  SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'
);

DELETE FROM email_codes
WHERE email = 'testing@getnuvo.net';

DELETE FROM member_passes
WHERE user_id IN ('review-crew-riley', 'review-crew-maya', 'review-crew-jules');

DELETE FROM profiles
WHERE user_id IN ('review-crew-riley', 'review-crew-maya', 'review-crew-jules');

DELETE FROM people
WHERE person_key IN (
  'review-person-google',
  'review-person-riley',
  'review-person-maya',
  'review-person-jules'
)
OR user_id IN (
  SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'
  UNION SELECT 'review-crew-riley'
  UNION SELECT 'review-crew-maya'
  UNION SELECT 'review-crew-jules'
);

DELETE FROM users
WHERE id IN ('review-crew-riley', 'review-crew-maya', 'review-crew-jules');

INSERT INTO users (
  id, primary_email, status, created_at, updated_at, last_login_at,
  terms_accepted_at, demo_world_enabled, demo_world_seed, demo_world_variant
)
SELECT
  'review-user-google', 'testing@getnuvo.net', 'active',
  CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP, 0, 'google-review-2026', 'summer_v1'
WHERE NOT EXISTS (
  SELECT 1 FROM users WHERE primary_email = 'testing@getnuvo.net'
);

UPDATE users
SET status = 'active',
    last_login_at = CURRENT_TIMESTAMP,
    terms_accepted_at = COALESCE(terms_accepted_at, CURRENT_TIMESTAMP),
    demo_world_enabled = 0,
    demo_world_seed = 'google-review-2026',
    demo_world_variant = 'summer_v1',
    updated_at = CURRENT_TIMESTAMP
WHERE primary_email = 'testing@getnuvo.net';

INSERT INTO users (
  id, primary_email, status, created_at, updated_at, last_login_at,
  terms_accepted_at, demo_world_enabled
)
VALUES
  ('review-crew-riley', 'riley.review@getnuvo.net', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('review-crew-maya', 'maya.review@getnuvo.net', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('review-crew-jules', 'jules.review@getnuvo.net', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0);

INSERT INTO profiles (
  user_id, full_name, username, avatar_url, avatar_object_key,
  private_profile, onboarding_complete, is_demo, created_at, updated_at
)
SELECT
  (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
  'Nuvo Review', 'nuvoreview', NULL, NULL, 0, 1, 1,
  CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
WHERE NOT EXISTS (
  SELECT 1 FROM profiles
  WHERE user_id = (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net')
);

UPDATE profiles
SET full_name = 'Nuvo Review',
    username = 'nuvoreview',
    private_profile = 0,
    onboarding_complete = 1,
    is_demo = 1,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net');

INSERT INTO profiles (
  user_id, full_name, username, avatar_url, avatar_object_key,
  private_profile, onboarding_complete, is_demo, created_at, updated_at
)
VALUES
  ('review-crew-riley', 'Riley Pace', 'rileypace', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('review-crew-maya', 'Maya Sprint', 'mayasprint', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('review-crew-jules', 'Jules Form', 'julesform', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO member_passes (id, user_id, member_id, pass_slug, created_at)
SELECT
  'review-pass-google',
  (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
  'NUVO-REVIEW-2026',
  'nuvo-review-2026',
  CURRENT_TIMESTAMP
WHERE NOT EXISTS (
  SELECT 1 FROM member_passes
  WHERE user_id = (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net')
);

INSERT INTO member_passes (id, user_id, member_id, pass_slug, created_at)
VALUES
  ('review-pass-riley', 'review-crew-riley', 'NUVO-RILEY-001', 'nuvo-riley-001', CURRENT_TIMESTAMP),
  ('review-pass-maya', 'review-crew-maya', 'NUVO-MAYA-001', 'nuvo-maya-001', CURRENT_TIMESTAMP),
  ('review-pass-jules', 'review-crew-jules', 'NUVO-JULES-001', 'nuvo-jules-001', CURRENT_TIMESTAMP);

INSERT INTO people (
  id, person_key, user_id, display_name, username, avatar_url, avatar_r2_key,
  bio, is_demo, status, created_at, updated_at
)
VALUES
  ('review-person-google', 'review-person-google', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'Nuvo Review', 'nuvoreview-person', NULL, NULL, 'Reviewer account for app-store access.', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('review-person-riley', 'review-person-riley', 'review-crew-riley', 'Riley Pace', 'rileypace-person', NULL, NULL, 'Crew racer for review data.', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('review-person-maya', 'review-person-maya', 'review-crew-maya', 'Maya Sprint', 'mayasprint-person', NULL, NULL, 'Crew racer for review data.', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('review-person-jules', 'review-person-jules', 'review-crew-jules', 'Jules Form', 'julesform-person', NULL, NULL, 'Crew racer for review data.', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO auth_identities (
  id, user_id, provider, provider_user_id, email, email_verified,
  display_name, avatar_url, created_at
)
VALUES (
  'review-auth-google',
  (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
  'reviewer',
  'testing@getnuvo.net',
  'testing@getnuvo.net',
  1,
  'Nuvo Review',
  NULL,
  CURRENT_TIMESTAMP
);

INSERT INTO crew_connections (id, user_id, crew_user_id, status, created_at)
VALUES
  ('review-crew-link-001', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'review-crew-riley', 'active', CURRENT_TIMESTAMP),
  ('review-crew-link-002', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'review-crew-maya', 'active', CURRENT_TIMESTAMP),
  ('review-crew-link-003', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'review-crew-jules', 'active', CURRENT_TIMESTAMP),
  ('review-crew-link-004', 'review-crew-riley', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'active', CURRENT_TIMESTAMP),
  ('review-crew-link-005', 'review-crew-maya', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'active', CURRENT_TIMESTAMP),
  ('review-crew-link-006', 'review-crew-jules', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'active', CURRENT_TIMESTAMP);

INSERT INTO races (
  id, creator_id, title, description, race_type, movement_type, verification_type,
  target_value, target_unit, activity_id, metric, format, scoring_rule,
  attempt_duration_seconds, attempt_limit, verification_method, timezone,
  recurrence, status, visibility, public_join_enabled, start_at, end_at,
  winner_user_id, completed_at, created_at, updated_at, deleted_at
)
VALUES
  (
    'review-race-pushups',
    (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
    'First to 100 Push-Ups',
    'Camera verified race for app review.',
    'first_to_target', 'push_ups', 'movecheck',
    100, 'reps', 'push_ups', 'reps', 'first_to_goal', 'cumulative_sum',
    NULL, NULL, 'camera_pose', 'America/New_York',
    'none', 'active', 'invite_code', 1,
    datetime('now', '-2 days'), datetime('now', '+12 days'),
    NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL
  ),
  (
    'review-race-squats',
    'review-crew-riley',
    'First to 60 Squats',
    'Crew race with verified progress.',
    'first_to_target', 'squats', 'movecheck',
    60, 'reps', 'squats', 'reps', 'first_to_goal', 'cumulative_sum',
    NULL, NULL, 'camera_pose', 'America/New_York',
    'none', 'active', 'crew_only', 1,
    datetime('now', '-1 day'), datetime('now', '+10 days'),
    NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL
  ),
  (
    'review-race-plank',
    'review-crew-maya',
    'First to 5:00 Plank',
    'Completed camera verified race.',
    'first_to_target', 'plank_hold', 'movecheck',
    300, 'seconds', 'plank_hold', 'seconds', 'first_to_goal', 'cumulative_sum',
    NULL, NULL, 'camera_pose', 'America/New_York',
    'none', 'completed', 'crew_only', 1,
    datetime('now', '-8 days'), datetime('now', '-1 day'),
    (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
    datetime('now', '-1 day'), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL
  ),
  (
    'review-race-lunges',
    (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'),
    'First to 40 Lunges',
    'Solo start line ready for crew.',
    'first_to_target', 'lunges', 'movecheck',
    40, 'reps', 'lunges', 'reps', 'first_to_goal', 'cumulative_sum',
    NULL, NULL, 'camera_pose', 'America/New_York',
    'none', 'active', 'private', 0,
    datetime('now'), datetime('now', '+7 days'),
    NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL
  );

INSERT INTO race_members (
  id, race_id, person_id, user_id, member_role, member_status, role, status,
  joined_at, cached_display_name, cached_avatar_url
)
VALUES
  ('review-rm-001', 'review-race-pushups', 'review-person-google', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'owner', 'active', 'creator', 'active', datetime('now', '-2 days'), 'Nuvo Review', NULL),
  ('review-rm-002', 'review-race-pushups', 'review-person-riley', 'review-crew-riley', 'member', 'active', 'racer', 'active', datetime('now', '-2 days'), 'Riley Pace', NULL),
  ('review-rm-003', 'review-race-pushups', 'review-person-maya', 'review-crew-maya', 'member', 'active', 'racer', 'active', datetime('now', '-2 days'), 'Maya Sprint', NULL),
  ('review-rm-004', 'review-race-squats', 'review-person-riley', 'review-crew-riley', 'owner', 'active', 'creator', 'active', datetime('now', '-1 day'), 'Riley Pace', NULL),
  ('review-rm-005', 'review-race-squats', 'review-person-google', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'member', 'active', 'racer', 'active', datetime('now', '-1 day'), 'Nuvo Review', NULL),
  ('review-rm-006', 'review-race-squats', 'review-person-jules', 'review-crew-jules', 'member', 'active', 'racer', 'active', datetime('now', '-1 day'), 'Jules Form', NULL),
  ('review-rm-007', 'review-race-plank', 'review-person-maya', 'review-crew-maya', 'owner', 'active', 'creator', 'active', datetime('now', '-8 days'), 'Maya Sprint', NULL),
  ('review-rm-008', 'review-race-plank', 'review-person-google', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'member', 'active', 'racer', 'active', datetime('now', '-8 days'), 'Nuvo Review', NULL),
  ('review-rm-009', 'review-race-plank', 'review-person-riley', 'review-crew-riley', 'member', 'active', 'racer', 'active', datetime('now', '-8 days'), 'Riley Pace', NULL),
  ('review-rm-010', 'review-race-lunges', 'review-person-google', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'owner', 'active', 'creator', 'active', datetime('now'), 'Nuvo Review', NULL);

INSERT INTO race_progress (
  id, race_id, user_id, progress_value, progress_percent, completed_at,
  rank_cache, updated_at
)
VALUES
  ('review-rp-001', 'review-race-pushups', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 68, 68, NULL, 2, CURRENT_TIMESTAMP),
  ('review-rp-002', 'review-race-pushups', 'review-crew-riley', 76, 76, NULL, 1, CURRENT_TIMESTAMP),
  ('review-rp-003', 'review-race-pushups', 'review-crew-maya', 41, 41, NULL, 3, CURRENT_TIMESTAMP),
  ('review-rp-004', 'review-race-squats', 'review-crew-riley', 36, 60, NULL, 1, CURRENT_TIMESTAMP),
  ('review-rp-005', 'review-race-squats', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 28, 46, NULL, 2, CURRENT_TIMESTAMP),
  ('review-rp-006', 'review-race-squats', 'review-crew-jules', 18, 30, NULL, 3, CURRENT_TIMESTAMP),
  ('review-rp-007', 'review-race-plank', 'review-crew-maya', 245, 81, NULL, 2, CURRENT_TIMESTAMP),
  ('review-rp-008', 'review-race-plank', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 300, 100, datetime('now', '-1 day'), 1, CURRENT_TIMESTAMP),
  ('review-rp-009', 'review-race-plank', 'review-crew-riley', 190, 63, NULL, 3, CURRENT_TIMESTAMP),
  ('review-rp-010', 'review-race-lunges', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 0, 0, NULL, 1, CURRENT_TIMESTAMP);

INSERT INTO move_logs (
  id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
  status, summary, media_object_key, validator_version, duration_ms,
  metadata_json, client_submission_id, previous_score, new_score,
  previous_rank, new_rank, race_completed, created_at
)
VALUES
  ('review-move-001', 'review-race-pushups', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'movecheck', 'push_ups', 'push_ups', 'reps', 22, 'reps',
   'verified', '22 push-ups verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 24000,
   '{"reviewSeed":true}', 'review-submission-001', 46, 68, 2, 2, 0, datetime('now', '-4 hours')),
  ('review-move-002', 'review-race-pushups', 'review-crew-riley', 'movecheck', 'push_ups', 'push_ups', 'reps', 18, 'reps',
   'verified', '18 push-ups verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 21000,
   '{"reviewSeed":true}', 'review-submission-002', 58, 76, 1, 1, 0, datetime('now', '-2 hours')),
  ('review-move-003', 'review-race-squats', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'movecheck', 'squats', 'squats', 'reps', 28, 'reps',
   'verified', '28 squats verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 28000,
   '{"reviewSeed":true}', 'review-submission-003', 0, 28, NULL, 2, 0, datetime('now', '-1 day')),
  ('review-move-004', 'review-race-plank', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'movecheck', 'plank_hold', 'plank_hold', 'seconds', 60, 'seconds',
   'verified', '60 plank seconds verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 60000,
   '{"reviewSeed":true}', 'review-submission-004', 240, 300, 2, 1, 1, datetime('now', '-1 day'));

INSERT INTO race_final_standings (
  id, race_id, user_id, rank_position, score_value, completed_at, created_at
)
VALUES
  ('review-rfs-001', 'review-race-plank', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 1, 300, datetime('now', '-1 day'), CURRENT_TIMESTAMP),
  ('review-rfs-002', 'review-race-plank', 'review-crew-maya', 2, 245, NULL, CURRENT_TIMESTAMP),
  ('review-rfs-003', 'review-race-plank', 'review-crew-riley', 3, 190, NULL, CURRENT_TIMESTAMP);

INSERT INTO race_invites (
  id, race_id, created_by, invite_code, status, expires_at, created_at
)
VALUES
  ('review-invite-001', 'review-race-pushups', (SELECT id FROM users WHERE primary_email = 'testing@getnuvo.net'), 'NUV-GOOGLE', 'active', datetime('now', '+30 days'), CURRENT_TIMESTAMP),
  ('review-invite-002', 'review-race-squats', 'review-crew-riley', 'NUV-REVIEW', 'active', datetime('now', '+30 days'), CURRENT_TIMESTAMP);
