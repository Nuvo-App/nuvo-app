-- Akshay live seed — production D1 dual-write schema
-- Akshay: f64f7f0b-fc9f-44fc-aede-ba46355e75e4

-- New demo people
INSERT OR IGNORE INTO users (id, primary_email, status, created_at, updated_at, last_login_at, demo_world_enabled) VALUES
  ('d0000000-de00-4000-8000-000000000005', 'demo+priya@nuvo.internal', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('d0000000-de00-4000-8000-000000000006', 'demo+jay@nuvo.internal', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('d0000000-de00-4000-8000-000000000007', 'demo+noah@nuvo.internal', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0),
  ('d0000000-de00-4000-8000-000000000008', 'demo+maya@nuvo.internal', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 0);

INSERT OR IGNORE INTO profiles (user_id, full_name, username, private_profile, onboarding_complete, created_at, updated_at) VALUES
  ('d0000000-de00-4000-8000-000000000005', 'Priya Nair', 'priya', 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000006', 'Jay Patel', 'jayp', 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000007', 'Noah Brooks', 'noahb', 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000008', 'Maya Chen', 'mayac', 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT OR IGNORE INTO people (id, person_key, user_id, display_name, username, is_demo, status, created_at, updated_at) VALUES
  ('d0000000-de00-4000-8000-000000000005', 'priya', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 'priya', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000006', 'jayp', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 'jayp', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000007', 'noahb', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 'noahb', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('d0000000-de00-4000-8000-000000000008', 'mayac', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 'mayac', 1, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Crew links for Akshay
INSERT OR IGNORE INTO crew_connections (id, user_id, crew_user_id, status, created_at, person_id, crew_person_id) VALUES
  ('crew-ak-001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf'),
  ('crew-ak-002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'a6703a63-0fee-424a-9d61-ab617aa45ffb'),
  ('crew-ak-003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f'),
  ('crew-ak-004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', '6dc3503d-c1f9-4fdb-989e-b3ae80accbe6', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', '6dc3503d-c1f9-4fdb-989e-b3ae80accbe6'),
  ('crew-ak-005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000001', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000001'),
  ('crew-ak-006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000002', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000002'),
  ('crew-ak-007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000003', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000003'),
  ('crew-ak-008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000004', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000004'),
  ('crew-ak-009', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000005', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000005'),
  ('crew-ak-010', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000006', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000006'),
  ('crew-ak-011', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000007', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000007'),
  ('crew-ak-012', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000008', 'active', CURRENT_TIMESTAMP, 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'd0000000-de00-4000-8000-000000000008');

-- 8 competitive races
INSERT OR IGNORE INTO races (
  id, creator_id, title, description, category, goal_type, target_value, unit, status,
  start_line_at, finish_line_at, created_at, updated_at, proof_requirement, proof_review_mode,
  visibility, ai_activity_type, target_unit, proof_mode, race_key, race_type, created_by_person_id, demo_priority
) VALUES
  ('a0000001-de00-4000-8000-000000000001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Crew Pushup Gauntlet', 'First to 100 pushups.', 'fitness', 'first_to_goal', 100, 'reps', 'active', datetime('now','-3 days'), datetime('now','+7 days'), datetime('now','-3 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'push_ups', 'reps', 'ai_check', 'seed_001', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Morning Jacks Sprint', 'First to 50 jumping jacks.', 'fitness', 'first_to_goal', 50, 'reps', 'active', datetime('now','-2 days'), datetime('now','+5 days'), datetime('now','-2 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'jumping_jacks', 'reps', 'ai_check', 'seed_002', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Plank Hold Wars', 'Stack 180 plank seconds.', 'fitness', 'first_to_goal', 180, 'seconds', 'active', datetime('now','-4 days'), datetime('now','+8 days'), datetime('now','-4 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'plank_hold', 'seconds', 'ai_check', 'seed_003', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Squat Sunday', 'First to 75 squats.', 'fitness', 'first_to_goal', 75, 'reps', 'active', datetime('now','-2 days'), datetime('now','+6 days'), datetime('now','-2 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'squats', 'reps', 'ai_check', 'seed_004', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Lunge Ladder', 'First to 60 lunges.', 'fitness', 'first_to_goal', 60, 'reps', 'active', datetime('now','-3 days'), datetime('now','+7 days'), datetime('now','-3 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'lunges', 'reps', 'ai_check', 'seed_005', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Study Sprint Week', 'Log 20 study sessions.', 'focus', 'manual', 20, 'sessions', 'active', datetime('now','-6 days'), datetime('now','+3 days'), datetime('now','-6 days'), CURRENT_TIMESTAMP, 'manual', 'auto_accept', 'invite_code', NULL, 'sessions', 'manual', 'seed_006', 'manual', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20),
  ('a0000001-de00-4000-8000-000000000007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Friday Finisher', 'Completed crew race.', 'fitness', 'first_to_goal', 30, 'reps', 'completed', datetime('now','-7 days'), datetime('now','-1 days'), datetime('now','-7 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'push_ups', 'reps', 'ai_check', 'seed_007', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 10),
  ('a0000001-de00-4000-8000-000000000008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Night Owl Jacks', 'First to 40 jumping jacks.', 'fitness', 'first_to_goal', 40, 'reps', 'active', datetime('now','-1 days'), datetime('now','+4 days'), datetime('now','-1 days'), CURRENT_TIMESTAMP, 'ai_check', 'auto_accept', 'invite_code', 'jumping_jacks', 'reps', 'ai_check', 'seed_008', 'ai_check', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 20);

-- Participants (legacy table the API reads)
INSERT OR IGNORE INTO race_participants (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at) VALUES
  -- Race 001 Pushups
  ('a0000002-de00-4000-8000-000000000001', 'a0000001-de00-4000-8000-000000000001', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'Shaurya', 78, 78, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000002', 'a0000001-de00-4000-8000-000000000001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 72, 72, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000003', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000003', 'London-Lee Easom-Oakley', 61, 61, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000004', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 54, 54, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000005', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 40, 40, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000006', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 33, 33, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000007', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 22, 22, datetime('now','-1 days')),
  -- Race 002 Jacks
  ('a0000002-de00-4000-8000-000000000008', 'a0000001-de00-4000-8000-000000000002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 41, 82, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000009', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000002', 'Ella Grace', 38, 76, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000010', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 30, 60, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000011', 'a0000001-de00-4000-8000-000000000002', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'Rithu Premraj', 24, 48, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000012', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000001', 'Marcus Kim', 18, 36, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000013', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 12, 24, datetime('now','-1 days')),
  -- Race 003 Plank
  ('a0000002-de00-4000-8000-000000000014', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 140, 78, datetime('now','-4 days')),
  ('a0000002-de00-4000-8000-000000000015', 'a0000001-de00-4000-8000-000000000003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 126, 70, datetime('now','-4 days')),
  ('a0000002-de00-4000-8000-000000000016', 'a0000001-de00-4000-8000-000000000003', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'Shresh', 110, 61, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000017', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 95, 53, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000018', 'a0000001-de00-4000-8000-000000000003', '6dc3503d-c1f9-4fdb-989e-b3ae80accbe6', 'Akaash Deepak', 80, 44, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000019', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 60, 33, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000020', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000003', 'London-Lee Easom-Oakley', 45, 25, datetime('now','-1 days')),
  -- Race 004 Squats
  ('a0000002-de00-4000-8000-000000000021', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000003', 'London-Lee Easom-Oakley', 58, 77, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000022', 'a0000001-de00-4000-8000-000000000004', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'Shaurya', 52, 69, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000023', 'a0000001-de00-4000-8000-000000000004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 49, 65, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000024', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 40, 53, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000025', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000002', 'Ella Grace', 28, 37, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000026', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000001', 'Marcus Kim', 15, 20, datetime('now','-1 days')),
  -- Race 005 Lunges
  ('a0000002-de00-4000-8000-000000000027', 'a0000001-de00-4000-8000-000000000005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 34, 57, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000028', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 31, 52, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000029', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000001', 'Marcus Kim', 27, 45, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000030', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 20, 33, datetime('now','-2 days')),
  ('a0000002-de00-4000-8000-000000000031', 'a0000001-de00-4000-8000-000000000005', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'Rithu Premraj', 14, 23, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000032', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 8, 13, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000033', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 5, 8, datetime('now','-1 days')),
  -- Race 006 Study
  ('a0000002-de00-4000-8000-000000000034', 'a0000001-de00-4000-8000-000000000006', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'Rithu Premraj', 16, 80, datetime('now','-6 days')),
  ('a0000002-de00-4000-8000-000000000035', 'a0000001-de00-4000-8000-000000000006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 14, 70, datetime('now','-6 days')),
  ('a0000002-de00-4000-8000-000000000036', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000002', 'Ella Grace', 12, 60, datetime('now','-5 days')),
  ('a0000002-de00-4000-8000-000000000037', 'a0000001-de00-4000-8000-000000000006', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'Shresh', 9, 45, datetime('now','-4 days')),
  ('a0000002-de00-4000-8000-000000000038', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000004', 'Akaash Deepak', 7, 35, datetime('now','-3 days')),
  ('a0000002-de00-4000-8000-000000000039', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 4, 20, datetime('now','-2 days')),
  -- Race 007 Completed
  ('a0000002-de00-4000-8000-000000000040', 'a0000001-de00-4000-8000-000000000007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 32, 100, datetime('now','-7 days')),
  ('a0000002-de00-4000-8000-000000000041', 'a0000001-de00-4000-8000-000000000007', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'Shaurya', 28, 93, datetime('now','-7 days')),
  ('a0000002-de00-4000-8000-000000000042', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000003', 'London-Lee Easom-Oakley', 24, 80, datetime('now','-6 days')),
  ('a0000002-de00-4000-8000-000000000043', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 18, 60, datetime('now','-6 days')),
  ('a0000002-de00-4000-8000-000000000044', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000001', 'Marcus Kim', 12, 40, datetime('now','-5 days')),
  -- Race 008 Night jacks
  ('a0000002-de00-4000-8000-000000000045', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 19, 48, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000046', 'a0000001-de00-4000-8000-000000000008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'Akshay Sanjai', 17, 43, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000047', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000002', 'Ella Grace', 14, 35, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000048', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 9, 23, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000049', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 6, 15, datetime('now','-1 days')),
  ('a0000002-de00-4000-8000-000000000050', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 3, 8, datetime('now','-1 days'));

-- race_members mirror
INSERT OR IGNORE INTO race_members (id, race_id, person_id, member_role, member_status, score_value, score_percent, is_current_user_highlight, joined_at, last_move_at, created_at, updated_at) VALUES
  ('a0000003-de00-4000-8000-000000000001', 'a0000001-de00-4000-8000-000000000001', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'member', 'active', 78, 78, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000002', 'a0000001-de00-4000-8000-000000000001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 72, 72, 1, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000003', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000003', 'member', 'active', 61, 61, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000004', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 54, 54, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000005', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 40, 40, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000006', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 33, 33, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000007', 'a0000001-de00-4000-8000-000000000001', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 22, 22, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000008', 'a0000001-de00-4000-8000-000000000002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 41, 82, 1, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000009', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000002', 'member', 'active', 38, 76, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000010', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 30, 60, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000011', 'a0000001-de00-4000-8000-000000000002', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'member', 'active', 24, 48, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000012', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000001', 'member', 'active', 18, 36, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000013', 'a0000001-de00-4000-8000-000000000002', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 12, 24, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000014', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 140, 78, 0, datetime('now','-4 days'), CURRENT_TIMESTAMP, datetime('now','-4 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000015', 'a0000001-de00-4000-8000-000000000003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 126, 70, 1, datetime('now','-4 days'), CURRENT_TIMESTAMP, datetime('now','-4 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000016', 'a0000001-de00-4000-8000-000000000003', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'member', 'active', 110, 61, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000017', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 95, 53, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000018', 'a0000001-de00-4000-8000-000000000003', '6dc3503d-c1f9-4fdb-989e-b3ae80accbe6', 'member', 'active', 80, 44, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000019', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 60, 33, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000020', 'a0000001-de00-4000-8000-000000000003', 'd0000000-de00-4000-8000-000000000003', 'member', 'active', 45, 25, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000021', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000003', 'member', 'active', 58, 77, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000022', 'a0000001-de00-4000-8000-000000000004', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'member', 'active', 52, 69, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000023', 'a0000001-de00-4000-8000-000000000004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 49, 65, 1, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000024', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 40, 53, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000025', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000002', 'member', 'active', 28, 37, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000026', 'a0000001-de00-4000-8000-000000000004', 'd0000000-de00-4000-8000-000000000001', 'member', 'active', 15, 20, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000027', 'a0000001-de00-4000-8000-000000000005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 34, 57, 1, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000028', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 31, 52, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000029', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000001', 'member', 'active', 27, 45, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000030', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 20, 33, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000031', 'a0000001-de00-4000-8000-000000000005', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'member', 'active', 14, 23, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000032', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 8, 13, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000033', 'a0000001-de00-4000-8000-000000000005', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 5, 8, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000034', 'a0000001-de00-4000-8000-000000000006', 'a6703a63-0fee-424a-9d61-ab617aa45ffb', 'member', 'active', 16, 80, 0, datetime('now','-6 days'), CURRENT_TIMESTAMP, datetime('now','-6 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000035', 'a0000001-de00-4000-8000-000000000006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 14, 70, 1, datetime('now','-6 days'), CURRENT_TIMESTAMP, datetime('now','-6 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000036', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000002', 'member', 'active', 12, 60, 0, datetime('now','-5 days'), CURRENT_TIMESTAMP, datetime('now','-5 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000037', 'a0000001-de00-4000-8000-000000000006', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'member', 'active', 9, 45, 0, datetime('now','-4 days'), CURRENT_TIMESTAMP, datetime('now','-4 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000038', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000004', 'member', 'active', 7, 35, 0, datetime('now','-3 days'), CURRENT_TIMESTAMP, datetime('now','-3 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000039', 'a0000001-de00-4000-8000-000000000006', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 4, 20, 0, datetime('now','-2 days'), CURRENT_TIMESTAMP, datetime('now','-2 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000040', 'a0000001-de00-4000-8000-000000000007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 32, 100, 1, datetime('now','-7 days'), CURRENT_TIMESTAMP, datetime('now','-7 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000041', 'a0000001-de00-4000-8000-000000000007', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'member', 'active', 28, 93, 0, datetime('now','-7 days'), CURRENT_TIMESTAMP, datetime('now','-7 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000042', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000003', 'member', 'active', 24, 80, 0, datetime('now','-6 days'), CURRENT_TIMESTAMP, datetime('now','-6 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000043', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 18, 60, 0, datetime('now','-6 days'), CURRENT_TIMESTAMP, datetime('now','-6 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000044', 'a0000001-de00-4000-8000-000000000007', 'd0000000-de00-4000-8000-000000000001', 'member', 'active', 12, 40, 0, datetime('now','-5 days'), CURRENT_TIMESTAMP, datetime('now','-5 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000045', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 19, 48, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000046', 'a0000001-de00-4000-8000-000000000008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'creator', 'active', 17, 43, 1, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000047', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000002', 'member', 'active', 14, 35, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000048', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 9, 23, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000049', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 6, 15, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('a0000003-de00-4000-8000-000000000050', 'a0000001-de00-4000-8000-000000000008', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 3, 8, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP);

-- Sample proofs so race detail isn't empty
INSERT OR IGNORE INTO proofs (id, race_id, user_id, proof_type, note, value, verification_status, verification_summary, created_at, ai_activity_type, detected_value, confidence, validator_version) VALUES
  ('a0000004-de00-4000-8000-000000000001', 'a0000001-de00-4000-8000-000000000001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 72 reps detected.', 72, 'ai_verified', 'Detected 72 pushups.', CURRENT_TIMESTAMP, 'push_ups', 72, 0.91, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000002', 'a0000001-de00-4000-8000-000000000001', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'ai_motion', 'AI motion proof: 78 reps detected.', 78, 'ai_verified', 'Detected 78 pushups.', CURRENT_TIMESTAMP, 'push_ups', 78, 0.9, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000003', 'a0000001-de00-4000-8000-000000000002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 41 reps detected.', 41, 'ai_verified', 'Detected 41 jumping jacks.', CURRENT_TIMESTAMP, 'jumping_jacks', 41, 0.92, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000004', 'a0000001-de00-4000-8000-000000000003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 126 seconds detected.', 126, 'ai_verified', 'Detected 126 plank seconds.', CURRENT_TIMESTAMP, 'plank_hold', 126, 0.89, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000005', 'a0000001-de00-4000-8000-000000000004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 49 reps detected.', 49, 'ai_verified', 'Detected 49 squats.', CURRENT_TIMESTAMP, 'squats', 49, 0.9, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000006', 'a0000001-de00-4000-8000-000000000005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 34 reps detected.', 34, 'ai_verified', 'Detected 34 lunges.', CURRENT_TIMESTAMP, 'lunges', 34, 0.88, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000007', 'a0000001-de00-4000-8000-000000000006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'manual', NULL, 14, 'accepted', NULL, CURRENT_TIMESTAMP, NULL, NULL, NULL, NULL),
  ('a0000004-de00-4000-8000-000000000008', 'a0000001-de00-4000-8000-000000000007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 32 reps detected.', 32, 'ai_verified', 'Detected 32 pushups.', CURRENT_TIMESTAMP, 'push_ups', 32, 0.93, 'nuvo-ai-motion-v2'),
  ('a0000004-de00-4000-8000-000000000009', 'a0000001-de00-4000-8000-000000000008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 'ai_motion', 'AI motion proof: 17 reps detected.', 17, 'ai_verified', 'Detected 17 jumping jacks.', CURRENT_TIMESTAMP, 'jumping_jacks', 17, 0.9, 'nuvo-ai-motion-v2');

INSERT OR IGNORE INTO moves (id, race_id, person_id, amount_value, amount_unit, move_status, move_source, note, checked_at, ai_summary, created_at, updated_at) VALUES
  ('a0000005-de00-4000-8000-000000000001', 'a0000001-de00-4000-8000-000000000001', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 72, 'reps', 'checked', 'ai', 'AI motion proof: 72 reps detected.', CURRENT_TIMESTAMP, 'Detected 72 pushups.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000002', 'a0000001-de00-4000-8000-000000000001', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 78, 'reps', 'checked', 'ai', 'AI motion proof: 78 reps detected.', CURRENT_TIMESTAMP, 'Detected 78 pushups.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000003', 'a0000001-de00-4000-8000-000000000002', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 41, 'reps', 'checked', 'ai', 'AI motion proof: 41 reps detected.', CURRENT_TIMESTAMP, 'Detected 41 jumping jacks.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000004', 'a0000001-de00-4000-8000-000000000003', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 126, 'seconds', 'checked', 'ai', 'AI motion proof: 126 seconds detected.', CURRENT_TIMESTAMP, 'Detected 126 plank seconds.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000005', 'a0000001-de00-4000-8000-000000000004', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 49, 'reps', 'checked', 'ai', 'AI motion proof: 49 reps detected.', CURRENT_TIMESTAMP, 'Detected 49 squats.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000006', 'a0000001-de00-4000-8000-000000000005', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 34, 'reps', 'checked', 'ai', 'AI motion proof: 34 reps detected.', CURRENT_TIMESTAMP, 'Detected 34 lunges.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000007', 'a0000001-de00-4000-8000-000000000006', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 14, 'sessions', 'checked', 'manual', NULL, CURRENT_TIMESTAMP, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000008', 'a0000001-de00-4000-8000-000000000007', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 32, 'reps', 'checked', 'ai', 'AI motion proof: 32 reps detected.', CURRENT_TIMESTAMP, 'Detected 32 pushups.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('a0000005-de00-4000-8000-000000000009', 'a0000001-de00-4000-8000-000000000008', 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4', 17, 'reps', 'checked', 'ai', 'AI motion proof: 17 reps detected.', CURRENT_TIMESTAMP, 'Detected 17 jumping jacks.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Fill a few existing solo races with competitors
INSERT OR IGNORE INTO race_participants (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at) VALUES
  ('b0000002-de00-4000-8000-000000000001', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'Shaurya', 4, 67, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000002', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 3, 50, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000003', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 2, 33, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000004', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'd0000000-de00-4000-8000-000000000003', 'London-Lee Easom-Oakley', 16, 80, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000005', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'd0000000-de00-4000-8000-000000000008', 'Maya Chen', 14, 70, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000006', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'Shresh', 10, 50, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000007', 'ce766334-a9cf-4669-906e-5354dcd2127f', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'Shaurya', 9, 90, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000008', 'ce766334-a9cf-4669-906e-5354dcd2127f', 'd0000000-de00-4000-8000-000000000006', 'Jay Patel', 7, 70, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000009', 'ce766334-a9cf-4669-906e-5354dcd2127f', 'd0000000-de00-4000-8000-000000000001', 'Marcus Kim', 5, 50, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000010', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000005', 'Priya Nair', 8, 80, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000011', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000002', 'Ella Grace', 6, 60, datetime('now','-1 days')),
  ('b0000002-de00-4000-8000-000000000012', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000007', 'Noah Brooks', 4, 40, datetime('now','-1 days'));

INSERT OR IGNORE INTO race_members (id, race_id, person_id, member_role, member_status, score_value, score_percent, is_current_user_highlight, joined_at, last_move_at, created_at, updated_at) VALUES
  ('b0000003-de00-4000-8000-000000000001', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'member', 'active', 4, 67, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000002', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 3, 50, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000003', '56e1d60d-9e76-4df1-b806-3adb564f4ff0', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 2, 33, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000004', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'd0000000-de00-4000-8000-000000000003', 'member', 'active', 16, 80, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000005', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'd0000000-de00-4000-8000-000000000008', 'member', 'active', 14, 70, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000006', '7caf9862-c73f-410d-a9c9-edb22bf351f4', 'af5f69e8-d2b6-4ad2-850c-edef793a3d4f', 'member', 'active', 10, 50, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000007', 'ce766334-a9cf-4669-906e-5354dcd2127f', '7112d8ff-14bc-4a5a-8c79-7ec5d63d28cf', 'member', 'active', 9, 90, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000008', 'ce766334-a9cf-4669-906e-5354dcd2127f', 'd0000000-de00-4000-8000-000000000006', 'member', 'active', 7, 70, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000009', 'ce766334-a9cf-4669-906e-5354dcd2127f', 'd0000000-de00-4000-8000-000000000001', 'member', 'active', 5, 50, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000010', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000005', 'member', 'active', 8, 80, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000011', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000002', 'member', 'active', 6, 60, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP),
  ('b0000003-de00-4000-8000-000000000012', '7df1438e-315e-4e26-8ba5-cea631c3aa98', 'd0000000-de00-4000-8000-000000000007', 'member', 'active', 4, 40, 0, datetime('now','-1 days'), CURRENT_TIMESTAMP, datetime('now','-1 days'), CURRENT_TIMESTAMP);

-- Give Akshay progress on zeroed solo races
UPDATE race_participants SET progress_value = 2, progress_percent = 33 WHERE race_id = '56e1d60d-9e76-4df1-b806-3adb564f4ff0' AND user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND progress_value = 0;
UPDATE race_members SET score_value = 2, score_percent = 33, last_move_at = CURRENT_TIMESTAMP WHERE race_id = '56e1d60d-9e76-4df1-b806-3adb564f4ff0' AND person_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND score_value = 0;
UPDATE race_participants SET progress_value = 3, progress_percent = 30 WHERE race_id = 'ce766334-a9cf-4669-906e-5354dcd2127f' AND user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND progress_value = 0;
UPDATE race_members SET score_value = 3, score_percent = 30, last_move_at = CURRENT_TIMESTAMP WHERE race_id = 'ce766334-a9cf-4669-906e-5354dcd2127f' AND person_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND score_value = 0;
UPDATE race_participants SET progress_value = 3, progress_percent = 30 WHERE race_id = '7df1438e-315e-4e26-8ba5-cea631c3aa98' AND user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND progress_value = 0;
UPDATE race_members SET score_value = 3, score_percent = 30, last_move_at = CURRENT_TIMESTAMP WHERE race_id = '7df1438e-315e-4e26-8ba5-cea631c3aa98' AND person_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4' AND score_value = 0;

-- Freshen classic demo races
UPDATE race_participants SET progress_value = 44, progress_percent = 88 WHERE race_id = 'd0000001-de00-4000-8000-000000000001' AND user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4';
UPDATE race_members SET score_value = 44, score_percent = 88, last_move_at = CURRENT_TIMESTAMP WHERE race_id = 'd0000001-de00-4000-8000-000000000001' AND person_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4';
UPDATE race_participants SET progress_value = 82, progress_percent = 82 WHERE race_id = 'd0000001-de00-4000-8000-000000000002' AND user_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4';
UPDATE race_members SET score_value = 82, score_percent = 82, last_move_at = CURRENT_TIMESTAMP WHERE race_id = 'd0000001-de00-4000-8000-000000000002' AND person_id = 'f64f7f0b-fc9f-44fc-aede-ba46355e75e4';
UPDATE races SET status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id IN ('d0000001-de00-4000-8000-000000000006', 'd0000001-de00-4000-8000-000000000007');
