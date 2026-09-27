-- 0038_undo_age_backfill.sql — corrects 0037.
--
-- An attestation must record an affirmative act the member actually made.
-- 0037 stamped age_attested_at from the Terms acceptance timestamp, which
-- would have represented an explicit attestation that never happened.
--
-- Terms grandfathering stays — 'legacy' terms_version is still a legitimate
-- recorded acceptance of the text in force at signup. Only the attestation
-- stamp is reverted, and only for rows carrying the exact 0037 signature
-- (terms_version = 'legacy' AND age_attested_at = terms_accepted_at), so a
-- genuine POST /auth/age-attestation row can never be cleared by this.
--
-- Effect: pre-enforcement members must complete the current age-eligibility
-- confirmation before anything that requires it — today that is only the
-- motion-training opt-in (PUT /motion/consent refuses with 403 until then).
-- Ordinary read access, races, proofs, and crew are untouched.

UPDATE users
SET age_attested_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE terms_version = 'legacy'
  AND age_attested_at = terms_accepted_at;
