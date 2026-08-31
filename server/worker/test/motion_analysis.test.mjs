import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { analyzeMotion, validateMotionRequest, motionAnalysisSchemaVersion } = require('../.tmp-test-dist/domain/motionAnalysis.js');

function frame(timestampMs, hipY, visible = true) {
  return {
    timestampMs,
    landmarks: visible ? {
      leftHip: { x: 0.45, y: hipY },
      rightHip: { x: 0.55, y: hipY },
    } : {},
  };
}

test('motion contract rejects malformed and unsupported requests', () => {
  assert.throws(() => validateMotionRequest(null), /object/);
  assert.throws(() => validateMotionRequest({ schemaVersion: 99, motionId: 'squat', frames: [] }), /schema/);
  assert.throws(() => validateMotionRequest({ schemaVersion: motionAnalysisSchemaVersion, motionId: 'squat', frames: [frame(0, 0.5)] }), /between 2/);
});

test('baseline analysis returns a reviewable result with versions and evidence', () => {
  const request = validateMotionRequest({
    schemaVersion: motionAnalysisSchemaVersion,
    motionId: 'squat',
    targetReps: 1,
    durationMs: 800,
    frames: [
      frame(0, 0.4), frame(100, 0.6), frame(200, 0.4),
      frame(300, 0.6), frame(400, 0.4),
    ],
  });
  const result = analyzeMotion(request);
  assert.equal(result.schemaVersion, 1);
  assert.equal(result.motionId, 'squat');
  assert.ok(result.modelVersion);
  assert.ok(result.validatorVersion);
  assert.ok(result.evidence.length >= 2);
  assert.ok(result.detectedReps >= 1);
});

test('poor visibility produces needs_review rather than a confident verdict', () => {
  const request = validateMotionRequest({
    schemaVersion: motionAnalysisSchemaVersion,
    motionId: 'squat',
    frames: [frame(0, 0.5, false), frame(100, 0.6, false), frame(200, 0.5, true), frame(300, 0.6, false)],
  });
  const result = analyzeMotion(request);
  assert.equal(result.verdict, 'needs_review');
  assert.ok(result.uncertainty > 0.5);
  assert.match(result.failureReasons[0], /visible clearly enough/);
});
