-- 0036_compliance_consent.sql — server-backed acceptance + consent state.
-- terms_version: which Terms text the acceptance covered.
-- age_attested_at: eligibility attestation (13+) — timestamp, never a DOB.
-- motion training consent: server-backed on/off with versioning.

ALTER TABLE users ADD COLUMN terms_version TEXT;
ALTER TABLE users ADD COLUMN age_attested_at TEXT;
ALTER TABLE users ADD COLUMN motion_training_consent INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN motion_consent_version TEXT;
ALTER TABLE users ADD COLUMN motion_consented_at TEXT;
ALTER TABLE users ADD COLUMN motion_consent_revoked_at TEXT;
