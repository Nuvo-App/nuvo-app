# Migration Plan: Simplified Nuvo Backend

This plan describes how to move the Nuvo backend from the legacy schema to the new simplified schema without data loss and without breaking the Flutter app.

---

## 1. Goal

- Replace the legacy `races`, `race_participants`, and `proofs` tables with the new `races`, `race_members`, `race_progress`, `move_logs`, and `media_objects` tables.
- Keep the old tables available under `_legacy` names for rollback and audit purposes.
- Update the Worker routes to read from and write to the new schema while preserving API contracts.

---

## 2. Phases

### Phase 1 — Schema migration (migration 0007)

Run `server/worker/migrations/0007_simplified_schema.sql`.

What it does:

1. Renames existing tables to `*_legacy`:
   - `races` → `races_legacy`
   - `race_participants` → `race_participants_legacy`
   - `proofs` → `proofs_legacy`
2. Adds `avatar_object_key` and `is_demo` to `profiles`.
3. Creates new tables:
   - `media_objects`
   - `races`
   - `race_members`
   - `race_progress`
   - `move_logs`
4. Adds indexes for the new tables.

**Safety:** no data is deleted or modified. Only renames and creates happen.

### Phase 2 — Data migration (migration 0008)

Run `server/worker/migrations/0008_migrate_to_simplified.sql`.

What it does:

1. Copies every legacy race into the new `races` table with field mapping.
2. Copies every legacy participant into `race_members` and initializes `race_progress`.
3. Copies every legacy proof into `move_logs`.
4. Creates `media_objects` rows for existing profile avatars that point to R2.

**Safety:** data is copied, not moved. Legacy tables remain intact.

### Phase 3 — Worker type update

Update `server/worker/src/types.ts` to add:

- `MediaObjectRow`
- `RaceRow`
- `RaceMemberRow`
- `RaceProgressRow`
- `MoveLogRow`
- New fields on `ProfileRow` (`avatar_object_key`, `is_demo`)

### Phase 4 — Route refactor

Update these route files to use the new schema:

- `server/worker/src/routes/races.ts`
- `server/worker/src/routes/profile.ts`
- `server/worker/src/routes/arena.ts`

Key changes:

- `races.ts` now reads `races`, `race_members`, `race_progress`, `move_logs`, and `race_invites`.
- `profile.ts` tracks uploads in `media_objects` and writes `avatar_object_key`.
- `arena.ts` aggregates from `race_members` and `race_progress`.

### Phase 5 — Demo seed

Run `server/worker/scripts/demo_seed.sql` to populate demo users, races, members, progress, and moves.

### Phase 6 — Verification

Run:

```bash
cd server/worker
npm run typecheck
```

Expected result: zero errors.

Optional smoke tests:

1. Create a race via the app.
2. Join a race via invite code.
3. Submit a manual proof.
4. Submit a MoveCheck proof.
5. Check the arena snapshot.
6. Upload a profile photo.

---

## 3. Field mapping

### `races_legacy` → `races`

| Legacy column | New column | Notes |
|---|---|---|
| `id` | `id` | copied |
| `creator_id` | `creator_id` | copied |
| `title` | `title` | copied |
| `description` | `description` | copied |
| `status` | `status` | copied |
| `race_type` | `race_type` | copied |
| `proof_requirement` | `verification_type` | `ai_check` → `movecheck` |
| `proof_mode` | — | dropped (redundant) |
| `ai_activity_type` | `movement_type` | copied |
| `target_value` | `target_value` | copied |
| `unit` / `target_unit` | `target_unit` | coalesce to `target_unit` |
| `start_line_at` | `start_line_at` | copied |
| `finish_line_at` | `finish_line_at` | copied |
| `visibility` | `visibility` | copied |
| `invite_code` | `invite_code` | copied |
| `rules` | `rules` | copied |
| `created_at` | `created_at` | copied |
| `updated_at` | `updated_at` | copied |
| `deleted_at` | `deleted_at` | copied |
| — | `demo_context` | new, defaults to NULL |

### `race_participants_legacy` → `race_members` + `race_progress`

| Legacy column | New table / column | Notes |
|---|---|---|
| `id` | `race_members.id` | copied |
| `race_id` | `race_members.race_id` | copied |
| `user_id` | `race_members.user_id` | copied |
| `status` | `race_members.status` | copied |
| `role` | `race_members.role` | copied |
| `display_name` | `race_members.cached_display_name` | copied |
| `avatar_url` | `race_members.cached_avatar_url` | copied |
| `joined_at` | `race_members.joined_at` | copied |
| `progress_value` | `race_progress.progress_value` | split to progress table |
| `progress_percent` | `race_progress.progress_percent` | split to progress table |
| `completed_at` | `race_progress.completed_at` | split to progress table |

### `proofs_legacy` → `move_logs`

| Legacy column | New column | Notes |
|---|---|---|
| `id` | `id` | copied |
| `race_id` | `race_id` | copied |
| `user_id` | `user_id` | copied |
| `value` | `value` | copied |
| `unit` | `unit` | copied |
| `proof_type` | `source` | `manual` → `manual`, `ai_motion` → `movecheck` |
| `status` | `status` | mapped to new statuses |
| `notes` / `summary` | `summary` | copied |
| `media_url` | `media_object_key` | R2 key, also creates `media_objects` row |
| `created_at` | `submitted_at` | copied |
| `reviewed_at` | `verified_at` | copied |

---

## 4. Backwards compatibility

- Legacy tables remain in place as `*_legacy`.
- The API contract is preserved:
  - `GET /races` still returns the same JSON shape.
  - `GET /races/:id` still returns the same JSON shape.
  - `POST /races/:id/proof` still accepts the same payload.
  - `PATCH /races/:id/proofs/:proofId` still accepts the same payload.
- The Flutter app does not need to change.
- New endpoints are additive:
  - `POST /races/:id/moves`
  - `GET /races/:id/moves`
  - `GET /races/:id/progress/:userId`
  - `PUT /races/:id/progress/:userId`

---

## 5. Rollback procedure

1. Re-deploy the previous Worker version that reads legacy tables.
2. Rename tables back:
   ```sql
   ALTER TABLE races RENAME TO races_simplified;
   ALTER TABLE races_legacy RENAME TO races;
   ALTER TABLE race_participants_legacy RENAME TO race_participants;
   ALTER TABLE proofs_legacy RENAME TO proofs;
   ```
3. Drop the new tables if you are certain they are no longer needed:
   ```sql
   DROP TABLE IF EXISTS race_members;
   DROP TABLE IF EXISTS race_progress;
   DROP TABLE IF EXISTS move_logs;
   DROP TABLE IF EXISTS media_objects;
   DROP TABLE IF EXISTS races_simplified;
   ```

> Do not drop legacy tables until you are fully committed to the simplified schema.

---

## 6. Migration execution checklist

- [ ] Back up the D1 database (export via `wrangler d1 backup create` or dashboard export).
- [ ] Apply migration 0007 (`wrangler d1 migrations apply nuvo_db`).
- [ ] Verify 0007 created new tables and renamed legacy tables.
- [ ] Apply migration 0008.
- [ ] Spot-check row counts:
   ```sql
   SELECT 'races_legacy' AS tbl, COUNT(*) AS n FROM races_legacy
   UNION ALL
   SELECT 'races', COUNT(*) FROM races
   UNION ALL
   SELECT 'race_participants_legacy', COUNT(*) FROM race_participants_legacy
   UNION ALL
   SELECT 'race_members', COUNT(*) FROM race_members;
   ```
- [ ] Deploy the updated Worker.
- [ ] Run `npm run typecheck` locally before deploying.
- [ ] Smoke-test the app: create race, join, submit proof, view arena.
- [ ] Run demo seed if demo data is needed.

---

## 7. Known limitations

- D1 does not enforce foreign keys. Manual edits must keep IDs consistent.
- Race progress rank is not automatically recomputed by D1 triggers; the Worker recomputes ranks after move/proof submissions and progress edits.
- Soft-deleted `media_objects` rows do not automatically delete R2 objects.
