#!/usr/bin/env node
// Nuvo API smoke check. No secrets needed.
//
// Usage:  node scripts/nuvo-smoke.mjs [baseUrl]
//   baseUrl defaults to https://nuvo-api.getnuvoapp.workers.dev
// Checks: GET /health (ok + db), GET /config (JSON flags), GET /squads without
// a token (401 JSON). Prints PASS/FAIL per check; exit code 0 = all passed.
const base = (process.argv[2] ?? 'https://nuvo-api.getnuvoapp.workers.dev').replace(/\/+$/, '');

async function call(path) {
  const res = await fetch(base + path, { headers: { Accept: 'application/json' } });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, json };
}

const checks = [
  ['GET /health -> 200 {ok:true, db:true}', async () => {
    const r = await call('/health');
    return r.status === 200 && r.json?.ok === true && r.json?.db === true;
  }],
  ['GET /config -> 200 JSON with flags', async () => {
    const r = await call('/config');
    return r.status === 200 && typeof r.json?.custom_motion === 'boolean';
  }],
  ['GET /squads without token -> 401 JSON', async () => {
    const r = await call('/squads');
    return r.status === 401 && r.json?.ok === false;
  }],
  ['GET /no-such-route -> 404 JSON', async () => {
    const r = await call('/no-such-route');
    return r.status === 404 && r.json?.ok === false;
  }],
];

let failed = 0;
for (const [name, fn] of checks) {
  let ok = false;
  try { ok = await fn(); } catch (e) { console.log(`   ${e.message}`); }
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
}
console.log(failed === 0 ? `ALL PASSED (${base})` : `${failed} FAILED (${base})`);
process.exit(failed === 0 ? 0 : 1);
