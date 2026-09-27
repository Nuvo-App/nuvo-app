-- 0030_race_v2_engine.sql
-- Race V2 engine: durable domain events, attempts lifecycle, member race
-- state, score direction, live-session flags, personal bests.
-- Additive only — no existing column is altered in meaning.

-- ── race_events ──────────────────────────────────────────────────────────────
-- Append-only domain log of meaningful transitions. The tables remain
-- authoritative for current state; this records what happened (docs/agents/
-- 21-race-system-v2-design.md §19). Consumers: Crew activity, notifications,
-- analytics.
CREATE TABLE IF NOT EXISTS race_events (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  event_type TEXT NOT NULL,
  actor_user_id TEXT,        -- who caused it (null for system transitions)
  subject_user_id TEXT,      -- who it is about (null = the race itself)
  payload_json TEXT,         -- compact structured payload (scores, ranks, gaps)
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_race_events_race ON race_events(race_id, created_at);
CREATE INDEX IF NOT EXISTS idx_race_events_type ON race_events(event_type, created_at);
CREATE INDEX IF NOT EXISTS idx_race_events_subject ON race_events(subject_user_id, created_at);

-- ── race_attempts ────────────────────────────────────────────────────────────
-- One row per declared attempt in best_attempt / timed_attempt races.
-- client_attempt_id makes retry-then-retry idempotent like
-- move_logs.client_submission_id.
CREATE TABLE IF NOT EXISTS race_attempts (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL,
  attempt_index INTEGER NOT NULL,            -- 1-based per (race,user)
  client_attempt_id TEXT,                    -- idempotency key from client
  status TEXT NOT NULL DEFAULT 'open',       -- open | submitted | expired | voided
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- authoritative start
  deadline_at TEXT,                          -- started_at + attempt_duration_seconds (timed only)
  submitted_at TEXT,
  score INTEGER,                             -- locked score once submitted
  move_log_id TEXT REFERENCES move_logs(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (race_id, user_id, attempt_index)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_race_attempts_client
  ON race_attempts(race_id, user_id, client_attempt_id)
  WHERE client_attempt_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_race_attempts_open
  ON race_attempts(race_id, user_id, status);

-- ── race_members: per-member race state ──────────────────────────────────────
-- ready_at: live-race lobby readiness. finished_at/finish_rank: ordered
-- finishes (goal-by-deadline finisher ordering, live race placements).
ALTER TABLE race_members ADD COLUMN ready_at TEXT;
ALTER TABLE race_members ADD COLUMN finished_at TEXT;
ALTER TABLE race_members ADD COLUMN finish_rank INTEGER;

-- ── races: V2 fields ─────────────────────────────────────────────────────────
-- score_direction: 'higher' (most/best wins) or 'lower' (fastest wins).
-- version: bumped on any score/member write — cheap poll guard for live UI.
-- is_live_session/live_window_seconds: presence-window races (Phase F/G).
ALTER TABLE races ADD COLUMN score_direction TEXT NOT NULL DEFAULT 'higher';
ALTER TABLE races ADD COLUMN version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE races ADD COLUMN is_live_session INTEGER NOT NULL DEFAULT 0;
ALTER TABLE races ADD COLUMN live_window_seconds INTEGER;

-- ── personal_bests ───────────────────────────────────────────────────────────
-- Best verified score per (user, activity, metric) from attempt-format races.
CREATE TABLE IF NOT EXISTS personal_bests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  activity_id TEXT NOT NULL,           -- preset activity id or 'custom:<name>' or 'manual:<unit>'
  metric TEXT NOT NULL,
  best_value INTEGER NOT NULL,
  score_direction TEXT NOT NULL DEFAULT 'higher',
  race_id TEXT REFERENCES races(id),
  move_log_id TEXT REFERENCES move_logs(id),
  set_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, activity_id, metric)
);
CREATE INDEX IF NOT EXISTS idx_personal_bests_user ON personal_bests(user_id);
