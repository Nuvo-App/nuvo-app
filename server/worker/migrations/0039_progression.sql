-- 0039_progression.sql
-- Nuvo Levels: persistent player progression projected from canonical
-- race_events. XP is never written inside the race transaction — a reconcile
-- pass derives awards from durable events, so a progression failure can
-- never affect race truth and backfill uses the same code path as live play.
-- Additive only — no existing column is altered in meaning.

-- ── xp_events ────────────────────────────────────────────────────────────────
-- Idempotent award ledger. One row per (user, source_type, source_id) where
-- source_id is the canonical race_events.id — a proof retry, a finalize
-- retry, or a backfill re-run can never double-award the same event.
CREATE TABLE IF NOT EXISTS xp_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  source_type TEXT NOT NULL,          -- race_events.event_type
  source_id TEXT NOT NULL,            -- race_events.id
  race_id TEXT,
  xp_amount INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, source_type, source_id)
);
CREATE INDEX IF NOT EXISTS idx_xp_events_user ON xp_events(user_id, created_at);

-- ── user_progression ─────────────────────────────────────────────────────────
-- Cached projection state (rebuildable from xp_events). last_seen_level backs
-- the once-only level-up presentation on the client.
CREATE TABLE IF NOT EXISTS user_progression (
  user_id TEXT PRIMARY KEY,
  total_xp INTEGER NOT NULL DEFAULT 0,
  level INTEGER NOT NULL DEFAULT 1,
  last_seen_level INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ── unlock_definitions ───────────────────────────────────────────────────────
-- Generic level-gated rewards. unlock_type is open-ended (badge today;
-- profile_cosmetic / profile_effect / celebration / badge_slot /
-- theme_accent later) so future rewards need no schema migration.
CREATE TABLE IF NOT EXISTS unlock_definitions (
  id TEXT PRIMARY KEY,
  required_level INTEGER NOT NULL,
  unlock_type TEXT NOT NULL,
  unlock_key TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  metadata_json TEXT,                 -- rarity, icon id, cosmetic payload
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (unlock_type, unlock_key)
);
CREATE INDEX IF NOT EXISTS idx_unlock_defs_level
  ON unlock_definitions(required_level) WHERE active = 1;

-- ── user_unlocks ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_unlocks (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  unlock_id TEXT NOT NULL REFERENCES unlock_definitions(id),
  unlocked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  source TEXT NOT NULL DEFAULT 'level',
  UNIQUE (user_id, unlock_id)
);
CREATE INDEX IF NOT EXISTS idx_user_unlocks_user ON user_unlocks(user_id);

-- ── user_featured_badges ─────────────────────────────────────────────────────
-- Ordered feature slots on Profile. (user_id, unlock_id) unique prevents
-- featuring the same badge twice; position is the display slot (0..2).
CREATE TABLE IF NOT EXISTS user_featured_badges (
  user_id TEXT NOT NULL,
  unlock_id TEXT NOT NULL REFERENCES unlock_definitions(id),
  position INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, position),
  UNIQUE (user_id, unlock_id)
);

-- ── launch badge set ─────────────────────────────────────────────────────────
-- Small intentional collection — no filler. Milestones (5/10/15/20/25) carry
-- metadata rarity 'milestone' for a stronger display treatment.
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json)
VALUES
  ('bdg-off-the-line',   2,  'badge', 'off_the_line',   'Off the Line',
   'You left the start line. Now keep moving.',
   '{"icon":"flag","rarity":"standard"}'),
  ('bdg-in-motion',      3,  'badge', 'in_motion',      'In Motion',
   'Three levels in — racing is becoming a habit.',
   '{"icon":"bolt","rarity":"standard"}'),
  ('bdg-five-deep',      5,  'badge', 'five_deep',      'Five Deep',
   'Five levels of real races. This is what momentum looks like.',
   '{"icon":"flame","rarity":"milestone"}'),
  ('bdg-locked-in',      7,  'badge', 'locked_in',      'Locked In',
   'You keep showing up to the start line.',
   '{"icon":"target","rarity":"standard"}'),
  ('bdg-double-digits',  10, 'badge', 'double_digits',  'Double Digits',
   'Level 10. Two digits of real competition.',
   '{"icon":"medal","rarity":"milestone"}'),
  ('bdg-built-different',15, 'badge', 'built_different','Built Different',
   'Fifteen levels deep and still climbing.',
   '{"icon":"trophy","rarity":"milestone"}'),
  ('bdg-veteran',        20, 'badge', 'veteran',        'Veteran',
   'Twenty levels of finish lines crossed.',
   '{"icon":"crown","rarity":"milestone"}'),
  ('bdg-unstoppable',    25, 'badge', 'unstoppable',    'Unstoppable',
   'Most crews never see Level 25.',
   '{"icon":"star","rarity":"milestone"}');
