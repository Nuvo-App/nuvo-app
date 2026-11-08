#!/usr/bin/env node
// Reads `flutter test --reporter json` output and fails only on test
// failures that are NOT listed in tool/ci/known_failing_tests.txt.
//
// usage: node tool/ci/check_test_failures.mjs <results.json> [known.txt]
// Known-failure lines look like: `test/path_test.dart :: full test name`.
// Lines starting with # are comments.
import { readFileSync, existsSync } from 'node:fs';

const [resultsPath, knownPath = 'tool/ci/known_failing_tests.txt'] = process.argv.slice(2);
if (!resultsPath) {
  console.error('usage: check_test_failures.mjs <results.json> [known.txt]');
  process.exit(2);
}

const events = readFileSync(resultsPath, 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((line) => { try { return JSON.parse(line); } catch { return null; } })
  .filter(Boolean);

const suites = {};
const tests = {};
let loadErrors = 0;
for (const e of events) {
  if (e.type === 'suite') suites[e.suite.id] = e.suite.path ?? '';
  if (e.type === 'testStart') tests[e.test.id] = { name: e.test.name, suite: e.test.suiteID };
  if (e.type === 'testDone' && !e.hidden && e.result !== 'success' && !e.skipped) {
    if (tests[e.testID]) tests[e.testID].failed = true;
  }
  if (e.type === 'error' && tests[e.testID] && /^loading /.test(tests[e.testID].name)) loadErrors++;
}

const rel = (p) => p.replace(/^.*?\/?(test\/)/, '$1');
const key = (t) => `${rel(suites[t.suite] || '')} :: ${t.name.replace(/^loading (.*)$/, (_, p) => `loading ${rel(p)}`)}`;
const failures = Object.values(tests).filter((t) => t.failed).map(key);

const known = new Set(
  existsSync(knownPath)
    ? readFileSync(knownPath, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
    : [],
);

const unexpected = failures.filter((f) => !known.has(f));
const fixed = [...known].filter((k) => !failures.includes(k));
const total = Object.values(tests).filter((t) => !/^loading /.test(t.name)).length;

console.log(`tests: ${total}, failing: ${failures.length}, known: ${known.size}, unexpected: ${unexpected.length}`);
if (fixed.length) {
  console.log(`\nKnown failures that now pass (remove them from ${knownPath}):`);
  for (const f of fixed) console.log(`  ${f}`);
}
if (unexpected.length) {
  console.log('\nNEW failures:');
  for (const f of unexpected) console.log(`  ${f}`);
  process.exit(1);
}
if (loadErrors) console.log(`(${loadErrors} suite load errors counted above)`);
