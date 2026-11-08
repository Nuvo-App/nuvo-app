-- v13 profile additions (W1). Additive only: new columns on profiles and the
-- new user_mutes table. Existing columns, rows and contracts are untouched.
--
--   bio                  — short profile bio (<= 80 chars, enforced by POST /profile)
--   favorite_movement_key — the member's favorite movement chip key
--   activity_map_shared  — 1: others may read GET /users/:id/activity, 0: hidden
--   race_invites_from    — 'everyone' | 'friends' ("who can race me")
--   user_mutes           — a viewer's invisible mute list (users and crews)

ALTER TABLE profiles ADD COLUMN bio TEXT;
ALTER TABLE profiles ADD COLUMN favorite_movement_key TEXT;
ALTER TABLE profiles ADD COLUMN activity_map_shared INTEGER NOT NULL DEFAULT 1;
ALTER TABLE profiles ADD COLUMN race_invites_from TEXT NOT NULL DEFAULT 'everyone';

CREATE TABLE IF NOT EXISTS user_mutes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  target_type TEXT NOT NULL CHECK (target_type IN ('user', 'crew')),
  target_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_user_mutes_user ON user_mutes(user_id);
