-- Migration 0027: publish the first remote pre-verify preview animation
-- (arm_raises), proving the Cloudflare-driven preview pipeline end to end.
--
-- previewSequence is decorative only (see RemotePreviewSpec / client-side
-- RemoteFrontKeyframeSequence) — the camera verifier never reads it, so an
-- invalid spec only ever falls back to the bundled compiled animation, never
-- affects scoring. The keyframe values below are extracted verbatim from the
-- compiled `_ArmRaisesSequence` (standing -> raised -> standing) so this
-- remote version renders identically to what's already shipped; the point of
-- this migration is proving the pipe works, not changing the animation.
--
-- Publishing a new spec here (or for any other activity) changes/adds its
-- preview for every installed app on its next catalog fetch — no app update.

UPDATE motion_activities
SET metadata_json = json_patch(metadata_json, '{"previewSequence":{"rig":"front","durationMs":1800,"keyframes":[{"torsoAngle":-90.0,"leftShoulderAngle":-180.0,"leftElbowAngle":0.0,"rightShoulderAngle":180.0,"rightElbowAngle":0.0,"leftHipAngle":-180.0,"leftKneeAngle":0.0,"rightHipAngle":180.0,"rightKneeAngle":0.0,"leftUpperArmScale":92.0,"leftLowerArmScale":92.0,"rightUpperArmScale":92.0,"rightLowerArmScale":92.0,"leftUpperLegScale":100.0,"leftLowerLegScale":100.0,"rightUpperLegScale":100.0,"rightLowerLegScale":100.0,"torsoScaleY":100.0,"rootYOffset":0.0},{"torsoAngle":-90.0,"leftShoulderAngle":-65.0,"leftElbowAngle":14.0,"rightShoulderAngle":65.0,"rightElbowAngle":-14.0,"leftHipAngle":-180.0,"leftKneeAngle":0.0,"rightHipAngle":180.0,"rightKneeAngle":0.0,"leftUpperArmScale":92.0,"leftLowerArmScale":92.0,"rightUpperArmScale":92.0,"rightLowerArmScale":92.0,"leftUpperLegScale":100.0,"leftLowerLegScale":100.0,"rightUpperLegScale":100.0,"rightLowerLegScale":100.0,"torsoScaleY":100.0,"rootYOffset":0.0},{"torsoAngle":-90.0,"leftShoulderAngle":-180.0,"leftElbowAngle":0.0,"rightShoulderAngle":180.0,"rightElbowAngle":0.0,"leftHipAngle":-180.0,"leftKneeAngle":0.0,"rightHipAngle":180.0,"rightKneeAngle":0.0,"leftUpperArmScale":92.0,"leftLowerArmScale":92.0,"rightUpperArmScale":92.0,"rightLowerArmScale":92.0,"leftUpperLegScale":100.0,"leftLowerLegScale":100.0,"rightUpperLegScale":100.0,"rightLowerLegScale":100.0,"torsoScaleY":100.0,"rootYOffset":0.0}]}}'),
    updated_at = CURRENT_TIMESTAMP
WHERE id = 'arm_raises';
