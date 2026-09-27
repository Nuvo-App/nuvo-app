-- Motion privacy: per-account data keys are wrapped by the Worker-only
-- MOTION_DATA_MASTER_KEY. Raw motion artifacts are encrypted before R2 put.
CREATE TABLE IF NOT EXISTS motion_account_keys (
  account_ref TEXT PRIMARY KEY,
  wrapped_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT
);
