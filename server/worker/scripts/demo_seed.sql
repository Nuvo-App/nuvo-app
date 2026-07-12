-- Nuvo Race System V2 Phase 1 demo seed.
--
-- Local run:
--   wrangler d1 execute nuvo_db --local --file=./scripts/demo_seed.sql
--
-- This seed only creates first-to-goal camera-verifiable races. It avoids
-- legacy manual units such as "pushups" as a score unit and keeps old scores
-- as immutable move logs plus race_progress cache rows.

INSERT OR IGNORE INTO users (id, primary_email, status, created_at, updated_at, last_login_at, demo_world_enabled)
VALUES
  ('demo-user-001', 'demo1@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('demo-user-002', 'demo2@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('demo-user-003', 'demo3@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0);

INSERT OR IGNORE INTO profiles (
  user_id, full_name, username, avatar_url, avatar_object_key,
  private_profile, onboarding_complete, is_demo, created_at, updated_at
)
VALUES
  ('demo-user-001', 'Alex Demo', 'alexdemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('demo-user-002', 'Jordan Demo', 'jordandemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('demo-user-003', 'Taylor Demo', 'taylordemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO member_passes (id, user_id, member_id, pass_slug, created_at)
VALUES
  ('pass-001', 'demo-user-001', 'DEMO-ALEX-001', 'demo-alex-001', CURRENT_TIMESTAMP),
  ('pass-002', 'demo-user-002', 'DEMO-JORDAN-001', 'demo-jordan-001', CURRENT_TIMESTAMP),
  ('pass-003', 'demo-user-003', 'DEMO-TAYLOR-001', 'demo-taylor-001', CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO races (
  id, creator_id, title, description, race_type, movement_type, verification_type,
  target_value, target_unit, activity_id, metric, format, scoring_rule,
  verification_method, timezone, recurrence, status, visibility, start_at, end_at,
  winner_user_id, completed_at, created_at, updated_at
)
VALUES
  (
    'demo-race-v2-001', 'demo-user-001', 'First to 100 Pushups',
    'Camera verified first-to-goal race.', 'first_to_target', 'push_ups', 'movecheck',
    100, 'reps', 'push_ups', 'reps', 'first_to_goal', 'cumulative_sum',
    'camera_pose', 'America/New_York', 'none', 'active', 'invite_code', CURRENT_TIMESTAMP, NULL,
    NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  ),
  (
    'demo-race-v2-002', 'demo-user-002', 'First to 15 Squats',
    'Camera verified first-to-goal race.', 'first_to_target', 'squats', 'movecheck',
    15, 'reps', 'squats', 'reps', 'first_to_goal', 'cumulative_sum',
    'camera_pose', 'America/New_York', 'none', 'active', 'invite_code', CURRENT_TIMESTAMP, NULL,
    NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  ),
  (
    'demo-race-v2-003', 'demo-user-003', 'First to 300 Plank Seconds',
    'Camera verified first-to-goal race.', 'first_to_target', 'plank_hold', 'movecheck',
    300, 'seconds', 'plank_hold', 'seconds', 'first_to_goal', 'cumulative_sum',
    'camera_pose', 'America/New_York', 'none', 'completed', 'invite_code', CURRENT_TIMESTAMP, NULL,
    'demo-user-003', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  );

INSERT OR IGNORE INTO race_members (
  id, race_id, user_id, role, status, joined_at, cached_display_name, cached_avatar_url
)
VALUES
  ('rm-v2-001', 'demo-race-v2-001', 'demo-user-001', 'creator', 'active', CURRENT_TIMESTAMP, 'Alex Demo', NULL),
  ('rm-v2-002', 'demo-race-v2-001', 'demo-user-002', 'racer', 'active', CURRENT_TIMESTAMP, 'Jordan Demo', NULL),
  ('rm-v2-003', 'demo-race-v2-001', 'demo-user-003', 'racer', 'active', CURRENT_TIMESTAMP, 'Taylor Demo', NULL),
  ('rm-v2-004', 'demo-race-v2-002', 'demo-user-002', 'creator', 'active', CURRENT_TIMESTAMP, 'Jordan Demo', NULL),
  ('rm-v2-005', 'demo-race-v2-002', 'demo-user-001', 'racer', 'active', CURRENT_TIMESTAMP, 'Alex Demo', NULL),
  ('rm-v2-006', 'demo-race-v2-002', 'demo-user-003', 'racer', 'active', CURRENT_TIMESTAMP, 'Taylor Demo', NULL),
  ('rm-v2-007', 'demo-race-v2-003', 'demo-user-003', 'creator', 'active', CURRENT_TIMESTAMP, 'Taylor Demo', NULL),
  ('rm-v2-008', 'demo-race-v2-003', 'demo-user-001', 'racer', 'active', CURRENT_TIMESTAMP, 'Alex Demo', NULL),
  ('rm-v2-009', 'demo-race-v2-003', 'demo-user-002', 'racer', 'active', CURRENT_TIMESTAMP, 'Jordan Demo', NULL);

INSERT OR IGNORE INTO race_progress (
  id, race_id, user_id, progress_value, progress_percent, completed_at, rank_cache, updated_at
)
VALUES
  ('rp-v2-001', 'demo-race-v2-001', 'demo-user-001', 65, 65, NULL, 2, CURRENT_TIMESTAMP),
  ('rp-v2-002', 'demo-race-v2-001', 'demo-user-002', 70, 70, NULL, 1, CURRENT_TIMESTAMP),
  ('rp-v2-003', 'demo-race-v2-001', 'demo-user-003', 30, 30, NULL, 3, CURRENT_TIMESTAMP),
  ('rp-v2-004', 'demo-race-v2-002', 'demo-user-002', 9, 60, NULL, 1, CURRENT_TIMESTAMP),
  ('rp-v2-005', 'demo-race-v2-002', 'demo-user-001', 6, 40, NULL, 2, CURRENT_TIMESTAMP),
  ('rp-v2-006', 'demo-race-v2-002', 'demo-user-003', 6, 40, NULL, 2, CURRENT_TIMESTAMP),
  ('rp-v2-007', 'demo-race-v2-003', 'demo-user-003', 315, 100, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP),
  ('rp-v2-008', 'demo-race-v2-003', 'demo-user-001', 180, 60, NULL, 2, CURRENT_TIMESTAMP),
  ('rp-v2-009', 'demo-race-v2-003', 'demo-user-002', 120, 40, NULL, 3, CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO move_logs (
  id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
  status, summary, validator_version, client_submission_id,
  previous_score, new_score, previous_rank, new_rank, race_completed, created_at
)
VALUES
  ('mv-v2-001', 'demo-race-v2-001', 'demo-user-001', 'movecheck', 'push_ups', 'push_ups', 'reps', 25, 'reps',
   'verified', '25 pushups verified by camera.', 'nuvo-ai-motion-v1', 'demo-submission-001',
   40, 65, 2, 2, 0, CURRENT_TIMESTAMP),
  ('mv-v2-002', 'demo-race-v2-001', 'demo-user-002', 'movecheck', 'push_ups', 'push_ups', 'reps', 30, 'reps',
   'verified', '30 pushups verified by camera.', 'nuvo-ai-motion-v1', 'demo-submission-002',
   40, 70, 1, 1, 0, CURRENT_TIMESTAMP),
  ('mv-v2-003', 'demo-race-v2-002', 'demo-user-001', 'movecheck', 'squats', 'squats', 'reps', 6, 'reps',
   'verified', '6 squats verified by camera.', 'nuvo-ai-motion-v1', 'demo-submission-003',
   0, 6, NULL, 2, 0, CURRENT_TIMESTAMP),
  ('mv-v2-004', 'demo-race-v2-003', 'demo-user-003', 'movecheck', 'plank_hold', 'plank_hold', 'seconds', 75, 'seconds',
   'verified', '75 plank seconds verified by camera.', 'nuvo-ai-motion-v1', 'demo-submission-004',
   240, 315, 1, 1, 1, CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO race_final_standings (
  id, race_id, user_id, rank_position, score_value, completed_at, created_at
)
VALUES
  ('rfs-v2-001', 'demo-race-v2-003', 'demo-user-003', 1, 315, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('rfs-v2-002', 'demo-race-v2-003', 'demo-user-001', 2, 180, NULL, CURRENT_TIMESTAMP),
  ('rfs-v2-003', 'demo-race-v2-003', 'demo-user-002', 3, 120, NULL, CURRENT_TIMESTAMP);
