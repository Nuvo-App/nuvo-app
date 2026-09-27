-- Migration 0022: publish the verified basketball shot release to stable.
-- The object-composition runtime and model artifact are already present; this
-- only makes the activity selectable through the normal race composer.

UPDATE motion_activities
SET availability = 'supported',
    metadata_json = '{"verifierMode":"object_composition","objectKinds":["ball","hoop"],"rawVideo":false}'
WHERE id = 'basketball_shot';

UPDATE verifier_releases
SET status = 'production',
    release_notes = 'Stable basketball shot object-composition verifier.'
WHERE id = 'basketball_shot-composition-2026.09.1';

INSERT OR REPLACE INTO activity_channel_releases
  (activity_id, channel, release_id, rollout_percent)
VALUES ('basketball_shot', 'stable', 'basketball_shot-composition-2026.09.1', 100);
