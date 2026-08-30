export const motionAnalysisSchemaVersion = 1;
export const motionModelVersion = 'nuvo-motion-baseline-v1';
export const motionValidatorVersion = 'nuvo-motion-server-rules-v1';

export type MotionLandmark = {
  x: number;
  y: number;
  z?: number;
  confidence?: number;
};

export type MotionFrame = {
  timestampMs: number;
  quality?: number;
  landmarks: Record<string, MotionLandmark>;
};

export type MotionAnalysisRequest = {
  schemaVersion: number;
  motionId: string;
  targetReps?: number;
  frames: MotionFrame[];
  durationMs?: number;
};

export type MotionEvidence = {
  key: string;
  label: string;
  value?: number;
  expected?: number;
  status: 'pass' | 'fail' | 'unknown';
};

export type MotionAnalysisResult = {
  schemaVersion: number;
  motionId: string;
  verdict: 'valid' | 'invalid' | 'needs_review';
  detectedReps: number;
  confidence: number;
  uncertainty: number;
  evidence: MotionEvidence[];
  failureReasons: string[];
  coaching: string[];
  modelVersion: string;
  validatorVersion: string;
  framesAnalyzed: number;
  validPoseFrames: number;
  durationMs: number;
};

function finite(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function validFrame(frame: MotionFrame): boolean {
  return finite(frame.timestampMs) && frame.timestampMs >= 0 &&
    Object.values(frame.landmarks).every((point) =>
      finite(point.x) && finite(point.y) &&
      point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1,
    );
}

function hasVisibleLandmarks(frame: MotionFrame): boolean {
  return Object.values(frame.landmarks).some((point) =>
    finite(point.x) && finite(point.y) && point.confidence !== 0,
  );
}

export function validateMotionRequest(input: unknown): MotionAnalysisRequest {
  if (!input || typeof input !== 'object') throw new Error('Request must be an object.');
  const value = input as Record<string, unknown>;
  if (value.schemaVersion !== motionAnalysisSchemaVersion) throw new Error('Unsupported motion schema version.');
  if (typeof value.motionId !== 'string' || value.motionId.length === 0 || value.motionId.length > 120) {
    throw new Error('motionId is required.');
  }
  if (!Array.isArray(value.frames) || value.frames.length < 2 || value.frames.length > 900) {
    throw new Error('frames must contain between 2 and 900 frames.');
  }
  const frames = value.frames as MotionFrame[];
  if (!frames.every(validFrame)) throw new Error('frames contain invalid landmarks.');
  const targetReps = value.targetReps === undefined ? undefined : value.targetReps;
  if (targetReps !== undefined && (!finite(targetReps) || targetReps < 1 || targetReps > 10000)) {
    throw new Error('targetReps is invalid.');
  }
  const durationMs = value.durationMs === undefined ? undefined : value.durationMs;
  if (durationMs !== undefined && (!finite(durationMs) || durationMs < 0 || durationMs > 3600000)) {
    throw new Error('durationMs is invalid.');
  }
  return { schemaVersion: motionAnalysisSchemaVersion, motionId: value.motionId, targetReps: targetReps as number | undefined, frames, durationMs: durationMs as number | undefined };
}

function countDirectionChanges(values: number[]): number {
  let changes = 0;
  let previousDirection = 0;
  for (let i = 1; i < values.length; i += 1) {
    const delta = values[i] - values[i - 1];
    const direction = Math.abs(delta) < 0.012 ? 0 : Math.sign(delta);
    if (direction !== 0 && previousDirection !== 0 && direction !== previousDirection) changes += 1;
    if (direction !== 0) previousDirection = direction;
  }
  return Math.floor(changes / 2);
}

export function analyzeMotion(input: MotionAnalysisRequest): MotionAnalysisResult {
  const validFrames = input.frames.filter((frame) => validFrame(frame) && hasVisibleLandmarks(frame));
  const hipY = validFrames.map((frame) => {
    const left = frame.landmarks.leftHip;
    const right = frame.landmarks.rightHip;
    return left && right ? (left.y + right.y) / 2 : null;
  }).filter((value): value is number => value !== null);
  const detectedReps = countDirectionChanges(hipY);
  const coverage = validFrames.length / input.frames.length;
  const confidence = Math.max(0, Math.min(1, coverage * (hipY.length > 3 ? 0.9 : 0.45)));
  const evidence: MotionEvidence[] = [
    { key: 'pose_coverage', label: 'Pose visibility', value: coverage, expected: 0.7, status: coverage >= 0.7 ? 'pass' : 'fail' },
    { key: 'motion_signal', label: 'Motion signal', value: detectedReps, status: detectedReps > 0 ? 'pass' : 'unknown' },
  ];
  const failureReasons: string[] = [];
  const coaching: string[] = [];
  if (coverage < 0.7) {
    failureReasons.push('The body was not visible clearly enough for reliable analysis.');
    coaching.push('Move farther from the camera and keep your whole body in frame.');
  }
  if (detectedReps === 0) {
    failureReasons.push('A complete movement cycle was not detected.');
    coaching.push('Perform the movement through its full range and return to the starting position.');
  }
  const verdict = coverage < 0.45 ? 'needs_review' : failureReasons.length === 0 ? 'valid' : 'invalid';
  return {
    schemaVersion: motionAnalysisSchemaVersion,
    motionId: input.motionId,
    verdict,
    detectedReps,
    confidence,
    uncertainty: 1 - confidence,
    evidence,
    failureReasons,
    coaching,
    modelVersion: motionModelVersion,
    validatorVersion: motionValidatorVersion,
    framesAnalyzed: input.frames.length,
    validPoseFrames: validFrames.length,
    durationMs: input.durationMs ?? Math.max(0, (input.frames.at(-1)?.timestampMs ?? 0) - (input.frames[0]?.timestampMs ?? 0)),
  };
}
