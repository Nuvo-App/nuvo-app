-- Repair basketball races created before the release registry had a stable
-- assignment. The verifier-session route also self-heals this condition for
-- races created while an older app/server was in use.
INSERT OR IGNORE INTO race_verifier_assignments
  (race_id, activity_id, release_id, release_checksum, assignment_policy,
   compatibility_group, assignment_reason)
SELECT r.id,
       r.activity_id,
       vr.id,
       vr.checksum,
       'follow_compatible_patch',
       vr.compatibility_group,
       'basketball_assignment_backfill'
FROM races r
JOIN activity_channel_releases ac
  ON ac.activity_id = r.activity_id
 AND ac.channel = 'stable'
 AND ac.rollout_percent > 0
JOIN verifier_releases vr
  ON vr.id = ac.release_id
 AND vr.status = 'stable'
WHERE r.activity_id = 'basketball_shot'
  AND r.deleted_at IS NULL
  AND COALESCE(r.verifier_type, 'preset_pose') <> 'custom_pose_sequence';

UPDATE races
SET verifier_release_id = (
  SELECT a.release_id
  FROM race_verifier_assignments a
  WHERE a.race_id = races.id
)
WHERE activity_id = 'basketball_shot'
  AND verifier_release_id IS NULL
  AND id IN (
    SELECT race_id
    FROM race_verifier_assignments
    WHERE activity_id = 'basketball_shot'
  );
