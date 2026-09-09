/**
 * Push transport (docs/agents/19 §10). Push is DELIVERY; the notification row
 * is the product state. This module is DORMANT until an FCM credential is
 * configured — `wrangler secret put FCM_SERVICE_ACCOUNT` (the service-account
 * JSON) + `wrangler secret put FCM_PROJECT_ID`. Without them `sendPush` looks
 * up device tokens, logs, and returns 0 sent — nothing else in the pipeline
 * changes.
 *
 * When configured it uses FCM HTTP v1 (OAuth2 service-account → bearer →
 * POST /v1/projects/<id>/messages:send), one request per live device token,
 * and disables a token FCM reports as UNREGISTERED / INVALID_ARGUMENT.
 */

interface PushEnv {
  DB: D1Database;
  FCM_SERVICE_ACCOUNT?: string;
  FCM_PROJECT_ID?: string;
}

export interface PushPayload {
  title: string;
  body?: string;
  category: string;
  dest?: { type: string; id?: string; context?: string };
}

interface DeviceRow {
  id: string;
  token: string;
  platform: string;
}

export function pushConfigured(env: PushEnv): boolean {
  return Boolean(env.FCM_SERVICE_ACCOUNT && env.FCM_PROJECT_ID);
}

/** Returns the number of devices a push was accepted for. */
export async function sendPush(
  env: PushEnv,
  userId: string,
  payload: PushPayload,
): Promise<number> {
  const devices = await env.DB.prepare(
    `SELECT id, token, platform FROM device_tokens
     WHERE user_id = ? AND disabled_at IS NULL`,
  )
    .bind(userId)
    .all<DeviceRow>();

  if (devices.results.length === 0) return 0;
  if (!pushConfigured(env)) {
    console.log(
      `[push] dormant — would send "${payload.category}" to ${devices.results.length} device(s) for ${userId}`,
    );
    return 0;
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken(env.FCM_SERVICE_ACCOUNT!);
  } catch (err) {
    console.error('[push] token exchange failed:', (err as Error).message);
    return 0;
  }

  let sent = 0;
  for (const device of devices.results) {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: { title: payload.title, body: payload.body ?? '' },
              data: {
                category: payload.category,
                destType: payload.dest?.type ?? '',
                destId: payload.dest?.id ?? '',
                destContext: payload.dest?.context ?? '',
              },
              apns: { payload: { aps: { sound: 'default' } } },
            },
          }),
        },
      );
      if (res.ok) {
        sent++;
      } else {
        const text = await res.text();
        if (res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(text)) {
          await env.DB.prepare(
            'UPDATE device_tokens SET disabled_at = CURRENT_TIMESTAMP WHERE id = ?',
          )
            .bind(device.id)
            .run();
        }
      }
    } catch (err) {
      console.error('[push] send failed:', (err as Error).message);
    }
  }
  return sent;
}

// ── FCM service-account → OAuth2 access token (JWT bearer grant) ──────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

async function getAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson) as ServiceAccount;
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: sa.token_uri ?? 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc(header)}.${enc(claim)}`;
  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch(sa.token_uri ?? 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`token endpoint ${res.status}`);
  const json = (await res.json()) as { access_token: string };
  return json.access_token;
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der.buffer as ArrayBuffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}
