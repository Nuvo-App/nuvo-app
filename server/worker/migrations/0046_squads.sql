-- Crew groups ("squads" in the API, shown as "crew" in the app).
--
-- A squad is a named, persistent group joined with a short code. Any race its
-- members create can be linked to the squad: every squad member is added to
-- the race, and the squad keeps a running standings table across all of its
-- races. Additive only — no existing table or column changes.

CREATE TABLE IF NOT EXISTS squads (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  join_code TEXT NOT NULL UNIQUE,         -- short, human-typable (A-Z, 2-9)
  owner_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT,
  FOREIGN KEY(owner_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_squads_owner ON squads(owner_id);

CREATE TABLE IF NOT EXISTS squad_members (
  id TEXT PRIMARY KEY,
  squad_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',    -- owner | member
  status TEXT NOT NULL DEFAULT 'active',  -- active | left
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(squad_id) REFERENCES squads(id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  UNIQUE(squad_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_squad_members_squad ON squad_members(squad_id, status);
CREATE INDEX IF NOT EXISTS idx_squad_members_user ON squad_members(user_id, status);

CREATE TABLE IF NOT EXISTS squad_races (
  id TEXT PRIMARY KEY,
  squad_id TEXT NOT NULL,
  race_id TEXT NOT NULL UNIQUE,           -- a race belongs to at most one squad
  created_by TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(squad_id) REFERENCES squads(id),
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_squad_races_squad ON squad_races(squad_id, created_at);
