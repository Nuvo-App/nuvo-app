-- Migration 0028: real (not simulated) crew presence.
-- Adds users.last_active_at, touched on /auth/me (every session restore and
-- periodic re-check). Exposed on crew list responses as lastActiveAt so the
-- client can render "Active now / Xh ago / Xd ago" from a genuine timestamp
-- instead of fabricating an online indicator.

ALTER TABLE users ADD COLUMN last_active_at TEXT;
