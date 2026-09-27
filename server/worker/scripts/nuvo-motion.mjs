#!/usr/bin/env node
// nuvo-motion — ops CLI for the motion control plane.
// Wraps the INTERNAL_API_KEY-gated routes in src/routes/internal.ts.
// No dependencies; Node 18+.
//
//   NUVO_API_BASE   worker base URL (default: prod worker; --env dev selects
//                   https://nuvo-api-dev.getnuvoapp.workers.dev)
//   NUVO_INTERNAL_KEY  the INTERNAL_API_KEY secret value (never hardcode it;
//                   `source .dev.vars` works locally since the dev key lives there)
//
// Commands:
//   list [--channel stable|beta|internal]
//   releases <activityId>
//   draft <specFile> --release-id R --parent P --semver S [--change-class patch|minor|major] [--notes "..."]
//   evaluate --release-id R --file report.json
//   promote --release-id R --channel internal|beta|stable [--rollout 0-100]
//   rollback --activity-id A --channel C --release-id R
//   disable --release-id R
//   preview <activityId> <previewFile|--clear>
//   upload-asset --release-id R --asset-id A --file F
//   audit [--activity-id A] [--release-id R] [--action X] [--limit N]
//   signals [--activity-id A] [--release-id R]
//
// System B — model releases (Nuvo Motion Intelligence, independent of
// verifier releases):
//   models [--family F]
//   model-register <release.json>
//   model-upload --release-id R --file model.onnx
//   model-evaluate --release-id R --file report.json
//   model-promote --release-id R --channel internal|beta|stable [--rollout N]
//   model-rollback --family F --channel C --release-id R
//   model-disable --release-id R
//   model-status [--family F]

const BASES = {
  prod: 'https://nuvo-api.getnuvoapp.workers.dev',
  dev: 'https://nuvo-api-dev.getnuvoapp.workers.dev',
};

const args = process.argv.slice(2);
const command = args.shift();

function flag(name, fallback) {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const v = args[i + 1];
  return v !== undefined && !v.startsWith('--') ? v : fallback;
}
// First bare arg not consumed by a flag.
function firstPositional() {
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) { i++; continue; }
    return args[i];
  }
  return null;
}

const env = flag('env', 'prod');
const base = process.env.NUVO_API_BASE ?? BASES[env];
const key = process.env.NUVO_INTERNAL_KEY;
if (!key) {
  console.error('NUVO_INTERNAL_KEY is not set (see .dev.vars / wrangler secret INTERNAL_API_KEY).');
  process.exit(2);
}

async function call(method, path, body) {
  const res = await fetch(`${base}/internal${path}`, {
    method,
    headers: {
      'X-Internal-Key': key,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: res.status, json };
}

function print(result) {
  console.log(`HTTP ${result.status}`);
  console.log(JSON.stringify(result.json, null, 2));
  if (!result.json?.ok) process.exit(1);
}

const fs = await import('node:fs');

switch (command) {
  case 'list':
    print(await call('GET', `/motion/catalog?channel=${flag('channel', 'stable')}`));
    break;
  case 'releases': {
    const activityId = firstPositional();
    if (!activityId) { console.error('usage: releases <activityId>'); process.exit(2); }
    print(await call('GET', `/motion/activities/${activityId}/releases`));
    break;
  }
  case 'draft': {
    const file = firstPositional();
    const releaseId = flag('release-id', null);
    const parent = flag('parent', null);
    const semver = flag('semver', null);
    if (!file || !releaseId || !parent || !semver) {
      console.error('usage: draft <specFile> --release-id R --parent P --semver S [--change-class] [--notes]');
      process.exit(2);
    }
    const spec = JSON.parse(fs.readFileSync(file, 'utf8'));
    print(await call('POST', '/motion/releases/drafts', {
      activityId: spec.activityId,
      releaseId,
      parentReleaseId: parent,
      semver,
      changeClass: flag('change-class', 'patch'),
      releaseNotes: flag('notes', ''),
      spec,
    }));
    break;
  }
  case 'evaluate': {
    const releaseId = flag('release-id', null);
    const file = flag('file', null);
    if (!releaseId || !file) { console.error('usage: evaluate --release-id R --file report.json'); process.exit(2); }
    const report = JSON.parse(fs.readFileSync(file, 'utf8'));
    print(await call('POST', '/motion/evaluations', { releaseId, report }));
    break;
  }
  case 'promote': {
    const releaseId = flag('release-id', null);
    const channel = flag('channel', null);
    if (!releaseId || !channel) { console.error('usage: promote --release-id R --channel internal|beta|stable [--rollout N]'); process.exit(2); }
    const rollout = flag('rollout', null);
    print(await call('POST', `/motion/releases/${releaseId}/promote`, {
      channel,
      ...(rollout != null ? { rolloutPercent: Number(rollout) } : {}),
    }));
    break;
  }
  case 'rollback': {
    const activityId = flag('activity-id', null);
    const channel = flag('channel', null);
    const releaseId = flag('release-id', null);
    if (!activityId || !channel || !releaseId) {
      console.error('usage: rollback --activity-id A --channel C --release-id R');
      process.exit(2);
    }
    print(await call('POST', `/motion/channels/${activityId}/${channel}/rollback`, { releaseId }));
    break;
  }
  case 'disable': {
    const releaseId = flag('release-id', null);
    if (!releaseId) { console.error('usage: disable --release-id R'); process.exit(2); }
    print(await call('POST', `/motion/releases/${releaseId}/disable`, {}));
    break;
  }
  case 'preview': {
    const activityId = firstPositional();
    const file = args.filter((a, i) => !a.startsWith('--') && a !== activityId)[0];
    const clear = args.includes('--clear');
    if (!activityId || (!file && !clear)) {
      console.error('usage: preview <activityId> <previewFile> | preview <activityId> --clear');
      process.exit(2);
    }
    const preview = clear ? null : JSON.parse(fs.readFileSync(file, 'utf8'));
    const res = await fetch(`${base}/internal/motion/activities/${activityId}/preview`, {
      method: 'PUT',
      headers: { 'X-Internal-Key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ preview }),
    });
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
    print({ status: res.status, json });
    break;
  }
  case 'upload-asset': {
    const releaseId = flag('release-id', null);
    const assetId = flag('asset-id', null);
    const file = flag('file', null);
    if (!releaseId || !assetId || !file) {
      console.error('usage: upload-asset --release-id R --asset-id A --file F');
      process.exit(2);
    }
    const bytes = fs.readFileSync(file);
    const res = await fetch(`${base}/internal/motion/releases/${releaseId}/assets/${assetId}`, {
      method: 'POST',
      headers: { 'X-Internal-Key': key },
      body: bytes,
    });
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
    print({ status: res.status, json });
    break;
  }
  case 'audit': {
    const qs = new URLSearchParams();
    for (const [flag_, param] of [['activity-id', 'activityId'], ['release-id', 'releaseId'], ['action', 'action'], ['limit', 'limit']]) {
      const v = flag(flag_, null);
      if (v) qs.set(param, v);
    }
    print(await call('GET', `/motion/audit?${qs}`));
    break;
  }
  case 'signals': {
    const qs = new URLSearchParams();
    for (const [flag_, param] of [['activity-id', 'activityId'], ['release-id', 'releaseId']]) {
      const v = flag(flag_, null);
      if (v) qs.set(param, v);
    }
    print(await call('GET', `/motion/adaptation/signals?${qs}`));
    break;
  }
  case 'activity-visibility': {
    const activityId = firstPositional();
    const availability = flag('set', null);
    if (!activityId || !['supported', 'hidden'].includes(availability)) {
      console.error('usage: activity-visibility <activityId> --set supported|hidden');
      process.exit(2);
    }
    const res = await fetch(`${base}/internal/motion/activities/${activityId}/availability`, {
      method: 'PUT',
      headers: { 'X-Internal-Key': key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ availability }),
    });
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
    print({ status: res.status, json });
    break;
  }
  // ── System B: model releases ────────────────────────────────────────────
  case 'models': {
    const qs = flag('family', null) ? `?family=${flag('family', null)}` : '';
    print(await call('GET', `/motion/models${qs}`));
    break;
  }
  case 'model-register': {
    const file = firstPositional();
    if (!file) { console.error('usage: model-register <release.json>'); process.exit(2); }
    print(await call('POST', '/motion/models', JSON.parse(fs.readFileSync(file, 'utf8'))));
    break;
  }
  case 'model-upload': {
    const releaseId = flag('release-id', null);
    const file = flag('file', null);
    if (!releaseId || !file) { console.error('usage: model-upload --release-id R --file model.onnx'); process.exit(2); }
    const bytes = fs.readFileSync(file);
    const res = await fetch(`${base}/internal/motion/models/${releaseId}/artifact`, {
      method: 'POST',
      headers: { 'X-Internal-Key': key },
      body: bytes,
    });
    const text = await res.text();
    let json; try { json = JSON.parse(text); } catch { json = { raw: text }; }
    print({ status: res.status, json });
    break;
  }
  case 'model-evaluate': {
    const releaseId = flag('release-id', null);
    const file = flag('file', null);
    if (!releaseId || !file) { console.error('usage: model-evaluate --release-id R --file report.json'); process.exit(2); }
    const report = JSON.parse(fs.readFileSync(file, 'utf8'));
    print(await call('POST', `/motion/models/${releaseId}/evaluations`, report));
    break;
  }
  case 'model-promote': {
    const releaseId = flag('release-id', null);
    const channel = flag('channel', null);
    if (!releaseId || !channel) { console.error('usage: model-promote --release-id R --channel internal|beta|stable [--rollout N]'); process.exit(2); }
    const rollout = flag('rollout', null);
    print(await call('POST', `/motion/models/${releaseId}/promote`, {
      channel,
      ...(rollout != null ? { rolloutPercent: Number(rollout) } : {}),
    }));
    break;
  }
  case 'model-rollback': {
    const family = flag('family', null);
    const channel = flag('channel', null);
    const releaseId = flag('release-id', null);
    if (!family || !channel || !releaseId) {
      console.error('usage: model-rollback --family F --channel C --release-id R');
      process.exit(2);
    }
    print(await call('POST', `/motion/models/channels/${family}/${channel}/rollback`, { releaseId }));
    break;
  }
  case 'model-disable': {
    const releaseId = flag('release-id', null);
    if (!releaseId) { console.error('usage: model-disable --release-id R'); process.exit(2); }
    print(await call('POST', `/motion/models/${releaseId}/disable`, {}));
    break;
  }
  case 'model-status': {
    const qs = flag('family', null) ? `?family=${flag('family', null)}` : '';
    print(await call('GET', `/motion/models${qs}`));
    break;
  }
  default:
    console.error(`Unknown command: ${command ?? '(none)'}\n`);
    console.error('Commands: list | releases | draft | evaluate | promote | rollback | disable | preview | upload-asset | audit | signals | models | model-register | model-upload | model-evaluate | model-promote | model-rollback | model-disable | model-status');
    process.exit(2);
}
