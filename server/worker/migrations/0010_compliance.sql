-- Migration 0010: Privacy/compliance additions for account deletion, terms acceptance,
-- private-profile enforcement, public-demo controls, and moderation.

-- Terms acceptance timestamp. Required before creating user-generated content.
ALTER TABLE users ADD COLUMN terms_accepted_at TEXT;

-- Public-demo races are visible only to signed-in users; joining is not allowed
-- unless the creator explicitly enables it.
ALTER TABLE races ADD COLUMN public_join_enabled INTEGER NOT NULL DEFAULT 1;

-- Table: blocked_users
-- One-way block list for user safety and moderation.
CREATE TABLE IF NOT EXISTS blocked_users (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  blocked_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, blocked_user_id),
  FOREIGN KEY(user_id) REFERENCES users(id),
  FOREIGN KEY(blocked_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_blocked_users_user ON blocked_users(user_id, blocked_user_id);
CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON blocked_users(blocked_user_id);

-- Table: reports
-- User- and content-reports for internal moderation review.
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  reporter_user_id TEXT NOT NULL,
  target_type TEXT NOT NULL,          -- user | race | content
  target_id TEXT NOT NULL,            -- user id, race id, or move log id
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | reviewed | resolved | dismissed
  reviewed_by TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(reporter_user_id) REFERENCES users(id),
  FOREIGN KEY(reviewed_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_user_id, status);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_type, target_id, status);
