CREATE TABLE IF NOT EXISTS crew_connections (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  crew_user_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(crew_user_id) REFERENCES users(id),
  UNIQUE(user_id, crew_user_id)
);

CREATE INDEX IF NOT EXISTS idx_crew_connections_user ON crew_connections(user_id, status);
CREATE INDEX IF NOT EXISTS idx_crew_connections_crew_user ON crew_connections(crew_user_id, status);

ALTER TABLE races ADD COLUMN ai_activity_type TEXT;
ALTER TABLE races ADD COLUMN target_unit TEXT;
ALTER TABLE races ADD COLUMN proof_mode TEXT;
