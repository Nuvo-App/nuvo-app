// System B — Nuvo Motion Intelligence model releases.
//
// Separate from System A (movement verifiers). A model release is an
// immutable, checksum-addressed artifact plus the contract the generic
// runtime already shipped in the binary needs (runtime family, schema
// versions, minimum app build). Channel pointers decide which release a
// family resolves to per channel; rollout percent buckets users
// deterministically. Nothing here is executable code — artifacts are
// data files the reviewed runtime loads.

import { generateId, hashBytes, hashValue } from '../lib/crypto';

export const MODEL_CHANNELS = ['internal', 'beta', 'stable'] as const;
export type ModelChannel = (typeof MODEL_CHANNELS)[number];

// Runtime families the shipping binary knows how to execute. A release whose
// runtime_family is not in this list can be registered (for review) but is
// rejected at resolution time — the client also fail-closes on unknown values.
export const KNOWN_RUNTIME_FAMILIES = new Set([
  'motionbert_rep_v1', // general MotionBERT encoder: pose[T,17,3] -> rep[T,17,512]
  'yolox_800_v1',      // auxiliary basketball object model
]);

export type ModelReleaseRow = {
  id: string;
  model_version: string;
  model_family: string;
  runtime_family: string;
  input_schema_version: number;
  output_schema_version: number | null;
  preprocessing_version: number | null;
  normalization_version: number | null;
  embedding_schema_version: number | null;
  minimum_app_build: number | null;
  artifact_key: string | null;
  artifact_sha256: string | null;
  artifact_size_bytes: number | null;
  status: string;
  supported_motion_ids_json: string;
  evaluation_id: string | null;
  metadata_json: string | null;
  disabled_at: string | null;
  created_at: string;
  promoted_at: string | null;
};

export type ModelReleaseDraft = {
  modelVersion: string;
  modelFamily: string;
  runtimeFamily: string;
  inputSchemaVersion: number;
  outputSchemaVersion: number | null;
  preprocessingVersion: number | null;
  normalizationVersion: number | null;
  embeddingSchemaVersion: number | null;
  minimumAppBuild: number | null;
  artifactSha256: string;
  artifactSizeBytes: number | null;
  artifactKey: string | null;
  supportedMotionIds: string[];
  metadata: Record<string, unknown>;
};

const SHA256_RE = /^[0-9a-f]{64}$/;
const VERSION_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,118}$/;
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;

function optVersion(v: unknown, name: string): number | null {
  if (v == null) return null;
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0 || v > 1_000) {
    throw new Error(`${name}_invalid`);
  }
  return v;
}

export function parseModelReleaseDraft(value: unknown): ModelReleaseDraft {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('model_release_invalid');
  }
  const v = value as Record<string, unknown>;
  const modelVersion = String(v.modelVersion ?? '').trim();
  if (!VERSION_RE.test(modelVersion)) throw new Error('model_version_invalid');
  const modelFamily = String(v.modelFamily ?? '').trim();
  if (!ID_RE.test(modelFamily)) throw new Error('model_family_invalid');
  const runtimeFamily = String(v.runtimeFamily ?? '').trim();
  if (!ID_RE.test(runtimeFamily)) throw new Error('runtime_family_invalid');
  const inputSchemaVersion = optVersion(v.inputSchemaVersion, 'input_schema_version');
  if (inputSchemaVersion == null || inputSchemaVersion < 1) {
    throw new Error('input_schema_version_required');
  }
  const artifactSha256 = String(v.artifactSha256 ?? '').trim().toLowerCase();
  if (!SHA256_RE.test(artifactSha256)) throw new Error('artifact_sha256_invalid');
  let artifactSizeBytes: number | null = null;
  if (v.artifactSizeBytes != null) {
    const n = v.artifactSizeBytes;
    if (typeof n !== 'number' || !Number.isInteger(n) || n <= 0 || n > 500_000_000) {
      throw new Error('artifact_size_bytes_invalid');
    }
    artifactSizeBytes = n;
  }
  const artifactKey =
    v.artifactKey == null ? null : String(v.artifactKey).trim().slice(0, 400) || null;
  const supportedMotionIds = Array.isArray(v.supportedMotionIds)
    ? v.supportedMotionIds.filter((m): m is string => typeof m === 'string').slice(0, 200)
    : [];
  const metadata =
    v.metadata && typeof v.metadata === 'object' && !Array.isArray(v.metadata)
      ? (v.metadata as Record<string, unknown>)
      : {};
  return {
    modelVersion,
    modelFamily,
    runtimeFamily,
    inputSchemaVersion,
    outputSchemaVersion: optVersion(v.outputSchemaVersion, 'output_schema_version'),
    preprocessingVersion: optVersion(v.preprocessingVersion, 'preprocessing_version'),
    normalizationVersion: optVersion(v.normalizationVersion, 'normalization_version'),
    embeddingSchemaVersion: optVersion(v.embeddingSchemaVersion, 'embedding_schema_version'),
    minimumAppBuild: optVersion(v.minimumAppBuild, 'minimum_app_build'),
    artifactSha256,
    artifactSizeBytes,
    artifactKey,
    supportedMotionIds,
    metadata,
  };
}

export type ModelEvaluationReport = {
  corpusId: string;
  sampleCount: number;
  hardGatesPassed: boolean;
  metrics: Record<string, unknown>;
};

/**
 * Model evaluation gate: the replay harness produces the numbers; the Worker
 * only enforces shape and the hard-gate flag. A stable promotion requires a
 * row where hardGatesPassed is true.
 */
export function parseModelEvaluationReport(value: unknown): ModelEvaluationReport {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('model_evaluation_invalid');
  }
  const v = value as Record<string, unknown>;
  const corpusId = typeof v.corpusId === 'string' ? v.corpusId.trim() : '';
  if (!corpusId) throw new Error('model_evaluation_corpus_required');
  if (
    typeof v.sampleCount !== 'number' ||
    !Number.isInteger(v.sampleCount) ||
    v.sampleCount < 20 ||
    v.sampleCount > 10_000_000
  ) {
    throw new Error('model_evaluation_sample_count_invalid');
  }
  if (v.hardGatesPassed !== true) throw new Error('model_evaluation_hard_gates_required');
  const metrics =
    v.metrics && typeof v.metrics === 'object' && !Array.isArray(v.metrics)
      ? (v.metrics as Record<string, unknown>)
      : {};
  return { corpusId: corpusId.slice(0, 200), sampleCount: v.sampleCount, hardGatesPassed: true, metrics };
}

/** Stable deterministic rollout bucket for (user, release). 0–99. */
export async function modelRolloutBucket(userId: string, releaseId: string): Promise<number> {
  const hex = await hashValue(`${userId}:${releaseId}`);
  return parseInt(hex.slice(0, 8), 16) % 100;
}

export function publicModelRelease(row: ModelReleaseRow) {
  let supportedMotionIds: unknown[] = [];
  try { supportedMotionIds = JSON.parse(row.supported_motion_ids_json); } catch { /* default */ }
  let metadata: Record<string, unknown> = {};
  try { metadata = row.metadata_json ? JSON.parse(row.metadata_json) : {}; } catch { /* default */ }
  return {
    modelReleaseId: row.id,
    modelVersion: row.model_version,
    modelFamily: row.model_family,
    runtimeFamily: row.runtime_family,
    inputSchemaVersion: row.input_schema_version,
    outputSchemaVersion: row.output_schema_version,
    preprocessingVersion: row.preprocessing_version,
    normalizationVersion: row.normalization_version,
    embeddingSchemaVersion: row.embedding_schema_version,
    minimumAppBuild: row.minimum_app_build,
    artifactKey: row.artifact_key,
    artifactSha256: row.artifact_sha256,
    artifactSizeBytes: row.artifact_size_bytes,
    status: row.status,
    evaluationId: row.evaluation_id,
    supportedMotionIds,
    metadata,
    createdAt: row.created_at,
    promotedAt: row.promoted_at,
  };
}

/**
 * Resolve the model release a user sees for (family, channel):
 * channel pointer → deterministic rollout bucket → previous-release fallback.
 * Disabled or artifact-less releases never resolve.
 */
export async function resolveModelForUser(
  db: D1Database,
  family: string,
  channel: ModelChannel,
  userId: string,
): Promise<ModelReleaseRow | null> {
  const pointer = await db
    .prepare(
      `SELECT release_id, previous_release_id, rollout_percent
       FROM motion_model_channels WHERE model_family = ? AND channel = ?`,
    )
    .bind(family, channel)
    .first<{ release_id: string; previous_release_id: string | null; rollout_percent: number }>();
  if (!pointer) return null;

  const byId = async (id: string) =>
    db
      .prepare(
        `SELECT * FROM motion_model_releases
         WHERE id = ? AND disabled_at IS NULL AND artifact_key IS NOT NULL`,
      )
      .bind(id)
      .first<ModelReleaseRow>();

  const current = await byId(pointer.release_id);
  if (current) {
    const rollout = Math.max(0, Math.min(100, pointer.rollout_percent));
    if (rollout >= 100) return current;
    if (rollout > 0 && (await modelRolloutBucket(userId, current.id)) < rollout) return current;
  }
  return pointer.previous_release_id ? byId(pointer.previous_release_id) : null;
}

export async function insertModelRelease(
  db: D1Database,
  draft: ModelReleaseDraft,
): Promise<{ id: string }> {
  const id = generateId();
  await db
    .prepare(
      `INSERT INTO motion_model_releases (
         id, model_version, model_family, runtime_family,
         input_schema_version, output_schema_version, preprocessing_version,
         normalization_version, embedding_schema_version, minimum_app_build,
         artifact_key, artifact_sha256, artifact_size_bytes,
         status, supported_motion_ids_json, metadata_json
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?)`,
    )
    .bind(
      id,
      draft.modelVersion,
      draft.modelFamily,
      draft.runtimeFamily,
      draft.inputSchemaVersion,
      draft.outputSchemaVersion,
      draft.preprocessingVersion,
      draft.normalizationVersion,
      draft.embeddingSchemaVersion,
      draft.minimumAppBuild,
      draft.artifactKey,
      draft.artifactSha256,
      draft.artifactSizeBytes,
      JSON.stringify(draft.supportedMotionIds),
      JSON.stringify(draft.metadata),
    )
    .run();
  return { id };
}

export async function recordModelEvaluation(
  db: D1Database,
  releaseId: string,
  report: ModelEvaluationReport,
  evaluator: string,
): Promise<{ evaluationId: string }> {
  const evaluationId = generateId();
  await db.batch([
    db
      .prepare(
        `INSERT INTO motion_model_evaluations
           (id, release_id, corpus_id, sample_count, passed, metrics_json, evaluator)
         VALUES (?, ?, ?, ?, 1, ?, ?)`,
      )
      .bind(evaluationId, releaseId, report.corpusId, report.sampleCount, JSON.stringify(report.metrics), evaluator),
    db
      .prepare(
        `UPDATE motion_model_releases
         SET status = CASE WHEN status = 'draft' THEN 'evaluated' ELSE status END,
             evaluation_id = ?
         WHERE id = ?`,
      )
      .bind(evaluationId, releaseId),
  ]);
  return { evaluationId };
}

/** Promote a release to a channel pointer. Requires evaluation for beta/stable. */
export async function promoteModelRelease(
  db: D1Database,
  releaseId: string,
  channel: ModelChannel,
  rolloutPercent: number,
): Promise<{ previousReleaseId: string | null }> {
  const release = await db
    .prepare('SELECT * FROM motion_model_releases WHERE id = ?')
    .bind(releaseId)
    .first<ModelReleaseRow>();
  if (!release) throw new Error('model_release_not_found');
  if (release.disabled_at) throw new Error('model_release_disabled');
  if (!release.artifact_key || !release.artifact_sha256) {
    throw new Error('model_artifact_required');
  }
  if (!KNOWN_RUNTIME_FAMILIES.has(release.runtime_family)) {
    throw new Error('model_runtime_family_unknown');
  }
  if (channel !== 'internal') {
    const evaluation = await db
      .prepare(
        `SELECT id FROM motion_model_evaluations
         WHERE release_id = ? AND passed = 1 ORDER BY created_at DESC LIMIT 1`,
      )
      .bind(releaseId)
      .first<{ id: string }>();
    if (!evaluation) throw new Error('model_evaluation_required');
  }

  const existing = await db
    .prepare(
      `SELECT release_id FROM motion_model_channels WHERE model_family = ? AND channel = ?`,
    )
    .bind(release.model_family, channel)
    .first<{ release_id: string }>();
  const previousReleaseId = existing && existing.release_id !== releaseId ? existing.release_id : null;

  await db.batch([
    db
      .prepare(
        `INSERT INTO motion_model_channels
           (model_family, channel, release_id, previous_release_id, rollout_percent, updated_at)
         VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
         ON CONFLICT(model_family, channel) DO UPDATE SET
           release_id = excluded.release_id,
           previous_release_id = COALESCE(excluded.previous_release_id, motion_model_channels.previous_release_id),
           rollout_percent = excluded.rollout_percent,
           updated_at = CURRENT_TIMESTAMP`,
      )
      .bind(release.model_family, channel, releaseId, previousReleaseId, Math.max(0, Math.min(100, Math.trunc(rolloutPercent)))),
    db
      .prepare(
        `UPDATE motion_model_releases
         SET status = 'production', promoted_at = CURRENT_TIMESTAMP
         WHERE id = ?`,
      )
      .bind(releaseId),
  ]);
  return { previousReleaseId };
}

/** Point a (family, channel) back at an earlier release. */
export async function rollbackModelChannel(
  db: D1Database,
  family: string,
  channel: ModelChannel,
  targetReleaseId: string,
): Promise<{ previousReleaseId: string }> {
  const pointer = await db
    .prepare(
      `SELECT release_id, previous_release_id FROM motion_model_channels WHERE model_family = ? AND channel = ?`,
    )
    .bind(family, channel)
    .first<{ release_id: string; previous_release_id: string | null }>();
  if (!pointer) throw new Error('model_channel_not_found');
  const target = await db
    .prepare('SELECT id, model_family FROM motion_model_releases WHERE id = ? AND disabled_at IS NULL')
    .bind(targetReleaseId)
    .first<{ id: string; model_family: string }>();
  if (!target || target.model_family !== family) {
    throw new Error('model_rollback_target_invalid');
  }
  const previous =
    pointer.release_id === targetReleaseId
      ? pointer.previous_release_id
      : pointer.release_id;
  await db
    .prepare(
      `UPDATE motion_model_channels
       SET release_id = ?, previous_release_id = ?, rollout_percent = 100, updated_at = CURRENT_TIMESTAMP
       WHERE model_family = ? AND channel = ?`,
    )
    .bind(targetReleaseId, previous, family, channel)
    .run();
  return { previousReleaseId: previous ?? '' };
}

/** Kill switch: disable a release and repoint any channel that used it. */
export async function disableModelRelease(
  db: D1Database,
  releaseId: string,
): Promise<{ modelFamily: string; repointedChannels: string[] }> {
  const release = await db
    .prepare('SELECT id, model_family FROM motion_model_releases WHERE id = ?')
    .bind(releaseId)
    .first<{ id: string; model_family: string }>();
  if (!release) throw new Error('model_release_not_found');
  const pointers = await db
    .prepare('SELECT model_family, channel, previous_release_id FROM motion_model_channels WHERE release_id = ?')
    .bind(releaseId)
    .all<{ model_family: string; channel: string; previous_release_id: string | null }>();
  const statements = [
    db.prepare('UPDATE motion_model_releases SET disabled_at = CURRENT_TIMESTAMP WHERE id = ?').bind(releaseId),
    ...pointers.results.map((p) =>
      p.previous_release_id
        ? db
            .prepare(
              `UPDATE motion_model_channels
               SET release_id = ?, previous_release_id = NULL, rollout_percent = 100, updated_at = CURRENT_TIMESTAMP
               WHERE model_family = ? AND channel = ?`,
            )
            .bind(p.previous_release_id, p.model_family, p.channel)
        : db
            .prepare('DELETE FROM motion_model_channels WHERE model_family = ? AND channel = ?')
            .bind(p.model_family, p.channel),
    ),
  ];
  await db.batch(statements);
  return {
    modelFamily: release.model_family,
    repointedChannels: pointers.results.map((p) => p.channel),
  };
}

export async function sha256Hex(bytes: ArrayBuffer | Uint8Array): Promise<string> {
  return hashBytes(bytes);
}
