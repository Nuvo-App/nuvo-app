# Cloudflare D1 Manual Management Guide

This guide is written for anyone managing the Nuvo database directly from the Cloudflare D1 visual editor or `wrangler d1 execute`. It covers the most common manual operations using the **simplified backend schema**.

---

## 1. Where to run SQL

### Option A: Cloudflare dashboard

1. Go to **Workers & Pages** → **D1** → `nuvo_db`.
2. Click the **Console / SQL editor** tab.
3. Paste a query and click **Run**.

### Option B: Wrangler CLI

```bash
wrangler d1 execute nuvo_db --command "SELECT ..."
wrangler d1 execute nuvo_db --file=./scripts/demo_seed.sql
```

---

## 2. Before you edit

- The simplified schema uses `CURRENT_TIMESTAMP` for dates.
- Boolean columns are stored as `INTEGER`: `1` = true, `0` = false.
- UUIDs are plain text. You can use any valid string you like for demo/test rows.
- Foreign keys are **not enforced** by D1. Always verify IDs manually.

---

## 3. Common manual operations

### 3.1 List all active races

```sql
SELECT id, title, status, verification_type, movement_type, target_value, target_unit, created_at
FROM races
WHERE deleted_at IS NULL
ORDER BY created_at DESC;
```

### 3.2 See one race with its members and progress

```sql
SELECT rm.user_id, rm.role, rm.status, rm.cached_display_name,
       rp.progress_value, rp.progress_percent, rp.rank_position, rp.completed_at
FROM race_members rm
LEFT JOIN race_progress rp ON rp.race_id = rm.race_id AND rp.user_id = rm.user_id
WHERE rm.race_id = 'RACE_UUID' AND rm.status = 'active'
ORDER BY rp.progress_percent DESC, rp.progress_value DESC;
```

### 3.3 Add a user to a race

```sql
-- 1. Insert the membership
INSERT INTO race_members (id, race_id, user_id, status, role, cached_display_name, cached_avatar_url, joined_at)
VALUES ('rm-new', 'RACE_UUID', 'USER_UUID', 'active', 'member', 'Display Name', NULL, CURRENT_TIMESTAMP);

-- 2. Initialize their progress row
INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, rank_position, completed_at, updated_at)
VALUES ('rp-new', 'RACE_UUID', 'USER_UUID', 0, 0, NULL, NULL, CURRENT_TIMESTAMP);
```

### 3.4 Update a member's progress

```sql
-- Example: set a user to 75/100 push-ups
UPDATE race_progress
SET progress_value = 75,
    progress_percent = 75,
    completed_at = CASE WHEN 75 >= 100 THEN CURRENT_TIMESTAMP ELSE NULL END,
    updated_at = CURRENT_TIMESTAMP
WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
```

After bulk progress edits, recompute ranks:

```sql
UPDATE race_progress
SET rank_position = (
  SELECT rank_position
  FROM (
    SELECT user_id,
           ROW_NUMBER() OVER (
             PARTITION BY race_id
             ORDER BY progress_percent DESC, progress_value DESC, updated_at ASC
           ) AS rank_position
    FROM race_progress
    WHERE race_id = 'RACE_UUID'
  ) ranked
  WHERE ranked.user_id = race_progress.user_id
)
WHERE race_id = 'RACE_UUID';
```

### 3.5 Submit a move/proof manually

```sql
-- Insert a manual move log
INSERT INTO move_logs (id, race_id, user_id, value, unit, source, status, summary, submitted_at, verified_at)
VALUES ('mv-001', 'RACE_UUID', 'USER_UUID', 25, 'reps', 'manual', 'verified', 'Manual entry from dashboard', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Update the matching progress row
UPDATE race_progress
SET progress_value = progress_value + 25,
    progress_percent = CASE
      WHEN target_value > 0 THEN MIN(100, ROUND(((progress_value + 25) * 100.0) / target_value))
      ELSE 0
    END,
    completed_at = CASE
      WHEN target_value > 0 AND (progress_value + 25) >= target_value THEN CURRENT_TIMESTAMP
      ELSE completed_at
    END,
    updated_at = CURRENT_TIMESTAMP
WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';

-- Note: the target_value reference above must come from the races table.
-- A safer two-step version is shown below.
```

Safer two-step progress update:

```sql
UPDATE race_progress
SET progress_value = (
  SELECT COALESCE(SUM(value), 0)
  FROM move_logs
  WHERE race_id = race_progress.race_id
    AND user_id = race_progress.user_id
    AND status = 'verified'
),
progress_percent = CASE
  WHEN (SELECT target_value FROM races WHERE id = race_progress.race_id) > 0
  THEN MIN(100, ROUND(
    (SELECT COALESCE(SUM(value), 0) FROM move_logs WHERE race_id = race_progress.race_id AND user_id = race_progress.user_id AND status = 'verified')
    * 100.0
    / (SELECT target_value FROM races WHERE id = race_progress.race_id)
  ))
  ELSE 0
END,
completed_at = CASE
  WHEN (SELECT target_value FROM races WHERE id = race_progress.race_id) > 0
       AND (SELECT COALESCE(SUM(value), 0) FROM move_logs WHERE race_id = race_progress.race_id AND user_id = race_progress.user_id AND status = 'verified')
           >= (SELECT target_value FROM races WHERE id = race_progress.race_id)
  THEN CURRENT_TIMESTAMP
  ELSE NULL
END,
updated_at = CURRENT_TIMESTAMP
WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';
```

### 3.6 Create a race manually

```sql
INSERT INTO races (
  id, creator_id, title, description, status,
  race_type, verification_type, movement_type,
  target_value, target_unit,
  start_line_at, finish_line_at,
  visibility, invite_code, rules,
  created_at, updated_at
) VALUES (
  'race-new', 'USER_UUID', 'Demo Push-Up Race', 'First to 50 push-ups.',
  'active', 'first_to_target', 'movecheck', 'pushups',
  50, 'reps',
  CURRENT_TIMESTAMP, NULL,
  'crew_only', NULL, 'Use MoveCheck.',
  CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
```

### 3.7 Create a user manually

```sql
INSERT INTO users (id, primary_email, status, created_at, updated_at, last_login_at)
VALUES ('user-new', 'new@nuvo.app', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO profiles (user_id, full_name, username, avatar_url, avatar_object_key, private_profile, onboarding_complete, is_demo, created_at, updated_at)
VALUES ('user-new', 'New User', 'newuser', NULL, NULL, 0, 1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO member_passes (id, user_id, pass_code, created_at)
VALUES ('pass-new', 'user-new', 'NEW-PASS-001', CURRENT_TIMESTAMP);
```

### 3.8 Reset a race

```sql
-- Remove all move logs for the race
DELETE FROM move_logs WHERE race_id = 'RACE_UUID';

-- Reset all progress
UPDATE race_progress
SET progress_value = 0, progress_percent = 0, rank_position = NULL, completed_at = NULL, updated_at = CURRENT_TIMESTAMP
WHERE race_id = 'RACE_UUID';

-- Optionally set status back to active
UPDATE races SET status = 'active', updated_at = CURRENT_TIMESTAMP WHERE id = 'RACE_UUID';
```

### 3.9 Mark a race as finished

```sql
-- Set the winner(s) to 100%
UPDATE race_progress
SET progress_percent = 100, completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
WHERE race_id = 'RACE_UUID' AND user_id = 'USER_UUID';

-- Archive the race
UPDATE races SET status = 'archived', updated_at = CURRENT_TIMESTAMP WHERE id = 'RACE_UUID';
```

### 3.10 Find orphaned media objects

```sql
-- Media rows whose object_key does not have a matching profile avatar
SELECT mo.*
FROM media_objects mo
LEFT JOIN profiles p ON p.avatar_object_key = mo.object_key
WHERE mo.purpose = 'profile_avatar'
  AND p.user_id IS NULL
  AND mo.status = 'active';
```

### 3.11 Delete a soft-deleted object

```sql
UPDATE media_objects
SET status = 'deleted', deleted_at = CURRENT_TIMESTAMP
WHERE id = 'MEDIA_UUID';

-- The corresponding R2 object is NOT deleted by this query. Remove it from the
-- R2 bucket separately if desired.
```

---

## 4. Manual management checklist

When editing from the dashboard:

- [ ] Did you use single quotes for strings and UUIDs?
- [ ] Did you set `updated_at = CURRENT_TIMESTAMP` on modified rows?
- [ ] Did you update `race_progress.rank_position` after changing progress?
- [ ] Did you verify foreign-key IDs exist before inserting?
- [ ] Did you avoid touching `*_legacy` tables unless rolling back?

---

## 5. Rollback notes

If the simplified schema causes problems, the legacy tables can be reactivated by renaming:

```sql
ALTER TABLE races RENAME TO races_simplified;
ALTER TABLE races_legacy RENAME TO races;
ALTER TABLE race_participants RENAME TO race_participants_simplified; -- if it existed
ALTER TABLE race_participants_legacy RENAME TO race_participants;
ALTER TABLE proofs RENAME TO proofs_simplified; -- if it existed
ALTER TABLE proofs_legacy RENAME TO proofs;
```

> Only run these if you are intentionally rolling back. The Worker code would also need to be reverted.
