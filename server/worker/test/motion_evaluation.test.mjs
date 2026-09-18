import assert from 'node:assert/strict';
import test from 'node:test';

const { parseEvaluationReport, decideEvaluation, adaptationRecommendation } = await import(
  '../.tmp-test-dist/domain/motionEvaluation.js'
);

const baseline = {
  validRepRecall: 0.8,
  falsePositiveRate: 0.03,
  readinessSuccessRate: 0.75,
  frameP95Ms: 32,
  unsupportedSpecRate: 0,
  proofMismatchRate: 0,
};

test('good replay report passes the Worker safety gate', () => {
  const report = parseEvaluationReport({
    datasetSnapshotId: 'heldout-2026-09-17',
    sampleCount: 40,
    hardGatesPassed: true,
    baseline,
    candidate: {
      ...baseline,
      validRepRecall: 0.88,
      falsePositiveRate: 0.032,
      readinessSuccessRate: 0.82,
      frameP95Ms: 34,
    },
  });
  assert.deepEqual(decideEvaluation(report), { status: 'passed', blockers: [] });
});

test('regression is blocked even when the report is well-formed', () => {
  const report = parseEvaluationReport({
    datasetSnapshotId: 'heldout-2026-09-17',
    sampleCount: 40,
    hardGatesPassed: true,
    baseline,
    candidate: { ...baseline, falsePositiveRate: 0.08 },
  });
  const decision = decideEvaluation(report);
  assert.equal(decision.status, 'blocked');
  assert.ok(decision.blockers.includes('false_positive_rate_regressed'));
});

test('insufficient samples cannot be treated as an adaptation signal', () => {
  assert.deepEqual(adaptationRecommendation('depth_not_reached', 4), {
    kind: 'insufficient_sample',
    action: 'collect_more_attempts',
  });
});
