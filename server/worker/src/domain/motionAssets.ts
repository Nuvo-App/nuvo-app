import type { RegistryRelease } from './motionRegistry';

/// Server-side view of a release spec's `package` manifest — deliberately
/// minimal: the only fields the Worker needs to decide whether an asset URL
/// is legitimate and how to serve it. The client performs the authoritative
/// integrity check (sha256 over fetched bytes); the Worker just never serves
/// an asset a release didn't declare.
export type PackageAssetEntry = {
  id: string;
  type: string;
  sha256: string;
  url: string;
  bytes: number;
  required: boolean;
};

export type DeclaredPackageAsset = {
  id: string;
  type: string;
  sha256: string;
  bytes: number;
};

const KNOWN_TYPES = new Set([
  'preview_v1',
  'motion_v2_spec_v1',
  'onnx_model',
  'test_vectors_v1',
]);

/// Extracts the declared asset list from a release spec, fail-closed:
/// returns [] unless every asset entry is well-formed. Mirrors the client's
/// `MotionPackageManifest` bounds (≤8 assets, allowlisted types, hex sha256).
export function declaredPackageAssets(release: RegistryRelease): DeclaredPackageAsset[] {
  const spec = release.spec;
  const pkg = spec['package'];
  if (!pkg || typeof pkg !== 'object' || Array.isArray(pkg)) return [];
  const assets = (pkg as Record<string, unknown>)['assets'];
  if (!Array.isArray(assets) || assets.length > 8) return [];
  const out: DeclaredPackageAsset[] = [];
  const seen = new Set<string>();
  for (const entry of assets) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return [];
    const e = entry as Record<string, unknown>;
    const id = e['id'];
    const type = e['type'];
    const sha256 = e['sha256'];
    const bytes = e['bytes'];
    if (
      typeof id !== 'string' || !id || id.length > 64 ||
      typeof type !== 'string' || !KNOWN_TYPES.has(type) ||
      typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256) ||
      typeof bytes !== 'number' || !Number.isInteger(bytes) || bytes <= 0 ||
      seen.has(id)
    ) {
      return [];
    }
    seen.add(id);
    out.push({ id, type, sha256, bytes });
  }
  return out;
}

/// The one canonical R2 key shape for package assets — content-bound to the
/// immutable release directory. Asset bytes are never served from paths a
/// request can shape; the URL's assetId only selects among assets the release
/// itself declared.
export function packageAssetKey(releaseId: string, assetId: string): string {
  return `motion-packages/${releaseId}/${assetId}`;
}

/// Canonical first-party URL path for a declared asset — what the manifest's
/// `url` field must equal (path form) or resolve to on the API host.
export function packageAssetPath(releaseId: string, assetId: string): string {
  return `/motion/releases/${releaseId}/assets/${assetId}`;
}

export function packageAssetContentType(type: string): string {
  switch (type) {
    case 'onnx_model':
      return 'application/octet-stream';
    default:
      return 'application/json';
  }
}
