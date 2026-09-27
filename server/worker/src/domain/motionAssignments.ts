import { readMotionRelease, type RegistryRelease } from './motionRegistry';

export type RaceVerifierAssignment = {
  raceId: string;
  activityId: string;
  releaseId: string;
  releaseChecksum: string;
  assignmentPolicy: 'pinned' | 'follow_compatible_patch';
  compatibilityGroup: string;
  assignmentReason: string;
};

type AssignmentRow = {
  race_id: string;
  activity_id: string;
  release_id: string;
  release_checksum: string;
  assignment_policy: 'pinned' | 'follow_compatible_patch';
  compatibility_group: string;
  assignment_reason: string;
};

type ReleasePointerRow = {
  release_id: string;
  checksum: string;
  compatibility_group: string;
  change_class: string;
  status: string;
};

/// Deterministic per-user rollout bucket in [0, 100):
/// `sha256(userId:releaseId)[0..3] % 100`. The same user always lands in the
/// same bucket for a given release, so a rollout cohort is stable across
/// requests and devices — no per-request randomness.
export async function rolloutBucketForUser(
  userId: string,
  releaseId: string,
): Promise<number> {
  const digest = new Uint8Array(
    await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(`${userId}:${releaseId}`),
    ),
  );
  const value =
    ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >>> 0;
  return value % 100;
}

/// The stable release immediately before [excludeReleaseId] for an activity —
/// used when a partial rollout buckets a user out of the current pointer.
async function previousStableRelease(
  db: D1Database,
  activityId: string,
  excludeReleaseId: string,
): Promise<RegistryRelease | null> {
  const row = await db.prepare(
    'SELECT id FROM verifier_releases WHERE activity_id = ? AND status = ? AND id <> ? ' +
    'ORDER BY published_at DESC, created_at DESC LIMIT 1',
  ).bind(activityId, 'stable', excludeReleaseId).first<{ id: string }>();
  return row ? readMotionRelease(db, row.id) : null;
}

/**
 * Resolves the stable release for an activity. When the channel pointer is a
 * partial rollout (`0 < rollout_percent < 100`) and a [userId] is available,
 * the user's deterministic bucket decides: in-bucket users get the pointed
 * release; out-of-bucket users fall back to the previous stable release so
 * they are never left without a verifier while a rollout is ramping.
 * Without a userId a partial rollout serves the pointed release — the race-
 * creation path always supplies one, so this only affects anonymous reads.
 */
export async function stableReleaseForActivity(
  db: D1Database,
  activityId: string,
  userId?: string,
): Promise<RegistryRelease | null> {
  const pointer = await db.prepare(
    'SELECT vr.id, cr.rollout_percent FROM activity_channel_releases cr ' +
    'JOIN verifier_releases vr ON vr.id = cr.release_id ' +
    'WHERE cr.activity_id = ? AND cr.channel = ? AND cr.rollout_percent > 0 ' +
    'AND vr.status = ? LIMIT 1',
  ).bind(activityId, 'stable', 'stable').first<{ id: string; rollout_percent: number }>();
  if (!pointer) return null;
  if (userId && pointer.rollout_percent < 100) {
    const bucket = await rolloutBucketForUser(userId, pointer.id);
    if (bucket >= pointer.rollout_percent) {
      return previousStableRelease(db, activityId, pointer.id);
    }
  }
  return readMotionRelease(db, pointer.id);
}

export async function assignmentForRace(
  db: D1Database,
  raceId: string,
): Promise<RaceVerifierAssignment | null> {
  const row = await db.prepare(
    'SELECT race_id, activity_id, release_id, release_checksum, assignment_policy, ' +
    'compatibility_group, assignment_reason FROM race_verifier_assignments ' +
    'WHERE race_id = ? LIMIT 1',
  ).bind(raceId).first<AssignmentRow>();
  if (!row) return null;
  return {
    raceId: row.race_id,
    activityId: row.activity_id,
    releaseId: row.release_id,
    releaseChecksum: row.release_checksum,
    assignmentPolicy: row.assignment_policy,
    compatibilityGroup: row.compatibility_group,
    assignmentReason: row.assignment_reason,
  };
}

export function assignmentInsert(
  db: D1Database,
  raceId: string,
  release: RegistryRelease,
  policy: 'pinned' | 'follow_compatible_patch' = 'follow_compatible_patch',
  reason = 'race_created',
) {
  return db.prepare(
    'INSERT INTO race_verifier_assignments ' +
    '(race_id, activity_id, release_id, release_checksum, assignment_policy, compatibility_group, assignment_reason) ' +
    'VALUES (?, ?, ?, ?, ?, ?, ?)',
  ).bind(
    raceId,
    release.activityId,
    release.id,
    release.checksum,
    policy,
    release.compatibilityGroup,
    reason,
  );
}

export async function assignmentForNextSession(
  db: D1Database,
  raceId: string,
): Promise<{ assignment: RaceVerifierAssignment; release: RegistryRelease } | null> {
  const assignment = await assignmentForRace(db, raceId);
  if (!assignment) return null;
  let release = await readMotionRelease(db, assignment.releaseId);
  if (!release) return null;

  if (assignment.assignmentPolicy === 'follow_compatible_patch') {
    const pointer = await db.prepare(
      'SELECT vr.id AS release_id, vr.checksum, vr.compatibility_group, ' +
      'vr.change_class, vr.status FROM activity_channel_releases cr ' +
      'JOIN verifier_releases vr ON vr.id = cr.release_id ' +
      'WHERE cr.activity_id = ? AND cr.channel = ? LIMIT 1',
    ).bind(assignment.activityId, 'stable').first<ReleasePointerRow>();
    const open = await db.prepare(
      'SELECT id FROM verification_sessions WHERE race_id = ? AND status IN (?, ?) LIMIT 1',
    ).bind(raceId, 'created', 'running').first<{ id: string }>();
    const compatiblePatch = pointer &&
      pointer.release_id !== assignment.releaseId &&
      pointer.status === 'stable' &&
      pointer.change_class === 'patch' &&
      pointer.compatibility_group === assignment.compatibilityGroup &&
      !open;
    if (compatiblePatch) {
      await db.prepare(
        'UPDATE race_verifier_assignments SET release_id = ?, release_checksum = ?, ' +
        'compatibility_group = ?, assignment_reason = ?, updated_at = CURRENT_TIMESTAMP WHERE race_id = ?',
      ).bind(
        pointer.release_id,
        pointer.checksum,
        pointer.compatibility_group,
        'compatible_patch',
        raceId,
      ).run();
      release = await readMotionRelease(db, pointer.release_id);
      if (!release) return null;
      return {
        assignment: {
          ...assignment,
          releaseId: release.id,
          releaseChecksum: release.checksum,
          compatibilityGroup: release.compatibilityGroup,
          assignmentReason: 'compatible_patch',
        },
        release,
      };
    }
  }
  return { assignment, release };
}
