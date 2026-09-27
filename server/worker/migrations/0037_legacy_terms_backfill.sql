-- 0037_legacy_terms_backfill.sql — make server Terms/age enforcement safe
-- for accounts that predate it.
--
-- Every existing account created under the deployed Terms (which already
-- required accepting the Terms of Service at signup and contained the 13+
-- eligibility representation). Enabling `hasAcceptedTerms` without a
-- backfill would lock those members out of every UGC write path, so their
-- original acceptance is recorded under the 'legacy' version. If the Terms
-- text is revised past CURRENT_TERMS_VERSION, enforcement can re-gate on
-- version without a rewrite.
--
-- Eligibility: the attestation column records when the member affirmed the
-- minimum age. For existing accounts the Terms acceptance contained that
-- affirmation, so the stamp inherits the acceptance timestamp. Members who
-- never completed acceptance stay unattested — the server refuses their
-- motion-training consent until they attest (POST /auth/age-attestation).

UPDATE users
SET terms_accepted_at = COALESCE(terms_accepted_at, created_at),
    terms_version = COALESCE(terms_version, 'legacy'),
    updated_at = CURRENT_TIMESTAMP
WHERE terms_accepted_at IS NULL;

UPDATE users
SET age_attested_at = terms_accepted_at
WHERE age_attested_at IS NULL
  AND terms_accepted_at IS NOT NULL;
