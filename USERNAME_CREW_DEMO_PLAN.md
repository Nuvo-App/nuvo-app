# Username Crew Demo Plan

## Implemented
- `GET /users/search?q=` searches username, member ID, display name, and safe email prefix.
- `GET /crew`, `POST /crew/add`, and `DELETE /crew/:userId` are live.
- Crew tab uses real member pass data, real search results, and real crew connections.
- Current user is excluded from search and cannot add self.

## Demo Flow
- Phone 1 opens Crew.
- Search Phone 2 by username or member ID.
- Tap Add.
- Phone 2 appears under Your crew.

## Verification
- Worker typecheck passed.
- Remote D1 migration `0005_demo_social_ai.sql` applied.
- Worker deployed and `/health` returned OK.
