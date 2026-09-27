-- Verification sessions negotiate only releases published on the stable
-- channel. The initial basketball rollout used the catalog's production
-- label, which made the release visible but unavailable to sessions.
UPDATE verifier_releases
SET status = 'stable',
    updated_at = CURRENT_TIMESTAMP,
    published_at = COALESCE(published_at, CURRENT_TIMESTAMP)
WHERE id = 'basketball_shot-composition-2026.09.1'
  AND status = 'production';
