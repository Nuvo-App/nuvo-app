-- Demo World Mode columns on the users table.
-- All three default to off / null so every existing user is unaffected.
-- Enable per-account via SQL only (see docs/DEMO_WORLD.md for commands).

ALTER TABLE users ADD COLUMN demo_world_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN demo_world_seed    TEXT;
ALTER TABLE users ADD COLUMN demo_world_variant TEXT DEFAULT 'summer_v1';
