import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { pushConfigured, sendPush } = require('../.tmp-test-dist/domain/push.js');

test('pushConfigured is false until BOTH secrets are set', () => {
  assert.equal(pushConfigured({}), false);
  assert.equal(pushConfigured({ FCM_SERVICE_ACCOUNT: '{}' }), false);
  assert.equal(pushConfigured({ FCM_PROJECT_ID: 'p' }), false);
  assert.equal(pushConfigured({ FCM_SERVICE_ACCOUNT: '{}', FCM_PROJECT_ID: 'p' }), true);
});

function dbWith(devices) {
  return {
    prepare() {
      return {
        bind() {
          return this;
        },
        async all() {
          return { results: devices };
        },
        async run() {},
      };
    },
  };
}

test('sendPush is a no-op (0 sent) when there are no devices', async () => {
  const n = await sendPush({ DB: dbWith([]) }, 'u1', { title: 't', category: 'race_joined' });
  assert.equal(n, 0);
});

test('sendPush stays dormant (0 sent, no fetch) when unconfigured, even with devices', async () => {
  const originalFetch = globalThis.fetch;
  let fetched = false;
  globalThis.fetch = async () => {
    fetched = true;
    return new Response('{}');
  };
  try {
    const n = await sendPush(
      { DB: dbWith([{ id: 'd1', token: 'tok', platform: 'ios' }]) },
      'u1',
      { title: 't', category: 'race_joined' },
    );
    assert.equal(n, 0);
    assert.equal(fetched, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
