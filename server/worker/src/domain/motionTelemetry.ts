import { generateId } from '../lib/crypto';

export type MotionMetricInput = {
  releaseId: string | null | undefined;
  activityId: string;
  outcome: string;
  failureReason?: string | null;
  detectedValue?: number;
  confidence?: number;
};

function boundedNumber(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export async function recordReleaseMetric(db: D1Database, input: MotionMetricInput): Promise<void> {
  const releaseId = typeof input.releaseId === 'string' ? input.releaseId.trim() : '';
  const activityId = input.activityId.trim();
  if (!releaseId || !activityId) return;
  const outcome = input.outcome.trim().slice(0, 32) || 'incomplete';
  const failureReason = typeof input.failureReason === 'string'
    ? input.failureReason.trim().slice(0, 160)
    : '';
  const detectedValue = Math.max(0, Math.trunc(boundedNumber(input.detectedValue)));
  const confidence = Math.max(0, Math.min(1, boundedNumber(input.confidence)));
  try {
    await db.prepare(
      `INSERT INTO motion_release_metrics
         (release_id, activity_id, outcome, failure_reason, sample_count, total_detected, total_confidence)
       VALUES (?, ?, ?, ?, 1, ?, ?)
       ON CONFLICT(release_id, activity_id, outcome, failure_reason) DO UPDATE SET
         sample_count = sample_count + 1,
         total_detected = total_detected + excluded.total_detected,
         total_confidence = total_confidence + excluded.total_confidence,
         last_seen_at = CURRENT_TIMESTAMP`,
    ).bind(releaseId, activityId, outcome, failureReason, detectedValue, confidence).run();
  } catch {
    // Telemetry aggregation must never block proof upload or completion. The
    // R2 artifact and motion_sessions row remain the source for backfill.
  }
}

export async function recordFeedback(
  db: D1Database,
  input: { motionSessionId: string; userId: string; label: string; note?: string | null },
): Promise<void> {
  await db.prepare(
    `INSERT OR IGNORE INTO motion_feedback_labels
       (id, motion_session_id, user_id, label, note)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(
    generateId(),
    input.motionSessionId,
    input.userId,
    input.label,
    input.note?.trim().slice(0, 500) ?? null,
  ).run();
}
