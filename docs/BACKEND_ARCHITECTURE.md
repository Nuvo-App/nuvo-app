# Nuvo Backend Architecture (Simplified)

This document describes the redesigned Nuvo backend data architecture. The goal is to make the database easier to manage manually from the Cloudflare D1 visual editor while preserving the existing app flows.

---

## 1. Design goals

- **Fewer tables**, clear ownership for each table.
- **No duplicated fields**: each concept lives in exactly one column.
- **Human-readable SQL**: D1 dashboard edits should be obvious.
- **Backwards compatible**: legacy tables are renamed, not dropped, so existing data and rollbacks are preserved.
- **Demo-friendly**: `is_demo` flags and a standalone seed script make it easy to spin up demo data.

---

## 2. Stack

| Service | Name | Purpose |
|---|---|---|
| Cloudflare Worker | `nuvo-api` | HTTP API runtime (Hono + TypeScript) |
| Cloudflare D1 | `nuvo_db` | Serverless SQL database |
| Cloudflare R2 | `nuvor2` | Object storage for avatars and proof media |

---

## 3. Table overview

| Table | Purpose | Core foreign keys |
|---|---|---|
| `users` | Account identity, email, demo flags | — |
| `profiles` | Public identity: name, username, avatar | `users.id` |
| `member_passes` | Invite/recovery pass codes | `users.id` |
| `auth_identities` | OAuth / email identity records | `users.id` |
| `email_codes` | Email OTP codes | `users.id` |
| `sessions` | Refresh token storage | `users.id` |
| `crew_connections` | One-way crew/following graph | `users.id` |
| `media_objects` | Registry of every R2 object | `users.id` |
| `races` | Race definition and settings | `users.id` (creator) |
| `race_members` | Membership + cached display data | `races.id`, `users.id` |
| `race_progress` | Per-user progress for a race | `races.id`, `users.id` |
| `move_logs` | Every proof / move submission | `races.id`, `users.id` |
| `race_invites` | Invite codes for races | `races.id`, `users.id` |

**Legacy tables** (renamed, read-only):
- `races_legacy`
- `race_participants_legacy`
- `proofs_legacy`

---

## 4. Entity diagrams

### Users and identity

```
users
├── profiles
├── member_passes
├── auth_identities
├── email_codes
├── sessions
└── crew_connections (outgoing)
```

### Media

```
media_objects
└── owner_user_id → users.id
```

`media_objects` replaces ad-hoc `avatar_url` strings. Every R2 upload is tracked here.

### Races

```
races
├── race_members
│   └── race_progress
│       └── move_logs
└── race_invites
```

A race has members. Each member has one progress row. Every move/proof is stored in `move_logs`.

---

## 5. Core tables in detail

### `users`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `primary_email` | TEXT | Login email, unique |
| `status` | TEXT | `active`, `suspended`, `deleted` |
| `demo_world_enabled` | INTEGER | 1 = arena shows demo world |
| `demo_world_seed` | TEXT | Seed for deterministic demo data |
| `demo_world_variant` | TEXT | e.g. `summer_v1` |
| `created_at`, `updated_at`, `last_login_at` | TEXT | ISO timestamps |

### `profiles`

| Column | Type | Notes |
|---|---|---|
| `user_id` | TEXT PK / FK |  |
| `full_name` | TEXT |  |
| `username` | TEXT UNIQUE |  |
| `avatar_url` | TEXT | Public URL (legacy + new) |
| `avatar_object_key` | TEXT | FK-ish to `media_objects.object_key` |
| `private_profile` | INTEGER | 0/1 |
| `onboarding_complete` | INTEGER | 0/1 |
| `is_demo` | INTEGER | 0/1 |

### `media_objects`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `owner_user_id` | TEXT FK |  |
| `bucket` | TEXT | Always `nuvor2` |
| `object_key` | TEXT UNIQUE | R2 key |
| `public_url` | TEXT | Worker public URL |
| `media_type` | TEXT | `image`, `video` |
| `purpose` | TEXT | `profile_avatar`, `race_proof`, etc. |
| `status` | TEXT | `active`, `deleted` |
| `deleted_at` | TEXT | Soft delete timestamp |

### `races`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `creator_id` | TEXT FK → users.id |  |
| `title` | TEXT |  |
| `description` | TEXT |  |
| `status` | TEXT | `draft`, `active`, `completed`, `archived`, `cancelled` |
| `race_type` | TEXT | `first_to_target`, `most_in_time`, etc. |
| `verification_type` | TEXT | `movecheck`, `manual`, `photo`, `none` |
| `movement_type` | TEXT | e.g. `pushups`, `squats` |
| `target_value` | INTEGER | Numeric goal |
| `target_unit` | TEXT | `reps`, `miles`, `minutes`, etc. |
| `start_line_at` | TEXT | ISO timestamp |
| `finish_line_at` | TEXT | ISO timestamp |
| `visibility` | TEXT | `private`, `crew_only`, `invite_code`, `public_demo` |
| `invite_code` | TEXT | Optional join code |
| `rules` | TEXT | Free-text rules |
| `demo_context` | TEXT | JSON metadata for demo races |

### `race_members`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `race_id` | TEXT FK |  |
| `user_id` | TEXT FK |  |
| `status` | TEXT | `active`, `left`, `removed` |
| `role` | TEXT | `creator`, `member` |
| `cached_display_name` | TEXT | Snapshot at join time |
| `cached_avatar_url` | TEXT | Snapshot at join time |
| `joined_at` | TEXT | ISO timestamp |

### `race_progress`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `race_id` | TEXT FK |  |
| `user_id` | TEXT FK |  |
| `progress_value` | INTEGER | Current numeric progress |
| `progress_percent` | INTEGER | 0-100 |
| `rank_position` | INTEGER | 1st, 2nd, etc. |
| `completed_at` | TEXT | ISO timestamp when 100% reached |

### `move_logs`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `race_id` | TEXT FK |  |
| `user_id` | TEXT FK |  |
| `value` | INTEGER | Move value |
| `unit` | TEXT | Move unit |
| `source` | TEXT | `movecheck`, `manual`, `demo`, `import` |
| `status` | TEXT | `pending`, `verified`, `rejected`, `removed` |
| `summary` | TEXT | Human summary |
| `media_object_key` | TEXT | Optional R2 key |
| `submitted_at`, `verified_at`, `removed_at` | TEXT | Timestamps |

### `race_invites`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK |  |
| `race_id` | TEXT FK |  |
| `created_by` | TEXT FK |  |
| `invite_code` | TEXT | Unique code |
| `status` | TEXT | `active`, `disabled` |
| `expires_at` | TEXT | ISO timestamp |

---

## 6. R2 architecture

| Path prefix | Purpose | Managed by |
|---|---|---|
| `profile-avatars/{userId}/{timestamp}.{ext}` | New avatar uploads | `profile.ts` |
| `profile-photos/{userId}/{timestamp}.{ext}` | Legacy avatar uploads | `profile.ts` (read-only) |
| `race-proofs/{raceId}/{userId}/{timestamp}.{ext}` | Manual photo/video proof uploads | `races.ts` (future) |

All uploads are tracked in `media_objects`.

---

## 7. Key design decisions

### Why rename legacy tables instead of dropping them?

- Zero risk of data loss.
- Easy rollback: rename tables back to original names.
- Existing Flutter app builds that somehow still read old tables would continue to work.

### Why `race_members` + `race_progress` instead of `race_participants`?

- Membership and progress are separate concerns.
- A member can exist without progress (joined but no moves yet).
- Progress can be edited independently of membership.
- Rankings are easier to compute and update.

### Why `move_logs` instead of `proofs`?

- One table for every move/proof submission.
- `source` distinguishes MoveCheck, manual, demo, and imported data.
- `status` handles pending/verified/rejected/removed lifecycle.

### Why `media_objects`?

- Central registry of every R2 object.
- Makes it easy to find orphaned objects.
- Allows soft-deletes without touching R2.
- Links avatars and future proof media to users.

---

## 8. Indexes

Key indexes on the new tables:

- `races(creator_id, deleted_at, created_at)`
- `race_members(race_id, status)`
- `race_members(user_id, status)`
- `race_progress(race_id, progress_percent DESC)`
- `move_logs(race_id, submitted_at DESC)`
- `move_logs(user_id, submitted_at DESC)`
- `media_objects(owner_user_id, purpose, status)`

See `server/worker/migrations/0007_simplified_schema.sql` for the full DDL.

---

## 9. API surface

The Worker exposes the following route modules:

- `auth.ts` — login, signup, token refresh, logout, account deletion
- `profile.ts` — profile CRUD, avatar upload via R2 signed URLs
- `races.ts` — race lifecycle, move logs, progress, proofs
- `crew.ts` — crew connections
- `arena.ts` — arena snapshot (real + demo)
- `users.ts` — search, public user info

For detailed request/response contracts see `docs/API_CONTRACT.md`.

---

## 10. MoveCheck backend behavior

MoveCheck is the camera-verified proof flow.

1. The Flutter app determines whether a race is MoveCheck-eligible using `aiActivityType`, `title`, `unit`, and `targetUnit`.
2. For eligible races the app opens `AI Motion Proof` and runs the on-device pose detector.
3. When verification succeeds, the app posts to `POST /races/:id/proof` with `source: 'ai'` and `aiActivityType`.
4. The Worker creates a `move_logs` row with `source = 'movecheck'` and `status = 'verified'`.
5. `applyMoveProgress` increments `race_progress.progress_value` and recalculates `progress_percent` and ranks.
6. The race detail response includes the move in `recentProofs`/`recentMoves`.

The backend does not run ML. It trusts the verified result from the Flutter client.

---

## 11. Demo data workflow

1. Run `server/worker/scripts/demo_seed.sql` against D1.
2. Three demo users, two demo races, and several moves are inserted.
3. Demo users have `profiles.is_demo = 1`.
4. The app can log in as a demo user or the arena can generate synthetic data via `demo_world_enabled`.

---

## 12. Safety rules

- Do not drop legacy tables.
- Do not edit old migrations (`0001` through `0006`).
- Do not delete data from `*_legacy` tables.
- New migrations must be additive or rename-only.
- Always run `npm run typecheck` after Worker changes.
