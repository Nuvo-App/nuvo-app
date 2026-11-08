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
  /** The durable inbox row this push mirrors — lets the client beacon opens. */
  notificationId?: string;
}

interface DeviceRow {
  id: string;
  token: string;
  platform: string;
}

export function pushConfigured(env: PushEnv): boolean {
  return Boolean(env.FCM_SERVICE_ACCOUNT && env.FCM_PROJECT_ID);
}

/**
 * Why a send did (or did not) reach FCM. Every outcome is distinguishable so a
 * missing notification can be traced to ONE cause:
 *
 *   no_devices   the recipient has no registered, enabled device token
 *   dormant      devices exist but FCM credentials are not configured
 *   auth_failed  FCM credentials are configured but the OAuth exchange failed
 *   rejected     FCM answered, and refused every device (see results[])
 *   partial      some devices accepted, some refused
 *   sent         FCM accepted every device (delivery to the phone is FCM/APNs'
 *                job and is NOT confirmed here)
 */
export type PushOutcome =
  | 'no_devices'
  | 'dormant'
  | 'auth_failed'
  | 'rejected'
  | 'partial'
  | 'sent';

export interface PushDeviceResult {
  platform: string;
  status: 'accepted' | 'rejected' | 'token_disabled' | 'error';
  httpStatus?: number;
  /** FCM error code, e.g. UNREGISTERED, SENDER_ID_MISMATCH, THIRD_PARTY_AUTH_ERROR. */
  code?: string;
}

export interface PushResult {
  outcome: PushOutcome;
  configured: boolean;
  devices: number;
  accepted: number;
  results: PushDeviceResult[];
  error?: string;
}

interface FcmError {
  code?: string;
  message?: string;
}

/** Pull the machine-readable code out of an FCM v1 error body. */
export function parseFcmError(text: string): FcmError {
  try {
    const body = JSON.parse(text) as {
      error?: {
        status?: string;
        message?: string;
        details?: Array<{ errorCode?: string }>;
      };
    };
    const detail = body.error?.details?.find((d) => d.errorCode)?.errorCode;
    return { code: detail ?? body.error?.status, message: body.error?.message };
  } catch {
    return { message: text.slice(0, 200) };
  }
}

/**
 * Only a response that says THIS TOKEN is dead disables it. A blanket
 * INVALID_ARGUMENT used to disable tokens for payload problems too, which would
 * silently kill every healthy device the first time a payload was malformed.
 */
export function tokenIsDead(httpStatus: number, err: FcmError): boolean {
  if (httpStatus === 404 || err.code === 'UNREGISTERED') return true;
  return err.code === 'INVALID_ARGUMENT' && /registration token/i.test(err.message ?? '');
}

function logPush(
  result: PushResult,
  userId: string,
  category: string,
): void {
  const detail = result.results
    .filter((r) => r.status !== 'accepted')
    .map((r) => `${r.platform}:${r.httpStatus ?? '-'}/${r.code ?? r.status}`)
    .join(',');
  const line =
    `[push] outcome=${result.outcome} category=${category} user=${userId} ` +
    `devices=${result.devices} accepted=${result.accepted}` +
    (detail ? ` failures=${detail}` : '') +
    (result.error ? ` error=${result.error}` : '');
  if (result.outcome === 'sent' || result.outcome === 'no_devices' || result.outcome === 'dormant') {
    console.log(line);
  } else {
    console.error(line);
  }
}

/** Returns the number of devices a push was accepted for. */
export async function sendPush(
  env: PushEnv,
  userId: string,
  payload: PushPayload,
): Promise<number> {
  return (await sendPushDetailed(env, userId, payload)).accepted;
}

/** Same send, with the full outcome. Always logs exactly one [push] line. */
export async function sendPushDetailed(
  env: PushEnv,
  userId: string,
  payload: PushPayload,
): Promise<PushResult> {
  const result = await attemptPush(env, userId, payload);
  logPush(result, userId, payload.category);
  return result;
}

async function attemptPush(
  env: PushEnv,
  userId: string,
  payload: PushPayload,
): Promise<PushResult> {
  const configured = pushConfigured(env);
  const devices = await env.DB.prepare(
    `SELECT id, token, platform FROM device_tokens
     WHERE user_id = ? AND disabled_at IS NULL`,
  )
    .bind(userId)
    .all<DeviceRow>();
  const base = { configured, devices: devices.results.length, accepted: 0, results: [] };

  if (devices.results.length === 0) return { ...base, outcome: 'no_devices' };
  if (!configured) return { ...base, outcome: 'dormant' };

  let accessToken: string;
  try {
    accessToken = await getAccessToken(env.FCM_SERVICE_ACCOUNT!);
  } catch (err) {
    return { ...base, outcome: 'auth_failed', error: (err as Error).message };
  }

  // The badge mirrors the durable inbox — a push always lands its row first,
  // so the unread count it carries is current at send time. (It can go stale
  // if the user reads in-app and no further push arrives; correcting that
  // needs a client-side badge API the SDK version doesn't expose.)
  const unread = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL',
  )
    .bind(userId)
    .first<{ n: number }>();

  const deliver = async (deviceToken: string): Promise<Response> => {
    const body = JSON.stringify({
      message: {
        token: deviceToken,
        notification: { title: payload.title, body: payload.body ?? '' },
        data: {
          category: payload.category,
          notificationId: payload.notificationId ?? '',
          destType: payload.dest?.type ?? '',
          destId: payload.dest?.id ?? '',
          destContext: payload.dest?.context ?? '',
        },
        apns: { payload: { aps: { sound: 'default', badge: unread?.n ?? 0 } } },
      },
    });
    const post = () =>
      fetch(
        `https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body,
        },
      );
    // One retry on transient failure (network error or 5xx) — FCM blips are
    // common and `waitUntil` gives the retry room. Permanent errors (4xx)
    // are never retried; a dead token is disabled on the first response.
    let res: Response;
    try {
      res = await post();
    } catch {
      await new Promise((r) => setTimeout(r, 700));
      res = await post();
    }
    if (res.status >= 500) {
      await new Promise((r) => setTimeout(r, 700));
      res = await post();
    }
    return res;
  };

  const results: PushDeviceResult[] = [];
  let accepted = 0;
  for (const device of devices.results) {
    try {
      const res = await deliver(device.token);
      if (res.ok) {
        accepted++;
        results.push({ platform: device.platform, status: 'accepted', httpStatus: res.status });
        continue;
      }
      const err = parseFcmError(await res.text());
      if (tokenIsDead(res.status, err)) {
        await env.DB.prepare(
          'UPDATE device_tokens SET disabled_at = CURRENT_TIMESTAMP WHERE id = ?',
        )
          .bind(device.id)
          .run();
        results.push({
          platform: device.platform,
          status: 'token_disabled',
          httpStatus: res.status,
          code: err.code,
        });
      } else {
        // e.g. SENDER_ID_MISMATCH (token minted by a DIFFERENT Firebase project
        // than the Worker's FCM_PROJECT_ID), THIRD_PARTY_AUTH_ERROR (APNs key
        // missing in Firebase), QUOTA_EXCEEDED. The token is NOT disabled.
        results.push({
          platform: device.platform,
          status: 'rejected',
          httpStatus: res.status,
          code: err.code,
        });
      }
    } catch (err) {
      results.push({ platform: device.platform, status: 'error', code: (err as Error).message.slice(0, 80) });
    }
  }
  const outcome: PushOutcome =
    accepted === 0 ? 'rejected' : accepted === devices.results.length ? 'sent' : 'partial';
  return { ...base, accepted, results, outcome };
}

export interface FcmCredentialCheck {
  configured: boolean;
  /** project_id inside the service-account JSON (not a secret). */
  serviceAccountProjectId: string | null;
  fcmProjectId: string | null;
  /** The two project ids agree. A mismatch means every send 403s. */
  projectsMatch: boolean | null;
  tokenExchange: 'ok' | 'failed' | 'skipped';
  error?: string;
}

/**
 * Proves the FCM credentials are usable WITHOUT sending anything: parses the
 * service account, checks its project against FCM_PROJECT_ID, and performs the
 * OAuth token exchange. Never returns key material.
 */
export async function checkFcmCredentials(env: PushEnv): Promise<FcmCredentialCheck> {
  const configured = pushConfigured(env);
  const out: FcmCredentialCheck = {
    configured,
    serviceAccountProjectId: null,
    fcmProjectId: env.FCM_PROJECT_ID ?? null,
    projectsMatch: null,
    tokenExchange: 'skipped',
  };
  if (!configured) return out;
  try {
    const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT!) as { project_id?: string };
    out.serviceAccountProjectId = sa.project_id ?? null;
    out.projectsMatch = out.serviceAccountProjectId === out.fcmProjectId;
  } catch {
    out.tokenExchange = 'failed';
    out.error = 'FCM_SERVICE_ACCOUNT is not valid JSON';
    return out;
  }
  try {
    await getAccessToken(env.FCM_SERVICE_ACCOUNT!);
    out.tokenExchange = 'ok';
  } catch (err) {
    out.tokenExchange = 'failed';
    out.error = (err as Error).message;
  }
  return out;
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
