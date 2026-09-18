export type EvaluationMetricSet = {
  validRepRecall: number;
  falsePositiveRate: number;
  readinessSuccessRate: number;
  frameP95Ms: number;
  unsupportedSpecRate: number;
  proofMismatchRate: number;
};

export type EvaluationReport = {
  datasetSnapshotId: string;
  sampleCount: number;
  hardGatesPassed: boolean;
  baseline: EvaluationMetricSet;
  candidate: EvaluationMetricSet;
};

export type EvaluationDecision = {
  status: 'passed' | 'blocked';
  blockers: string[];
};

function finiteRate(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
}

function finiteLatency(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 60_000;
}

function metrics(value: unknown): value is EvaluationMetricSet {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entry = value as Record<string, unknown>;
  return finiteRate(entry.validRepRecall) &&
    finiteRate(entry.falsePositiveRate) &&
    finiteRate(entry.readinessSuccessRate) &&
    finiteLatency(entry.frameP95Ms) &&
    finiteRate(entry.unsupportedSpecRate) &&
    finiteRate(entry.proofMismatchRate);
}

export function parseEvaluationReport(value: unknown): EvaluationReport {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('evaluation_report_invalid');
  }
  const report = value as Record<string, unknown>;
  if (typeof report.datasetSnapshotId !== 'string' || !report.datasetSnapshotId.trim()) {
    throw new Error('dataset_snapshot_required');
  }
  if (typeof report.sampleCount !== 'number' || !Number.isInteger(report.sampleCount) || report.sampleCount < 20 || report.sampleCount > 10_000_000) {
    throw new Error('evaluation_sample_count_invalid');
  }
  if (report.hardGatesPassed !== true) throw new Error('evaluation_hard_gates_required');
  if (!metrics(report.baseline) || !metrics(report.candidate)) throw new Error('evaluation_metrics_invalid');
  return {
    datasetSnapshotId: report.datasetSnapshotId.trim().slice(0, 200),
    sampleCount: report.sampleCount,
    hardGatesPassed: true,
    baseline: report.baseline,
    candidate: report.candidate,
  };
}

/**
 * A Worker-side safety gate. Replay itself happens in the evaluation tool;
 * this gate refuses reports that claim improvement while violating guardrails.
 */
export function decideEvaluation(report: EvaluationReport): EvaluationDecision {
  const blockers: string[] = [];
  const { baseline, candidate } = report;
  if (candidate.validRepRecall < baseline.validRepRecall) blockers.push('valid_rep_recall_regressed');
  if (candidate.falsePositiveRate > baseline.falsePositiveRate + 0.01) blockers.push('false_positive_rate_regressed');
  if (candidate.readinessSuccessRate < baseline.readinessSuccessRate - 0.02) blockers.push('readiness_success_rate_regressed');
  if (candidate.frameP95Ms > Math.max(baseline.frameP95Ms * 1.25, baseline.frameP95Ms + 8)) blockers.push('frame_latency_regressed');
  if (candidate.unsupportedSpecRate > 0.02) blockers.push('unsupported_spec_rate_exceeded');
  if (candidate.proofMismatchRate > 0.02) blockers.push('proof_mismatch_rate_exceeded');
  return { status: blockers.length === 0 ? 'passed' : 'blocked', blockers };
}

export function adaptationRecommendation(failureReason: string, sampleCount: number) {
  const reason = failureReason.trim().toLowerCase();
  if (sampleCount < 5) return { kind: 'insufficient_sample', action: 'collect_more_attempts' };
  if (reason.includes('visibility') || reason.includes('camera') || reason.includes('pose')) {
    return { kind: 'framing_cluster', action: 'review_camera_policy_and_visibility_thresholds' };
  }
  if (reason.includes('depth') || reason.includes('range') || reason.includes('incomplete')) {
    return { kind: 'range_cluster', action: 'review_motion_thresholds_and_hysteresis' };
  }
  return { kind: 'recognition_cluster', action: 'replay_against_labeled_attempts' };
}
