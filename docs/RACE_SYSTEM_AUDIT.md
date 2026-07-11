# Nuvo Race System Audit

Date: 2026-07-11

Scope: read-only audit of the current Flutter app and Cloudflare Worker race system. No implementation, schema, seed, dependency, auth, camera, or native code was changed.

## Executive Summary

Nuvo currently has one generic cumulative leaderboard model. A race has a title, optional target value/unit, one movement type, one verification type, members, cached progress, and move logs. Verified moves add to a user's cumulative `race_progress.progress_value`; `progress_percent` is capped at 100, but raw progress can exceed the target.

The current app does not yet support distinct competition formats as behavior. `first_to_target`, `most_in_time`, `daily_streak`, and `habit_check` exist as strings or legacy mappings, but scoring, completion, recurrence, teams, best attempts, streak windows, time windows, and distance/sensor rules are not implemented as separate engines.

Camera verification exists for several movements in the validator layer, but support is inconsistent across layers:

- Validator engine: pushups, jumping jacks, squats, lunges, high knees, arm raises, plank hold.
- Product catalog/resolver UI: pushups, jumping jacks, squats, lunges, plank hold.
- `Race.isSupportedAiMotionRace`: jumping jacks, squats, high knees, arm raises, plank hold, plus a jumping-jack title fallback. It omits pushups/lunges even though other layers include them.

Unsupported races do not currently fall back to manual logging in the main Submit Proof UI. The backend still accepts manual proof through `POST /races/:id/proof`, but the current unsupported proof screen only returns the user to the race.

## Current Race Types

Current persisted backend race types are defined as strings in `server/worker/migrations/0007_simplified_schema.sql:56`:

- `first_to_target`
- `most_in_time`
- `daily_streak`
- `habit_check`

Legacy Flutter-facing `goalType` maps in `server/worker/src/routes/races.ts:62-78`:

- Flutter `manual` or unknown -> backend `first_to_target`
- Flutter `most` -> backend `most_in_time`
- Flutter `streak` -> backend `daily_streak`
- Flutter `habit` -> backend `habit_check`

Important: only cumulative progress behavior is implemented. Race type does not change scoring logic in `applyMoveProgress` (`server/worker/src/routes/races.ts:133-157`).

## Current Activities

| Activity ID | Display Names | Metric/Unit | Camera Verifiable | Validator/Resolver | Camera Orientation | Supports | Limitations | Fallback |
|---|---|---:|---|---|---|---|---|---|
| `push_ups` | Pushups, push-ups | reps | Yes in catalog and validator | `PushupsValidator`; resolver regex for pushups | Front preferred / upper body + hands | reps | `Race.isSupportedAiMotionRace` omits it; legacy `push_up_counter.dart` says push-up proof is experimental and unused | UI unsupported if resolver fails; backend manual endpoint still exists |
| `jumping_jacks` | Jumping Jacks | reps | Yes | `JumpingJacksValidator`; resolver regex; `Race` title/unit fallback | Full body front | reps | Most hard-coded demo path; default activity fallback is jumping jacks | No manual fallback in current Submit Proof UI |
| `squats` | Squats | reps | Yes | `SquatsValidator`; resolver regex | Full body front | reps | Simple hip-to-knee heuristic | No manual fallback in current Submit Proof UI |
| `lunges` | Lunges | reps | Yes in catalog and validator | `LungesValidator`; resolver regex | Full body front or slight angle | reps | Not present in `Race.isSupportedAiMotionRace` | No manual fallback in current Submit Proof UI |
| `plank_hold` | Plank Hold | seconds | Yes | `PlankHoldValidator`; resolver regex for plank | Side or diagonal required | duration seconds | Timer only advances while posture is valid; backend still stores value as integer progress | No manual fallback in current Submit Proof UI |
| `high_knees` | High knees | reps | Validator exists only | `HighKneesValidator`; `AiMotionActivity` enum | Front preferred default | reps | Not in catalog/resolver quick starts, so not user-creatable in current UI | Not surfaced |
| `arm_raises` | Arm raises | reps | Validator exists only | `ArmRaisesValidator`; `AiMotionActivity` enum | Front preferred default | reps | Not in catalog/resolver quick starts, so not user-creatable in current UI | Not surfaced |

Activity definitions live in `lib/features/races/domain/motion_activity_catalog.dart:3-58`. Validator definitions live in `lib/features/races/ai/motion_validators.dart:39-76` and validator routing in `motion_validators.dart:225-238`.

## Current Units

Units are free-form strings in the backend (`target_unit`, `unit`) and Flutter model (`unit`, `targetUnit`). There is no enum or conversion layer.

Observed units:

- UI/catalog: `reps`, `seconds`, `pushups`, `jumping jacks`, `squats`, `lunges`.
- Onboarding/manual templates: `sessions`, `milestones`, `books`, `days`.
- Demo scripts/generator: `reps`, `miles`, `sessions`, `milestones`, `days`.

There is no unit conversion logic. `plank_hold` uses seconds as integer progress.

## Race-Related Models

### `lib/features/races/data/race_models.dart`

`Race`

| Field | Meaning | Nullable/default | Used | Persisted | UI exposed | Duplicated |
|---|---|---|---|---|---|---|
| `id` | Race ID | required | routing/API | `races.id` | yes | Arena board ID |
| `creatorId` | Owner user ID | required | permissions/UI owner checks | `races.creator_id` | indirectly | backend `creator_id` |
| `title` | Race name | required | all screens/resolver | `races.title` | yes | demo generators |
| `description` | Description | nullable | create/settings | `races.description` | limited | old seed |
| `category` | Category | nullable; backend returns `''` | create/settings only | not in simplified schema response | settings | legacy schema/scripts |
| `goalType` | Flutter goal/race type | defaults `manual` | create/settings | maps to `races.race_type` | not directly | backend `race_type` |
| `targetValue` | Finish line target | nullable | progress labels, validators | `races.target_value` | yes | race progress percent |
| `unit` | Display unit | nullable | labels/resolver | `races.target_unit` | yes | `targetUnit` |
| `aiActivityType` | Movement type | nullable | resolver/AI proof | `races.movement_type` | indirectly | `movement_type`, `activityType` |
| `targetUnit` | Alternate unit | nullable | resolver/API compatibility | `races.target_unit` | not directly | `unit` |
| `proofMode` | Legacy proof mode | nullable | `isAiMotionRace` | derived from verification type | not directly | `proofRequirement` |
| `status` | `active`, `archived`, etc. | default `active` | routing/UI/lifecycle | `races.status` | yes | Arena result status |
| `startLineAt` | Start timestamp string | nullable | settings, display only | `races.start_at` | settings/days | raw string |
| `finishLineAt` | End timestamp string | nullable | days-left display only | `races.end_at` | settings/days | raw string |
| `rules` | Rules text | nullable | UI display/settings | simplified backend returns `''` | yes | not persisted in simplified schema |
| `proofRequirement` | `manual`, `ai_check`, etc. | default `manual` | AI race detection | maps from `verification_type` | indirectly | `proofMode` |
| `proofReviewMode` | Review mode | default `auto_accept` | settings only | simplified backend returns constant | settings | old schema |
| `visibility` | Join visibility | default `private` | join/settings | `races.visibility` | settings | backend enum |
| `inviteCode` | Active invite code | nullable | copy/join | `race_invites.invite_code` | yes | invite endpoint |
| `createdAt` | Creation timestamp string | required | sorting/server result | `races.created_at` | limited | raw string |
| `updatedAt` | Update timestamp string | required | model only | `races.updated_at` | no | raw string |
| `participants` | Active members/progress | default `[]` | board/detail | `race_members` + `race_progress` | yes | Arena mini leaderboard |
| `recentProofs` | Recent moves/proofs | default `[]` | move log/review | `move_logs` | yes | proof legacy endpoints |

`RaceParticipant`

Fields: `id`, `userId`, `displayName`, `progressValue`, `progressPercent`, `joinedAt`, `profilePhotoUrl`.

Meaning/persistence: built from `race_members` plus `race_progress` in `buildRaceResponse` (`server/worker/src/routes/races.ts:160-216`). Used by Race Detail, Arena, Profile, ChaseContext. `progressPercent` is persisted cache and used for rank sorting; `progressValue` is persisted raw cumulative score.

`RaceProof`

Fields: `id`, `userId`, `displayName`, `proofType`, `aiActivityType`, `note`, `value`, `detectedValue`, `targetValue`, `confidence`, `validatorVersion`, `framesAnalyzed`, `validPoseFrames`, `durationMs`, `verificationStatus`, `verificationSummary`, `reviewedBy`, `reviewedAt`, `createdAt`, `profilePhotoUrl`, `thumbnailUrl`, `rankBefore`, `rankAfter`, `peoplePassed`.

Meaning/persistence: currently built from `move_logs` and `metadata_json`. `reviewedBy`, `reviewedAt`, `thumbnailUrl`, `rankBefore`, `rankAfter`, and `peoplePassed` are modeled in Flutter but not populated by the simplified backend response (`server/worker/src/routes/races.ts:217-246`). `confidence`, frame counts, target, and detected value are persisted inside `move_logs.metadata_json`, not typed columns.

`PublicUser`

Fields: `id`, `displayName`, `username`, `memberId`, `initials`, `addedAt`, `profilePhotoUrl`. Used by crew search/invite flow. It is race-adjacent, not a race model.

### `lib/features/races/data/ai_motion_models.dart`

`AiMotionActivity`: enum values `jumpingJacks`, `squats`, `highKnees`, `armRaises`, `plankHold`, `pushUps`, `lunges`. Maps to backend strings.

`AiMotionResult`: fields `activity`, `targetReps`, `detectedReps`, `confidence`, `verificationStatus`, `verificationSummary`, `framesAnalyzed`, `validPoseFrames`, `durationMs`, `validatorVersion`. `toProofPayload()` sends `proofType: ai_motion`, `activityType`, `value`, `targetValue`, `detectedValue`, confidence and validator metadata to `POST /races/:id/proof`.

`NuvoPoseFrame` / `NuvoPosePoint`: transient camera/pose data only. Not persisted except aggregate frame counts and duration in the submitted proof.

### `lib/features/races/domain/motion_activity.dart`

`MotionActivityType`: frontend catalog enum for `push_ups`, `jumping_jacks`, `squats`, `lunges`, `high_knees`, `arm_raises`, `plank_hold`.

`MotionActivityDefinition`: type, title, unit, defaultTarget, aliases, proofLabel, cameraInstruction, isHold. Used by create flow and resolver.

`ParsedRaceIdea`: typed title parse result with `input`, optional `activity`, `targetValue`; `unit` defaults to `units` for unsupported input.

### `lib/features/arena/data/arena_models.dart`

`ArenaSnapshot`, `ArenaBoard`, `ArenaMiniLeaderboardRow`, `ArenaActivity` are API presentation models. They duplicate race title, progress, proof labels, result state, primary action, mini leaderboard rows, rank/chase/day fields. They are not persisted directly; built by `GET /arena`.

### `lib/data/models/race.dart`

Legacy UI model with `RacePlayer` and `Race`. Fields: `RacePlayer.name`, `initials`, `progress`; `Race.id`, `title`, `description`, `daysLeft`, `proof`, `players`, `note`. Still imported by `lib/core/widgets/arena_card.dart` and `lib/core/widgets/progress_player_row.dart`, but separate from the API-backed race system.

### Backend Types

`server/worker/src/types.ts` defines persisted simplified rows:

- `RaceRow`: `id`, `creator_id`, `title`, `description`, `race_type`, `movement_type`, `verification_type`, `target_value`, `target_unit`, `status`, `visibility`, `start_at`, `end_at`, `created_at`, `updated_at`, `deleted_at`.
- `RaceMemberRow`: membership/role/status/cached display/avatar.
- `RaceProgressRow`: cumulative progress, percent, `completed_at`, `rank_cache`.
- `MoveLogRow`: source, movement, value, unit, status, summary, media, validator, duration, metadata, created timestamp.

## Race Creation Flow

### Main Create Race

File: `lib/features/races/presentation/create_race_screen.dart`.

Fields:

- One text field: `Race idea`.
- Quick starts: `10 Pushups`, `10 Jumping Jacks`, `10 Squats`, `10 Lunges`, `20 Second Plank`.

Parsing/defaults:

- `parseRaceIdea()` grabs the first integer from text.
- If no integer, it uses the matched activity default target; if unsupported, target defaults to `1`.
- `_canStart` requires non-empty input and `parsed.aiSupported`, so unsupported typed titles cannot be created from this screen.

Generated payload:

- `title`: typed idea.
- `description`: `Camera counts <target> automatically.` for supported activity.
- `category`: `fitness`.
- `goalType`: always `manual`.
- `targetValue`: parsed target.
- `unit`: `reps`, except plank uses `seconds`.
- `proofRequirement`: `ai_check`.
- `proofReviewMode`: `auto_accept`.
- `aiActivityType`: activity backend value.
- `targetUnit`: same as unit.
- `proofMode`: `ai_check`.

Backend result:

- `goalType: manual` maps to backend `race_type: first_to_target`.
- `proofRequirement: ai_check` maps to `verification_type: movecheck`.
- Creator is inserted into `race_members`; progress row starts at 0.

### Onboarding First Race

File: `lib/features/onboarding/presentation/first_race_screen.dart`.

Templates:

- `10 Jumping Jacks`: `ai_check`, target `10`, unit `jumping jacks`.
- `Race to a 6-pack`: manual, target `20`, unit `sessions`.
- `Ship a side project`: manual, target `5`, unit `milestones`.
- `Most books read`: manual, target `10`, unit `books`.
- `30 days no scrolling`: manual, target `30`, unit `days`.

This path can still create manual/non-camera races, unlike the main create screen.

### Race Settings

File: `lib/features/races/presentation/race_settings_screen.dart`.

Settings exposes title, description, category, target, unit, start, finish, rules, visibility, archive, cancel, delete. Start/finish are raw text fields and sent as strings; there is no date picker or format validation. For non-camera races, the "Move method" dropdown is fixed to `unsupported movement` and does not allow manual configuration.

## Progress Submission Flow

1. Race Detail loads `Race` and resolves camera eligibility (`race_detail_screen.dart:286-295`).
2. If active, participant/owner, and camera-verifiable, primary action opens `/race/:id/proof`.
3. Submit Proof reloads race detail and resolves camera eligibility again.
4. Supported movement opens `/race/:id/proof/ai-motion`.
5. AI Motion Proof loads race, resolves movement, selects target from `race.targetValue` or activity default or `10`.
6. Camera starts on mobile with ML Kit pose detection. Web shows a static mobile-only placeholder.
7. `NuvoVerifyEngine` updates the selected validator per pose frame.
8. User finishes recording; validator returns `AiMotionResult`.
9. Only verified results auto-submit. Failed/partial results remain local and ask the user to try again.
10. `RaceApi.submitAiMotionProof()` posts to legacy `/races/:id/proof`.
11. Backend inserts a `move_logs` row. If status is verified, it increments `race_progress`.
12. Race Detail refreshes and displays the updated board/move log.

Duplicate submissions are not prevented. There is no idempotency key, session ID, uniqueness constraint, or client duplicate guard beyond UI state. A user can submit multiple verified sessions; each verified submission adds to the cumulative total. Partial failed sets are not persisted from the current UI, but the backend can store rejected/pending AI moves if called directly.

## Leaderboards, Ties, Completion, History

Leaderboard sorting:

- Backend response participants: `ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rm.joined_at ASC`.
- `recomputeRanks`: `ORDER BY progress_percent DESC, progress_value DESC, updated_at ASC`.
- Flutter Race Detail re-sorts only by `progressPercent DESC`.

Tie behavior is inconsistent:

- Backend query uses joined time as the final tie-breaker.
- Rank cache recompute uses updated time.
- Race Detail UI ignores both tie-breakers and sorts by percent only.

Completion:

- `race_progress.completed_at` is set when an individual's percent reaches 100.
- `races.status` is not automatically changed to `completed`.
- Arena treats a race as a result if the current user's progress is 100, even if the race status is still active.

History:

- `move_logs` stores every submitted/verified move.
- `race_progress` stores current cached progress only.
- Profile derives recent race history from race/proof data, not from a separate completed-races table.

## Hard-Coded Assumptions and Line References

- Default quick starts are hard-coded to five physical movements: `create_race_screen.dart:28-34`.
- Main create starts with the first quick start by default: `create_race_screen.dart:53`.
- Main create requires `parsed.aiSupported`; unsupported race ideas cannot be started: `create_race_screen.dart:64-67`.
- Main create always sends `goalType: manual`: `create_race_screen.dart:98`.
- Main create always sends AI proof settings for supported parsed ideas: `create_race_screen.dart:101-105`.
- Activity parsing uses first number in title and regex aliases: `motion_activity_catalog.dart:120-144`.
- Unsupported parsed unit defaults to raw `units`: `motion_activity.dart:60-63`.
- Catalog default targets: pushups/jumping jacks/squats/lunges `10`, plank `20`: `motion_activity_catalog.dart:3-50`.
- Validator default targets duplicate the catalog: `motion_validators.dart:39-76`.
- AI screen engine starts with first supported movement and target `10` before race load: `ai_motion_proof_screen_io.dart:38-42`.
- AI screen falls back to target `10` if no race target/catalog target exists: `ai_motion_proof_screen_io.dart:76-79`.
- `Race.effectiveAiActivityType` defaults to `jumping_jacks`: `race_models.dart:109-114`.
- `Race.isSupportedAiMotionRace` has its own supported set and title/unit fallback, inconsistent with catalog: `race_models.dart:91-107`.
- Camera resolver duplicates regex inference logic already in the catalog: `camera_verification_resolver.dart:126-153`.
- Backend `manual`/unknown race type maps to `first_to_target`: `server/worker/src/routes/races.ts:62-68`.
- Backend progress always increments cumulative value: `server/worker/src/routes/races.ts:133-155`.
- Progress percent is capped at 100 while raw value can exceed target: `server/worker/src/routes/races.ts:144-147`.
- Race status is not auto-completed when a participant finishes: `server/worker/src/routes/races.ts:148-157`.
- AI legacy proof activity defaults to `jumping_jacks` if omitted: `server/worker/src/routes/races.ts:665`.
- Manual proof is always verified by backend legacy endpoint: `server/worker/src/routes/races.ts:680-682`.
- Race Detail sorts participants by percent only: `race_detail_screen.dart:300-302`.
- Arena result state treats current user's 100% as result even if race status remains active: `arena_screen.dart:286-288`; backend mirrors this in `arena.ts:41-44`.
- Settings date fields are raw text from/to raw strings: `race_settings_screen.dart:83-84`, `race_settings_screen.dart:132-133`.
- User-facing technical/raw labels still exist: `race_settings_screen.dart:321` (`Unit`), `race_settings_screen.dart:355-358` (`Move method`, `unsupported movement`), `proof_review_screen.dart:277` (`Manual`), demo generator `demoArenaWorld.ts:155` (`Manual`).
- Seed scripts include legacy table/column logic after simplified schema migration: `seed-clickable-demo-world.sql:82-164`, `seed-clickable-demo-world.sql:169-320`; `demo_seed.sql:51-120`.

## Edge Cases

- Multiple sessions: supported and cumulative; every verified move adds progress.
- Exceeds goal: allowed; percent caps at 100, value keeps growing.
- Race ends while verifying: no explicit end-time check in proof submission; only `race.status === active` is enforced.
- Tied scores: tie behavior differs between backend response, rank cache, and Flutter sort.
- User joins late: allowed for active non-private direct join or invite code; progress starts at 0.
- User leaves race: non-creators can leave; membership status changes to `left`; progress row remains.
- Creator deletes race: soft delete via `deleted_at`; move history remains.
- Unsupported movement: current UI blocks camera proof and does not expose manual fallback.
- Camera loses detection: validators mark missing/low-confidence frames; plank timer pauses; rep validators do not count unknown frames.
- Partial valid reps: shown locally as failed/try again; not submitted by current UI.
- Timer-based race pause: plank timer pauses on invalid posture/detection.
- Race with no participants: normally creator/member row is created; UI handles empty board text if it occurs.

## Gap Against Target Conceptual Model

| Target concept | Current state |
|---|---|
| Activity | Partially present as frontend enums/catalog and backend `movement_type`; no backend activity catalog table. |
| Metric | Free-form unit strings only; no metric enum, conversion, or compatibility rules. |
| Competition format | String labels exist; behavior is always cumulative sum toward target. |
| Verification method | `verification_type` supports `movecheck`, `manual`, `photo`, `none`; active UI only supports camera path for verifiable motion, plus backend manual legacy path. |
| Schedule | `start_at`/`end_at` strings exist; no enforcement, windows, recurrence, or jobs found. |
| Scoring rule | Hard-coded cumulative sum for verified moves; no maximum attempt, minimum time, streak length, team sum, or session count engine. |

## Overall Distance From Flexible Physical Competition Platform

The app has the foundation for a race room, member list, move log, camera proof, and cumulative leaderboard. It is not yet a flexible competition platform. The main architectural missing piece is a first-class rule model that separates activity, metric, format, verification method, schedule, and scoring. Today those concerns are blended across title parsing, unit strings, proof requirement strings, movement validators, and cumulative progress updates.

The biggest risks before expanding formats are:

- inconsistent supported-movement definitions across layers;
- no scoring abstraction beyond cumulative sum;
- no enforcement of start/end windows;
- no idempotency or duplicate submission protection;
- no clean unsupported/manual fallback in current UI;
- stale demo seed logic using older schema concepts;
- tie and completion semantics differing between backend and Flutter.
