# Multi-Phone Demo Plan

## Implemented
- `POST /races/:id/participants` adds a real user to an active race.
- `GET /races` already returns participant races, so added users can see races after refresh.
- Invite Crew can add by search, add from existing crew, and still shows the invite code fallback.
- Race Detail continues polling every 5 seconds.

## Demo Flow
- Phone 1 creates a race.
- Phone 1 opens Pull in your crew.
- Phone 1 adds Phone 2 from search or Your crew.
- Phone 2 refreshes Arena and opens the race.
- Phone 1 submits proof.
- Phone 2 waits for polling or pulls to refresh and sees leaderboard progress.

## Verification
- Backend typecheck passed.
- Remote migration and Worker deploy completed.
- Physical two-phone validation was not run in this Codex session.
