import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { sendVerificationCode } = require('../.tmp-test-dist/lib/resend.js');

// Capture the exact Resend payload without hitting the network.
async function captureSend(code = '483920') {
  let body;
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (_url, init) => {
    body = JSON.parse(init.body);
    return new Response('{}', { status: 200 });
  };
  try {
    await sendVerificationCode('racer@example.com', code, 'test-key', 'no-reply@getnuvo.net');
  } finally {
    globalThis.fetch = realFetch;
  }
  return body;
}

test('verification email contract', async () => {
  const body = await captureSend('483920');

  assert.equal(body.subject, 'Your Nuvo verification code');
  assert.deepEqual(body.to, ['racer@example.com']);
  assert.equal(body.from, 'Nuvo <no-reply@getnuvo.net>');
  assert.equal(typeof body.html, 'string');
  assert.equal(typeof body.text, 'string');

  // The OTP is contiguous text — letter-spacing is visual only, so copy
  // yields a clean value. No spaces/punctuation inside the code node.
  assert.match(body.html, />483920</);
  assert.ok(body.text.includes('483920'));

  // No debug/dev leakage.
  assert.ok(!/localhost|127\.0\.0\.1|workers\.dev|example\.com/i.test(body.html));
  assert.ok(!/localhost|127\.0\.0\.1|workers\.dev/i.test(body.text));

  // Canonical links.
  assert.ok(body.html.includes('https://getnuvo.net/privacy'));
  assert.ok(body.html.includes('https://getnuvo.net/terms'));
  assert.ok(body.html.includes('https://getnuvo.net'));

  // One-line OTP on mobile.
  assert.ok(body.html.includes('white-space:nowrap'));
});

test('code is never logged or leaked on send failure', async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('err', { status: 500 });
  try {
    await assert.rejects(
      sendVerificationCode('racer@example.com', '112233', 'test-key', 'no-reply@getnuvo.net'),
      (err) => {
        assert.ok(!String(err.message).includes('112233'));
        return true;
      },
    );
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('logo is an inline CID attachment with alt text and explicit size', async () => {
  const body = await captureSend('483920');
  assert.ok(body.html.includes('src="cid:nuvo-logo"'));
  const img = body.html.match(/<img[^>]*>/)[0];
  assert.match(img, /alt="Nuvo"/);
  assert.match(img, /width="\d+"/);
  assert.match(img, /height="\d+"/);
  const att = body.attachments.find((a) => a.content_id === 'nuvo-logo');
  assert.ok(att && att.content.length > 1000 && att.content_type === 'image/png');
  assert.ok(body.html.includes('10 minutes') && body.text.includes('10 minutes'));
});
