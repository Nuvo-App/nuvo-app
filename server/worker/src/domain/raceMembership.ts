/**
 * Shared race-membership primitives. The invite-acceptance path
 * (routes/invites.ts) and the legacy join-code path (routes/races.ts) must
 * produce IDENTICAL membership state, so the "add a person to a race" steps
 * live here rather than being reimplemented per entry point.
 *
 * NOTE: routes/races.ts still carries its own private copies of these (it
 * predates this module and is the critical race path — not touched in the
 * social-platform pass). Consolidating races.ts onto this module is a safe
 * follow-up. Keep the two in sync until then.
 */
import type { RaceRow } from '../types';
import { generateId } from '../lib/crypto';

export async function getRace(db: D1Database, raceId: string): Promise<RaceRow | null> {
  return db
    .prepare('SELECT * FROM races WHERE id = ? AND deleted_at IS NULL')
    .bind(raceId)
    .first<RaceRow>();
}

export async function getProfileName(db: D1Database, userId: string): Promise<string | null> {
  const row = await db
    .prepare('SELECT full_name FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<{ full_name: string | null }>();
  return row?.full_name ?? null;
}

/**
 * race_members.person_id is a legacy NOT NULL FK to people(id); every member
 * row must resolve to a people row first.
 */
export async function ensurePersonId(db: D1Database, userId: string): Promise<string> {
  const existing = await db
    .prepare('SELECT id FROM people WHERE user_id = ?')
    .bind(userId)
    .first<{ id: string }>();
  if (existing) return existing.id;
  const personId = generateId();
  const displayName = await getProfileName(db, userId);
  await db
    .prepare(
      `INSERT INTO people (id, person_key, user_id, display_name, created_at, updated_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    )
    .bind(personId, `user-${userId}`, userId, displayName ?? 'Racer')
    .run();
  return personId;
}

/** Idempotent: a repeated call for an existing member is a no-op. */
export async function ensureMember(
  db: D1Database,
  raceId: string,
  userId: string,
  role = 'racer',
): Promise<{ created: boolean }> {
  const existing = await db
    .prepare('SELECT id FROM race_members WHERE race_id = ? AND user_id = ?')
    .bind(raceId, userId)
    .first<{ id: string }>();
  if (existing) return { created: false };
  const displayName = await getProfileName(db, userId);
  const personId = await ensurePersonId(db, userId);
  await db
    .prepare(
      `INSERT INTO race_members (id, race_id, user_id, person_id, role, status, joined_at, cached_display_name)
       VALUES (?, ?, ?, ?, ?, 'active', CURRENT_TIMESTAMP, ?)`,
    )
    .bind(generateId(), raceId, userId, personId, role, displayName)
    .run();
  return { created: true };
}

/** Idempotent. */
export async function ensureProgress(db: D1Database, raceId: string, userId: string): Promise<void> {
  const existing = await db
    .prepare('SELECT id FROM race_progress WHERE race_id = ? AND user_id = ?')
    .bind(raceId, userId)
    .first<{ id: string }>();
  if (existing) return;
  await db
    .prepare(
      `INSERT INTO race_progress (id, race_id, user_id, progress_value, progress_percent, updated_at)
       VALUES (?, ?, ?, 0, 0, CURRENT_TIMESTAMP)`,
    )
    .bind(generateId(), raceId, userId)
    .run();
}
