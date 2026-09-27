-- 0035_proof_review_mode.sql
-- Restore proof_review_mode on races. It was added in 0003 but lost when
-- 0007 rebuilt the `races` table, so the review policy silently defaulted to
-- auto_accept. Pending/peer-review races need this column to gate scoring.
ALTER TABLE races ADD COLUMN proof_review_mode TEXT NOT NULL DEFAULT 'auto_accept';
