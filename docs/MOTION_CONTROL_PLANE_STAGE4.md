# Nuvo Motion Control Plane — Stage 4

Status: implementation complete; physical-device acceptance remains a manual owner gate.

## Production contracts changed

- Dart now parses bounded `state_machine_v1`, `alternating_rep_v1`, and `hold_v1` releases and adapts them to the existing proof runtime contract.
- Race detail responses carry the assigned immutable release specification for preset races.
- The Worker validates release identity, engine family, landmarks, operators, thresholds, list bounds, and native rollback keys before serving a release.
- Migration `0016_remote_motion_releases.sql` publishes declarative arm raises, squats, jumping jacks, and plank hold releases while retaining the 0015 native releases.

## Safety and compatibility

- No executable code, model binary, or LLM instruction is downloaded.
- Existing native releases remain immutable rollback targets. Existing race assignments remain pinned; only new sessions on follow-compatible assignments can adopt a compatible patch.
- Unknown remote activities are not inferred into a local movement. They remain unavailable until the installed runtime has an explicit adapter.
- The compact release shape is deliberately allowlisted on both Dart and TypeScript. Invalid specs fail closed.

## Evidence

- `test/remote_verifier_runtime_test.dart`: parser bounds and all three runtime factories.
- `test/remote_verifier_integration_test.dart`: race response → release resolver → local runtime → proof result for arm raises, squats, and jumping jacks; release mismatch rejection.
- `server/worker/test/motion_spec.test.mjs`: Worker/Dart-compatible validation, unsafe field rejection, native rollback acceptance.
- `server/worker/test/verification_sessions.test.mjs`: session release pinning and checksum mismatch rejection.
- `server/worker/test/motion_assignments.test.mjs`: compatible patch adoption only between sessions.
- Populated local D1 rehearsal: migrations 0001–0016 applied successfully, including all four remote release seeds.

## Manual acceptance still required

A physical device owner must replay arm raises, squats, and jumping jacks in representative framing and lighting, including a close upper-body arm-raise framing case. The requested workflow excludes simulator execution, so this is not claimed from automated tests.
