-- Nuvo Database V2 admin-friendly tables.
-- Adds V2 tables beside the legacy schema and backfills readable control-panel data.

CREATE TABLE IF NOT EXISTS people (
  id TEXT PRIMARY KEY,
  person_key TEXT NOT NULL UNIQUE,
  user_id TEXT UNIQUE,
  display_name TEXT NOT NULL,
  username TEXT UNIQUE,
  avatar_url TEXT,
  avatar_r2_key TEXT,
  bio TEXT,
  is_demo INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_people_user_id ON people(user_id);
CREATE INDEX IF NOT EXISTS idx_people_status ON people(status);
CREATE INDEX IF NOT EXISTS idx_people_demo ON people(is_demo);

ALTER TABLE races ADD COLUMN race_key TEXT;
ALTER TABLE races ADD COLUMN subtitle TEXT;
ALTER TABLE races ADD COLUMN race_type TEXT;
ALTER TABLE races ADD COLUMN created_by_person_id TEXT;
ALTER TABLE races ADD COLUMN cover_url TEXT;
ALTER TABLE races ADD COLUMN cover_r2_key TEXT;
ALTER TABLE races ADD COLUMN demo_priority INTEGER;

CREATE INDEX IF NOT EXISTS idx_races_race_key ON races(race_key);
CREATE INDEX IF NOT EXISTS idx_races_created_by_person ON races(created_by_person_id);
CREATE INDEX IF NOT EXISTS idx_races_demo_priority ON races(demo_priority);

CREATE TABLE IF NOT EXISTS race_members (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  member_role TEXT NOT NULL DEFAULT 'member',
  member_status TEXT NOT NULL DEFAULT 'active',
  score_value INTEGER NOT NULL DEFAULT 0,
  score_percent INTEGER NOT NULL DEFAULT 0,
  rank_override INTEGER,
  is_current_user_highlight INTEGER NOT NULL DEFAULT 0,
  joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_move_at TEXT,
  display_note TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(person_id) REFERENCES people(id),
  UNIQUE(race_id, person_id)
);

CREATE INDEX IF NOT EXISTS idx_race_members_race ON race_members(race_id, member_status);
CREATE INDEX IF NOT EXISTS idx_race_members_person ON race_members(person_id);
CREATE INDEX IF NOT EXISTS idx_race_members_score ON race_members(race_id, score_percent DESC, score_value DESC);

CREATE TABLE IF NOT EXISTS moves (
  id TEXT PRIMARY KEY,
  race_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  amount_value INTEGER,
  amount_unit TEXT,
  move_status TEXT NOT NULL DEFAULT 'checked',
  move_source TEXT NOT NULL DEFAULT 'manual',
  note TEXT,
  media_url TEXT,
  media_r2_key TEXT,
  checked_at TEXT,
  checked_by TEXT,
  ai_summary TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(race_id) REFERENCES races(id),
  FOREIGN KEY(person_id) REFERENCES people(id),
  FOREIGN KEY(checked_by) REFERENCES people(id)
);

CREATE INDEX IF NOT EXISTS idx_moves_race_created ON moves(race_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moves_person_created ON moves(person_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moves_status ON moves(move_status);

CREATE TABLE IF NOT EXISTS media_assets (
  id TEXT PRIMARY KEY,
  owner_person_id TEXT,
  asset_type TEXT NOT NULL,
  bucket_name TEXT NOT NULL DEFAULT 'nuvor2',
  object_key TEXT NOT NULL,
  public_url TEXT NOT NULL,
  mime_type TEXT,
  file_size INTEGER,
  width INTEGER,
  height INTEGER,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(owner_person_id) REFERENCES people(id)
);

CREATE INDEX IF NOT EXISTS idx_media_assets_owner ON media_assets(owner_person_id);
CREATE INDEX IF NOT EXISTS idx_media_assets_type ON media_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_media_assets_object_key ON media_assets(object_key);

CREATE TABLE IF NOT EXISTS admin_change_log (
  id TEXT PRIMARY KEY,
  actor_label TEXT NOT NULL,
  target_table TEXT NOT NULL,
  target_id TEXT NOT NULL,
  change_type TEXT NOT NULL,
  before_json TEXT,
  after_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_change_log_target ON admin_change_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_admin_change_log_created ON admin_change_log(created_at DESC);

INSERT OR IGNORE INTO people (
  id,
  person_key,
  user_id,
  display_name,
  username,
  avatar_url,
  is_demo,
  status,
  created_at,
  updated_at
)
SELECT
  u.id,
  COALESCE(NULLIF(p.username, ''), 'user_' || substr(u.id, 1, 8)),
  u.id,
  COALESCE(NULLIF(p.full_name, ''), NULLIF(p.username, ''), NULLIF(u.primary_email, ''), 'Unknown'),
  NULLIF(p.username, ''),
  NULLIF(p.avatar_url, ''),
  0,
  u.status,
  COALESCE(p.created_at, u.created_at, CURRENT_TIMESTAMP),
  COALESCE(p.updated_at, u.updated_at, CURRENT_TIMESTAMP)
FROM users u
LEFT JOIN profiles p ON p.user_id = u.id;

UPDATE races
SET
  race_key = COALESCE(
    race_key,
    lower(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(trim(title), ' ', '_'),
                '-', '_'
              ),
              '/', '_'
            ),
            ':',
            ''
          ),
          '.',
          ''
        ),
        '''',
        ''
      )
    ) || '_' || substr(id, 1, 8)
  ),
  race_type = COALESCE(race_type, proof_mode, proof_requirement, goal_type, 'manual'),
  created_by_person_id = COALESCE(
    created_by_person_id,
    (SELECT id FROM people WHERE people.user_id = races.creator_id)
  );

INSERT OR IGNORE INTO race_members (
  id,
  race_id,
  person_id,
  member_role,
  member_status,
  score_value,
  score_percent,
  is_current_user_highlight,
  joined_at,
  last_move_at,
  created_at,
  updated_at
)
SELECT
  rp.id,
  rp.race_id,
  p.id,
  CASE WHEN r.creator_id = rp.user_id THEN 'creator' ELSE 'member' END,
  'active',
  rp.progress_value,
  rp.progress_percent,
  CASE WHEN r.creator_id = rp.user_id THEN 1 ELSE 0 END,
  rp.joined_at,
  (
    SELECT max(pr.created_at)
    FROM proofs pr
    WHERE pr.race_id = rp.race_id
      AND pr.user_id = rp.user_id
      AND pr.verification_status IN ('accepted', 'ai_verified')
  ),
  rp.joined_at,
  CURRENT_TIMESTAMP
FROM race_participants rp
JOIN people p ON p.user_id = rp.user_id
JOIN races r ON r.id = rp.race_id;

INSERT OR IGNORE INTO moves (
  id,
  race_id,
  person_id,
  amount_value,
  amount_unit,
  move_status,
  move_source,
  note,
  media_url,
  checked_at,
  checked_by,
  ai_summary,
  created_at,
  updated_at
)
SELECT
  pr.id,
  pr.race_id,
  p.id,
  pr.value,
  COALESCE(r.target_unit, r.unit),
  CASE
    WHEN pr.verification_status IN ('accepted', 'ai_verified') THEN 'checked'
    WHEN pr.verification_status IN ('rejected', 'ai_failed') THEN 'rejected'
    ELSE 'pending'
  END,
  CASE
    WHEN pr.proof_type = 'ai_motion' THEN 'ai'
    WHEN pr.proof_type IN ('photo', 'photo_video') THEN 'photo'
    ELSE 'manual'
  END,
  pr.note,
  pr.media_url,
  CASE
    WHEN pr.verification_status IN ('accepted', 'ai_verified') THEN COALESCE(pr.reviewed_at, pr.created_at)
    ELSE pr.reviewed_at
  END,
  reviewer.id,
  pr.verification_summary,
  pr.created_at,
  CURRENT_TIMESTAMP
FROM proofs pr
JOIN people p ON p.user_id = pr.user_id
JOIN races r ON r.id = pr.race_id
LEFT JOIN people reviewer ON reviewer.user_id = pr.reviewed_by;

DROP VIEW IF EXISTS v_admin_people;
CREATE VIEW v_admin_people AS
SELECT
  p.person_key,
  p.display_name,
  p.username,
  p.avatar_url,
  p.is_demo,
  u.primary_email AS linked_email,
  p.status
FROM people p
LEFT JOIN users u ON u.id = p.user_id
ORDER BY p.is_demo DESC, p.display_name COLLATE NOCASE ASC;

DROP VIEW IF EXISTS v_admin_race_board;
CREATE VIEW v_admin_race_board AS
SELECT
  r.race_key,
  r.title AS race_title,
  r.target_value,
  COALESCE(r.target_unit, r.unit) AS target_unit,
  p.person_key,
  p.display_name,
  p.username,
  p.avatar_url,
  rm.score_value,
  rm.score_percent,
  rank() OVER (
    PARTITION BY rm.race_id
    ORDER BY
      COALESCE(rm.rank_override, 999999) ASC,
      rm.score_percent DESC,
      rm.score_value DESC,
      rm.joined_at ASC
  ) AS rank,
  rm.last_move_at
FROM race_members rm
JOIN races r ON r.id = rm.race_id
JOIN people p ON p.id = rm.person_id
WHERE r.deleted_at IS NULL
  AND rm.member_status = 'active'
ORDER BY r.demo_priority IS NULL, r.demo_priority ASC, r.created_at DESC, rank ASC;

DROP VIEW IF EXISTS v_admin_move_log;
CREATE VIEW v_admin_move_log AS
SELECT
  r.race_key,
  r.title AS race_title,
  p.person_key,
  p.display_name,
  m.amount_value,
  m.amount_unit,
  m.move_status,
  m.move_source,
  m.note,
  m.media_url,
  m.created_at
FROM moves m
JOIN races r ON r.id = m.race_id
JOIN people p ON p.id = m.person_id
ORDER BY m.created_at DESC;
