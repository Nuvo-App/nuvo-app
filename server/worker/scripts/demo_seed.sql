-- Demo seed for Nuvo simplified backend.
-- Run this against your D1 database via the Cloudflare dashboard SQL editor or:
--   wrangler d1 execute nuvo_db --file=./scripts/demo_seed.sql
--
-- This script creates 3 demo users, their profiles, a member pass each,
-- two races (one MoveCheck push-ups race, one manual running race),
-- race membership, progress, and a few move logs.
--
-- Replace the UUIDs below if you want deterministic values, or leave them as-is
-- for a fresh demo environment.

-- ---------------------------------------------------------------------------
-- 1. Demo users
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO users (id, primary_email, status, created_at, updated_at, last_login_at, demo_world_enabled)
VALUES
  ('demo-user-001', 'demo1@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('demo-user-002', 'demo2@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('demo-user-003', 'demo3@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0);

-- ---------------------------------------------------------------------------
-- 2. Demo profiles
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO profiles (user_id, full_name, username, avatar_url, avatar_object_key, private_profile, onboarding_complete, is_demo, created_at, updated_at)
VALUES
  ('demo-user-001', 'Alex Demo', 'alexdemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('demo-user-002', 'Jordan Demo', 'jordandemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('demo-user-003', 'Taylor Demo', 'taylordemo', NULL, NULL, 0, 1, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 3. Demo member passes
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO member_passes (id, user_id, pass_code, created_at)
VALUES
  ('pass-001', 'demo-user-001', 'DEMO-ALEX-001', CURRENT_TIMESTAMP),
  ('pass-002', 'demo-user-002', 'DEMO-JORDAN-001', CURRENT_TIMESTAMP),
  ('pass-003', 'demo-user-003', 'DEMO-TAYLOR-001', CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 4. Demo crew connections
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO crew_connections (id, user_id, crew_user_id, status, created_at)
VALUES
  ('crew-001', 'demo-user-001', 'demo-user-002', 'active', CURRENT_TIMESTAMP),
  ('crew-002', 'demo-user-001', 'demo-user-003', 'active', CURRENT_TIMESTAMP),
  ('crew-003', 'demo-user-002', 'demo-user-003', 'active', CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 5. Demo races
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO races (
  id, creator_id, title, description, status,
  race_type, verification_type, movement_type,
  target_value, target_unit,
  start_line_at, finish_line_at,
  visibility, invite_code,
  rules, demo_context, created_at, updated_at
)
VALUES
  (
    'demo-race-001', 'demo-user-001', 'Push-Up Showdown', 'First to 100 push-ups wins. MoveCheck verified.',
    'active', 'first_to_target', 'movecheck', 'pushups',
    100, 'reps',
    CURRENT_TIMESTAMP, NULL,
    'crew_only', NULL,
    'Use MoveCheck camera proof. No manual entries.', '{"demo": true}',
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  ),
  (
    'demo-race-002', 'demo-user-002', 'Morning Mile Crew', 'Run the most miles this week. Manual proof.',
    'active', 'most_in_time', 'manual', NULL,
    10, 'miles',
    CURRENT_TIMESTAMP, datetime('now', '+7 days'),
    'crew_only', NULL,
    'Post a photo of your run stats.', '{"demo": true}',
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  );

-- ---------------------------------------------------------------------------
-- 6. Demo race members
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO race_members (id, race_id, user_id, status, role, cached_display_name, cached_avatar_url, joined_at)
VALUES
  ('rm-001', 'demo-race-001', 'demo-user-001', 'active', 'creator', 'Alex Demo', NULL, CURRENT_TIMESTAMP),
  ('rm-002', 'demo-race-001', 'demo-user-002', 'active', 'member', 'Jordan Demo', NULL, CURRENT_TIMESTAMP),
  ('rm-003', 'demo-race-001', 'demo-user-003', 'active', 'member', 'Taylor Demo', NULL, CURRENT_TIMESTAMP),
  ('rm-004', 'demo-race-002', 'demo-user-002', 'active', 'creator', 'Jordan Demo', NULL, CURRENT_TIMESTAMP),
  ('rm-005', 'demo-race-002', 'demo-user-001', 'active', 'member', 'Alex Demo', NULL, CURRENT_TIMESTAMP),
  ('rm-006', 'demo-race-002', 'demo-user-003', 'active', 'member', 'Taylor Demo', NULL, CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 7. Demo race progress
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO race_progress (id, race_id, user_id, progress_value, progress_percent, rank_position, completed_at, updated_at)
VALUES
  ('rp-001', 'demo-race-001', 'demo-user-001', 65, 65, 2, NULL, CURRENT_TIMESTAMP),
  ('rp-002', 'demo-race-001', 'demo-user-002', 100, 100, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('rp-003', 'demo-race-001', 'demo-user-003', 30, 30, 3, NULL, CURRENT_TIMESTAMP),
  ('rp-004', 'demo-race-002', 'demo-user-001', 4, 40, 3, NULL, CURRENT_TIMESTAMP),
  ('rp-005', 'demo-race-002', 'demo-user-002', 7, 70, 1, NULL, CURRENT_TIMESTAMP),
  ('rp-006', 'demo-race-002', 'demo-user-003', 5, 50, 2, NULL, CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 8. Demo move logs
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO move_logs (id, race_id, user_id, value, unit, source, status, summary, submitted_at, verified_at)
VALUES
  ('mv-001', 'demo-race-001', 'demo-user-001', 20, 'reps', 'movecheck', 'verified', '20 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-002', 'demo-race-001', 'demo-user-001', 25, 'reps', 'movecheck', 'verified', '25 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-003', 'demo-race-001', 'demo-user-001', 20, 'reps', 'movecheck', 'verified', '20 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-004', 'demo-race-001', 'demo-user-002', 50, 'reps', 'movecheck', 'verified', '50 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-005', 'demo-race-001', 'demo-user-002', 50, 'reps', 'movecheck', 'verified', '50 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-006', 'demo-race-001', 'demo-user-003', 15, 'reps', 'movecheck', 'verified', '15 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-007', 'demo-race-001', 'demo-user-003', 15, 'reps', 'movecheck', 'verified', '15 push-ups verified by MoveCheck.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),

  ('mv-008', 'demo-race-002', 'demo-user-001', 2, 'miles', 'manual', 'verified', 'Morning 2 mile run.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-009', 'demo-race-002', 'demo-user-001', 2, 'miles', 'manual', 'verified', 'Evening 2 mile run.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-010', 'demo-race-002', 'demo-user-002', 3, 'miles', 'manual', 'verified', '5K run.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-011', 'demo-race-002', 'demo-user-002', 4, 'miles', 'manual', 'verified', 'Long run.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('mv-012', 'demo-race-002', 'demo-user-003', 5, 'miles', 'manual', 'verified', 'Tempo 5 miles.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- ---------------------------------------------------------------------------
-- 9. Demo media object placeholders (optional)
-- ---------------------------------------------------------------------------
-- If you upload demo avatars to R2, uncomment and fill in the public_url.
-- INSERT OR IGNORE INTO media_objects (id, owner_user_id, bucket, object_key, public_url, media_type, purpose, status, created_at)
-- VALUES
--   ('media-001', 'demo-user-001', 'nuvor2', 'profile-avatars/demo-user-001/avatar.jpg', 'https://your-domain/profile/photo/object/...', 'image', 'profile_avatar', 'active', CURRENT_TIMESTAMP),
--   ('media-002', 'demo-user-002', 'nuvor2', 'profile-avatars/demo-user-002/avatar.jpg', 'https://your-domain/profile/photo/object/...', 'image', 'profile_avatar', 'active', CURRENT_TIMESTAMP),
--   ('media-003', 'demo-user-003', 'nuvor2', 'profile-avatars/demo-user-003/avatar.jpg', 'https://your-domain/profile/photo/object/...', 'image', 'profile_avatar', 'active', CURRENT_TIMESTAMP);
