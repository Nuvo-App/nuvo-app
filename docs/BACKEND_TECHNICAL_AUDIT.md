# Nuvo Backend Technical Audit

**Scope:** This document is a complete, read-only audit of the Nuvo backend as it exists today. No code was changed to produce it. It is written for a human who wants to own the backend and perform manual operations in the Cloudflare dashboard.

**Last inspected:** `server/worker/` source code and migrations.

**Key infrastructure:**
- **Cloudflare Worker:** `nuvo-api` (`src/index.ts`)
- **Production domain:** `https://nuvo-api.getnuvoapp.workers.dev`
- **Cloudflare D1 database:** `nuvo_db`, binding `DB`
- **Cloudflare R2 bucket:** `nuvor2`, binding `PROFILE_PHOTOS`
- **Email provider:** Resend (`no-reply@getnuvo.net`)
- **Auth providers:** Email OTP, Google Sign-In

---

## 1. Cloudflare D1 — Every Table

There are **12 active tables** plus `audit_events` which is defined but never used.

All primary keys are `TEXT` and use `crypto.randomUUID()` values generated in the Worker. All timestamp columns store ISO-8601 strings (e.g., `2025-01-15T10:30:00.000Z`).

### Table: `users`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | The internal user ID used everywhere else |
| `primary_email` | TEXT UNIQUE | Normalized lowercase email |
| `status` | TEXT NOT NULL DEFAULT 'active' | `'active'` or `'deleted'` |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | Account creation time |
| `updated_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | Last update time |
| `last_login_at` | TEXT | Last successful login |
| `demo_world_enabled` | INTEGER NOT NULL DEFAULT 0 | SQL-only demo flag (migration 0006) |
| `demo_world_seed` | TEXT | Optional seed for deterministic demo data |
| `demo_world_variant` | TEXT DEFAULT 'summer_v1' | Demo theme variant |

**What it stores:** One row per account. This is the root identity row.

**Why it exists:** Every other entity references this ID.

**Who writes:** `POST /auth/email/verify`, `POST /auth/google`, `DELETE /auth/account`.

**Who reads:** Almost every route (via JWT `sub` claim), `/users/search`, `/crew`, `/races`.

**Read-only?** No.

**Example rows:**
```
id: "550e8400-e29b-41d4-a716-446655440000"
primary_email: "alex@example.com"
status: "active"
created_at: "2025-01-10T14:22:00.000Z"
updated_at: "2025-01-15T09:00:00.000Z"
last_login_at: "2025-01-15T09:00:00.000Z"
demo_world_enabled: 0
demo_world_seed: NULL
demo_world_variant: "summer_v1"
```

### Table: `auth_identities`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `user_id` | TEXT NOT NULL | FK → `users(id)` |
| `provider` | TEXT NOT NULL | `'email'` or `'google'` |
| `provider_user_id` | TEXT | Google `sub`; NULL for email |
| `email` | TEXT | Stored email for this identity |
| `email_verified` | INTEGER NOT NULL DEFAULT 0 | 1 after verification |
| `display_name` | TEXT | Google name |
| `avatar_url` | TEXT | Google picture URL (not used by app currently) |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (`provider`, `provider_user_id`) | |

**What it stores:** Login methods attached to a user account.

**Why it exists:** Allows the same user to log in via email or Google, and links Google `sub` to the internal user.

**Who writes:** `POST /auth/email/verify` (creates `email` identity), `POST /auth/google` (creates/updates `google` identity).

**Who reads:** Not directly read by any current route after creation. It is a lookup table used during login to avoid duplicates.

**Read-only?** No (updated on Google re-login).

**Example rows:**
```
id: "..."
user_id: "550e8400-e29b-41d4-a716-446655440000"
provider: "google"
provider_user_id: "1234567890"
email: "alex@example.com"
email_verified: 1
display_name: "Alex Chen"
avatar_url: "https://lh3.googleusercontent.com/..."
created_at: "2025-01-10T14:22:00.000Z"
```

### Table: `email_codes`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `email` | TEXT NOT NULL | Lowercase target email |
| `code_hash` | TEXT NOT NULL | SHA-256 of the 6-digit OTP |
| `attempts` | INTEGER NOT NULL DEFAULT 0 | Count of verification attempts |
| `expires_at` | TEXT NOT NULL | ISO timestamp when code expires |
| `used_at` | TEXT | Timestamp when successfully consumed |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Email login OTPs (hashed, not plaintext).

**Why it exists:** Passwordless email login.

**Who writes:** `POST /auth/email/start` (insert), `POST /auth/email/verify` (updates `attempts`, then `used_at`).

**Who reads:** `POST /auth/email/verify` only.

**Read-only?** No.

**Example rows:**
```
id: "..."
email: "alex@example.com"
code_hash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
attempts: 1
expires_at: "2025-01-15T09:10:00.000Z"
used_at: "2025-01-15T09:05:00.000Z"
created_at: "2025-01-15T09:00:00.000Z"
```

### Table: `sessions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `user_id` | TEXT NOT NULL | FK → `users(id)` |
| `refresh_token_hash` | TEXT NOT NULL | SHA-256 of the refresh token |
| `device_label` | TEXT | Optional device name |
| `expires_at` | TEXT NOT NULL | ISO timestamp |
| `revoked_at` | TEXT | Set on logout or account deletion |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| `last_seen_at` | TEXT | Updated on token refresh |

**What it stores:** Active and revoked refresh token sessions.

**Why it exists:** Long-lived sessions without storing plaintext tokens.

**Who writes:** `POST /auth/email/verify`, `POST /auth/google` (insert), `POST /auth/refresh` (updates `last_seen_at`), `POST /auth/logout`, `DELETE /auth/account` (sets `revoked_at`).

**Who reads:** `POST /auth/refresh`.

**Read-only?** No.

**Example rows:**
```
id: "..."
user_id: "550e8400-e29b-41d4-a716-446655440000"
refresh_token_hash: "abc123..."
device_label: "iPhone 15"
expires_at: "2025-02-14T09:00:00.000Z"
revoked_at: NULL
created_at: "2025-01-15T09:00:00.000Z"
last_seen_at: "2025-01-15T09:00:00.000Z"
```

### Table: `profiles`

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | TEXT PRIMARY KEY | FK → `users(id)` |
| `full_name` | TEXT | Display name |
| `username` | TEXT UNIQUE | 3-20 lowercase letters/digits/underscores |
| `avatar_url` | TEXT | Public URL to profile photo in R2 |
| `private_profile` | INTEGER NOT NULL DEFAULT 0 | Currently unused by app |
| `onboarding_complete` | INTEGER NOT NULL DEFAULT 0 | 1 after `POST /onboarding/complete` |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Public identity and onboarding state.

**Why it exists:** Separates auth identity from public profile; `username` must be unique.

**Who writes:** `ensureProfileAndPass()` called at login (insert if missing), `POST /profile` (update), `POST /onboarding/complete`.

**Who reads:** `/auth/me`, `/profile/me`, `/users/search`, `/crew`, `/races/*`, `/arena`.

**Read-only?** No.

**Example rows:**
```
user_id: "550e8400-e29b-41d4-a716-446655440000"
full_name: "Alex Chen"
username: "alexc"
avatar_url: "https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/profile-photos/550e8400-e29b-41d4-a716-446655440000/1705312800000.jpg"
private_profile: 0
onboarding_complete: 1
created_at: "2025-01-10T14:22:00.000Z"
updated_at: "2025-01-15T09:00:00.000Z"
```

### Table: `member_passes`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `user_id` | TEXT NOT NULL UNIQUE | FK → `users(id)` |
| `member_id` | TEXT NOT NULL UNIQUE | e.g., `NUVO-A3B9K2` |
| `pass_slug` | TEXT NOT NULL UNIQUE | e.g., `a3b9k2` |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** A generated identity card / QR code for each user.

**Why it exists:** Provides a short, shareable member ID and slug for QR passes.

**Who writes:** `ensureProfileAndPass()` at login.

**Who reads:** `/pass/me`, `/users/search`, `/crew`.

**Read-only?** No, but treat it as effectively immutable. If you change `member_id` or `pass_slug`, existing QR shares and friend searches break.

**Example rows:**
```
id: "..."
user_id: "550e8400-e29b-41d4-a716-446655440000"
member_id: "NUVO-A3B9K2"
pass_slug: "a3b9k2"
created_at: "2025-01-10T14:22:00.000Z"
```

### Table: `audit_events`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `user_id` | TEXT | FK → `users(id)` |
| `event_type` | TEXT NOT NULL | Free-text event name |
| `metadata` | TEXT | JSON string or free text |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Audit log events.

**Why it exists:** Reserved for security/audit logging.

**Who writes:** No current route writes to it.

**Who reads:** No current route reads it.

**Read-only?** Effectively unused. Safe to leave empty.

**Legacy/unused?** Yes — defined in initial migration but never used.

### Table: `races`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `creator_id` | TEXT NOT NULL | FK → `users(id)` |
| `title` | TEXT NOT NULL | Race name |
| `description` | TEXT | Optional description |
| `category` | TEXT | e.g., "fitness", "school" |
| `goal_type` | TEXT NOT NULL DEFAULT 'manual' | Currently freeform string |
| `target_value` | INTEGER | Finish-line numeric target |
| `unit` | TEXT | e.g., "reps", "days" |
| `ai_activity_type` | TEXT | AI motion activity name |
| `target_unit` | TEXT | Redundant with `unit` |
| `proof_mode` | TEXT | Redundant with `proof_requirement` |
| `status` | TEXT NOT NULL DEFAULT 'active' | `'active'`, `'archived'`, `'cancelled'` |
| `start_line_at` | TEXT | ISO start time (optional) |
| `finish_line_at` | TEXT | ISO end time (optional) |
| `rules` | TEXT | Freeform rules text |
| `proof_requirement` | TEXT NOT NULL DEFAULT 'manual' | `'manual'`, `'photo_video'`, `'ai_check'` |
| `proof_review_mode` | TEXT NOT NULL DEFAULT 'auto_accept' | `'auto_accept'`, `'owner_review'`, `'ai_review'` |
| `visibility` | TEXT NOT NULL DEFAULT 'private' | `'private'`, `'crew_only'`, `'invite_code'` |
| `deleted_at` | TEXT | Soft-delete timestamp |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| `updated_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Race definitions and settings.

**Why it exists:** Central table for every race.

**Who writes:** `POST /races` (create), `PATCH /races/:id` (edit), `POST /races/:id/archive`, `POST /races/:id/cancel`, `DELETE /races/:id` (soft delete).

**Who reads:** `GET /races`, `GET /races/:id`, `GET /arena`, `/races/:id/*`.

**Read-only?** No.

**Example rows:**
```
id: "660e8400-e29b-41d4-a716-446655440000"
creator_id: "550e8400-e29b-41d4-a716-446655440000"
title: "First to 100 Pushups"
description: "Daily pushup race"
category: "fitness"
goal_type: "first_to_finish"
target_value: 100
unit: "reps"
ai_activity_type: NULL
target_unit: "reps"
proof_mode: "manual"
status: "active"
start_line_at: NULL
finish_line_at: NULL
rules: "No half reps"
proof_requirement: "manual"
proof_review_mode: "auto_accept"
visibility: "private"
deleted_at: NULL
created_at: "2025-01-12T10:00:00.000Z"
updated_at: "2025-01-12T10:00:00.000Z"
```

### Table: `race_participants`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `race_id` | TEXT NOT NULL | FK → `races(id)` |
| `user_id` | TEXT NOT NULL | FK → `users(id)` |
| `display_name` | TEXT | Cached copy of profile `full_name` at join time |
| `progress_value` | INTEGER NOT NULL DEFAULT 0 | Accumulated raw progress |
| `progress_percent` | INTEGER NOT NULL DEFAULT 0 | `min(100, round(value/target*100))` |
| `joined_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (`race_id`, `user_id`) | One participant row per user per race |

**What it stores:** Membership and leaderboard position for each race.

**Why it exists:** This is the leaderboard. Race detail and arena sort by `progress_percent DESC, progress_value DESC, joined_at ASC`.

**Who writes:** `ensureParticipant()` (called by create, join, proof submit), `POST /races/:id/leave` (delete), `applyProofProgress()` (updates progress).

**Who reads:** `GET /races`, `GET /races/:id`, `GET /arena`.

**Read-only?** No.

**Example rows:**
```
id: "..."
race_id: "660e8400-e29b-41d4-a716-446655440000"
user_id: "550e8400-e29b-41d4-a716-446655440000"
display_name: "Alex Chen"
progress_value: 45
progress_percent: 45
joined_at: "2025-01-12T10:00:00.000Z"
```

### Table: `proofs`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `race_id` | TEXT NOT NULL | FK → `races(id)` |
| `user_id` | TEXT NOT NULL | FK → `users(id)` |
| `proof_type` | TEXT NOT NULL DEFAULT 'manual' | `'manual'`, `'ai_motion'` |
| `ai_activity_type` | TEXT | e.g., `jumping_jacks` |
| `note` | TEXT | Optional user note |
| `value` | INTEGER | Progress increment applied to leaderboard |
| `detected_value` | INTEGER | AI-detected rep count |
| `target_value` | INTEGER | AI target reps |
| `confidence` | REAL | 0.0–1.0 AI confidence |
| `validator_version` | TEXT | e.g., `nuvo-ai-motion-v1` |
| `frames_analyzed` | INTEGER | AI stats |
| `valid_pose_frames` | INTEGER | AI stats |
| `duration_ms` | INTEGER | AI stats |
| `verification_status` | TEXT NOT NULL DEFAULT 'accepted' | See status list below |
| `verification_summary` | TEXT | Human-readable summary |
| `reviewed_by` | TEXT | User ID of reviewer |
| `reviewed_at` | TEXT | ISO timestamp |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Every proof submission and its review/AI status.

**Why it exists:** Audit trail for every progress update; powers leaderboard updates.

**Who writes:** `POST /races/:id/proof`, `PATCH /races/:id/proofs/:proofId`.

**Who reads:** `GET /races/:id`, `GET /races/:id/proofs`.

**Read-only?** No.

**Verification statuses:**
- `submitted` — pending owner review
- `accepted` — counts toward progress
- `rejected` — does not count
- `needs_review` — AI motion awaiting review
- `ai_check_pending` — reserved
- `ai_verified` — AI approved, counts toward progress
- `ai_failed` — AI rejected

**Example rows:**
```
id: "..."
race_id: "660e8400-e29b-41d4-a716-446655440000"
user_id: "550e8400-e29b-41d4-a716-446655440000"
proof_type: "manual"
note: "Morning set"
value: 20
detected_value: NULL
target_value: NULL
confidence: NULL
validator_version: NULL
frames_analyzed: NULL
valid_pose_frames: NULL
duration_ms: NULL
verification_status: "accepted"
verification_summary: "Manual proof accepted. AI validation coming soon."
reviewed_by: NULL
reviewed_at: NULL
created_at: "2025-01-13T08:00:00.000Z"
```

### Table: `race_invites`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `race_id` | TEXT NOT NULL | FK → `races(id)` |
| `created_by` | TEXT NOT NULL | FK → `users(id)` |
| `invite_code` | TEXT NOT NULL UNIQUE | e.g., `NUV-A3B9K2` |
| `status` | TEXT NOT NULL DEFAULT 'active' | `'active'` or `'disabled'` |
| `expires_at` | TEXT | Optional expiration |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |

**What it stores:** Active invite codes for races.

**Why it exists:** Allows users to join private races with short codes.

**Who writes:** `POST /races/:id/invite-code`.

**Who reads:** `POST /races/join-code`, `GET /races/:id` (returns active code).

**Read-only?** No.

**Example rows:**
```
id: "..."
race_id: "660e8400-e29b-41d4-a716-446655440000"
created_by: "550e8400-e29b-41d4-a716-446655440000"
invite_code: "NUV-A3B9K2"
status: "active"
expires_at: NULL
created_at: "2025-01-12T10:05:00.000Z"
```

### Table: `crew_connections`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PRIMARY KEY | UUID |
| `user_id` | TEXT NOT NULL | FK → `users(id)` |
| `crew_user_id` | TEXT NOT NULL | FK → `users(id)` |
| `status` | TEXT NOT NULL DEFAULT 'active' | `'active'` or `'removed'` |
| `created_at` | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | |
| UNIQUE | (`user_id`, `crew_user_id`) | |

**What it stores:** One-directional social graph edges.

**Why it exists:** A user's "crew" is the set of `crew_user_id` rows where `user_id = me` and `status = 'active'`.

**Who writes:** `POST /crew/add` (inserts both directions), `DELETE /crew/:userId` (sets `status = 'removed'`).

**Who reads:** `GET /crew`, `/users/search` (filters by `status='active'`).

**Read-only?** No.

**Example rows:**
```
id: "..."
user_id: "550e8400-e29b-41d4-a716-446655440000"
crew_user_id: "770e8400-e29b-41d4-a716-446655440000"
status: "active"
created_at: "2025-01-11T09:00:00.000Z"
```

---

## 2. Indexes and Constraints Summary

### Indexes

| Index | Table | Purpose |
|-------|-------|---------|
| `idx_users_email` | users | Login by email |
| `idx_users_status` | users | Filter active/deleted users |
| `idx_auth_identities_user_id` | auth_identities | Find identities for a user |
| `idx_auth_identities_provider` | auth_identities | Find user by Google sub |
| `idx_email_codes_email` | email_codes | Look up active code |
| `idx_email_codes_expires` | email_codes | Cleanup/pagination |
| `idx_sessions_user_id` | sessions | List/revoke user's sessions |
| `idx_sessions_token_hash` | sessions | Refresh lookup |
| `idx_sessions_expires` | sessions | Expired session cleanup |
| `idx_profiles_username` | profiles | Username availability |
| `idx_member_passes_slug` | member_passes | QR pass lookup (unused by code currently) |
| `idx_audit_events_user_id` | audit_events | Reserved |
| `idx_audit_events_created` | audit_events | Reserved |
| `idx_races_creator` | races | List races by creator |
| `idx_races_deleted_at` | races | Hide soft-deleted races |
| `idx_race_participants_race` | race_participants | Leaderboard query |
| `idx_race_participants_user` | race_participants | Races a user joined |
| `idx_proofs_race` | proofs | Recent proofs for race |
| `idx_proofs_user` | proofs | User's proof history |
| `idx_proofs_reviewed_by` | proofs | Reserved |
| `idx_race_invites_code` | race_invites | Join by code |
| `idx_race_invites_race` | race_invites | Active code for race |
| `idx_crew_connections_user` | crew_connections | Get my crew |
| `idx_crew_connections_crew_user` | crew_connections | Reverse lookup |

### Foreign Keys

| Child Table | Column | Parent Table | On Delete |
|-------------|--------|--------------|-----------|
| auth_identities | user_id | users | None (SQLite default: RESTRICT) |
| sessions | user_id | users | None |
| profiles | user_id | users | None |
| member_passes | user_id | users | None |
| races | creator_id | users | None |
| race_participants | race_id | races | None |
| race_participants | user_id | users | None |
| proofs | race_id | races | None |
| proofs | user_id | users | None |
| race_invites | race_id | races | None |
| race_invites | created_by | users | None |
| crew_connections | user_id | users | None |
| crew_connections | crew_user_id | users | None |

**Critical implication:** There are no `ON DELETE CASCADE` rules. If you delete a user from `users`, SQLite will block the delete unless all child rows are removed first. If you delete a race, `race_participants`, `proofs`, and `race_invites` rows remain (they just reference a missing race).

---

## 3. Read-Only, Active, Legacy, and Unused Tables

| Table | Status | Notes |
|-------|--------|-------|
| `users` | Active write | Created at login, soft-deleted via `status` |
| `auth_identities` | Active write | Created on first email/Google login |
| `email_codes` | Active write | OTPs are single-use but rows stay forever |
| `sessions` | Active write | Created, refreshed, revoked |
| `profiles` | Active write | Updated by profile edits and onboarding |
| `member_passes` | Active write | Created once at first login |
| `audit_events` | **Legacy/unused** | Defined but never written or read |
| `races` | Active write | Created and edited by creators |
| `race_participants` | Active write | Join/leave/progress updates |
| `proofs` | Active write | Submit and review |
| `race_invites` | Active write | Codes created on demand |
| `crew_connections` | Active write | Add/remove crew |

### Important: unused columns

| Column | Status | Why |
|--------|--------|-----|
| `proofs.media_url` | **Unused** | Photo/video proof is not implemented; no route writes this |
| `profiles.private_profile` | **Unused in app** | Stored and returned but no UI consumes it |
| `races.start_line_at`, `finish_line_at` | **Mostly unused** | Stored but app does not enforce start/end dates |
| `races.category` | **Optional metadata** | Passed through but not validated |
| `races.ai_activity_type`, `target_unit`, `proof_mode` | **Redundant** | Duplicates or shadows `proof_requirement`/`unit` |
| `users.demo_world_*` | **SQL-only flags** | Enable per-account synthetic arena data |

---

## 4. Which Tables Power Which App Screens

| Screen | Primary tables | How |
|--------|----------------|-----|
| **Welcome / Email login** | `users`, `email_codes`, `auth_identities`, `sessions` | OTP create → verify → user/identity/profile/pass/session create |
| **Google login** | `users`, `auth_identities`, `sessions` | Verify Google token → upsert user/identity → session |
| **Onboarding** | `profiles` | `POST /profile` saves name/username/photo; `POST /onboarding/complete` sets flag |
| **Profile** | `profiles`, `users`, `member_passes` | `GET /profile/me`, `GET /pass/me`, `GET /auth/me` |
| **Pass / QR** | `member_passes` | `GET /pass/me` returns `memberId` and `shareUrl` |
| **Arena** | `races`, `race_participants`, `profiles`, `users` | `GET /arena` builds snapshot from races I created/joined |
| **Compete → Create Race** | `races`, `race_participants` | `POST /races` inserts race + creator participant |
| **Compete → Join Race** | `races`, `race_invites`, `race_participants` | `POST /races/join-code` or `POST /races/:id/join` |
| **Race Detail** | `races`, `race_participants`, `proofs`, `profiles`, `race_invites` | `GET /races/:id` returns full response with leaderboard and recent proofs |
| **Submit Proof** | `proofs`, `race_participants` | `POST /races/:id/proof` inserts proof and applies progress |
| **AI Motion Proof** | `proofs` | Same endpoint with `proofType: 'ai_motion'` and AI fields |
| **Proof Review** | `proofs`, `race_participants` | `PATCH /races/:id/proofs/:proofId` updates status; applies progress if accepted |
| **Crew** | `crew_connections`, `users`, `profiles`, `member_passes` | `GET /crew`, `POST /crew/add`, `DELETE /crew/:userId` |
| **User Search** | `users`, `profiles`, `member_passes` | `GET /users/search?q=` |

---

## 5. Cloudflare R2

### Bucket

- **Bucket name:** `nuvor2`
- **Worker binding:** `PROFILE_PHOTOS`
- **Public domain:** `https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/...`

### Folder/path conventions

Only one logical folder is used today:

```
profile-photos/{userId}/{timestamp}.{ext}
```

Examples:
```
profile-photos/550e8400-e29b-41d4-a716-446655440000/1705312800000.jpg
profile-photos/770e8400-e29b-41d4-a716-446655440000/1705316400000.png
```

### What is stored

- **Profile photos only.**
- Race images are not stored in R2.
- Verification media is not stored in R2 (AI Motion Proof happens on-device and only the result is sent to the Worker).
- There is no temporary-file folder.

### Naming convention

- `userId` = the user's UUID from `users.id`
- `timestamp` = `Date.now()` milliseconds at upload time (e.g., `1705312800000`)
- `ext` = normalized extension: `jpg`, `png`, or `webp` (`jpeg` becomes `jpg`)

### Upload flow

The Worker does **not** accept direct image uploads with auth. It uses signed upload tokens to keep the public bucket write-protected.

1. **Client requests upload URL**
   - `POST /profile/photo/upload-url`
   - Body: `{ fileName, contentType }`
   - Worker verifies auth, creates key `profile-photos/{userId}/{Date.now()}.{ext}`
   - Worker signs an HMAC-SHA256 token (10-minute expiry) containing `key` and `contentType`
   - Returns `{ uploadUrl, publicUrl, key }`

2. **Client uploads to R2**
   - PUT/POST to `/profile/photo/upload?token={signedToken}`
   - No auth header needed; the signed token is the credential
   - Worker verifies token signature and expiry, checks `key` starts with `profile-photos/`
   - Worker writes bytes to R2 with `contentType` metadata
   - Returns `{ ok: true, key }`

3. **Client saves public URL**
   - `POST /profile` with `{ profilePhotoUrl: publicUrl }`
   - Worker writes the public URL to `profiles.avatar_url`

### Download / visibility flow

- The client uses the `publicUrl` directly: `https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/profile-photos/{userId}/{timestamp}.{ext}`
- `GET /profile/photo/object/*` streams the object from R2 with `Cache-Control: public, max-age=31536000, immutable`
- The path is AWS-style URL-encoded.

### Delete flow

- There is **no API endpoint** to delete a profile photo from R2 today.
- The client can "remove" the photo by sending `profilePhotoUrl: null` to `POST /profile`, which sets `profiles.avatar_url = NULL`. The object remains in R2.

### Cleanup logic

- None. Orphaned profile photos (when a user deletes their account or replaces their photo) are not cleaned up automatically.

### How an uploaded image becomes visible in the app

```
User picks photo
    ↓
Flutter app → POST /profile/photo/upload-url
    ↓
Worker returns uploadUrl + publicUrl
    ↓
Flutter app → PUT uploadUrl (uploads bytes to R2 via /profile/photo/upload?token=...)
    ↓
R2 stores object at profile-photos/{userId}/{timestamp}.{ext}
    ↓
Flutter app → POST /profile { profilePhotoUrl: publicUrl }
    ↓
Worker writes publicUrl to profiles.avatar_url
    ↓
Arena, Race Detail, Crew, Profile read profiles.avatar_url and display the image
```

---

## 6. Workers

There is **one Worker** named `nuvo-api`. It is a single Cloudflare Worker (Hono app) mounted at `src/index.ts`. The "Workers" plural in the request refers to this one service plus its routers.

### Worker: `nuvo-api`

**Purpose:** All backend API services: health, auth, profile, member pass, social graph, races, arena.

**Entry point:** `server/worker/src/index.ts`

**Routers mounted:**
- `/auth` → `auth.ts`
- `/profile` → `profile.ts`
- `/pass` → `pass.ts`
- `/users` → `users.ts`
- `/crew` → `crew.ts`
- `/races` → `races.ts`
- `/arena` → `arena.ts`
- `POST /onboarding/complete` (inline in `index.ts`)
- `GET /health` (inline in `index.ts`)

### Environment variables / bindings

| Name | Type | Purpose |
|------|------|---------|
| `DB` | D1Database | All SQL operations |
| `PROFILE_PHOTOS` | R2Bucket | Profile photo storage |
| `JWT_SECRET` | secret | HMAC-SHA256 signing for access tokens and upload tokens |
| `GOOGLE_IOS_CLIENT_ID` | secret | Google iOS client ID for token verification |
| `RESEND_API_KEY` | secret | Send email OTPs |
| `RESEND_FROM_EMAIL` | plain var | `no-reply@getnuvo.net` |
| `API_BASE_URL` | secret/var | Base URL for absolute links |

### Route reference

| Method | Route | Auth | Handler file | Tables touched |
|--------|-------|------|--------------|----------------|
| GET | `/health` | — | `index.ts` | None |
| POST | `/auth/email/start` | — | `auth.ts` | `email_codes` |
| POST | `/auth/email/verify` | — | `auth.ts` | `email_codes`, `users`, `auth_identities`, `profiles`, `member_passes`, `sessions` |
| POST | `/auth/google` | — | `auth.ts` | `users`, `auth_identities`, `profiles`, `member_passes`, `sessions` |
| POST | `/auth/refresh` | — | `auth.ts` | `sessions` |
| POST | `/auth/logout` | JWT | `auth.ts` | `sessions` |
| GET | `/auth/me` | JWT | `auth.ts` | `users`, `profiles`, `member_passes` |
| DELETE | `/auth/account` | JWT | `auth.ts` | `users`, `sessions` |
| GET | `/profile/me` | JWT | `profile.ts` | `profiles` |
| POST | `/profile` | JWT | `profile.ts` | `profiles` |
| POST | `/profile/username/check` | JWT | `profile.ts` | `profiles` |
| POST | `/profile/photo/upload-url` | JWT | `profile.ts` | None (returns R2 upload token) |
| PUT | `/profile/photo/upload` | upload token | `profile.ts` | R2 `PROFILE_PHOTOS` |
| GET | `/profile/photo/object/*` | — | `profile.ts` | R2 `PROFILE_PHOTOS` |
| GET | `/pass/me` | JWT | `pass.ts` | `member_passes` |
| POST | `/onboarding/complete` | JWT | `index.ts` | `profiles` |
| GET | `/users/search` | JWT | `users.ts` | `users`, `profiles`, `member_passes` |
| GET | `/crew` | JWT | `crew.ts` | `crew_connections`, `users`, `profiles`, `member_passes` |
| POST | `/crew/add` | JWT | `crew.ts` | `crew_connections`, `users` |
| DELETE | `/crew/:userId` | JWT | `crew.ts` | `crew_connections` |
| GET | `/races` | JWT | `races.ts` | `races`, `race_participants`, `profiles`, `proofs`, `race_invites` |
| POST | `/races` | JWT | `races.ts` | `races`, `race_participants` |
| POST | `/races/join-code` | JWT | `races.ts` | `race_invites`, `races`, `race_participants`, `profiles` |
| GET | `/races/:id` | JWT | `races.ts` | `races`, `race_participants`, `profiles`, `proofs`, `race_invites` |
| PATCH | `/races/:id` | JWT | `races.ts` | `races` |
| POST | `/races/:id/archive` | JWT | `races.ts` | `races` |
| POST | `/races/:id/cancel` | JWT | `races.ts` | `races` |
| DELETE | `/races/:id` | JWT | `races.ts` | `races` (soft delete) |
| POST | `/races/:id/leave` | JWT | `races.ts` | `race_participants` |
| POST | `/races/:id/join` | JWT | `races.ts` | `races`, `race_participants`, `profiles` |
| POST | `/races/:id/participants` | JWT | `races.ts` | `races`, `race_participants`, `users`, `profiles` |
| POST | `/races/:id/invite-code` | JWT | `races.ts` | `races`, `race_invites` |
| POST | `/races/:id/proof` | JWT | `races.ts` | `races`, `proofs`, `race_participants` |
| GET | `/races/:id/proofs` | JWT | `races.ts` | `races`, `proofs`, `profiles` |
| PATCH | `/races/:id/proofs/:proofId` | JWT | `races.ts` | `proofs`, `race_participants` |
| GET | `/arena` | JWT | `arena.ts` | `users`, `races`, `race_participants`, `profiles` |

---

## 7. Authentication

### Login flows

#### Email OTP login

1. Client: `POST /auth/email/start { email }`
   - Worker normalizes email, generates 6-digit OTP, SHA-256 hashes it, inserts row into `email_codes`.
   - Worker calls Resend to send the code (failures are logged but response is generic).
   - Response is always generic: "If that email can receive mail, a code has been sent."

2. Client: `POST /auth/email/verify { email, code }`
   - Worker finds newest unused, non-expired row for email.
   - Increments `attempts`. If `attempts >= 5`, returns 429.
   - Hashes provided code and compares to `code_hash`.
   - On match, marks row `used_at = now`.
   - Calls `findOrCreateUser(email)`:
     - If `users.primary_email` exists, update `last_login_at`.
     - If not, insert new `users` row with `status = 'active'`.
   - Ensures an `auth_identities` row with `provider = 'email'` exists.
   - Calls `ensureProfileAndPass(userId)`:
     - Inserts `profiles` row if missing.
     - Inserts `member_passes` row if missing.
   - Calls `createSession(userId)`:
     - Generates refresh token and SHA-256 hash.
     - Inserts `sessions` row.
     - Signs a 15-minute access JWT.
   - Returns `{ accessToken, refreshToken, user }`.

#### Google Sign-In login

1. Client sends Google ID token to `POST /auth/google { idToken }`.
2. Worker verifies token with `https://oauth2.googleapis.com/tokeninfo` and checks `aud`, `email_verified`, and expiry.
3. Worker calls `findOrCreateUser(email)`.
4. Worker upserts `auth_identities` row with `provider = 'google'`, storing `sub`, `name`, `picture`.
5. Worker calls `ensureProfileAndPass(userId)`.
6. Worker creates session and returns tokens + user object.

### Session flow

- **Access token:** JWT (HMAC-SHA256), 15 minutes, sent as `Authorization: Bearer {token}`.
- **Refresh token:** 96 hex characters, stored only as SHA-256 hash in `sessions.refresh_token_hash`.
- **Refresh:** `POST /auth/refresh { refreshToken }` hashes the provided token, looks up an unrevoked, non-expired session, updates `last_seen_at`, and returns a new 15-minute access token.
- **Logout:** `POST /auth/logout` sets `revoked_at = CURRENT_TIMESTAMP` on all active sessions for the user.
- **Account deletion:** `DELETE /auth/account` sets `users.status = 'deleted'` and revokes all sessions.

### User creation flow

A user row is created at first successful login only. There is no sign-up endpoint separate from login.

```
POST /auth/email/start
  ↓
POST /auth/email/verify (or /auth/google)
  ↓
INSERT users
  ↓
INSERT auth_identities
  ↓
INSERT profiles (empty, if missing)
  ↓
INSERT member_passes (auto-generated, if missing)
  ↓
INSERT sessions
  ↓
Return tokens + user object
```

### Profile creation flow

- `profiles` is auto-inserted as an empty row at first login.
- The user updates it via `POST /profile`:
  - `fullName`
  - `username` (unique check enforced)
  - `privateProfile` (stored but unused)
  - `profilePhotoUrl` or `avatarUrl` (stored in `avatar_url`)
- Onboarding is marked complete via `POST /onboarding/complete`, which sets `profiles.onboarding_complete = 1`.

---

## 8. Race System Lifecycle

### 1. Create Race

**Endpoint:** `POST /races`

**Body example:**
```json
{
  "title": "First to 100 Pushups",
  "description": "Daily pushup race",
  "category": "fitness",
  "goalType": "first_to_finish",
  "targetValue": 100,
  "unit": "reps",
  "proofRequirement": "manual",
  "proofReviewMode": "auto_accept",
  "visibility": "private"
}
```

**Tables touched:**
1. `races` — insert new race row with `status = 'active'`.
2. `race_participants` — insert creator as participant with `progress_value = 0`, `progress_percent = 0`.

### 2. Invite Users

**Endpoint:** `POST /races/:id/invite-code`

**Tables touched:**
1. `race_invites` — create row with `status = 'active'`, `invite_code` like `NUV-XXXXXX`.

Only one active code is returned per race. If an active code exists, it is reused.

### 3. Join Race

**By code:** `POST /races/join-code { code }`

**By direct join (crew_only visibility):** `POST /races/:id/join`

**By owner adding participant:** `POST /races/:id/participants { userId }`

**Tables touched:**
1. `race_invites` — lookup by code (read).
2. `races` — verify race is active (read).
3. `race_participants` — insert if not exists (sets `display_name` from `profiles.full_name`).

### 4. Verification (Submit Proof)

**Manual proof endpoint:** `POST /races/:id/proof`

**Body example:**
```json
{
  "proofType": "manual",
  "value": 25,
  "note": "Morning set"
}
```

**AI motion proof body example:**
```json
{
  "proofType": "ai_motion",
  "value": 30,
  "verificationStatus": "ai_verified",
  "activityType": "jumping_jacks",
  "detectedValue": 30,
  "targetValue": 100,
  "confidence": 0.94,
  "validatorVersion": "nuvo-ai-motion-v1",
  "framesAnalyzed": 120,
  "validPoseFrames": 115,
  "durationMs": 45000
}
```

**Tables touched:**
1. `races` — verify active (read).
2. `race_participants` — ensure participant exists.
3. `proofs` — insert proof row.
4. `race_participants` — if status is `accepted` or `ai_verified`, update `progress_value` and `progress_percent`.

### 5. Progress Update

Progress is computed incrementally, not recalculated from all proofs:

```
newProgressValue = current progress_value + proof.value
newProgressPercent = race.target_value > 0
  ? min(100, round((newProgressValue / race.target_value) * 100))
  : 0
```

**Important:** If you manually edit `proofs.value` or insert fake proofs, the corresponding `race_participants.progress_value` is **not** automatically recomputed. You must update the participant row too.

### 6. Leaderboard Update

There is no separate leaderboard table. The leaderboard is derived at read time:

```sql
SELECT * FROM race_participants rp
LEFT JOIN profiles p ON p.user_id = rp.user_id
WHERE rp.race_id = ?
ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rp.joined_at ASC
```

So the leaderboard updates as soon as `race_participants.progress_value` changes.

### 7. Completion

There is no explicit "race completed" row. Completion is inferred:

- `arena.ts` treats a race as a "result" if:
  - `races.status` is `archived`, `cancelled`, or any `RESULT_STATUSES` value; OR
  - the user's `progress_percent >= 100`.

- The race does not auto-complete when someone hits 100%. The creator must call `POST /races/:id/archive` or `POST /races/:id/cancel`.

### Full lifecycle table touch map

```
Create Race
  ↓ races (insert), race_participants (insert creator)

Invite Users
  ↓ race_invites (insert active code)

Join Race
  ↓ race_invites (read), races (read), race_participants (insert)

Submit Proof
  ↓ races (read), race_participants (ensure + update), proofs (insert)

Review Proof
  ↓ proofs (update status), race_participants (update progress)

Leaderboard
  ↓ race_participants (read, ordered)

Completion / Archive
  ↓ races (update status)

Delete Race
  ↓ races (update deleted_at)

Leave Race
  ↓ race_participants (delete)
```

---

## 9. MoveCheck / Verification

"MoveCheck" in the app refers to the proof verification and progress application system.

### Where verification results are stored

**Table: `proofs`**

Key columns:
- `verification_status`
- `verification_summary`
- `proof_type` (`manual` or `ai_motion`)
- `value` — the amount applied to leaderboard (for AI motion, this equals detected reps)
- `detected_value`, `target_value`, `confidence`, `validator_version`, `frames_analyzed`, `valid_pose_frames`, `duration_ms` — AI metadata

### Which tables update on proof submission

1. `proofs` — always inserted.
2. `race_participants` — updated only if `verification_status` is `accepted` or `ai_verified` at submit time, or later changed to one of those statuses via review.

### How progress is calculated

```
increment = max(0, floor(proof.value))
newValue = participant.progress_value + increment
newPercent = race.target_value > 0
  ? min(100, round(newValue / race.target_value * 100))
  : 0
```

### How leaderboard updates happen

The leaderboard is not a stored table. It is a query over `race_participants` joined to `profiles`. Therefore, as soon as `progress_value` and `progress_percent` are updated, the leaderboard returned by `GET /races/:id` and `GET /arena` reflects the change.

### AI Motion Proof specifics

- The actual pose detection happens **on the device** (Flutter + ML Kit).
- The Worker trusts the client-submitted `verificationStatus` for `ai_motion` proofs.
- The app sends `proofType: 'ai_motion'` and AI result fields.
- If `verificationStatus` is `ai_verified` and `value > 0`, progress is applied immediately.
- If status is `needs_review`, progress is **not** applied until an owner reviews it.

---

## 10. ER Diagram

```
┌─────────────────┐
│     users       │
├─────────────────┤
│ id (PK)         │◄──────────────────────────────────────────┐
│ primary_email   │                                           │
│ status          │                                           │
│ created_at      │                                           │
│ updated_at      │                                           │
│ last_login_at   │                                           │
│ demo_world_*    │                                           │
└────────┬────────┘                                           │
         │                                                     │
         │ 1:N                                                 │
         ▼                                                     │
┌─────────────────┐     ┌─────────────────┐     ┌───────────────┴─┐
│ auth_identities │     │    sessions     │     │     profiles    │
├─────────────────┤     ├─────────────────┤     ├─────────────────┤
│ id (PK)         │     │ id (PK)         │     │ user_id (PK/FK) │
│ user_id (FK)    │     │ user_id (FK)    │     │ full_name       │
│ provider        │     │ refresh_token_..│     │ username        │
│ provider_user_id│     │ expires_at      │     │ avatar_url      │
│ email           │     │ revoked_at      │     │ onboarding_..   │
│ email_verified  │     │ created_at      │     │ created_at      │
│ display_name    │     │ last_seen_at    │     │ updated_at      │
│ avatar_url      │     └─────────────────┘     └─────────────────┘
│ created_at      │
└─────────────────┘
         │
         │ 1:1
         ▼
┌─────────────────┐
│  member_passes  │
├─────────────────┤
│ id (PK)         │
│ user_id (FK)    │
│ member_id       │
│ pass_slug       │
│ created_at      │
└─────────────────┘

         │
         │ creator_id
         ▼
┌─────────────────┐
│     races       │
├─────────────────┤
│ id (PK)         │◄───────────────────────────────┐
│ creator_id (FK) │                                │
│ title           │                                │
│ description     │                                │
│ category        │                                │
│ goal_type       │                                │
│ target_value    │                                │
│ unit            │                                │
│ status          │                                │
│ visibility      │                                │
│ proof_require.. │                                │
│ proof_review_.. │                                │
│ deleted_at      │                                │
│ created_at      │                                │
│ updated_at      │                                │
└────────┬────────┘                                │
         │                                          │
         │ race_id                                  │ race_id
         ▼                                          │
┌─────────────────┐                                   │
│race_participants│                                   │
├─────────────────┤                                   │
│ id (PK)         │                                   │
│ race_id (FK)    │                                   │
│ user_id (FK)    │                                   │
│ display_name    │                                   │
│ progress_value  │                                   │
│ progress_percent│                                   │
│ joined_at       │                                   │
└─────────────────┘                                   │
         ▲                                            │
         │ user_id                                     │
         │                                             │
┌─────────────────┐                                   │
│     proofs        │◄──────────────────────────────────┘
├─────────────────┤
│ id (PK)         │
│ race_id (FK)    │
│ user_id (FK)    │
│ proof_type      │
│ value           │
│ detected_value  │
│ target_value    │
│ confidence      │
│ validator_vers..│
│ verification_.. │
│ verification_.. │
│ reviewed_by     │
│ reviewed_at     │
│ created_at      │
└─────────────────┘

         │
         │ user_id / crew_user_id
         ▼
┌─────────────────┐
│ crew_connections│
├─────────────────┤
│ id (PK)         │
│ user_id (FK)    │
│ crew_user_id(FK)│
│ status          │
│ created_at      │
└─────────────────┘

┌─────────────────┐
│  race_invites   │
├─────────────────┤
│ id (PK)         │
│ race_id (FK)    │
│ created_by (FK) │
│ invite_code     │
│ status          │
│ expires_at      │
│ created_at      │
└─────────────────┘

┌─────────────────┐
│  email_codes    │
├─────────────────┤
│ id (PK)         │
│ email           │
│ code_hash       │
│ attempts        │
│ expires_at      │
│ used_at         │
│ created_at      │
└─────────────────┘

┌─────────────────┐
│  audit_events   │  ← unused
├─────────────────┤
│ id (PK)         │
│ user_id         │
│ event_type      │
│ metadata        │
│ created_at      │
└─────────────────┘
```

---

## 11. Database Management — Manual Cloudflare D1 Guide

This section tells you exactly how to manage fake/demo data through the Cloudflare dashboard D1 visual editor.

### Generating UUIDs for new rows

The Worker uses standard UUID v4 values for every `id` column. Use any UUID generator online or generate one locally:

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

Record the UUIDs you create; you will need them for foreign keys.

### Safe edit principles

1. **Never delete a `users` row while child rows exist.** There are no `ON DELETE CASCADE` rules. The dashboard will throw a foreign-key error.
2. **Never change `users.id` or `races.id`.** These are referenced everywhere.
3. **Keep `profiles.username` unique.** The Worker enforces this; duplicate usernames will break login/profile reads.
4. **Keep `member_passes.member_id` and `pass_slug` unique.** Duplicates break pass generation.
5. **Keep `race_invites.invite_code` unique.** Duplicates break join-by-code.
6. **Keep `race_participants` UNIQUE(race_id, user_id).** A user cannot be in the same race twice.
7. **After editing `proofs`, manually recompute `race_participants.progress_value` and `progress_percent`.** The Worker does not recalculate these from scratch.
8. **Never set `proofs.verification_status` to `accepted` or `ai_verified` without also updating the participant's progress if you want it to count.**

---

### How to create a brand new account

You cannot fully create an account through the dashboard because:
- Email codes are hashed, so you cannot log in with a dashboard-created user without generating a code_hash.
- Sessions require a refresh token hash.

**Recommended approach:** Create the user through the app first, then edit profile/race data in D1.

If you must create a test account purely in SQL, do it in this order:

1. **Insert `users`**
   ```sql
   INSERT INTO users (id, primary_email, status, created_at, updated_at, last_login_at)
   VALUES ('USER_UUID', 'test@example.com', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
   ```

2. **Insert `auth_identities`** (email identity required for email login)
   ```sql
   INSERT INTO auth_identities (id, user_id, provider, email, email_verified, created_at)
   VALUES ('IDENTITY_UUID', 'USER_UUID', 'email', 'test@example.com', 1, CURRENT_TIMESTAMP);
   ```

3. **Insert `profiles`**
   ```sql
   INSERT INTO profiles (user_id, full_name, username, avatar_url, private_profile, onboarding_complete, created_at, updated_at)
   VALUES ('USER_UUID', 'Test User', 'testuser123', NULL, 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
   ```

4. **Insert `member_passes`**
   ```sql
   INSERT INTO member_passes (id, user_id, member_id, pass_slug, created_at)
   VALUES ('PASS_UUID', 'USER_UUID', 'NUVO-A3B9K2', 'a3b9k2', CURRENT_TIMESTAMP);
   ```

5. **Insert `sessions`** (only if you need a refresh token; generate a random token and hash it with SHA-256)
   ```sql
   INSERT INTO sessions (id, user_id, refresh_token_hash, device_label, expires_at, created_at, last_seen_at)
   VALUES ('SESSION_UUID', 'USER_UUID', 'SHA256_OF_REFRESH_TOKEN', 'Dashboard', '2026-01-01T00:00:00.000Z', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
   ```

**What NOT to edit:** Do not manually set `users.status = 'deleted'` unless you also revoke sessions. A deleted user with active sessions could still refresh tokens.

---

### How to create a race

1. **Get the creator's `users.id`** (call it `CREATOR_UUID`).

2. **Insert `races`**
   ```sql
   INSERT INTO races (
     id, creator_id, title, description, category, goal_type, target_value, unit,
     status, proof_requirement, proof_review_mode, visibility, created_at, updated_at
   ) VALUES (
     'RACE_UUID', 'CREATOR_UUID', 'Demo Race', 'For testing', 'fitness', 'first_to_finish', 100, 'reps',
     'active', 'manual', 'auto_accept', 'private', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
   );
   ```

3. **Insert creator as `race_participants`**
   ```sql
   INSERT INTO race_participants (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
   VALUES ('PARTICIPANT_UUID', 'RACE_UUID', 'CREATOR_UUID', 'Creator Name', 0, 0, CURRENT_TIMESTAMP);
   ```

**What NOT to edit:** Do not leave `races.status` as anything other than `active`, `archived`, or `cancelled`. Other values may break validation.

---

### How to add users to a race

1. **Get `RACE_UUID` and `USER_UUID`.**

2. **Insert `race_participants`**
   ```sql
   INSERT INTO race_participants (id, race_id, user_id, display_name, progress_value, progress_percent, joined_at)
   VALUES ('PARTICIPANT_UUID', 'RACE_UUID', 'USER_UUID', 'User Name', 0, 0, CURRENT_TIMESTAMP);
   ```

**What could break:**
- Duplicate `(race_id, user_id)` violates the unique constraint.
- `user_id` not in `users` violates foreign key.
- `race_id` not in `races` violates foreign key.

---

### How to remove users from a race

1. **Delete the participant row**
   ```sql
   DELETE FROM race_participants WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
   ```

2. **Optional:** Delete their proofs for that race if you want a clean slate
   ```sql
   DELETE FROM proofs WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
   ```

**What NOT to do:** Do not delete the creator's participant row if you still want the race to display correctly; the creator is expected to be a participant. Deleting it does not break the database, but `GET /races` may return inconsistent data.

---

### How to change a username

1. **Check availability first**
   ```sql
   SELECT user_id FROM profiles WHERE username = 'new_username';
   ```
   If a row is returned, the username is taken.

2. **Update**
   ```sql
   UPDATE profiles SET username = 'new_username', updated_at = CURRENT_TIMESTAMP WHERE user_id = 'USER_UUID';
   ```

**What could break:** Duplicate usernames are rejected by the unique constraint. Race detail joins username to user but the app primarily reads `full_name`; changing username is safe if unique.

---

### How to change a profile picture

1. **Upload the image to R2** using the same signed-token flow as the app, OR manually upload through the Cloudflare R2 dashboard to a path like:
   ```
   profile-photos/USER_UUID/1705312800000.jpg
   ```

2. **Build the public URL**
   ```
   https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/profile-photos/USER_UUID/1705312800000.jpg
   ```

3. **Update `profiles.avatar_url`**
   ```sql
   UPDATE profiles SET avatar_url = 'https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/profile-photos/USER_UUID/1705312800000.jpg', updated_at = CURRENT_TIMESTAMP WHERE user_id = 'USER_UUID';
   ```

**What NOT to do:** Do not put a URL that is not reachable from the public internet; the app will show a broken image.

---

### How to link an R2 image

Same as "change a profile picture." The only place R2 images are linked is `profiles.avatar_url`.

---

### How to delete a race

The app does a **soft delete** only. To match app behavior:

```sql
UPDATE races SET deleted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = 'RACE_UUID';
```

The race and all its participants/proofs/invites remain in the database but are hidden from queries because every read filters `deleted_at IS NULL`.

**Hard delete (use with extreme caution):**

If you truly want the race gone, delete in this order due to foreign keys:

```sql
DELETE FROM proofs WHERE race_id = 'RACE_UUID';
DELETE FROM race_participants WHERE race_id = 'RACE_UUID';
DELETE FROM race_invites WHERE race_id = 'RACE_UUID';
DELETE FROM races WHERE id = 'RACE_UUID';
```

**What NOT to do:** Do not delete `races` first. Foreign keys will block it.

---

### How to reset a race

"Reset" is not a feature in the app. To manually reset a race:

1. **Set progress to zero for all participants**
   ```sql
   UPDATE race_participants
   SET progress_value = 0, progress_percent = 0
   WHERE race_id = 'RACE_UUID';
   ```

2. **Delete all proofs**
   ```sql
   DELETE FROM proofs WHERE race_id = 'RACE_UUID';
   ```

3. **Reset race status to active**
   ```sql
   UPDATE races SET status = 'active', deleted_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = 'RACE_UUID';
   ```

**What could break:** If you delete proofs but forget to reset `race_participants`, the leaderboard still shows old progress.

---

### How to create fake progress

To make it look like a user has made progress without submitting proofs:

1. **Update `race_participants`**
   ```sql
   UPDATE race_participants
   SET progress_value = 45, progress_percent = 45
   WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
   ```

2. **Optional: create a matching proof row for realism**
   ```sql
   INSERT INTO proofs (
     id, race_id, user_id, proof_type, note, value, verification_status, verification_summary, created_at
   ) VALUES (
     'PROOF_UUID', 'RACE_UUID', 'USER_UUID', 'manual', 'Fake progress', 45, 'accepted',
     'Manual proof accepted. AI validation coming soon.', CURRENT_TIMESTAMP
   );
   ```

**What could break:**
- If `progress_percent` does not match `progress_value / races.target_value * 100`, the leaderboard math looks wrong.
- If `progress_value > target_value`, `progress_percent` should still be capped at 100.

**Correct formula to use:**
```sql
-- For a race with target_value = 100 and desired progress_value = 45:
UPDATE race_participants
SET progress_value = 45,
    progress_percent = MIN(100, ROUND((45.0 / target_value) * 100))
WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
```
(You cannot reference `target_value` in an UPDATE like that in D1; compute the percent manually.)

---

### How to create leaderboard data

The leaderboard is just `race_participants` sorted by `progress_percent DESC, progress_value DESC, joined_at ASC`. To set the leaderboard order, update each participant's `progress_value` and `progress_percent`.

**Example:** Race with target 100. Set three users:

| User | progress_value | progress_percent |
|------|----------------|-------------------|
| User A | 90 | 90 |
| User B | 75 | 75 |
| User C | 30 | 30 |

```sql
UPDATE race_participants SET progress_value = 90, progress_percent = 90 WHERE race_id = 'RACE_UUID' AND user_id = 'USER_A_UUID';
UPDATE race_participants SET progress_value = 75, progress_percent = 75 WHERE race_id = 'RACE_UUID' AND user_id = 'USER_B_UUID';
UPDATE race_participants SET progress_value = 30, progress_percent = 30 WHERE race_id = 'RACE_UUID' AND user_id = 'USER_C_UUID';
```

**What could break:** If two participants have the same `progress_percent`, the app uses `progress_value` then `joined_at` to break ties. Make sure those columns reflect the order you want.

---

### How to create completed races

"Completed" is inferred, not stored. To make a race appear completed in the app:

1. **Archive or cancel the race**
   ```sql
   UPDATE races SET status = 'archived', updated_at = CURRENT_TIMESTAMP WHERE id = 'RACE_UUID';
   ```

2. **Or make a participant reach 100% progress**
   ```sql
   UPDATE race_participants
   SET progress_value = 100, progress_percent = 100
   WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
   ```

**Best practice for a realistic completed race:**
- Set one or more participants to `progress_percent = 100`.
- Set `races.status = 'archived'`.
- Add a proof row showing the final submission.

**What could break:** If `progress_value` and `progress_percent` are inconsistent (e.g., value 120 but percent 90), the race detail screen may show confusing numbers.

---

## 12. AI Safety — Complex or Over-Engineered Areas

This section only identifies problems. It does not propose changes.

### Weird abstractions

1. **Two race "proof" columns**
   - `races.proof_requirement` and `races.proof_mode` store overlapping concepts.
   - `proof_mode` was added later and is often set to the same value as `proof_requirement`.
   - Danger: editing one but not the other may confuse future code that reads `proof_mode`.

2. **`race_participants.display_name` cache**
   - This column stores a snapshot of `profiles.full_name` at join time.
   - It is never updated when the user changes their profile name.
   - The app already falls back to `profiles.full_name` in `COALESCE(rp.display_name, p.full_name, 'Unknown')`, so the cached value is mostly ignored.

3. **Unused `audit_events` table**
   - A full table exists for audit logging but nothing writes to it.
   - It is harmless but adds cognitive overhead.

### Duplicate tables / redundant data

1. **`races.ai_activity_type` vs `proofs.ai_activity_type`**
   - The race can specify an AI activity type, but each proof also carries its own.
   - They can disagree.

2. **`races.target_unit` and `races.unit`**
   - `target_unit` defaults to `unit` and serves the same purpose.

3. **`profiles.avatar_url` and auth identity `avatar_url`**
   - Google login stores a picture URL in `auth_identities.avatar_url` but it is never copied to `profiles.avatar_url`.

### Unnecessary joins

1. **`GET /races/:id` joins `profiles` twice**
   - Once for participants and once for proofs.
   - This is correct for the current data model but could be flattened if `race_participants.display_name` were removed.

2. **`GET /users/search` joins three tables**
   - `users`, `profiles`, `member_passes` are joined for every search.
   - The query is complex and relies on `COALESCE` and `SUBSTR` for email prefix matching.

### Over-engineered structures

1. **Invite code table without expiration enforcement**
   - `race_invites.expires_at` exists but no cron job or query actively prunes expired codes.
   - The `POST /races/join-code` query checks `expires_at > CURRENT_TIMESTAMP`, so the column is used, but managing expiration manually is awkward.

2. **`email_codes` retention forever**
   - Used and expired codes are never cleaned up.
   - The table will grow indefinitely.

3. **Demo World Mode columns on `users`**
   - `demo_world_enabled`, `demo_world_seed`, `demo_world_variant` are SQL-only toggles.
   - They are not exposed in the app UI; enabling them requires dashboard edits.
   - They create a whole separate code path in `arena.ts` (`generateDemoSnapshot`).

### Tables that are dangerous to edit manually

| Table / Column | Why dangerous |
|----------------|---------------|
| `sessions.refresh_token_hash` | Hard to generate correctly; a mismatch locks the user out |
| `email_codes.code_hash` | Requires SHA-256 of a code you know; used only for login |
| `auth_identities.provider_user_id` | Changing Google's `sub` mapping breaks Google login |
| `member_passes.member_id` / `pass_slug` | Breaks QR passes and search-by-member-id |
| `users.id` | Every foreign key references this |
| `races.id` | Every participant/proof/invite references this |
| `proofs.value` | Editing it does not update `race_participants`; leaderboard drifts |
| `race_participants.progress_value` / `progress_percent` | Must be kept in sync manually |

### Most fragile manual edits

1. **Deleting users.** Because there is no cascade, you must delete child rows in the right order.
2. **Changing proof status to accepted.** You must also update `race_participants` progress.
3. **Creating fake progress without matching proof rows.** The app may show activity feeds that do not match leaderboard state.
4. **Changing `races.target_value` after proofs exist.** Old `progress_percent` values become stale.

---

## 13. Backend Owner Guide

This is the operating manual for the only engineer at Nuvo. It assumes you are comfortable with the Cloudflare dashboard and basic SQL.

### Daily checks

1. Open the Cloudflare dashboard → D1 → `nuvo_db`.
2. Run:
   ```sql
   SELECT COUNT(*) FROM users WHERE status = 'active';
   SELECT COUNT(*) FROM races WHERE deleted_at IS NULL;
   SELECT COUNT(*) FROM proofs WHERE created_at > datetime('now', '-1 day');
   ```
3. If any count looks wrong, inspect the relevant table.

### How the dashboard maps to the app

| Cloudflare object | App feature |
|-------------------|-------------|
| D1 `users` | Accounts |
| D1 `profiles` | Names, usernames, photos, onboarding |
| D1 `member_passes` | QR pass / member ID |
| D1 `races` | Race settings |
| D1 `race_participants` | Leaderboard |
| D1 `proofs` | Proof history and verification status |
| D1 `race_invites` | Invite codes |
| D1 `crew_connections` | Friends / crew |
| R2 `nuvor2` bucket | Profile photos |
| Worker `nuvo-api` | All API logic |

### Editing data safely

**Always:**
- Take a D1 backup or export before bulk edits.
- Edit one race or one user at a time.
- Verify foreign keys exist before inserting.
- Keep `progress_value` and `progress_percent` consistent.
- Use ISO-8601 timestamps (`2025-01-15T10:00:00.000Z`).

**Never:**
- Change `users.id` or `races.id`.
- Delete rows from `users` without deleting children first.
- Set `proofs.verification_status` to `accepted` or `ai_verified` without updating the participant's progress.
- Manually insert into `sessions` unless you know how to hash the refresh token.
- Leave `races.status` as an invalid string.

### Common tasks quick reference

| Task | Tables to edit | Order |
|------|----------------|-------|
| Create fake user | users → auth_identities → profiles → member_passes | Left to right |
| Create race | races → race_participants | Race first, then creator participant |
| Add user to race | race_participants | Verify user and race exist |
| Remove user from race | race_participants (and optionally proofs) | Participant first |
| Fake progress | race_participants (+ optional proofs) | Update participant, then insert proof |
| Complete race | races + race_participants | Set status to archived and/or progress to 100% |
| Delete race | races only (soft) or proofs → participants → invites → races (hard) | Children before parent for hard delete |
| Change username | profiles | Check uniqueness first |
| Change profile photo | R2 + profiles | Upload to R2, then update `avatar_url` |
| Reset race | race_participants, proofs, races | Zero progress, delete proofs, set status active |

### Troubleshooting

**User cannot log in:**
- Check `users.status = 'active'`.
- Check `auth_identities` has a row for `provider = 'email'` or `provider = 'google'`.
- Check `sessions` has an unrevoked, non-expired row.

**Race does not appear:**
- Check `races.deleted_at IS NULL`.
- Check `races.status` is valid.
- Check `race_participants` has a row linking the user to the race.

**Leaderboard is wrong:**
- Check `race_participants.progress_value` and `progress_percent`.
- Recompute percent from `races.target_value`.
- Check that accepted proofs have matching progress increments.

**Profile photo broken:**
- Check `profiles.avatar_url` is a full URL.
- Check the object exists in R2 at the exact path.
- Check the path starts with `profile-photos/`.

### When to deploy vs. when to edit data

- **Deploy the Worker** when you change code in `server/worker/src/`.
- **Apply migrations** when you add new schema in `server/worker/migrations/`.
- **Edit D1 directly** for demo data, fixing one-off mistakes, or onboarding support.
- **Upload R2 directly** for quick profile photo fixes.

### Migration policy

- Migrations run from `server/worker/migrations/`.
- They are applied locally with `npx wrangler d1 migrations apply nuvo_db --local`.
- They are applied to production with `npx wrangler d1 migrations apply nuvo_db --remote`.
- Never edit a migration file that has already been applied.
- Never rename or delete a migration that has already been applied.

### R2 policy

- Only profile photos use R2 today.
- Public URL pattern: `https://nuvo-api.getnuvoapp.workers.dev/profile/photo/object/profile-photos/{userId}/{timestamp}.{ext}`
- If you upload directly through the Cloudflare dashboard, make sure the content type is set correctly (`image/jpeg`, `image/png`, or `image/webp`).
- There is no automatic cleanup. Orphaned objects stay forever unless you delete them manually.

### Final rule

If you are unsure about a manual edit, do it on a local dev database first, or create the data through the app and only tweak it afterward. The schema has no cascading deletes and several derived values, so dashboard edits require care.

---

## Appendix: Useful D1 Queries

### List all active races with participant counts
```sql
SELECT r.id, r.title, r.status, r.target_value, r.unit, COUNT(rp.id) as racers
FROM races r
LEFT JOIN race_participants rp ON rp.race_id = r.id
WHERE r.deleted_at IS NULL
GROUP BY r.id
ORDER BY r.created_at DESC;
```

### Show leaderboard for a race
```sql
SELECT rp.user_id,
       COALESCE(rp.display_name, p.full_name, 'Unknown') as name,
       rp.progress_value,
       rp.progress_percent,
       rp.joined_at
FROM race_participants rp
LEFT JOIN profiles p ON p.user_id = rp.user_id
WHERE rp.race_id = 'RACE_UUID'
ORDER BY rp.progress_percent DESC, rp.progress_value DESC, rp.joined_at ASC;
```

### Find users with no profile
```sql
SELECT u.id, u.primary_email
FROM users u
LEFT JOIN profiles p ON p.user_id = u.id
WHERE p.user_id IS NULL;
```

### Count proofs per race
```sql
SELECT race_id, COUNT(*) as proof_count
FROM proofs
GROUP BY race_id
ORDER BY proof_count DESC;
```

### Find orphaned race participants (race was hard-deleted)
```sql
SELECT rp.*
FROM race_participants rp
LEFT JOIN races r ON r.id = rp.race_id
WHERE r.id IS NULL;
```
