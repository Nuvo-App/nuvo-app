# Data, auth, and Cloudflare backend

## Client data flow

The client uses a thin API/repository split:

```text
screen/provider → repository → API client → Worker endpoint
                              ↑
                       secure token store
```

Auth files are contract-sensitive:

- `lib/features/auth/data/auth_api.dart`: HTTP and JSON mapping for auth/profile/pass endpoints.
- `auth_repository.dart`: token injection, refresh/session restore, and API-to-domain handoff.
- `secure_token_store.dart`: platform storage.
- `auth_controller.dart`: Riverpod state machine.
- `auth_gate.dart`: redirects.

Race files follow the same pattern through `race_api.dart`, `race_repository.dart`, and `race_controller.dart`.

## Worker/D1

The backend is `server/worker/`:

- `src/index.ts`: Worker/Hono composition and middleware.
- `src/routes/`: auth, profile, pass, crew, races, arena, users, and reports.
- `src/domain/`: race validation, lifecycle, scoring, ranking, and activities.
- `src/lib/`: JWT/crypto, privacy, response, validation, email, and provider helpers.
- `migrations/`: ordered D1 schema changes.

The Worker README and `docs/API_CONTRACT.md` are the endpoint references. The client JSON fields must remain aligned with Worker responses. A backend migration is not “just a code cleanup”: it needs local migration testing, compatibility review, and an explicit deployment decision.

## Auth and privacy rules

- Access tokens are short-lived; refresh tokens are stored hashed server-side.
- Do not log tokens, email codes, camera frames, or private profile data.
- Keep secrets in `.dev.vars` locally or Wrangler secrets remotely; never commit them.
- Treat camera/pose data as sensitive. Store only what the product contract requires.
- Auth changes require tests for sign-in, verification failure, refresh, restore, logout, expired sessions, and route redirects.

## Environment and deployment distinction

Flutter local app, Worker local dev, D1 local, D1 remote, and deployed Worker are separate environments. Verify the API base URL and D1 target before any data-affecting command. Read-only health checks are safe; migrations and deploys require explicit release scope.
