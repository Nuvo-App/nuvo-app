#!/usr/bin/env node
// nuvo-broadcast — send ONE notification to EVERY active Nuvo user.
// Wraps POST /internal/notifications/broadcast (INTERNAL_API_KEY-gated).
//
//   NUVO_API_BASE      worker base URL (default prod; --env dev selects dev)
//   NUVO_INTERNAL_KEY  the INTERNAL_API_KEY secret value
//
// Dry run (default, writes nothing):
//   node scripts/nuvo-broadcast.mjs --title 'Welcome to Nuvo Capitol Hackers' \
//     --body "Let's get moving" --id capitol-hackers-welcome
// Real send (needs the recipient count the dry run printed):
//   node scripts/nuvo-broadcast.mjs --title '...' --body '...' --id <id> --send --expect <N>
// Options: --category <c>  --dest notifications|crew  --batch <n>  --env prod|dev
// Safe to re-run with the same --id: users who already have it are skipped.

const BASES = {
  prod: 'https://nuvo-api.getnuvoapp.workers.dev',
  dev: 'https://nuvo-api-dev.getnuvoapp.workers.dev',
};
const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(`--${name}`);
  if (i === -1) return fallback;
  const v = args[i + 1];
  return v !== undefined && !v.startsWith('--') ? v : fallback;
}
const has = (name) => args.includes(`--${name}`);

const base = process.env.NUVO_API_BASE ?? BASES[flag('env', 'prod')];
const key = process.env.NUVO_INTERNAL_KEY;
if (!key) {
  console.error('NUVO_INTERNAL_KEY is not set (the INTERNAL_API_KEY secret value).');
  process.exit(2);
}
const title = flag('title', 'Welcome to Nuvo Capitol Hackers');
const body = flag('body', "Let's get moving");
const broadcastId = flag('id', null);
const send = has('send');
const expect = flag('expect', null);

async function call(payload) {
  const res = await fetch(`${base}/internal/notifications/broadcast`, {
    method: 'POST',
    headers: { 'X-Internal-Key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: res.status, json };
}

const common = {
  title,
  body,
  ...(broadcastId ? { broadcastId } : {}),
  ...(flag('category', null) ? { category: flag('category') } : {}),
  ...(flag('dest', null) ? { dest: { type: flag('dest') } } : {}),
  ...(flag('batch', null) ? { batchSize: Number(flag('batch')) } : {}),
};

if (!send) {
  const r = await call({ ...common, dryRun: true });
  console.log(`HTTP ${r.status}`);
  console.log(JSON.stringify(r.json, null, 2));
  if (!r.json?.ok) process.exit(1);
  console.log(
    `\nDry run only. To send to all ${r.json.recipients} users, re-run with:\n  --id <broadcastId> --send --expect ${r.json.recipients}`,
  );
  process.exit(0);
}

if (!broadcastId || expect === null || !/^\d+$/.test(expect)) {
  console.error('A real send needs --id <broadcastId> and --expect <recipient count from the dry run>.');
  process.exit(2);
}

const totals = { batches: 0, sent: 0, inboxRows: 0, alreadyHad: 0, pushSent: 0, pushFailed: 0 };
let cursor = null;
let pushConfigured = null;
do {
  const r = await call({ ...common, dryRun: false, expectedCount: Number(expect), ...(cursor ? { cursor } : {}) });
  if (!r.json?.ok) {
    console.error(`HTTP ${r.status}`, JSON.stringify(r.json, null, 2));
    console.error(`Stopped after ${totals.batches} batch(es); cursor=${cursor}. Re-running the same --id is safe.`);
    process.exit(1);
  }
  totals.batches += 1;
  for (const k of ['sent', 'inboxRows', 'alreadyHad', 'pushSent', 'pushFailed']) totals[k] += r.json[k] ?? 0;
  pushConfigured = r.json.pushConfigured;
  cursor = r.json.nextCursor ?? null;
  console.log(`batch ${totals.batches}: sent=${r.json.sent} inboxRows=${r.json.inboxRows} pushSent=${r.json.pushSent} next=${cursor}`);
} while (cursor);

console.log(JSON.stringify({ done: true, ...totals, pushConfigured }, null, 2));
if (pushConfigured === false) {
  console.log('Push is not configured (no FCM secrets): inbox rows were written, 0 pushes were sent.');
}
