-- ─────────────────────────────────────────────────────────────────────────────
-- Nuvo · Clickable Demo World Seed
-- Target: sideswifter2010@gmail.com (f64f7f0b-fc9f-44fc-aede-ba46355e75e4)
-- Idempotent: INSERT OR IGNORE throughout.
-- ─────────────────────────────────────────────────────────────────────────────
-- Run:
--   npx wrangler d1 execute nuvo_db --remote \
--     --file server/worker/scripts/seed-clickable-demo-world.sql
-- ─────────────────────────────────────────────────────────────────────────────

-- STEP 1: Soft-delete old zero-proof test races for target user only
UPDATE races
SET deleted_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE creator_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4'
  AND deleted_at IS NULL
  AND id NOT IN (
    'd0000001-de00-4000-8000-000000000001',
    'd0000001-de00-4000-8000-000000000002',
    'd0000001-de00-4000-8000-000000000003',
    'd0000001-de00-4000-8000-000000000004',
    'd0000001-de00-4000-8000-000000000005',
    'd0000001-de00-4000-8000-000000000006',
    'd0000001-de00-4000-8000-000000000007'
  )
  AND (SELECT COUNT(*) FROM proofs WHERE race_id = races.id) = 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2: Demo persona users
-- ─────────────────────────────────────────────────────────────────────────────

INSERT OR IGNORE INTO users
  (id, primary_email, status, demo_world_enabled, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000001', 'demo+marcus@nuvo.internal',  'active', 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO users
  (id, primary_email, status, demo_world_enabled, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000002', 'demo+jamie@nuvo.internal',   'active', 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO users
  (id, primary_email, status, demo_world_enabled, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000003', 'demo+leo@nuvo.internal',     'active', 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO users
  (id, primary_email, status, demo_world_enabled, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000004', 'demo+anaya@nuvo.internal',   'active', 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 3: Demo persona profiles
-- ─────────────────────────────────────────────────────────────────────────────

INSERT OR IGNORE INTO profiles
  (user_id, full_name, username, onboarding_complete, private_profile, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000001', 'Marcus Kim',   '_demo_marcus', 1, 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO profiles
  (user_id, full_name, username, onboarding_complete, private_profile, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000002', 'Jamie Torres', '_demo_jamie',  1, 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO profiles
  (user_id, full_name, username, onboarding_complete, private_profile, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000003', 'Leo Park',     '_demo_leo',    1, 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

INSERT OR IGNORE INTO profiles
  (user_id, full_name, username, onboarding_complete, private_profile, created_at, updated_at)
VALUES
  ('d0000000-de00-4000-8000-000000000004', 'Anaya Davis',  '_demo_anaya',  1, 0, '2026-06-01 00:00:00', '2026-06-01 00:00:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Races  (3 live  +  2 active  +  2 archived)
-- created_at DESC order: newest race becomes focus board
-- ─────────────────────────────────────────────────────────────────────────────

-- Live race 1: Summer Fit Race  ← will become focus board (most recent)
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000001',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   'Summer Fit Race', '', 'general', 'manual', 50, 'reps',
   'reps', 'manual', 'manual', 'auto_accept', 'invite_code',
   'active', '2026-06-20 08:00:00', '2026-06-20 08:00:00');

-- Live race 2: First to 100 Pushups
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000002',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   'First to 100 Pushups', '', 'general', 'manual', 100, 'pushups',
   'pushups', 'manual', 'manual', 'auto_accept', 'invite_code',
   'active', '2026-06-20 07:00:00', '2026-06-20 07:00:00');

-- Live race 3: Study Sprint
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000003',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   'Study Sprint', '', 'general', 'manual', 20, 'sessions',
   'sessions', 'manual', 'manual', 'auto_accept', 'invite_code',
   'active', '2026-06-20 06:00:00', '2026-06-20 06:00:00');

-- Active race 4: Ship a Side Project
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000004',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   'Ship a Side Project', '', 'general', 'manual', 5, 'milestones',
   'milestones', 'manual', 'manual', 'auto_accept', 'invite_code',
   'active', '2026-06-20 05:00:00', '2026-06-20 05:00:00');

-- Active race 5: 30 Days No Scrolling
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000005',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   '30 Days No Scrolling', '', 'general', 'manual', 30, 'days',
   'days', 'manual', 'manual', 'auto_accept', 'invite_code',
   'active', '2026-06-20 04:00:00', '2026-06-20 04:00:00');

-- Archived race 1: 10 Squats
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000006',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   '10 Squats', '', 'general', 'manual', 10, 'squats',
   'squats', 'manual', 'manual', 'auto_accept', 'invite_code',
   'archived', '2026-06-12 10:00:00', '2026-06-12 10:00:00');

-- Archived race 2: Touch Grass 20
INSERT OR IGNORE INTO races
  (id, creator_id, title, description, category, goal_type, target_value, unit,
   target_unit, proof_mode, proof_requirement, proof_review_mode, visibility,
   status, created_at, updated_at)
VALUES
  ('d0000001-de00-4000-8000-000000000007',
   'f64f7f0b-fc9f-44fc-aede-ba46355e75e4',
   'Touch Grass 20', '', 'general', 'manual', 20, 'sessions',
   'sessions', 'manual', 'manual', 'auto_accept', 'invite_code',
   'archived', '2026-06-08 08:00:00', '2026-06-08 08:00:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Race participants
-- ─────────────────────────────────────────────────────────────────────────────

-- Race 1: Summer Fit Race  (target=50)  — target user last, Leo leading
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000001','d0000001-de00-4000-8000-000000000001','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai', 8,  16,'2026-06-20 08:10:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000002','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000003','Leo Park',     38,  76,'2026-06-20 08:10:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000003','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000001','Marcus Kim',   22,  44,'2026-06-20 08:10:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000004','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000002','Jamie Torres',  5,  10,'2026-06-20 08:10:00');

-- Race 2: First to 100 Pushups  (target=100)  — target close to Marcus
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000005','d0000001-de00-4000-8000-000000000002','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai',65,  65,'2026-06-20 07:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000006','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000001','Marcus Kim',   71,  71,'2026-06-20 07:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000007','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000004','Anaya Davis',  42,  42,'2026-06-20 07:05:00');

-- Race 3: Study Sprint  (target=20)  — target leading
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000008','d0000001-de00-4000-8000-000000000003','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai',14,  70,'2026-06-20 06:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000009','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000002','Jamie Torres', 10,  50,'2026-06-20 06:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000010','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000003','Leo Park',      7,  35,'2026-06-20 06:05:00');

-- Race 4: Ship a Side Project  (target=5)  — Anaya leading, target behind
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000011','d0000001-de00-4000-8000-000000000004','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai', 1,  20,'2026-06-20 05:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000012','d0000001-de00-4000-8000-000000000004','d0000000-de00-4000-8000-000000000004','Anaya Davis',   3,  60,'2026-06-20 05:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000013','d0000001-de00-4000-8000-000000000004','d0000000-de00-4000-8000-000000000001','Marcus Kim',    2,  40,'2026-06-20 05:05:00');

-- Race 5: 30 Days No Scrolling  (target=30)  — target has no proof yet
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000014','d0000001-de00-4000-8000-000000000005','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai', 0,   0,'2026-06-20 04:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000015','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000003','Leo Park',     12,  40,'2026-06-20 04:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000016','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000002','Jamie Torres',  8,  27,'2026-06-20 04:05:00');

-- Race 6: 10 Squats (archived, target=10)
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000017','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000001','Marcus Kim',  10, 100,'2026-06-12 10:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000018','d0000001-de00-4000-8000-000000000006','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai', 8,  80,'2026-06-12 10:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000019','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000004','Anaya Davis',  10, 100,'2026-06-12 10:05:00');

-- Race 7: Touch Grass 20 (archived, target=20)  — target won
INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000020','d0000001-de00-4000-8000-000000000007','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','Akshay Sanjai',20, 100,'2026-06-08 08:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000021','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000002','Jamie Torres', 15,  75,'2026-06-08 08:05:00');

INSERT OR IGNORE INTO race_participants
  (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
VALUES ('d0000002-de00-4000-8000-000000000022','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000003','Leo Park',     12,  60,'2026-06-08 08:05:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 6: Proofs
-- All manual / accepted. Only the value column drives participant progress.
-- ─────────────────────────────────────────────────────────────────────────────

-- Race 1: Summer Fit Race  (Leo=38, Marcus=22, Akshay=8, Jamie=5)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000001','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000003','manual',15,'accepted','2026-06-14 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000002','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000001','manual',12,'accepted','2026-06-14 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000003','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000003','manual',12,'accepted','2026-06-16 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000004','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000002','manual', 5,'accepted','2026-06-16 11:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000005','d0000001-de00-4000-8000-000000000001','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 8,'accepted','2026-06-17 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000006','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000001','manual',10,'accepted','2026-06-17 15:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000007','d0000001-de00-4000-8000-000000000001','d0000000-de00-4000-8000-000000000003','manual',11,'accepted','2026-06-19 08:00:00');

-- Race 2: First to 100 Pushups  (Marcus=71, Akshay=65, Anaya=42)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000008','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000001','manual',30,'accepted','2026-06-13 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000009','d0000001-de00-4000-8000-000000000002','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual',30,'accepted','2026-06-13 12:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000010','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000004','manual',20,'accepted','2026-06-14 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000011','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000001','manual',25,'accepted','2026-06-15 11:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000012','d0000001-de00-4000-8000-000000000002','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual',25,'accepted','2026-06-15 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000013','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000004','manual',15,'accepted','2026-06-16 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000014','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000001','manual',16,'accepted','2026-06-18 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000015','d0000001-de00-4000-8000-000000000002','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual',10,'accepted','2026-06-18 12:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000016','d0000001-de00-4000-8000-000000000002','d0000000-de00-4000-8000-000000000004','manual', 7,'accepted','2026-06-19 10:00:00');

-- Race 3: Study Sprint  (Akshay=14, Jamie=10, Leo=7)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000017','d0000001-de00-4000-8000-000000000003','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 5,'accepted','2026-06-13 08:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000018','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000002','manual', 5,'accepted','2026-06-14 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000019','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000003','manual', 4,'accepted','2026-06-14 16:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000020','d0000001-de00-4000-8000-000000000003','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 5,'accepted','2026-06-15 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000021','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000002','manual', 5,'accepted','2026-06-17 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000022','d0000001-de00-4000-8000-000000000003','d0000000-de00-4000-8000-000000000003','manual', 3,'accepted','2026-06-17 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000023','d0000001-de00-4000-8000-000000000003','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 4,'accepted','2026-06-19 11:00:00');

-- Race 4: Ship a Side Project  (Anaya=3, Marcus=2, Akshay=1)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000024','d0000001-de00-4000-8000-000000000004','d0000000-de00-4000-8000-000000000004','manual', 2,'accepted','2026-06-15 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000025','d0000001-de00-4000-8000-000000000004','d0000000-de00-4000-8000-000000000001','manual', 2,'accepted','2026-06-16 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000026','d0000001-de00-4000-8000-000000000004','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 1,'accepted','2026-06-17 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000027','d0000001-de00-4000-8000-000000000004','d0000000-de00-4000-8000-000000000004','manual', 1,'accepted','2026-06-18 11:00:00');

-- Race 5: 30 Days No Scrolling  (Leo=12, Jamie=8, Akshay=0 / no proofs)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000028','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000003','manual', 7,'accepted','2026-06-14 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000029','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000002','manual', 5,'accepted','2026-06-15 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000030','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000003','manual', 5,'accepted','2026-06-17 08:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000031','d0000001-de00-4000-8000-000000000005','d0000000-de00-4000-8000-000000000002','manual', 3,'accepted','2026-06-18 09:00:00');

-- Race 6: 10 Squats (archived)  (Marcus=10, Anaya=10, Akshay=8)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000032','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000001','manual', 6,'accepted','2026-06-10 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000033','d0000001-de00-4000-8000-000000000006','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 5,'accepted','2026-06-10 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000034','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000004','manual', 6,'accepted','2026-06-10 11:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000035','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000001','manual', 4,'accepted','2026-06-11 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000036','d0000001-de00-4000-8000-000000000006','d0000000-de00-4000-8000-000000000004','manual', 4,'accepted','2026-06-11 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000037','d0000001-de00-4000-8000-000000000006','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 3,'accepted','2026-06-11 14:00:00');

-- Race 7: Touch Grass 20 (archived)  (Akshay=20 won, Jamie=15, Leo=12)
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000038','d0000001-de00-4000-8000-000000000007','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 8,'accepted','2026-06-08 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000039','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000002','manual', 8,'accepted','2026-06-09 10:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000040','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000003','manual', 7,'accepted','2026-06-10 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000041','d0000001-de00-4000-8000-000000000007','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 7,'accepted','2026-06-10 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000042','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000002','manual', 7,'accepted','2026-06-11 09:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000043','d0000001-de00-4000-8000-000000000007','d0000000-de00-4000-8000-000000000003','manual', 5,'accepted','2026-06-11 14:00:00');
INSERT OR IGNORE INTO proofs (id,race_id,user_id,proof_type,value,verification_status,created_at) VALUES ('d0000004-de00-4000-8000-000000000044','d0000001-de00-4000-8000-000000000007','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','manual', 5,'accepted','2026-06-12 09:00:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 7: Race invites (one per live race)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT OR IGNORE INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
VALUES ('d0000003-de00-4000-8000-000000000001','d0000001-de00-4000-8000-000000000001','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','NUV-DEMO01','active','2026-06-20 08:10:00');

INSERT OR IGNORE INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
VALUES ('d0000003-de00-4000-8000-000000000002','d0000001-de00-4000-8000-000000000002','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','NUV-DEMO02','active','2026-06-20 07:10:00');

INSERT OR IGNORE INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
VALUES ('d0000003-de00-4000-8000-000000000003','d0000001-de00-4000-8000-000000000003','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','NUV-DEMO03','active','2026-06-20 06:10:00');

INSERT OR IGNORE INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
VALUES ('d0000003-de00-4000-8000-000000000004','d0000001-de00-4000-8000-000000000004','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','NUV-DEMO04','active','2026-06-20 05:10:00');

INSERT OR IGNORE INTO race_invites (id, race_id, created_by, invite_code, status, created_at)
VALUES ('d0000003-de00-4000-8000-000000000005','d0000001-de00-4000-8000-000000000005','f64f7f0b-fc9f-44fc-aede-ba46355e75e4','NUV-DEMO05','active','2026-06-20 04:10:00');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 8: Switch target user to real data path
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE users
SET demo_world_enabled = 0,
    updated_at = CURRENT_TIMESTAMP
WHERE id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4';
