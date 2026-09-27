-- Migration 0026: revert squats/arm_raises/jumping_jacks/plank_hold from their
-- 0016 declarative "remote" releases back to native.
--
-- The 0016 remote specs compare raw, fixed pose-point coordinates (e.g.
-- leftKnee.y >= 0.78) with no adjustment for camera distance or body
-- proportions. The native validators they replaced deliberately do NOT do
-- this — SquatsValidator uses hipToKneeRatio (knee position normalized by
-- torso height) specifically because a fixed threshold failed to register a
-- rep for realistically-framed users (see docs / squat device bug, fixed
-- 2026-09-03). ArmRaisesValidator's own comment states the same rationale
-- ("Body-scale-relative so the same raise reads consistently at any camera
-- distance"). jumping_jacks' remote spec reuses arm_raises' exact thresholds
-- verbatim, indicating it was never independently calibrated.
--
-- The current remote spec schema (RemotePoseRule: single point, single axis,
-- fixed threshold) cannot express a ratio between two points normalized by a
-- third — so these presets cannot be correctly expressed remotely until the
-- schema gains that capability. Reverting to native is the safe state until
-- then. Reversible by re-pointing the channel back to the *-remote-* release
-- ids once the schema/specs are fixed and device-validated.

UPDATE activity_channel_releases
SET release_id = 'squats-legacy-2026.09.0', updated_at = CURRENT_TIMESTAMP
WHERE activity_id = 'squats' AND channel = 'stable';

UPDATE activity_channel_releases
SET release_id = 'arm_raises-legacy-2026.09.0', updated_at = CURRENT_TIMESTAMP
WHERE activity_id = 'arm_raises' AND channel = 'stable';

UPDATE activity_channel_releases
SET release_id = 'jumping_jacks-legacy-2026.09.0', updated_at = CURRENT_TIMESTAMP
WHERE activity_id = 'jumping_jacks' AND channel = 'stable';

UPDATE activity_channel_releases
SET release_id = 'plank_hold-legacy-2026.09.0', updated_at = CURRENT_TIMESTAMP
WHERE activity_id = 'plank_hold' AND channel = 'stable';
