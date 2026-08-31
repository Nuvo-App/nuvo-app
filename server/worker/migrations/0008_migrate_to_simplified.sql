-- Migration 0008: Copy legacy race/proof data into the simplified schema.
--
-- Goal: One-time migration from races_legacy, race_participants_legacy,
-- and proofs_legacy into the new races, race_members, race_progress, and
-- move_logs tables.
--
-- Safety: This migration only INSERTS into new tables. It does not modify or
-- delete the *_legacy tables. Rollback is possible by dropping the new tables
-- and renaming *_legacy back.

-- ---------------------------------------------------------------------------
-- Migrate races
-- ---------------------------------------------------------------------------
INSERT INTO races (
  id,
  creator_id,
  title,
  description,
  race_type,
  movement_type,
  verification_type,
  target_value,
  target_unit,
  status,
  visibility,
  start_at,
  end_at,
  created_at,
  updated_at,
  deleted_at
)
SELECT
  rl.id,
  rl.creator_id,
  rl.title,
  rl.description,
  CASE
    WHEN lower(rl.goal_type) = 'first_to_finish' THEN 'first_to_target'
    WHEN lower(rl.goal_type) = 'most' THEN 'most_in_time'
    WHEN lower(rl.goal_type) = 'streak' THEN 'daily_streak'
    WHEN lower(rl.goal_type) = 'habit' THEN 'habit_check'
    ELSE 'first_to_target'
  END AS race_type,
  rl.ai_activity_type AS movement_type,
  CASE
    WHEN lower(rl.proof_requirement) = 'ai_check' OR lower(rl.proof_mode) = 'ai_check' THEN 'movecheck'
    WHEN lower(rl.proof_requirement) = 'photo_video' THEN 'photo'
    WHEN lower(rl.proof_mode) = 'photo_video' THEN 'photo'
    ELSE 'manual'
  END AS verification_type,
  rl.target_value,
  COALESCE(rl.unit, rl.target_unit) AS target_unit,
  CASE
    WHEN lower(rl.status) = 'active' THEN 'active'
    WHEN lower(rl.status) = 'archived' THEN 'archived'
    WHEN lower(rl.status) = 'cancelled' THEN 'cancelled'
    ELSE 'active'
  END AS status,
  CASE
    WHEN lower(rl.visibility) = 'private' THEN 'private'
    WHEN lower(rl.visibility) = 'crew_only' THEN 'crew_only'
    WHEN lower(rl.visibility) = 'invite_code' THEN 'invite_code'
    ELSE 'private'
  END AS visibility,
  rl.start_line_at AS start_at,
  rl.finish_line_at AS end_at,
  rl.created_at,
  rl.updated_at,
  rl.deleted_at
FROM races_legacy rl;

-- ---------------------------------------------------------------------------
-- Migrate race members
-- ---------------------------------------------------------------------------
INSERT INTO race_members (
  id,
  race_id,
  user_id,
  role,
  status,
  joined_at,
  cached_display_name,
  cached_avatar_url
)
SELECT
  rpl.id,
  rpl.race_id,
  rpl.user_id,
  CASE WHEN rpl.user_id = rl.creator_id THEN 'creator' ELSE 'racer' END AS role,
  'active' AS status,
  rpl.joined_at,
  rpl.display_name AS cached_display_name,
  NULL AS cached_avatar_url
FROM race_participants_legacy rpl
JOIN races_legacy rl ON rl.id = rpl.race_id;

-- ---------------------------------------------------------------------------
-- Migrate race progress
-- ---------------------------------------------------------------------------
INSERT INTO race_progress (
  id,
  race_id,
  user_id,
  progress_value,
  progress_percent,
  completed_at,
  rank_cache,
  updated_at
)
SELECT
  lower(hex(randomblob(16))) AS id,
  rpl.race_id,
  rpl.user_id,
  rpl.progress_value,
  rpl.progress_percent,
  CASE
    WHEN rpl.progress_percent >= 100 THEN rpl.joined_at
    ELSE NULL
  END AS completed_at,
  NULL AS rank_cache,
  rpl.joined_at AS updated_at
FROM race_participants_legacy rpl;

-- ---------------------------------------------------------------------------
-- Migrate move logs (from proofs)
-- ---------------------------------------------------------------------------
INSERT INTO move_logs (
  id,
  race_id,
  user_id,
  source,
  movement_type,
  value,
  unit,
  status,
  summary,
  media_object_key,
  validator_version,
  duration_ms,
  metadata_json,
  created_at
)
SELECT
  pl.id,
  pl.race_id,
  pl.user_id,
  CASE
    WHEN lower(pl.proof_type) = 'ai_motion' THEN 'movecheck'
    ELSE 'manual'
  END AS source,
  pl.ai_activity_type AS movement_type,
  pl.value,
  COALESCE(rl.unit, rl.target_unit) AS unit,
  CASE
    WHEN lower(pl.verification_status) IN ('accepted', 'ai_verified') THEN 'verified'
    WHEN lower(pl.verification_status) = 'rejected' THEN 'rejected'
    ELSE 'pending'
  END AS status,
  pl.verification_summary AS summary,
  NULL AS media_object_key,
  pl.validator_version,
  pl.duration_ms,
  json_object(
    'confidence', pl.confidence,
    'detected_value', pl.detected_value,
    'target_value', pl.target_value,
    'frames_analyzed', pl.frames_analyzed,
    'valid_pose_frames', pl.valid_pose_frames
  ) AS metadata_json,
  pl.created_at
FROM proofs_legacy pl
JOIN races_legacy rl ON rl.id = pl.race_id;

-- ---------------------------------------------------------------------------
-- Best-effort: create media_objects rows for existing profile avatars that
-- point to the R2 bucket. Profiles.avatar_object_key will be updated lazily
-- on the next upload if this step misses any URLs.
-- ---------------------------------------------------------------------------
INSERT INTO media_objects (
  id,
  owner_user_id,
  bucket,
  object_key,
  public_url,
  media_type,
  purpose,
  status,
  created_at
)
SELECT
  lower(hex(randomblob(16))) AS id,
  p.user_id AS owner_user_id,
  'nuvor2' AS bucket,
  'profile-photos/' || substr(
    p.avatar_url,
    instr(p.avatar_url, 'profile-photos/') + length('profile-photos/')
  ) AS object_key,
  p.avatar_url AS public_url,
  'image' AS media_type,
  'profile_avatar' AS purpose,
  'active' AS status,
  CURRENT_TIMESTAMP
FROM profiles p
WHERE p.avatar_url IS NOT NULL
  AND p.avatar_url LIKE '%profile-photos/%'
  AND instr(p.avatar_url, 'profile-photos/') > 0;

-- Link profiles to the media objects we just created.
UPDATE profiles
SET avatar_object_key = (
  SELECT mo.object_key
  FROM media_objects mo
  WHERE mo.owner_user_id = profiles.user_id
    AND mo.purpose = 'profile_avatar'
    AND mo.status = 'active'
  ORDER BY mo.created_at DESC
  LIMIT 1
)
WHERE avatar_url LIKE '%profile-photos/%';
