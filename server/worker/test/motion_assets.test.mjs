import test from 'node:test';
import assert from 'node:assert/strict';

const {
  declaredPackageAssets,
  packageAssetKey,
  packageAssetPath,
  packageAssetContentType,
} = await import('../.tmp-test-dist/domain/motionAssets.js');

const sha = 'a'.repeat(64);

function releaseWithPackage(pkg) {
  return {
    id: 'rel-1',
    activityId: 'reach_taps',
    spec: pkg === undefined ? {} : { package: pkg },
  };
}

test('declaredPackageAssets extracts a well-formed manifest', () => {
  const assets = declaredPackageAssets(releaseWithPackage({
    packageSchemaVersion: 1,
    assets: [
      { id: 'engine', type: 'motion_v2_spec_v1', sha256: sha, url: '/x', bytes: 64, required: true },
      { id: 'preview', type: 'preview_v1', sha256: sha, url: '/y', bytes: 32, required: false },
    ],
  }));
  assert.equal(assets.length, 2);
  assert.equal(assets[0].id, 'engine');
  assert.equal(assets[1].type, 'preview_v1');
});

test('declaredPackageAssets is fail-closed — one malformed entry voids all', () => {
  // No package block.
  assert.deepEqual(declaredPackageAssets(releaseWithPackage(undefined)), []);
  // Unknown asset type.
  assert.deepEqual(declaredPackageAssets(releaseWithPackage({
    packageSchemaVersion: 1,
    assets: [{ id: 'x', type: 'executable_dart', sha256: sha, url: '/x', bytes: 8 }],
  })), []);
  // Bad checksum shape.
  assert.deepEqual(declaredPackageAssets(releaseWithPackage({
    packageSchemaVersion: 1,
    assets: [{ id: 'x', type: 'preview_v1', sha256: 'nope', url: '/x', bytes: 8 }],
  })), []);
  // Duplicate IDs.
  assert.deepEqual(declaredPackageAssets(releaseWithPackage({
    packageSchemaVersion: 1,
    assets: [
      { id: 'x', type: 'preview_v1', sha256: sha, url: '/a', bytes: 8 },
      { id: 'x', type: 'preview_v1', sha256: sha, url: '/b', bytes: 8 },
    ],
  })), []);
  // Oversized manifest.
  assert.deepEqual(declaredPackageAssets(releaseWithPackage({
    packageSchemaVersion: 1,
    assets: Array.from({ length: 9 }, (_, i) => ({
      id: `a${i}`, type: 'preview_v1', sha256: sha, url: '/x', bytes: 8,
    })),
  })), []);
});

test('asset keys are content-bound to the release, never requester-shaped', () => {
  assert.equal(
    packageAssetKey('rel-1', 'engine'),
    'motion-packages/rel-1/engine',
  );
  assert.equal(
    packageAssetPath('rel-1', 'engine'),
    '/motion/releases/rel-1/assets/engine',
  );
});

test('content type is allowlisted by asset type', () => {
  assert.equal(packageAssetContentType('onnx_model'), 'application/octet-stream');
  assert.equal(packageAssetContentType('preview_v1'), 'application/json');
});
