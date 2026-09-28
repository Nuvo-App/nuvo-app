-- PROD D1 (nuvo_db) schema snapshot, DDL only — no rows. Captured read-only via
-- sqlite_master on 2026-09-28 (d1_migrations through 0039; 0040/0041 applied
-- out-of-band). Includes out-of-repo legacy tables (people, moves, ...).
-- Used by release_p0_sql.test.mjs to exercise real SQLite FK/schema semantics.

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  primary_email TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at TEXT
, demo_world_enabled INTEGER NOT NULL DEFAULT 0, demo_world_seed    TEXT, demo_world_variant TEXT DEFAULT 'summer_v1', terms_accepted_at TEXT, last_active_at TEXT, terms_version TEXT, age_attested_at TEXT, motion_training_consent INTEGER NOT NULL DEFAULT 0, motion_consent_version TEXT, motion_consented_at TEXT, motion_consent_revoked_at TEXT);

CREATE TABLE auth_identities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_user_id TEXT,
  email TEXT,
  email_verified INTEGER NOT NULL DEFAULT 0,
  display_name TEXT,
  avatar_url TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, provider_refresh_token TEXT,
  UNIQUE(provider, provider_user_id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE email_codes (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT NOT NULL,
  used_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  refresh_token_hash TEXT NOT NULL,
  device_label TEXT,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE profiles (
  user_id TEXT PRIMARY KEY,
  full_name TEXT,
  username TEXT UNIQUE,
  avatar_url TEXT,
  private_profile INTEGER NOT NULL DEFAULT 0,
  onboarding_complete INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, avatar_object_key TEXT, is_demo INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE member_passes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  member_id TEXT NOT NULL UNIQUE,
  pass_slug TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE audit_events (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  event_type TEXT NOT NULL,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE races (
  id TEXT PRIMARY KEY,
  creator_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  description TEXT,
  category TEXT,
  goal_type TEXT NOT NULL DEFAULT 'manual',
  target_value INTEGER,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  start_line_at TEXT,
  finish_line_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
, rules TEXT, proof_requirement TEXT NOT NULL DEFAULT 'manual', proof_review_mode TEXT NOT NULL DEFAULT 'auto_accept', visibility TEXT NOT NULL DEFAULT 'private', deleted_at TEXT, ai_activity_type TEXT, target_unit TEXT, proof_mode TEXT, race_key TEXT, subtitle TEXT, race_type TEXT, created_by_person_id TEXT, cover_url TEXT, cover_r2_key TEXT, demo_priority INTEGER, movement_type TEXT, verification_type TEXT NOT NULL DEFAULT 'manual', start_at TEXT, end_at TEXT, activity_id TEXT, metric TEXT, format TEXT NOT NULL DEFAULT 'first_to_goal', scoring_rule TEXT NOT NULL DEFAULT 'cumulative_sum', attempt_duration_seconds INTEGER, attempt_limit INTEGER, verification_method TEXT NOT NULL DEFAULT 'camera_pose', timezone TEXT NOT NULL DEFAULT 'America/New_York', recurrence TEXT NOT NULL DEFAULT 'none', winner_user_id TEXT, completed_at TEXT, public_join_enabled INTEGER NOT NULL DEFAULT 1, verifier_type TEXT, verifier_version INTEGER, verifier_spec_json TEXT, custom_activity_name TEXT, verifier_release_id TEXT, score_direction TEXT NOT NULL DEFAULT 'higher', version INTEGER NOT NULL DEFAULT 0, is_live_session INTEGER NOT NULL DEFAULT 0, live_window_seconds INTEGER);

CREATE TABLE race_participants (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  display_name TEXT,
  progress_value INTEGER NOT NULL DEFAULT 0,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(race_id, user_id)
);

CREATE TABLE proofs (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  proof_type TEXT NOT NULL DEFAULT 'manual',
  note TEXT,
  value INTEGER,
  media_url TEXT,
  verification_status TEXT NOT NULL DEFAULT 'accepted',
  verification_summary TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
, reviewed_by TEXT, reviewed_at TEXT, ai_activity_type TEXT, detected_value INTEGER, target_value INTEGER, confidence REAL, validator_version TEXT, frames_analyzed INTEGER, valid_pose_frames INTEGER, duration_ms INTEGER);

CREATE TABLE race_invites (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, created_by_person_id TEXT,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
);

CREATE TABLE crew_connections (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  crew_user_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, person_id TEXT, crew_person_id TEXT, requested_by TEXT, updated_at TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(crew_user_id) REFERENCES users(id),
  UNIQUE(user_id, crew_user_id)
);

CREATE TABLE people (
  id TEXT PRIMARY KEY,
  person_key TEXT NOT NULL UNIQUE,
  user_id TEXT UNIQUE,
  display_name TEXT NOT NULL,
  username TEXT UNIQUE,
  avatar_url TEXT,
  avatar_r2_key TEXT,
  bio TEXT,
  is_demo INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE race_members (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  member_role TEXT NOT NULL DEFAULT 'member',
  member_status TEXT NOT NULL DEFAULT 'active',
  score_value INTEGER NOT NULL DEFAULT 0,
  score_percent INTEGER NOT NULL DEFAULT 0,
  rank_override INTEGER,
  is_current_user_highlight INTEGER NOT NULL DEFAULT 0,
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_move_at TEXT,
  display_note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, user_id TEXT, role TEXT NOT NULL DEFAULT 'racer', status TEXT NOT NULL DEFAULT 'active', cached_display_name TEXT, cached_avatar_url TEXT, ready_at TEXT, finished_at TEXT, finish_rank INTEGER,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(person_id) REFERENCES people(id),
  UNIQUE(race_id, person_id)
);

CREATE TABLE moves (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  amount_value INTEGER,
  amount_unit TEXT,
  move_status TEXT NOT NULL DEFAULT 'checked',
  move_source TEXT NOT NULL DEFAULT 'manual',
  note TEXT,
  media_url TEXT,
  media_r2_key TEXT,
  checked_at TEXT,
  checked_by TEXT,
  ai_summary TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(person_id) REFERENCES people(id),
  FOREIGN KEY(checked_by) REFERENCES people(id)
);

CREATE TABLE media_assets (
  id TEXT PRIMARY KEY,
  owner_person_id TEXT,
  asset_type TEXT NOT NULL,
  bucket_name TEXT NOT NULL DEFAULT 'nuvor2',
  object_key TEXT NOT NULL,
  public_url TEXT NOT NULL,
  mime_type TEXT,
  file_size INTEGER,
  width INTEGER,
  height INTEGER,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(owner_person_id) REFERENCES people(id)
);

CREATE TABLE admin_change_log (
  id TEXT PRIMARY KEY,
  actor_label TEXT NOT NULL,
  target_table TEXT NOT NULL,
  target_id TEXT NOT NULL,
  change_type TEXT NOT NULL,
  before_json TEXT,
  after_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE media_objects (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT,
  bucket TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  public_url TEXT,
  media_type TEXT NOT NULL DEFAULT 'image',
  purpose TEXT NOT NULL DEFAULT 'system_asset',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  FOREIGN KEY(owner_user_id) REFERENCES users(id)
);

CREATE TABLE race_progress (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  progress_value INTEGER NOT NULL DEFAULT 0,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  completed_at TEXT,
  rank_cache INTEGER,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(race_id, user_id)
);

CREATE TABLE move_logs (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  source TEXT NOT NULL,
  movement_type TEXT,
  value INTEGER,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  summary TEXT,
  media_object_key TEXT,
  validator_version TEXT,
  duration_ms INTEGER,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  client_submission_id TEXT,
  activity_id TEXT,
  metric TEXT,
  previous_score INTEGER,
  new_score INTEGER,
  previous_rank INTEGER,
  new_rank INTEGER,
  race_completed INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(media_object_key) REFERENCES media_objects(object_key)
);

CREATE TABLE race_final_standings (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  rank_position INTEGER NOT NULL,
  score_value INTEGER NOT NULL,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(race_id, user_id)
);

CREATE TABLE blocked_users (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(blocked_user_id) REFERENCES users(id),
  UNIQUE(user_id, blocked_user_id)
);

CREATE TABLE motion_definitions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1,
  definition_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE motion_analysis_jobs (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  motion_id TEXT NOT NULL,
  status TEXT NOT NULL,
  request_schema_version INTEGER NOT NULL,
  model_version TEXT NOT NULL,
  validator_version TEXT NOT NULL,
  result_json TEXT,
  frame_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at TEXT
);

CREATE TABLE motion_training_examples (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  motion_id TEXT NOT NULL,
  object_key TEXT,
  label TEXT,
  review_status TEXT NOT NULL DEFAULT 'unreviewed',
  consent_version TEXT NOT NULL,
  schema_version INTEGER NOT NULL,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT
);

CREATE TABLE motion_model_releases (
  id TEXT PRIMARY KEY,
  model_version TEXT NOT NULL UNIQUE,
  input_schema_version INTEGER NOT NULL,
  artifact_key TEXT,
  artifact_sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'candidate',
  supported_motion_ids_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  promoted_at TEXT
, model_family TEXT NOT NULL DEFAULT 'auxiliary_object', runtime_family TEXT NOT NULL DEFAULT '', output_schema_version INTEGER, preprocessing_version INTEGER, normalization_version INTEGER, embedding_schema_version INTEGER, minimum_app_build INTEGER, artifact_size_bytes INTEGER, evaluation_id TEXT, disabled_at TEXT);

CREATE TABLE motion_sessions (
  id TEXT PRIMARY KEY,                    
  session_id TEXT NOT NULL UNIQUE,        
  user_id TEXT NOT NULL,
  race_id TEXT,
  activity_id TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'preset',    
  outcome TEXT NOT NULL DEFAULT 'incomplete', 
  detected_value INTEGER NOT NULL DEFAULT 0,
  goal_value INTEGER,
  confidence REAL NOT NULL DEFAULT 0,
  failed_rule_reason TEXT NOT NULL DEFAULT '',
  started_at TEXT,
  ended_at TEXT,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  frame_count INTEGER NOT NULL DEFAULT 0,
  schema_version INTEGER NOT NULL DEFAULT 1,
  app_version TEXT NOT NULL DEFAULT 'unknown',
  git_commit TEXT NOT NULL DEFAULT 'unknown',
  verifier_version TEXT NOT NULL DEFAULT 'unknown',
  model_version TEXT NOT NULL DEFAULT 'unknown',
  object_key TEXT NOT NULL,               
  metadata_json TEXT,                     
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
, verifier_release_id TEXT, verifier_release_checksum TEXT, engine_type TEXT, spec_schema_version INTEGER, assignment_policy TEXT);

CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,             
  kind TEXT NOT NULL,                     
  actor_user_id TEXT NOT NULL,            
  target_type TEXT NOT NULL,              
  target_id TEXT NOT NULL,
  max_uses INTEGER,                       
  use_count INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT,                        
  revoked_at TEXT,
  metadata TEXT,                          
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(actor_user_id) REFERENCES users(id)
);

CREATE TABLE invite_uses (
  id TEXT PRIMARY KEY,
  invite_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(invite_id, user_id),
  FOREIGN KEY(invite_id) REFERENCES invites(id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,                  
  category TEXT NOT NULL,                 
  actor_user_id TEXT,                     
  title TEXT NOT NULL,
  body TEXT,
  dest_type TEXT,                         
  dest_id TEXT,
  dest_context TEXT,                      
  entity_type TEXT,                       
  entity_id TEXT,
  dedupe_key TEXT,                        
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, priority TEXT NOT NULL DEFAULT 'medium', aggregate_count INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE notification_preferences (
  user_id TEXT NOT NULL,
  category TEXT NOT NULL,
  in_app INTEGER NOT NULL DEFAULT 1,
  push INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(user_id, category),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE device_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token TEXT NOT NULL,
  platform TEXT NOT NULL,                 
  app_version TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disabled_at TEXT,
  UNIQUE(user_id, token),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE motion_activities (id TEXT PRIMARY KEY, display_name TEXT NOT NULL, category TEXT NOT NULL, proof_label TEXT NOT NULL, measurement_type TEXT NOT NULL CHECK (measurement_type IN ('repetitions', 'duration', 'distance')), metric TEXT NOT NULL CHECK (metric IN ('reps', 'seconds')), suggested_targets_json TEXT NOT NULL, supported_formats_json TEXT NOT NULL, icon_key TEXT NOT NULL, sort_priority INTEGER NOT NULL DEFAULT 100, featured INTEGER NOT NULL DEFAULT 0, availability TEXT NOT NULL DEFAULT 'supported', metadata_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);

CREATE TABLE verifier_releases (id TEXT PRIMARY KEY, activity_id TEXT NOT NULL, semver TEXT NOT NULL, change_class TEXT NOT NULL, engine_type TEXT NOT NULL, spec_schema_version INTEGER NOT NULL, spec_json TEXT NOT NULL, object_key TEXT, checksum TEXT NOT NULL UNIQUE, required_capabilities_json TEXT NOT NULL, minimum_app_build TEXT NOT NULL, compatibility_group TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft', release_notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, published_at TEXT, parent_release_id TEXT, updated_at TEXT, FOREIGN KEY(activity_id) REFERENCES motion_activities(id), FOREIGN KEY(parent_release_id) REFERENCES verifier_releases(id));

CREATE TABLE activity_channel_releases (activity_id TEXT NOT NULL, channel TEXT NOT NULL CHECK (channel IN ('internal', 'beta', 'stable')), release_id TEXT NOT NULL, rollout_percent INTEGER NOT NULL DEFAULT 0 CHECK (rollout_percent BETWEEN 0 AND 100), created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (activity_id, channel), FOREIGN KEY(activity_id) REFERENCES motion_activities(id), FOREIGN KEY(release_id) REFERENCES verifier_releases(id));

CREATE TABLE race_verifier_assignments (race_id TEXT PRIMARY KEY, activity_id TEXT NOT NULL, release_id TEXT NOT NULL, release_checksum TEXT NOT NULL, assignment_policy TEXT NOT NULL CHECK (assignment_policy IN ('pinned', 'follow_compatible_patch')), compatibility_group TEXT NOT NULL, assigned_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, assignment_reason TEXT NOT NULL, FOREIGN KEY(race_id) REFERENCES races(id), FOREIGN KEY(activity_id) REFERENCES motion_activities(id), FOREIGN KEY(release_id) REFERENCES verifier_releases(id));

CREATE TABLE verification_sessions (id TEXT PRIMARY KEY, race_id TEXT NOT NULL, user_id TEXT NOT NULL, activity_id TEXT NOT NULL, release_id TEXT NOT NULL, release_checksum TEXT NOT NULL, spec_schema_version INTEGER NOT NULL, engine_type TEXT NOT NULL, app_version TEXT NOT NULL, app_build TEXT NOT NULL, runtime_capabilities_json TEXT NOT NULL, status TEXT NOT NULL, result_value INTEGER, confidence REAL, failure_reason TEXT, started_at TEXT, completed_at TEXT, motion_session_id TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(race_id) REFERENCES races(id), FOREIGN KEY(activity_id) REFERENCES motion_activities(id), FOREIGN KEY(release_id) REFERENCES verifier_releases(id));

CREATE TABLE verifier_evaluation_runs (id TEXT PRIMARY KEY, release_id TEXT NOT NULL, dataset_snapshot_id TEXT NOT NULL, status TEXT NOT NULL, report_json TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, completed_at TEXT, FOREIGN KEY(release_id) REFERENCES verifier_releases(id));

CREATE TABLE motion_release_metrics (
  release_id TEXT NOT NULL,
  activity_id TEXT NOT NULL,
  outcome TEXT NOT NULL,
  failure_reason TEXT NOT NULL DEFAULT '',
  sample_count INTEGER NOT NULL DEFAULT 0,
  total_detected INTEGER NOT NULL DEFAULT 0,
  total_confidence REAL NOT NULL DEFAULT 0,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (release_id, activity_id, outcome, failure_reason),
  FOREIGN KEY (release_id) REFERENCES verifier_releases(id),
  FOREIGN KEY (activity_id) REFERENCES motion_activities(id)
);

CREATE TABLE motion_feedback_labels (
  id TEXT PRIMARY KEY,
  motion_session_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  label TEXT NOT NULL CHECK (label IN ('missed_count', 'false_count', 'camera_issue', 'worked')),
  note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (motion_session_id, user_id, label)
);

CREATE TABLE verifier_audit_log (
  id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  activity_id TEXT,
  release_id TEXT,
  previous_release_id TEXT,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE motion_account_keys (
  account_ref TEXT PRIMARY KEY,
  wrapped_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT
);

CREATE TABLE race_events (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  event_type TEXT NOT NULL,
  actor_user_id TEXT,        
  subject_user_id TEXT,      
  payload_json TEXT,         
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE race_attempts (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL,
  attempt_index INTEGER NOT NULL,            
  client_attempt_id TEXT,                    
  status TEXT NOT NULL DEFAULT 'open',       
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,   
  deadline_at TEXT,                          
  submitted_at TEXT,
  score INTEGER,                             
  move_log_id TEXT REFERENCES move_logs(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (race_id, user_id, attempt_index)
);

CREATE TABLE personal_bests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  activity_id TEXT NOT NULL,           
  metric TEXT NOT NULL,
  best_value INTEGER NOT NULL,
  score_direction TEXT NOT NULL DEFAULT 'higher',
  race_id TEXT REFERENCES races(id),
  move_log_id TEXT REFERENCES move_logs(id),
  set_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, activity_id, metric)
);

CREATE TABLE activity_reactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, entity_type, entity_id)
);

CREATE TABLE notification_jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,            
  entity_type TEXT NOT NULL,     
  entity_id TEXT NOT NULL,
  user_id TEXT,                  
  dedupe_key TEXT NOT NULL UNIQUE,
  run_at TEXT NOT NULL,
  payload_json TEXT,
  status TEXT NOT NULL DEFAULT 'pending',  
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE xp_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_type TEXT NOT NULL,          
  source_id TEXT NOT NULL,            
  race_id TEXT,
  xp_amount INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, source_type, source_id)
);

CREATE TABLE user_progression (
  user_id TEXT PRIMARY KEY,
  total_xp INTEGER NOT NULL DEFAULT 0,
  level INTEGER NOT NULL DEFAULT 1,
  last_seen_level INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE unlock_definitions (
  id TEXT PRIMARY KEY,
  required_level INTEGER NOT NULL,
  unlock_type TEXT NOT NULL,
  unlock_key TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  metadata_json TEXT,                 
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (unlock_type, unlock_key)
);

CREATE TABLE user_unlocks (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  unlock_id TEXT NOT NULL REFERENCES unlock_definitions(id),
  unlocked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  source TEXT NOT NULL DEFAULT 'level',
  UNIQUE (user_id, unlock_id)
);

CREATE TABLE user_featured_badges (
  user_id TEXT NOT NULL,
  unlock_id TEXT NOT NULL REFERENCES unlock_definitions(id),
  position INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, position),
  UNIQUE (user_id, unlock_id)
);

CREATE TABLE motion_model_channels (
  model_family TEXT NOT NULL,
  channel TEXT NOT NULL,
  release_id TEXT NOT NULL REFERENCES motion_model_releases(id),
  previous_release_id TEXT REFERENCES motion_model_releases(id),
  rollout_percent INTEGER NOT NULL DEFAULT 100,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (model_family, channel)
);

CREATE TABLE motion_model_evaluations (
  id TEXT PRIMARY KEY,
  release_id TEXT NOT NULL REFERENCES motion_model_releases(id),
  corpus_id TEXT,
  sample_count INTEGER NOT NULL,
  passed INTEGER NOT NULL,
  metrics_json TEXT NOT NULL DEFAULT '{}',
  evaluator TEXT NOT NULL DEFAULT 'ops',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(primary_email);

CREATE INDEX idx_users_status ON users(status);

CREATE INDEX idx_auth_identities_user_id ON auth_identities(user_id);

CREATE INDEX idx_auth_identities_provider ON auth_identities(provider, provider_user_id);

CREATE INDEX idx_email_codes_email ON email_codes(email);

CREATE INDEX idx_email_codes_expires ON email_codes(expires_at);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);

CREATE INDEX idx_sessions_token_hash ON sessions(refresh_token_hash);

CREATE INDEX idx_sessions_expires ON sessions(expires_at);

CREATE INDEX idx_profiles_username ON profiles(username);

CREATE INDEX idx_member_passes_slug ON member_passes(pass_slug);

CREATE INDEX idx_audit_events_user_id ON audit_events(user_id);

CREATE INDEX idx_audit_events_created ON audit_events(created_at);

CREATE INDEX idx_races_creator ON races(creator_id);

CREATE INDEX idx_race_participants_race ON race_participants(race_id);

CREATE INDEX idx_race_participants_user ON race_participants(user_id);

CREATE INDEX idx_proofs_race ON proofs(race_id);

CREATE INDEX idx_proofs_user ON proofs(user_id);

CREATE INDEX idx_races_deleted_at ON races(deleted_at);

CREATE INDEX idx_race_invites_code ON race_invites(invite_code);

CREATE INDEX idx_race_invites_race ON race_invites(race_id);

CREATE INDEX idx_proofs_reviewed_by ON proofs(reviewed_by);

CREATE INDEX idx_crew_connections_user ON crew_connections(user_id, status);

CREATE INDEX idx_crew_connections_crew_user ON crew_connections(crew_user_id, status);

CREATE INDEX idx_people_user_id ON people(user_id);

CREATE INDEX idx_people_status ON people(status);

CREATE INDEX idx_people_demo ON people(is_demo);

CREATE INDEX idx_races_race_key ON races(race_key);

CREATE INDEX idx_races_created_by_person ON races(created_by_person_id);

CREATE INDEX idx_races_demo_priority ON races(demo_priority);

CREATE INDEX idx_race_members_race ON race_members(race_id, member_status);

CREATE INDEX idx_race_members_person ON race_members(person_id);

CREATE INDEX idx_race_members_score ON race_members(race_id, score_percent DESC, score_value DESC);

CREATE INDEX idx_moves_race_created ON moves(race_id, created_at DESC);

CREATE INDEX idx_moves_person_created ON moves(person_id, created_at DESC);

CREATE INDEX idx_moves_status ON moves(move_status);

CREATE INDEX idx_media_assets_owner ON media_assets(owner_person_id);

CREATE INDEX idx_media_assets_type ON media_assets(asset_type);

CREATE INDEX idx_media_assets_object_key ON media_assets(object_key);

CREATE INDEX idx_admin_change_log_target ON admin_change_log(target_table, target_id);

CREATE INDEX idx_admin_change_log_created ON admin_change_log(created_at DESC);

CREATE INDEX idx_crew_connections_person ON crew_connections(person_id, status);

CREATE INDEX idx_crew_connections_crew_person ON crew_connections(crew_person_id, status);

CREATE INDEX idx_race_invites_created_by_person ON race_invites(created_by_person_id);

CREATE INDEX idx_media_objects_owner ON media_objects(owner_user_id, status);

CREATE INDEX idx_media_objects_purpose ON media_objects(purpose, status);

CREATE INDEX idx_media_objects_object_key ON media_objects(object_key);

CREATE INDEX idx_race_members_race_compat ON race_members(race_id, status);

CREATE INDEX idx_race_members_user_compat ON race_members(user_id, status);

CREATE INDEX idx_race_progress_race ON race_progress(race_id, progress_percent DESC, progress_value DESC);

CREATE INDEX idx_race_progress_user ON race_progress(user_id);

CREATE INDEX idx_move_logs_race ON move_logs(race_id, created_at DESC);

CREATE INDEX idx_move_logs_user ON move_logs(user_id, created_at DESC);

CREATE INDEX idx_move_logs_status ON move_logs(status);

CREATE UNIQUE INDEX idx_move_logs_client_submission
  ON move_logs(race_id, user_id, client_submission_id)
  WHERE client_submission_id IS NOT NULL;

CREATE INDEX idx_race_final_standings_race
  ON race_final_standings(race_id, rank_position);

CREATE INDEX idx_blocked_users_user ON blocked_users(user_id);

CREATE INDEX idx_blocked_users_blocked ON blocked_users(blocked_user_id);

CREATE INDEX idx_race_members_user ON race_members(user_id, status);

CREATE INDEX idx_motion_analysis_jobs_user_created
  ON motion_analysis_jobs(user_id, created_at DESC);

CREATE INDEX idx_motion_sessions_user_created
  ON motion_sessions(user_id, created_at DESC);

CREATE INDEX idx_motion_sessions_user_activity_created
  ON motion_sessions(user_id, activity_id, created_at DESC);

CREATE INDEX idx_motion_sessions_activity_created
  ON motion_sessions(activity_id, created_at DESC);

CREATE INDEX idx_motion_sessions_outcome_created
  ON motion_sessions(outcome, created_at DESC);

CREATE INDEX idx_motion_sessions_race
  ON motion_sessions(race_id, created_at DESC);

CREATE UNIQUE INDEX idx_invites_token ON invites(token);

CREATE INDEX idx_invites_target ON invites(target_type, target_id, revoked_at);

CREATE INDEX idx_invites_actor ON invites(actor_user_id, created_at);

CREATE INDEX idx_notifications_recipient ON notifications(user_id, created_at DESC);

CREATE INDEX idx_notifications_unread ON notifications(user_id, read_at);

CREATE UNIQUE INDEX idx_notifications_dedupe
  ON notifications(user_id, dedupe_key);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id, disabled_at);

CREATE INDEX idx_motion_activities_availability ON motion_activities(availability, sort_priority);

CREATE INDEX idx_verifier_releases_activity_status ON verifier_releases(activity_id, status, created_at DESC);

CREATE INDEX idx_race_verifier_assignments_activity ON race_verifier_assignments(activity_id, release_id);

CREATE INDEX idx_verification_sessions_race ON verification_sessions(race_id, created_at DESC);

CREATE INDEX idx_verification_sessions_user ON verification_sessions(user_id, created_at DESC);

CREATE INDEX idx_motion_release_metrics_activity
  ON motion_release_metrics(activity_id, release_id, last_seen_at DESC);

CREATE INDEX idx_motion_feedback_session
  ON motion_feedback_labels(motion_session_id, created_at DESC);

CREATE INDEX idx_verifier_audit_release
  ON verifier_audit_log(release_id, created_at DESC);

CREATE INDEX idx_race_events_race ON race_events(race_id, created_at);

CREATE INDEX idx_race_events_type ON race_events(event_type, created_at);

CREATE INDEX idx_race_events_subject ON race_events(subject_user_id, created_at);

CREATE UNIQUE INDEX idx_race_attempts_client
  ON race_attempts(race_id, user_id, client_attempt_id)
  WHERE client_attempt_id IS NOT NULL;

CREATE INDEX idx_race_attempts_open
  ON race_attempts(race_id, user_id, status);

CREATE INDEX idx_personal_bests_user ON personal_bests(user_id);

CREATE INDEX activity_reactions_entity_idx
  ON activity_reactions (entity_type, entity_id);

CREATE INDEX idx_notification_jobs_due
  ON notification_jobs(status, run_at);

CREATE INDEX idx_notification_jobs_entity
  ON notification_jobs(entity_type, entity_id);

CREATE INDEX idx_xp_events_user ON xp_events(user_id, created_at);

CREATE INDEX idx_unlock_defs_level
  ON unlock_definitions(required_level) WHERE active = 1;

CREATE INDEX idx_user_unlocks_user ON user_unlocks(user_id);

CREATE INDEX idx_motion_model_evaluations_release
  ON motion_model_evaluations(release_id, created_at DESC);

CREATE VIEW v_admin_people AS
SELECT
  p.person_key,
  p.display_name,
  p.username,
  p.avatar_url,
  p.is_demo,
  u.primary_email AS linked_email,
  p.status
FROM people p
LEFT JOIN users u ON u.id = p.user_id
ORDER BY p.is_demo DESC, p.display_name COLLATE NOCASE ASC;

CREATE VIEW v_admin_race_board AS
SELECT
  r.race_key,
  r.title AS race_title,
  r.target_value,
  COALESCE(r.target_unit, r.unit) AS target_unit,
  p.person_key,
  p.display_name,
  p.username,
  p.avatar_url,
  rm.score_value,
  rm.score_percent,
  rank() OVER (
    PARTITION BY rm.race_id
    ORDER BY
      COALESCE(rm.rank_override, 999999) ASC,
      rm.score_percent DESC,
      rm.score_value DESC,
      rm.joined_at ASC
  ) AS rank,
  rm.last_move_at
FROM race_members rm
JOIN races r ON r.id = rm.race_id
JOIN people p ON p.id = rm.person_id
WHERE r.deleted_at IS NULL
  AND rm.member_status = 'active'
ORDER BY r.demo_priority IS NULL, r.demo_priority ASC, r.created_at DESC, rank ASC;

CREATE VIEW v_admin_move_log AS
SELECT
  r.race_key,
  r.title AS race_title,
  p.person_key,
  p.display_name,
  m.amount_value,
  m.amount_unit,
  m.move_status,
  m.move_source,
  m.note,
  m.media_url,
  m.created_at
FROM moves m
JOIN races r ON r.id = m.race_id
JOIN people p ON p.id = m.person_id
ORDER BY m.created_at DESC;
