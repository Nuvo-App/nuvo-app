# Demo Social + AI Pass Plan

## Goals
- Add/find users by username/member ID.
- Add users to crew.
- Add crew/users to a race.
- Multi-phone race visibility works.
- Typed movement races auto-detect AI Motion Proof support.
- AI supports multiple movement validators.

## Existing Pieces Found
- Email auth, profile, member pass, race creation, invite codes, race participants, proof submission, and race auto-refresh already exist.
- `GET /races` already returns races created by or joined by the current user.
- Proof rows already store AI Motion Proof metadata.
- Flutter already has Race API/repository/controller layers and a real camera/ML Kit pose flow for jumping jacks.
- Crew/search UI is present but not backed by real crew data yet.

## Backend Changes
- Add `crew_connections` table.
- Add race-level AI metadata fields: `ai_activity_type`, `target_unit`, and `proof_mode`.
- Add authenticated user search at `GET /users/search?q=...`.
- Add authenticated crew endpoints: `GET /crew`, `POST /crew/add`, `DELETE /crew/:userId`.
- Add `POST /races/:id/participants` for adding a searched user or crew user to a race.

## Flutter Changes
- Add public user/crew models and repository/controller methods for search, crew, and race participant add.
- Update Crew tab to show member pass, search, add buttons, and real crew list.
- Update Invite Crew to support search, existing crew, and invite code fallback.
- Add motion activity catalog and natural typed race parser.
- Update Create Race to use one typed race idea field and detect AI support automatically.
- Replace hardcoded jumping-jack AI proof with a validator registry and activity-specific labels.

## Demo Test Plan
- Search by username/member ID and add another account to crew.
- Create typed races: `10 jumping jacks`, `10 squats`, `20 high knees`, `10 arm raises`, `20 second plank`.
- Confirm `100 pushups` stays manual.
- Add another account to a race from Invite Crew.
- Confirm the second account sees the race in Arena after refresh.
- Submit AI proof from the first phone and confirm leaderboard progress refreshes on the second phone.
