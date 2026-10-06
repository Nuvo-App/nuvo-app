#!/usr/bin/env node
// Prints the release checksum the Worker publish route would store for each
// motion-release spec file — 'sha256:' + sha256hex(JSON.stringify(spec)) —
// where `spec` is the parsed spec object (see internal.ts /motion/releases/drafts).
// Used to fill the checksum column in DRAFT_converted_remote_releases_*.sql.
//
// Usage: node scripts/motion_release_checksums.mjs [spec-dir]

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir =
  process.argv[2] ??
  join(dirname(fileURLToPath(import.meta.url)), '..', 'motion-releases');

for (const name of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
  const spec = JSON.parse(readFileSync(join(dir, name), 'utf8'));
  const checksum =
    'sha256:' + createHash('sha256').update(JSON.stringify(spec)).digest('hex');
  console.log(`${name.replace(/\.json$/, '')}  ${checksum}`);
}
