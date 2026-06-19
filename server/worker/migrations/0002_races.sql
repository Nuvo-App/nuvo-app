CREATE TABLE IF NOT EXISTS races (
  id TEXT PRIMARY KEY,
  creator_id TEXT NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  description TEXT,
  category TEXT,
  goal_type TEXT NOT NULL DEFAULT 'manual',
  target_value INTEGER,
  unit TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  start_line_at TEXT,
  finish_line_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS race_participants (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  display_name TEXT,
  progress_value INTEGER NOT NULL DEFAULT 0,
  progress_percent INTEGER NOT NULL DEFAULT 0,
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(race_id, user_id)
);

CREATE TABLE IF NOT EXISTS proofs (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL REFERENCES races(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  proof_type TEXT NOT NULL DEFAULT 'manual',
  note TEXT,
  value INTEGER,
  media_url TEXT,
  verification_status TEXT NOT NULL DEFAULT 'accepted',
  verification_summary TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_races_creator ON races(creator_id);
CREATE INDEX IF NOT EXISTS idx_race_participants_race ON race_participants(race_id);
CREATE INDEX IF NOT EXISTS idx_race_participants_user ON race_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_proofs_race ON proofs(race_id);
CREATE INDEX IF NOT EXISTS idx_proofs_user ON proofs(user_id);
