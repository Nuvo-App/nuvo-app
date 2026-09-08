-- Migration 0014: Nuvo Social Platform v1.
--
-- One coherent social infrastructure — see docs/agents/19-social-platform-contract.md.
-- Everything additive. crew_connections keeps its shape (existing rows stay
-- valid); it only gains nullable lifecycle columns. No table is rewritten.
--
-- New primitives:
--   invites / invite_uses      — one signed-URL invite model (race / crew / squad)
--   notifications              — notifications as domain objects, not push messages
--   notification_preferences   — per-category in-app + push toggles
--   device_tokens              — push transport registration

-- ─────────────────────────────────────────────────────────────────────────────
-- INVITES — one opaque-token model for every "join / connect" link + QR.
-- The token is a high-entropy random lookup key (NOT derived from any internal
-- id), stored here; the shared URL is https://<host>/j/<token>. Revocable
-- (revoked_at), expirable (expires_at), usage-limited (max_uses / use_count).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS invites (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,             -- opaque, base64url, ~32 bytes entropy
  kind TEXT NOT NULL,                     -- race_join | crew_connect | squad_join
  actor_user_id TEXT NOT NULL,            -- who minted it
  target_type TEXT NOT NULL,              -- race | user | squad
  target_id TEXT NOT NULL,
  max_uses INTEGER,                       -- NULL = unlimited
  use_count INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT,                        -- NULL = no expiry
  revoked_at TEXT,
  metadata TEXT,                          -- JSON blob, optional
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(actor_user_id) REFERENCES users(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_invites_token ON invites(token);
CREATE INDEX IF NOT EXISTS idx_invites_target ON invites(target_type, target_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_invites_actor ON invites(actor_user_id, created_at);

-- One row per (invite, accepting user) — makes acceptance idempotent and gives
-- an audit trail without a second "did I already use this" query path.
CREATE TABLE IF NOT EXISTS invite_uses (
  id TEXT PRIMARY KEY,
  invite_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(invite_id, user_id),
  FOREIGN KEY(invite_id) REFERENCES invites(id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTIFICATIONS — the product-state record. Push is a transport (device_tokens);
-- the in-app inbox is the source of truth. dest_* is a STRUCTURED destination
-- (type + id + optional context), never a raw client route string, so the
-- client owns route construction and presentation can change without data loss.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,                  -- recipient
  category TEXT NOT NULL,                 -- race_invite | race_joined | passed_on_leaderboard | crew_request | ...
  actor_user_id TEXT,                     -- who caused it (avatar), may be null
  title TEXT NOT NULL,
  body TEXT,
  dest_type TEXT,                         -- race | profile | crew | invite | notifications
  dest_id TEXT,
  dest_context TEXT,                      -- e.g. 'leaderboard' | 'review'
  entity_type TEXT,                       -- for grouping / bulk-read (e.g. 'race')
  entity_id TEXT,
  dedupe_key TEXT,                        -- idempotency: one logical event => one row
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id, read_at);
-- Idempotency guard: an emit with a dedupe_key that already exists for this
-- recipient is a no-op (INSERT OR IGNORE).
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_dedupe
  ON notifications(user_id, dedupe_key);

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTIFICATION PREFERENCES — per-category in-app + push. Absent row => category
-- default (transactional: push on; engagement: push off; all in-app on).
-- Essential account/security notices are not represented here (not disableable).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id TEXT NOT NULL,
  category TEXT NOT NULL,
  in_app INTEGER NOT NULL DEFAULT 1,
  push INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(user_id, category),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- DEVICE TOKENS — push registration. Multi-device: many rows per user.
-- disabled_at set when a provider reports the token invalid, or on sign-out.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS device_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token TEXT NOT NULL,
  platform TEXT NOT NULL,                 -- ios | android
  app_version TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disabled_at TEXT,
  UNIQUE(user_id, token),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id, disabled_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- CREW CONNECTIONS — lifecycle upgrade (additive columns only).
-- status already exists ('active' | 'removed'); v1 adds 'pending' | 'declined'
-- for private-profile connect requests. requested_by = user_id who initiated.
-- Existing rows: requested_by / updated_at stay NULL and are treated as legacy
-- active connections by the route code.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE crew_connections ADD COLUMN requested_by TEXT;
ALTER TABLE crew_connections ADD COLUMN updated_at TEXT;
