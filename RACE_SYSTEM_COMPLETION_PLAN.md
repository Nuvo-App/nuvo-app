# Race System Completion Plan

## Existing Race Backend
- Routes found:
  - `GET /races`
  - `POST /races`
  - `GET /races/:id`
  - `POST /races/:id/proof`
  - `GET /races/:id/proofs`
- Tables found:
  - `races`
  - `race_participants`
  - `proofs`
- Missing routes:
  - `PATCH /races/:id`
  - `POST /races/:id/archive`
  - `POST /races/:id/cancel`
  - `DELETE /races/:id`
  - `POST /races/:id/leave`
  - `POST /races/:id/join`
  - `POST /races/:id/invite-code`
  - `POST /races/join-code`
  - `PATCH /races/:id/proofs/:proofId`

## Existing Flutter Race UI
- Screens found:
  - `ArenaScreen`
  - `CompeteScreen`
  - `CreateRaceScreen`
  - `RaceDetailScreen`
  - `SubmitProofScreen`
  - legacy `ProofScreen` bridge
- Providers/controllers found:
  - `RaceApi`
  - `RaceRepository`
  - `RaceController`
  - `raceControllerProvider`
- Missing screens:
  - race editor/settings
  - invite crew / invite code
  - join race by code
  - proof review UI

## Missing Race Actions
- Edit race: missing backend route and Flutter editor.
- Archive race: missing backend route and owner UI.
- Cancel race: missing backend route and owner UI.
- Delete race: missing soft-delete route and danger-zone UI.
- Leave race: missing backend route and participant UI.
- Invite crew: missing invite-code table/route and invite UI.
- Proof review: missing proof status review route and owner UI.
- Race settings: missing full settings screen with proof/visibility/lifecycle controls.

## UI Polish Gaps
- Buttons needing Nuvo backplate:
  - `Save changes`
  - `Archive race`
  - `Cancel race`
  - `Delete race`
  - `Invite crew`
  - `Copy invite code`
  - `Share race`
  - `Join race`
  - `Review proof`
- Screens needing stronger CTA treatment:
  - Race detail action area
  - Race settings lifecycle/danger zone
  - Invite crew
  - Join race
- Empty states needing polish:
  - no crew
  - no proof
  - no completed races / archived races

## Implementation Order
1. Add D1 migration for race completion fields, race invites, and proof review metadata. Done in `0003_race_system_completion.sql`.
2. Extend Worker race routes with owner checks, lifecycle actions, invite codes, join/leave, and proof review. Done in `server/worker/src/routes/races.ts`.
3. Extend Flutter race models, API, repository, and controller methods. Done in `lib/features/races/data/*` and `race_controller.dart`.
4. Add race settings/editor, invite crew, join race, and proof review screens/routes. Done.
5. Update race detail owner/participant actions and honest empty states. Done.
6. Polish Nuvo button variants and replace important raw/default button usage where in scope. Done.
7. Update audits/checklists and run backend + Flutter verification commands. In progress.

## Implemented Routes
- `PATCH /races/:id`
- `POST /races/:id/archive`
- `POST /races/:id/cancel`
- `DELETE /races/:id`
- `POST /races/:id/leave`
- `POST /races/:id/join`
- `POST /races/:id/invite-code`
- `POST /races/join-code`
- `PATCH /races/:id/proofs/:proofId`

## Implemented Flutter Screens
- `lib/features/races/presentation/race_settings_screen.dart`
- `lib/features/races/presentation/invite_crew_screen.dart`
- `lib/features/races/presentation/join_race_screen.dart`
- `lib/features/races/presentation/proof_review_screen.dart`

## Verification Notes
- `npm run typecheck` passed after Worker route changes.
- `flutter analyze` passed after Flutter route/screen/API changes.
- Remote migration/deploy and launch checks are tracked in `QA_CHECKLIST.md`.
