-- Migration 0018: make release changes visible to catalog revalidation.
-- Forward-only compatibility fix for the original 0015 table shape.

ALTER TABLE verifier_releases ADD COLUMN updated_at TEXT;
UPDATE verifier_releases
   SET updated_at = COALESCE(published_at, created_at, CURRENT_TIMESTAMP)
 WHERE updated_at IS NULL;
