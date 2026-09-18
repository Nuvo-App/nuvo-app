import {
  activityForId,
  RACE_ACTIVITY_CATALOG,
  type RaceActivityDefinition,
} from './raceActivities';
import { validateMotionVerifierSpec } from './motionSpec';

type RegistryActivityRow = {
  id: string;
  display_name: string;
  category: string;
  proof_label: string;
  measurement_type: string;
  metric: string;
  suggested_targets_json: string;
  supported_formats_json: string;
  icon_key: string;
  sort_priority: number;
  featured: number;
  availability: string;
  metadata_json: string;
  release_id: string | null;
  release_checksum: string | null;
  engine_type: string | null;
  required_capabilities_json: string | null;
  minimum_app_build: string | null;
};

type RegistryReleaseRow = {
  id: string;
  activity_id: string;
  semver: string;
  change_class: string;
  engine_type: string;
  spec_schema_version: number;
  spec_json: string;
  checksum: string;
  required_capabilities_json: string;
  minimum_app_build: string;
  compatibility_group: string;
  status: string;
  release_notes: string;
  created_at: string;
  published_at: string | null;
  parent_release_id: string | null;
};

export type RegistryActivity = {
  id: string;
  displayName: string;
  category: string;
  proofLabel: string;
  measurementType: string;
  metric: string;
  suggestedTargets: number[];
  supportedFormats: string[];
  iconKey: string;
  sortPriority: number;
  featured: boolean;
  availability: string;
  releaseId: string | null;
  releaseChecksum: string | null;
  engineType: string | null;
  requiredCapabilities: string[];
  minimumAppBuild: string | null;
  legacy: RaceActivityDefinition | null;
};

export type RegistryRelease = {
  id: string;
  activityId: string;
  semver: string;
  changeClass: string;
  engineType: string;
  specSchemaVersion: number;
  spec: Record<string, unknown>;
  checksum: string;
  requiredCapabilities: string[];
  minimumAppBuild: string;
  compatibilityGroup: string;
  status: string;
  releaseNotes: string;
  createdAt: string;
  publishedAt: string | null;
  parentReleaseId: string | null;
};

function jsonValue<T>(raw: string | null | undefined, fallback: T): T {
  if (!raw) return fallback;
  try {
    const first = JSON.parse(raw) as unknown;
    // Early local seeds may have stored a JSON string rather than JSON text.
    const value = typeof first === 'string' ? JSON.parse(first) : first;
    return value as T;
  } catch {
    return fallback;
  }
}

function legacyDefinition(row: RegistryActivityRow): RaceActivityDefinition | null {
  const definition = activityForId(row.id);
  if (!definition) return null;
  return { ...definition, displayName: row.display_name };
}

function mapActivity(row: RegistryActivityRow): RegistryActivity {
  return {
    id: row.id,
    displayName: row.display_name,
    category: row.category,
    proofLabel: row.proof_label,
    measurementType: row.measurement_type,
    metric: row.metric,
    suggestedTargets: jsonValue<number[]>(row.suggested_targets_json, []),
    supportedFormats: jsonValue<string[]>(row.supported_formats_json, []),
    iconKey: row.icon_key,
    sortPriority: row.sort_priority,
    featured: row.featured === 1,
    availability: row.availability,
    releaseId: row.release_id,
    releaseChecksum: row.release_checksum,
    engineType: row.engine_type,
    requiredCapabilities: jsonValue<string[]>(row.required_capabilities_json, []),
    minimumAppBuild: row.minimum_app_build,
    legacy: legacyDefinition(row),
  };
}

function mapRelease(row: RegistryReleaseRow): RegistryRelease {
  return {
    id: row.id,
    activityId: row.activity_id,
    semver: row.semver,
    changeClass: row.change_class,
    engineType: row.engine_type,
    specSchemaVersion: row.spec_schema_version,
    spec: jsonValue<Record<string, unknown>>(row.spec_json, {}),
    checksum: row.checksum,
    requiredCapabilities: jsonValue<string[]>(row.required_capabilities_json, []),
    minimumAppBuild: row.minimum_app_build,
    compatibilityGroup: row.compatibility_group,
    status: row.status,
    releaseNotes: row.release_notes,
    createdAt: row.created_at,
    publishedAt: row.published_at,
    parentReleaseId: row.parent_release_id,
  };
}

export async function readMotionCatalog(
  db: D1Database,
  channel = 'stable',
): Promise<{ catalogVersion: string; activities: RegistryActivity[] }> {
  const result = await db.prepare(
    'SELECT a.id, a.display_name, a.category, a.proof_label, a.measurement_type, ' +
    'a.metric, a.suggested_targets_json, a.supported_formats_json, a.icon_key, ' +
    'a.sort_priority, a.featured, a.availability, a.metadata_json, ' +
    'cr.release_id, vr.checksum AS release_checksum, vr.engine_type, ' +
    'vr.required_capabilities_json, vr.minimum_app_build ' +
    'FROM motion_activities a ' +
    'LEFT JOIN activity_channel_releases cr ON cr.activity_id = a.id AND cr.channel = ? ' +
    'LEFT JOIN verifier_releases vr ON vr.id = cr.release_id ' +
    'WHERE ? <> ? OR a.availability = ? ' +
    'ORDER BY a.sort_priority, a.display_name',
  ).bind(channel, channel, 'stable', 'supported').all<RegistryActivityRow>();
  const version = await db.prepare(
    'SELECT COALESCE(MAX(updated_at), CURRENT_TIMESTAMP) AS version FROM (' +
    'SELECT updated_at FROM motion_activities UNION ALL ' +
    'SELECT updated_at FROM verifier_releases UNION ALL ' +
    'SELECT updated_at FROM activity_channel_releases' +
    ')',
  ).first<{ version: string }>();
  return {
    catalogVersion: version?.version ?? 'registry-1',
    activities: result.results.map(mapActivity),
  };
}

export async function readMotionRelease(
  db: D1Database,
  releaseId: string,
): Promise<RegistryRelease | null> {
  const row = await db.prepare(
    'SELECT id, activity_id, semver, change_class, engine_type, spec_schema_version, ' +
    'spec_json, checksum, required_capabilities_json, minimum_app_build, ' +
    'compatibility_group, status, release_notes, created_at, published_at, parent_release_id ' +
    'FROM verifier_releases WHERE id = ? LIMIT 1',
  ).bind(releaseId).first<RegistryReleaseRow>();
  if (!row) return null;
  const release = mapRelease(row);
  try {
    validateMotionVerifierSpec(release.spec, {
      releaseId: release.id,
      activityId: release.activityId,
    });
  } catch {
    return null;
  }
  return release;
}

export function legacyCatalogResponse() {
  return RACE_ACTIVITY_CATALOG;
}
