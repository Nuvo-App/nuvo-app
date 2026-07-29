#!/usr/bin/env node

import { execFileSync } from 'node:child_process';

const database = process.env.NUVO_D1_DATABASE || 'nuvo_db';
const remote = !process.argv.includes('--local');
const dryRun = process.argv.includes('--dry-run');

const modeArgs = remote ? ['--remote'] : ['--local'];

const createTables = [
  `CREATE TABLE IF NOT EXISTS race_invites (
    id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL,
    created_by TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'active',
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(race_id) REFERENCES races(id),
    FOREIGN KEY(created_by) REFERENCES users(id)
  )`,
  `CREATE TABLE IF NOT EXISTS crew_connections (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    crew_user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id),
    FOREIGN KEY(crew_user_id) REFERENCES users(id),
    UNIQUE(user_id, crew_user_id)
  )`,
  `CREATE TABLE IF NOT EXISTS race_members (
    id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'racer',
    status TEXT NOT NULL DEFAULT 'active',
    joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cached_display_name TEXT,
    cached_avatar_url TEXT,
    FOREIGN KEY(race_id) REFERENCES races(id),
    FOREIGN KEY(user_id) REFERENCES users(id),
    UNIQUE(race_id, user_id)
  )`,
  `CREATE TABLE IF NOT EXISTS race_progress (
    id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    progress_value INTEGER NOT NULL DEFAULT 0,
    progress_percent INTEGER NOT NULL DEFAULT 0,
    completed_at TEXT,
    rank_cache INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(race_id) REFERENCES races(id),
    FOREIGN KEY(user_id) REFERENCES users(id),
    UNIQUE(race_id, user_id)
  )`,
  `CREATE TABLE IF NOT EXISTS move_logs (
    id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    source TEXT NOT NULL,
    movement_type TEXT,
    value INTEGER,
    unit TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    summary TEXT,
    media_object_key TEXT,
    validator_version TEXT,
    duration_ms INTEGER,
    metadata_json TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    client_submission_id TEXT,
    activity_id TEXT,
    metric TEXT,
    previous_score INTEGER,
    new_score INTEGER,
    previous_rank INTEGER,
    new_rank INTEGER,
    race_completed INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY(race_id) REFERENCES races(id),
    FOREIGN KEY(user_id) REFERENCES users(id)
  )`,
  `CREATE TABLE IF NOT EXISTS race_final_standings (
    id TEXT PRIMARY KEY,
    race_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    rank_position INTEGER NOT NULL,
    score_value INTEGER NOT NULL,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(race_id) REFERENCES races(id),
    FOREIGN KEY(user_id) REFERENCES users(id),
    UNIQUE(race_id, user_id)
  )`,
  `CREATE TABLE IF NOT EXISTS blocked_users (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    blocked_user_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(user_id) REFERENCES users(id),
    FOREIGN KEY(blocked_user_id) REFERENCES users(id),
    UNIQUE(user_id, blocked_user_id)
  )`,
  `CREATE TABLE IF NOT EXISTS media_objects (
    id TEXT PRIMARY KEY,
    owner_user_id TEXT,
    bucket TEXT NOT NULL,
    object_key TEXT NOT NULL UNIQUE,
    public_url TEXT,
    media_type TEXT NOT NULL DEFAULT 'image',
    purpose TEXT NOT NULL DEFAULT 'system_asset',
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TEXT,
    FOREIGN KEY(owner_user_id) REFERENCES users(id)
  )`,
];

const requiredColumns = {
  users: [
    ['terms_accepted_at', 'TEXT'],
  ],
  profiles: [
    ['avatar_object_key', 'TEXT'],
    ['is_demo', 'INTEGER NOT NULL DEFAULT 0'],
  ],
  races: [
    ['rules', 'TEXT'],
    ['proof_requirement', "TEXT NOT NULL DEFAULT 'manual'"],
    ['proof_review_mode', "TEXT NOT NULL DEFAULT 'auto_accept'"],
    ['visibility', "TEXT NOT NULL DEFAULT 'private'"],
    ['deleted_at', 'TEXT'],
    ['movement_type', 'TEXT'],
    ['verification_type', "TEXT NOT NULL DEFAULT 'manual'"],
    ['start_at', 'TEXT'],
    ['end_at', 'TEXT'],
    ['activity_id', 'TEXT'],
    ['metric', 'TEXT'],
    ['format', "TEXT NOT NULL DEFAULT 'first_to_goal'"],
    ['scoring_rule', "TEXT NOT NULL DEFAULT 'cumulative_sum'"],
    ['attempt_duration_seconds', 'INTEGER'],
    ['attempt_limit', 'INTEGER'],
    ['verification_method', "TEXT NOT NULL DEFAULT 'camera_pose'"],
    ['timezone', "TEXT NOT NULL DEFAULT 'America/New_York'"],
    ['recurrence', "TEXT NOT NULL DEFAULT 'none'"],
    ['winner_user_id', 'TEXT'],
    ['completed_at', 'TEXT'],
    ['public_join_enabled', 'INTEGER NOT NULL DEFAULT 1'],
  ],
  race_members: [
    ['user_id', 'TEXT'],
    ['role', "TEXT NOT NULL DEFAULT 'racer'"],
    ['status', "TEXT NOT NULL DEFAULT 'active'"],
    ['joined_at', 'TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP'],
    ['cached_display_name', 'TEXT'],
    ['cached_avatar_url', 'TEXT'],
  ],
  move_logs: [
    ['client_submission_id', 'TEXT'],
    ['activity_id', 'TEXT'],
    ['metric', 'TEXT'],
    ['previous_score', 'INTEGER'],
    ['new_score', 'INTEGER'],
    ['previous_rank', 'INTEGER'],
    ['new_rank', 'INTEGER'],
    ['race_completed', 'INTEGER NOT NULL DEFAULT 0'],
  ],
};

const indexes = [
  'CREATE INDEX IF NOT EXISTS idx_race_invites_code ON race_invites(invite_code)',
  'CREATE INDEX IF NOT EXISTS idx_race_invites_race ON race_invites(race_id)',
  'CREATE INDEX IF NOT EXISTS idx_crew_connections_user ON crew_connections(user_id, status)',
  'CREATE INDEX IF NOT EXISTS idx_crew_connections_crew_user ON crew_connections(crew_user_id, status)',
  'CREATE INDEX IF NOT EXISTS idx_race_members_race ON race_members(race_id, status)',
  'CREATE INDEX IF NOT EXISTS idx_race_members_user ON race_members(user_id, status)',
  'CREATE INDEX IF NOT EXISTS idx_race_progress_race ON race_progress(race_id, progress_percent DESC, progress_value DESC)',
  'CREATE INDEX IF NOT EXISTS idx_race_progress_user ON race_progress(user_id)',
  'CREATE INDEX IF NOT EXISTS idx_move_logs_race ON move_logs(race_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_move_logs_user ON move_logs(user_id, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_move_logs_status ON move_logs(status)',
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_move_logs_client_submission
    ON move_logs(race_id, user_id, client_submission_id)
    WHERE client_submission_id IS NOT NULL`,
  'CREATE INDEX IF NOT EXISTS idx_race_final_standings_race ON race_final_standings(race_id, rank_position)',
  'CREATE INDEX IF NOT EXISTS idx_blocked_users_user ON blocked_users(user_id)',
  'CREATE INDEX IF NOT EXISTS idx_blocked_users_blocked ON blocked_users(blocked_user_id)',
  'CREATE INDEX IF NOT EXISTS idx_media_objects_owner ON media_objects(owner_user_id, status)',
  'CREATE INDEX IF NOT EXISTS idx_media_objects_purpose ON media_objects(purpose, status)',
  'CREATE INDEX IF NOT EXISTS idx_media_objects_object_key ON media_objects(object_key)',
];

function wrangler(args) {
  return execFileSync('npx', ['wrangler', 'd1', 'execute', database, ...modeArgs, ...args], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function execute(sql) {
  if (dryRun) {
    console.log(`[dry-run] ${sql}`);
    return;
  }
  wrangler(['--command', sql]);
  console.log(`[applied] ${sql.split('\n')[0]}`);
}

function query(sql) {
  const output = wrangler(['--json', '--command', sql]);
  const start = output.indexOf('[');
  if (start === -1) throw new Error(`Unable to parse wrangler JSON output:\n${output}`);
  return JSON.parse(output.slice(start));
}

function tableColumns(table) {
  const rows = query(`PRAGMA table_info(${table});`)?.[0]?.results ?? [];
  return new Set(rows.map((row) => row.name));
}

console.log(`Repairing ${remote ? 'remote' : 'local'} D1 schema for ${database}${dryRun ? ' (dry run)' : ''}`);

for (const sql of createTables) execute(sql);

for (const [table, columns] of Object.entries(requiredColumns)) {
  const existing = tableColumns(table);
  for (const [column, definition] of columns) {
    if (!existing.has(column)) execute(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

for (const sql of indexes) execute(sql);

console.log('Schema repair complete.');
