import assert from 'node:assert/strict';
import test from 'node:test';

const {
  parseModelReleaseDraft,
  parseModelEvaluationReport,
  modelRolloutBucket,
  resolveModelForUser,
} = await import('../.tmp-test-dist/domain/motionModels.js');

const draft = {
  modelVersion: 'motion_v2_encoder_fp32_2026.10.1',
  modelFamily: 'motion_v2_encoder',
  runtimeFamily: 'motionbert_rep_v1',
  inputSchemaVersion: 1,
  outputSchemaVersion: 1,
  preprocessingVersion: 1,
  normalizationVersion: 1,
  embeddingSchemaVersion: 1,
  minimumAppBuild: 1,
  artifactSha256: 'a'.repeat(64),
  artifactSizeBytes: 170183283,
  supportedMotionIds: [],
  metadata: { source: 'test' },
};

test('model release draft: parses a complete payload', () => {
  const d = parseModelReleaseDraft(draft);
  assert.equal(d.modelVersion, draft.modelVersion);
  assert.equal(d.runtimeFamily, 'motionbert_rep_v1');
  assert.equal(d.embeddingSchemaVersion, 1);
});

test('model release draft: rejects bad checksum / schema / version', () => {
  assert.throws(
    () => parseModelReleaseDraft({ ...draft, artifactSha256: 'xyz' }),
    /artifact_sha256_invalid/,
  );
  assert.throws(
    () => parseModelReleaseDraft({ ...draft, inputSchemaVersion: 0 }),
    /input_schema_version_required/,
  );
  assert.throws(
    () => parseModelReleaseDraft({ ...draft, modelVersion: 'bad version!' }),
    /model_version_invalid/,
  );
});

test('model evaluation gate: needs corpus, samples, hard gates', () => {
  const good = parseModelEvaluationReport({
    corpusId: 'holdout-2026-10',
    sampleCount: 120,
    hardGatesPassed: true,
    metrics: { trueAccept: 0.91 },
  });
  assert.equal(good.sampleCount, 120);
  assert.throws(
    () => parseModelEvaluationReport({ corpusId: 'c', sampleCount: 3, hardGatesPassed: true }),
    /sample_count_invalid/,
  );
  assert.throws(
    () => parseModelEvaluationReport({ corpusId: 'c', sampleCount: 40, hardGatesPassed: false }),
    /hard_gates_required/,
  );
});

test('rollout bucket is deterministic and in range', async () => {
  const a = await modelRolloutBucket('user-1', 'rel-a');
  const b = await modelRolloutBucket('user-1', 'rel-a');
  const c = await modelRolloutBucket('user-2', 'rel-a');
  assert.equal(a, b);
  assert.ok(a >= 0 && a < 100);
  assert.ok(c >= 0 && c < 100);
});

// ── resolveModelForUser with a fake D1 ─────────────────────────────────────

function fakeDb({ pointer, releases }) {
  return {
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async first() {
              if (sql.includes('motion_model_channels')) {
                const [family, channel] = args;
                return pointer && pointer.family === family && pointer.channel === channel
                  ? pointer
                  : null;
              }
              const [id] = args;
              const row = releases.find(
                (r) => r.id === id && !r.disabled_at && r.artifact_key,
              );
              return row ?? null;
            },
          };
        },
      };
    },
  };
}

const relA = { id: 'A', model_version: 'enc_a', artifact_key: 'k', disabled_at: null };
const relB = { id: 'B', model_version: 'enc_b', artifact_key: 'k', disabled_at: null };

test('resolution: rollout 100 always serves the pointer release', async () => {
  const db = fakeDb({
    pointer: { family: 'f', channel: 'stable', release_id: 'B', previous_release_id: 'A', rollout_percent: 100 },
    releases: [relA, relB],
  });
  const r = await resolveModelForUser(db, 'f', 'stable', 'any-user');
  assert.equal(r.id, 'B');
});

test('resolution: rollout 0 falls back to previous release', async () => {
  const db = fakeDb({
    pointer: { family: 'f', channel: 'stable', release_id: 'B', previous_release_id: 'A', rollout_percent: 0 },
    releases: [relA, relB],
  });
  const r = await resolveModelForUser(db, 'f', 'stable', 'any-user');
  assert.equal(r.id, 'A');
});

test('resolution: disabled current release resolves to previous', async () => {
  const db = fakeDb({
    pointer: { family: 'f', channel: 'stable', release_id: 'B', previous_release_id: 'A', rollout_percent: 100 },
    releases: [relA, { ...relB, disabled_at: 'now' }],
  });
  const r = await resolveModelForUser(db, 'f', 'stable', 'any-user');
  assert.equal(r.id, 'A');
});

test('resolution: rollout membership is stable per user', async () => {
  const db = fakeDb({
    pointer: { family: 'f', channel: 'stable', release_id: 'B', previous_release_id: 'A', rollout_percent: 50 },
    releases: [relA, relB],
  });
  const r1 = await resolveModelForUser(db, 'f', 'stable', 'user-x');
  const r2 = await resolveModelForUser(db, 'f', 'stable', 'user-x');
  assert.equal(r1.id, r2.id);
});
