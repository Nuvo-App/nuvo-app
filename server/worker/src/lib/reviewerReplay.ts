// Canonical store-review replay reset — testing@getnuvo.net.
//
// The shared App Review credential is a STABLE backend identity that must
// always present the GENUINE first-use experience: every /auth/reviewer
// sign-in returns the account to its just-created state so the reviewer can
// replay setup → story → notification education → first-race guide → real
// proof → Profile progression on every cold launch, indefinitely, with
// exactly one user row and zero accumulated artifacts.
//
// What is preserved (the seeded review world — google_review_seed.sql):
//   the users row, the member pass, the reviewer auth identity, the
//   review-person-* row, all review-race-* races, all review-crew-* accounts,
//   and every seeded row owned by a review-crew member.
//
// What is reset to the seeded baseline:
//   reviewer-owned rows inside seeded races (membership, progress, move logs,
//   standings) are deleted and re-asserted from the seed values, so progress
//   submitted during a replay never drifts the seeded leaderboard.
//
// What is deleted (prior-replay artifacts):
//   non-seeded races the reviewer created (with full child cleanup),
//   reviewer-authored move logs / proofs / attempts / votes / verification
//   sessions / reactions / personal bests, reviewer XP / unlocks /
//   progression, reviewer notifications (both directions), reviewer invites
//   and invite uses, non-seeded crew connections, reports the reviewer
//   filed, blocks involving the reviewer, sessions, OTP codes, and
//   reviewer-owned media objects.
//
// First-run fields are cleared so the client walks the REAL setup path:
//   terms, age attestation, motion consent, name/username, avatar,
//   onboarding_complete — and is_demo is pinned to 0 so the reviewer sees
//   the production data world, not the presentation fixture layer.

// Reviewer-created replay races are never the seeded review-race-* rows.
const NOT_SEEDED_RACE = "id NOT LIKE 'review-race-%'";

/// Every statement is idempotent and scoped to reviewer-owned rows — this
/// runs on EVERY reviewer sign-in, so it must be safe to replay N times.
export async function resetReviewerReplayState(
  db: D1Database,
  r2: R2Bucket | undefined,
  userId: string,
): Promise<void> {
  // ── 1. Non-seeded races created during prior replays ─────────────────────
  // Full child cleanup, mirroring hardDeleteAccount's per-race order — but
  // unconditional (these are disposable replay artifacts, never shared data
  // another real user depends on, and never the seeded review-race-* rows).
  const ownedRaces = await db
    .prepare(
      `SELECT id FROM races WHERE creator_id = ? AND ${NOT_SEEDED_RACE}`,
    )
    .bind(userId)
    .all<{ id: string }>();

  for (const race of ownedRaces.results) {
    await db.prepare('DELETE FROM race_members WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_progress WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM proof_votes WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_attempts WHERE race_id = ?').bind(race.id).run();
    await db
      .prepare(
        'DELETE FROM personal_bests WHERE race_id = ? OR move_log_id IN (SELECT id FROM move_logs WHERE race_id = ?)',
      )
      .bind(race.id, race.id)
      .run();
    await db.prepare('DELETE FROM move_logs WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_invites WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_final_standings WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_events WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM verification_sessions WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM proofs WHERE race_id = ?').bind(race.id).run();
    await db.prepare('DELETE FROM race_participants WHERE race_id = ?').bind(race.id).run();
    await db
      .prepare("DELETE FROM activity_reactions WHERE entity_type = 'race' AND entity_id = ?")
      .bind(race.id)
      .run();
    await db
      .prepare("DELETE FROM notification_jobs WHERE entity_type = 'race' AND entity_id = ?")
      .bind(race.id)
      .run();
    const raceInvites = await db
      .prepare("SELECT id FROM invites WHERE target_type = 'race' AND target_id = ?")
      .bind(race.id)
      .all<{ id: string }>();
    for (const inv of raceInvites.results) {
      await db.prepare('DELETE FROM invite_uses WHERE invite_id = ?').bind(inv.id).run();
    }
    await db
      .prepare("DELETE FROM invites WHERE target_type = 'race' AND target_id = ?")
      .bind(race.id)
      .run();
    // Proof evidence uploaded under this race's key prefix.
    const mediaPrefix = `proof-evidence/${race.id}/`;
    const raceMedia = await db
      .prepare('SELECT object_key FROM media_objects WHERE SUBSTR(object_key, 1, ?) = ?')
      .bind(mediaPrefix.length, mediaPrefix)
      .all<{ object_key: string }>();
    if (r2) {
      for (const obj of raceMedia.results) {
        try { await r2.delete(obj.object_key); } catch { /* idempotent */ }
      }
    }
    await db
      .prepare('DELETE FROM media_objects WHERE SUBSTR(object_key, 1, ?) = ?')
      .bind(mediaPrefix.length, mediaPrefix)
      .run();
    await db.prepare('DELETE FROM races WHERE id = ?').bind(race.id).run();
  }

  // ── 2. Reviewer-authored residue inside seeded races + personal records ──
  // move_logs: reviewer's seeded logs (review-move-*) are re-asserted below,
  // so deleting them here is part of the re-normalization, not data loss.
  await db
    .prepare(
      'DELETE FROM proof_votes WHERE voter_user_id = ? OR move_log_id IN (SELECT id FROM move_logs WHERE user_id = ?)',
    )
    .bind(userId, userId)
    .run();
  await db.prepare('DELETE FROM personal_bests WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM race_attempts WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM verification_sessions WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM proofs WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM race_participants WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM activity_reactions WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM move_logs WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM race_progress WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM race_final_standings WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM race_members WHERE user_id = ?').bind(userId).run();
  await db
    .prepare("DELETE FROM race_invites WHERE created_by = ? AND race_id NOT LIKE 'review-race-%'")
    .bind(userId)
    .run();
  await db
    .prepare('DELETE FROM race_events WHERE actor_user_id = ? OR subject_user_id = ?')
    .bind(userId, userId)
    .run();

  // Reviewer-minted universal invites (+ uses), and uses the reviewer made.
  const myInvites = await db
    .prepare('SELECT id FROM invites WHERE actor_user_id = ?')
    .bind(userId)
    .all<{ id: string }>();
  for (const inv of myInvites.results) {
    await db.prepare('DELETE FROM invite_uses WHERE invite_id = ?').bind(inv.id).run();
  }
  await db.prepare('DELETE FROM invites WHERE actor_user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM invite_uses WHERE user_id = ?').bind(userId).run();

  // Progression — a fresh account earns its first XP every run.
  await db.prepare('DELETE FROM xp_events WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM user_unlocks WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM user_featured_badges WHERE user_id = ?').bind(userId).run();
  await db.prepare('DELETE FROM user_progression WHERE user_id = ?').bind(userId).run();

  // Inbox both directions, pending notification jobs, moderation residue.
  await db
    .prepare('DELETE FROM notifications WHERE user_id = ? OR actor_user_id = ?')
    .bind(userId, userId)
    .run();
  await db.prepare('DELETE FROM notification_jobs WHERE user_id = ?').bind(userId).run();
  // `reports` is not in every schema snapshot — guard so a missing table can
  // never turn a reviewer sign-in into a 500.
  const tableNames = await db
    .prepare("SELECT name FROM sqlite_master WHERE type = 'table'")
    .all<{ name: string }>();
  if (tableNames.results.some((t) => t.name === 'reports')) {
    await db.prepare('DELETE FROM reports WHERE reporter_user_id = ?').bind(userId).run();
  }
  await db
    .prepare('DELETE FROM blocked_users WHERE user_id = ? OR blocked_user_id = ?')
    .bind(userId, userId)
    .run();

  // Non-seeded crew connections (seeded review-crew-link-* are re-asserted below).
  await db
    .prepare(
      "DELETE FROM crew_connections WHERE (user_id = ? OR crew_user_id = ?) AND id NOT LIKE 'review-crew-link-%'",
    )
    .bind(userId, userId)
    .run();

  // Every replay is a fresh authentication — one live session per run.
  await db.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId).run();
  await db.prepare("DELETE FROM email_codes WHERE email = 'testing@getnuvo.net'").run();

  // Reviewer-owned media (avatars, proof uploads from prior runs).
  const media = await db
    .prepare('SELECT object_key FROM media_objects WHERE owner_user_id = ?')
    .bind(userId)
    .all<{ object_key: string }>();
  if (r2) {
    for (const obj of media.results) {
      try { await r2.delete(obj.object_key); } catch { /* idempotent */ }
    }
  }
  await db.prepare('DELETE FROM media_objects WHERE owner_user_id = ?').bind(userId).run();

  // ── 3. Re-assert the seeded baseline rows the purge removed ──────────────
  // Verbatim from google_review_seed.sql. Each insert is gated on the seeded
  // world existing (the race / crew account it belongs to), so an unseeded
  // database still resets cleanly instead of violating foreign keys.
  const seededRaceExists = async (raceId: string) =>
    (await db
      .prepare('SELECT id FROM races WHERE id = ?')
      .bind(raceId)
      .first()) != null;
  const seededCrewReady =
    (await db
      .prepare("SELECT id FROM users WHERE id = 'review-crew-riley'")
      .first()) != null &&
    (await db
      .prepare("SELECT id FROM people WHERE person_key = 'review-person-google'")
      .first()) != null;

  const allSeededRaces =
    (await seededRaceExists('review-race-pushups')) &&
    (await seededRaceExists('review-race-squats')) &&
    (await seededRaceExists('review-race-plank')) &&
    (await seededRaceExists('review-race-lunges'));

  if (seededCrewReady && allSeededRaces) {
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_members
           (id, race_id, person_id, user_id, member_role, member_status, role, status, joined_at, cached_display_name, cached_avatar_url)
         VALUES
           ('review-rm-001', 'review-race-pushups', 'review-person-google', ?, 'owner', 'active', 'creator', 'active', datetime('now', '-2 days'), 'Nuvo Review', NULL),
           ('review-rm-005', 'review-race-squats', 'review-person-google', ?, 'member', 'active', 'racer', 'active', datetime('now', '-1 day'), 'Nuvo Review', NULL),
           ('review-rm-008', 'review-race-plank', 'review-person-google', ?, 'member', 'active', 'racer', 'active', datetime('now', '-8 days'), 'Nuvo Review', NULL),
           ('review-rm-010', 'review-race-lunges', 'review-person-google', ?, 'owner', 'active', 'creator', 'active', datetime('now'), 'Nuvo Review', NULL)`,
      )
      .bind(userId, userId, userId, userId)
      .run();

    await db
      .prepare(
        `INSERT OR IGNORE INTO crew_connections (id, user_id, crew_user_id, status, created_at)
         VALUES
           ('review-crew-link-001', ?, 'review-crew-riley', 'active', CURRENT_TIMESTAMP),
           ('review-crew-link-002', ?, 'review-crew-maya', 'active', CURRENT_TIMESTAMP),
           ('review-crew-link-003', ?, 'review-crew-jules', 'active', CURRENT_TIMESTAMP),
           ('review-crew-link-004', 'review-crew-riley', ?, 'active', CURRENT_TIMESTAMP),
           ('review-crew-link-005', 'review-crew-maya', ?, 'active', CURRENT_TIMESTAMP),
           ('review-crew-link-006', 'review-crew-jules', ?, 'active', CURRENT_TIMESTAMP)`,
      )
      .bind(userId, userId, userId, userId, userId, userId)
      .run();
  }

  if (await seededRaceExists('review-race-pushups')) {
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_progress
           (id, race_id, user_id, progress_value, progress_percent, completed_at, rank_cache, updated_at)
         VALUES
           ('review-rp-001', 'review-race-pushups', ?, 68, 68, NULL, 2, CURRENT_TIMESTAMP)`,
      )
      .bind(userId)
      .run();
    await db
      .prepare(
        `INSERT OR IGNORE INTO move_logs
           (id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
            status, summary, media_object_key, validator_version, duration_ms,
            metadata_json, client_submission_id, previous_score, new_score,
            previous_rank, new_rank, race_completed, created_at)
         VALUES
           ('review-move-001', 'review-race-pushups', ?, 'movecheck', 'push_ups', 'push_ups', 'reps', 22, 'reps',
            'verified', '22 push-ups verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 24000,
            '{"reviewSeed":true}', 'review-submission-001', 46, 68, 2, 2, 0, datetime('now', '-4 hours'))`,
      )
      .bind(userId)
      .run();
  }
  if (await seededRaceExists('review-race-squats')) {
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_progress
           (id, race_id, user_id, progress_value, progress_percent, completed_at, rank_cache, updated_at)
         VALUES
           ('review-rp-005', 'review-race-squats', ?, 28, 46, NULL, 2, CURRENT_TIMESTAMP)`,
      )
      .bind(userId)
      .run();
    await db
      .prepare(
        `INSERT OR IGNORE INTO move_logs
           (id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
            status, summary, media_object_key, validator_version, duration_ms,
            metadata_json, client_submission_id, previous_score, new_score,
            previous_rank, new_rank, race_completed, created_at)
         VALUES
           ('review-move-003', 'review-race-squats', ?, 'movecheck', 'squats', 'squats', 'reps', 28, 'reps',
            'verified', '28 squats verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 28000,
            '{"reviewSeed":true}', 'review-submission-003', 0, 28, NULL, 2, 0, datetime('now', '-1 day'))`,
      )
      .bind(userId)
      .run();
  }
  if (await seededRaceExists('review-race-plank')) {
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_progress
           (id, race_id, user_id, progress_value, progress_percent, completed_at, rank_cache, updated_at)
         VALUES
           ('review-rp-008', 'review-race-plank', ?, 300, 100, datetime('now', '-1 day'), 1, CURRENT_TIMESTAMP)`,
      )
      .bind(userId)
      .run();
    await db
      .prepare(
        `INSERT OR IGNORE INTO move_logs
           (id, race_id, user_id, source, movement_type, activity_id, metric, value, unit,
            status, summary, media_object_key, validator_version, duration_ms,
            metadata_json, client_submission_id, previous_score, new_score,
            previous_rank, new_rank, race_completed, created_at)
         VALUES
           ('review-move-004', 'review-race-plank', ?, 'movecheck', 'plank_hold', 'plank_hold', 'seconds', 60, 'seconds',
            'verified', '60 plank seconds verified by AI Motion Proof.', NULL, 'nuvo-ai-motion-v1', 60000,
            '{"reviewSeed":true}', 'review-submission-004', 240, 300, 2, 1, 1, datetime('now', '-1 day'))`,
      )
      .bind(userId)
      .run();
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_final_standings
           (id, race_id, user_id, rank_position, score_value, completed_at, created_at)
         VALUES
           ('review-rfs-001', 'review-race-plank', ?, 1, 300, datetime('now', '-1 day'), CURRENT_TIMESTAMP)`,
      )
      .bind(userId)
      .run();
  }
  if (await seededRaceExists('review-race-lunges')) {
    await db
      .prepare(
        `INSERT OR IGNORE INTO race_progress
           (id, race_id, user_id, progress_value, progress_percent, completed_at, rank_cache, updated_at)
         VALUES
           ('review-rp-010', 'review-race-lunges', ?, 0, 0, NULL, 1, CURRENT_TIMESTAMP)`,
      )
      .bind(userId)
      .run();
  }

  // ── 4. First-run fields — the account owes the genuine setup path ────────
  await db
    .prepare(
      `UPDATE users
       SET status = 'active',
           terms_accepted_at = NULL,
           terms_version = NULL,
           age_attested_at = NULL,
           motion_training_consent = 0,
           motion_consent_version = NULL,
           motion_consented_at = NULL,
           motion_consent_revoked_at = NULL,
           demo_world_enabled = 0,
           demo_world_seed = NULL,
           demo_world_variant = NULL,
           last_login_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = ?`,
    )
    .bind(userId)
    .run();

  // Blank identity + incomplete onboarding + the REAL data world (is_demo = 0
  // keeps the reviewer off the presentation fixture layer).
  await db
    .prepare(
      `UPDATE profiles
       SET full_name = NULL,
           username = NULL,
           avatar_url = NULL,
           avatar_object_key = NULL,
           private_profile = 0,
           onboarding_complete = 0,
           is_demo = 0,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = ?`,
    )
    .bind(userId)
    .run();
}
