-- Migration 0052 (onboarding v2, part E): the one-time onboarding reward.
--
-- Additive only. The 100 XP grant itself is a row in the existing xp_events
-- ledger (source_type 'onboarding_v2', source_id 'onboarding_v2'); the
-- table's UNIQUE (user_id, source_type, source_id) makes it idempotent, so
-- no new table is needed. This migration only seeds the "Day One" badge the
-- level-up screen shows.
--
-- unlock_type is 'badge' (NOT 'achievement') so the 43-tile achievement
-- collection and its "0 of 43" count are unchanged. requirement_kind 'stat'
-- with an unknown stat key means reconcileProgression never auto-grants it;
-- only POST /onboarding/complete does, via user_unlocks.
INSERT OR IGNORE INTO unlock_definitions
  (id, required_level, unlock_type, unlock_key, name, description, metadata_json, category, icon_key, requirement_kind, stat_key, threshold, sort_order)
VALUES
  ('bdg-day-one', 0, 'badge', 'day_one', 'Day One',
   'You joined Nuvo and started your first day.',
   '{"rarity":"common"}', 'onboarding', 'flag', 'stat', 'onboarding_day_one', 1, 5);
