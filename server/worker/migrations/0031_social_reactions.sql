-- Migration 0031: social reactions on activity entities.
--
-- Reactions key off (entity_type, entity_id) — the same entity refs
-- notifications already carry ('race', 'move_log'), so a reaction aggregates
-- across every recipient's copy of the same event. One row per
-- (user, entity): posting a different emoji updates it, DELETE removes it.
-- The row is also the durable ReactionAdded domain-event record — the
-- notification policy layer (docs/agents/21-notification-reengagement-plan)
-- decides later whether it produces a notification; this table is the
-- canonical fact, not a message.

CREATE TABLE IF NOT EXISTS activity_reactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS activity_reactions_entity_idx
  ON activity_reactions (entity_type, entity_id);
