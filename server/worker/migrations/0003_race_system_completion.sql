ALTER TABLE races ADD COLUMN rules TEXT;
ALTER TABLE races ADD COLUMN proof_requirement TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE races ADD COLUMN proof_review_mode TEXT NOT NULL DEFAULT 'auto_accept';
ALTER TABLE races ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private';
ALTER TABLE races ADD COLUMN deleted_at TEXT;

ALTER TABLE proofs ADD COLUMN reviewed_by TEXT;
ALTER TABLE proofs ADD COLUMN reviewed_at TEXT;

CREATE TABLE IF NOT EXISTS race_invites (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  created_by TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(created_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_races_deleted_at ON races(deleted_at);
CREATE INDEX IF NOT EXISTS idx_race_invites_code ON race_invites(invite_code);
CREATE INDEX IF NOT EXISTS idx_race_invites_race ON race_invites(race_id);
CREATE INDEX IF NOT EXISTS idx_proofs_reviewed_by ON proofs(reviewed_by);
