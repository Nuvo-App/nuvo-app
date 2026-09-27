-- Migration 0032: notification policy + scheduled reminder jobs
-- (docs/agents/21-notification-reengagement-plan.md §5–6).
--
-- notifications gains the priority the policy assigned and an aggregate
-- counter so rollup rows ("Riley and 3 others joined") can update in place
-- instead of stacking.
--
-- notification_jobs are deterministic scheduled reminders. They NEVER mutate
-- domain state — claim-time handlers re-validate the domain (race still
-- scheduled? recipient still a member?) and no-op when the world moved on.
-- Race correctness lives in domain/raceFinalize.ts; these rows only decide
-- whether a notification should exist at a future moment.

ALTER TABLE notifications ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium';
ALTER TABLE notifications ADD COLUMN aggregate_count INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS notification_jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,            -- race_starting_soon | invite_reminder | …
  entity_type TEXT NOT NULL,     -- race | invite
  entity_id TEXT NOT NULL,
  user_id TEXT,                  -- null = fan out to members at claim time
  dedupe_key TEXT NOT NULL UNIQUE,
  run_at TEXT NOT NULL,
  payload_json TEXT,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending | claimed | sent | cancelled
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_due
  ON notification_jobs(status, run_at);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_entity
  ON notification_jobs(entity_type, entity_id);
