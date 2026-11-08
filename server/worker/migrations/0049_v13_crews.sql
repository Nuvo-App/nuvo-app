-- v13 crew additions (W2). Additive only: new columns on squads /
-- squad_members, the recurring-race tables, and the crew activity log.
-- Existing columns, rows and contracts are untouched.
--
--   squads.bio / color_key / icon_key — crew identity (client maps keys)
--   squad_members.muted_at            — per-member crew mute
--   squad_members.status 'requested'  — join requests reuse the existing
--                                       free-TEXT status column (no CHECK)
--   squad_recurring_races             -- a weekly race definition per crew
--   squad_recurring_optouts           -- per-member auto-join opt-out
--   crew_activity                     -- append-only feed source for things
--                                        that are not race events (today:
--                                        badge_earned when a friend earns
--                                        an achievement)

ALTER TABLE squads ADD COLUMN bio TEXT;
ALTER TABLE squads ADD COLUMN color_key TEXT;   -- coral|sun|lilac|mint|sky
ALTER TABLE squads ADD COLUMN icon_key TEXT;

ALTER TABLE squad_members ADD COLUMN muted_at TEXT;

CREATE TABLE IF NOT EXISTS squad_recurring_races (
  id TEXT PRIMARY KEY,
  squad_id TEXT NOT NULL,
  title TEXT NOT NULL,
  activity_id TEXT,
  race_type TEXT,
  target_value INTEGER,
  target_unit TEXT,
  weekday INTEGER NOT NULL CHECK (weekday BETWEEN 0 AND 6), -- 0=Sunday..6=Saturday (UTC)
  auto_join INTEGER NOT NULL DEFAULT 1,
  active INTEGER NOT NULL DEFAULT 1,
  last_spawned_at TEXT,
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(squad_id) REFERENCES squads(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_squad_recurring_squad ON squad_recurring_races(squad_id, active);
-- Cron sweep: WHERE active = 1 AND weekday = <utc weekday>
CREATE INDEX IF NOT EXISTS idx_squad_recurring_spawn ON squad_recurring_races(active, weekday);

CREATE TABLE IF NOT EXISTS squad_recurring_optouts (
  recurring_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (recurring_id, user_id),
  FOREIGN KEY(recurring_id) REFERENCES squad_recurring_races(id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

-- Crew activity — the durable row behind feed items that are not race
-- events. `ref_id` points at the source record (badge_earned → the
-- user_unlocks.unlock_id); UNIQUE(actor, kind, ref) keeps a re-granted
-- achievement from double-posting after a revoke/re-award cycle.
CREATE TABLE IF NOT EXISTS crew_activity (
  id TEXT PRIMARY KEY,
  actor_user_id TEXT NOT NULL,
  kind TEXT NOT NULL,               -- badge_earned
  ref_id TEXT,
  payload_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(actor_user_id) REFERENCES users(id),
  UNIQUE (actor_user_id, kind, ref_id)
);

CREATE INDEX IF NOT EXISTS idx_crew_activity_actor ON crew_activity(actor_user_id, created_at);
