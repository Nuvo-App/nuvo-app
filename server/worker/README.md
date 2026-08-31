# nuvo-api — Cloudflare Worker

Nuvo backend: auth (email code + Google Sign-In), profile, and member pass.

## Stack

- Cloudflare Worker (TypeScript + Hono)
- Cloudflare D1 (SQLite)
- Resend (transactional email)
- Google Sign-In token verification

## Local setup

```bash
cd server/worker
npm install
cp .dev.vars.example .dev.vars
# Fill in .dev.vars with real values (never commit .dev.vars)
npx wrangler d1 migrations apply nuvo_db --local
npm run dev
```

The worker starts at `http://localhost:8787`.

## Remote deployment

Set secrets via Wrangler (never commit these):

```bash
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put JWT_SECRET
npx wrangler secret put GOOGLE_IOS_CLIENT_ID
```

Non-secret vars are set in `wrangler.toml` or as plain environment variables:

```bash
# RESEND_FROM_EMAIL and API_BASE_URL can go in wrangler.toml [vars] if not sensitive
```

Apply migrations and deploy:

```bash
npx wrangler d1 migrations apply nuvo_db --remote
npm run deploy
```

## Type-check

```bash
npm run typecheck
```

## Routes

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /health | — | Liveness check |
| POST | /auth/email/start | — | Send 6-digit email code |
| POST | /auth/email/verify | — | Verify code → tokens |
| POST | /auth/google | — | Google ID token → tokens |
| POST | /auth/refresh | — | Refresh → new access token |
| POST | /auth/logout | JWT | Revoke all sessions |
| GET | /auth/me | JWT | Current user object |
| DELETE | /auth/account | JWT | Soft-delete account |
| GET | /profile/me | JWT | Get profile |
| POST | /profile | JWT | Update profile fields |
| POST | /profile/username/check | JWT | Check username availability |
| POST | /onboarding/complete | JWT | Mark onboarding done |
| GET | /pass/me | JWT | Get member pass + share URL |
| GET | /races | JWT | List races created or joined by current user |
| POST | /races | JWT | Create race |
| POST | /races/join-code | JWT | Join race by invite code |
| GET | /races/:id | JWT | Get race detail |
| PATCH | /races/:id | JWT | Edit race settings (creator only) |
| POST | /races/:id/archive | JWT | Archive race (creator only) |
| POST | /races/:id/cancel | JWT | Cancel race (creator only) |
| DELETE | /races/:id | JWT | Soft-delete race (creator only) |
| POST | /races/:id/leave | JWT | Leave race (non-creator participant) |
| POST | /races/:id/join | JWT | Join directly joinable race |
| POST | /races/:id/invite-code | JWT | Create or return race invite code |
| POST | /races/:id/proof | JWT | Submit manual proof |
| GET | /races/:id/proofs | JWT | List race proofs |
| PATCH | /races/:id/proofs/:proofId | JWT | Review proof (creator only) |

## Token lifetimes

- Access token: 15 minutes (JWT, HMAC-SHA256)
- Refresh token: 30 days (random, stored as SHA-256 hash only)
- Email code: 10 minutes, max 5 attempts

## Environment variables

See `.dev.vars.example` for the full list.
Secrets go in `.dev.vars` locally and `wrangler secret put` for remote.
