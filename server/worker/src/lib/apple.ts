export interface AppleTokenInfo {
  sub: string;
  email: string;
  emailVerified: boolean;
}

interface AppleJwk {
  kty: string;
  kid: string;
  n: string;
  e: string;
  alg: string;
  use: string;
}

interface AppleKeyResponse {
  keys: AppleJwk[];
}

interface AppleJwtHeader {
  kid: string;
  alg: string;
}

interface AppleJwtPayload {
  iss: string;
  aud: string;
  exp: number;
  sub: string;
  email?: string;
  email_verified?: boolean | 'true' | 'false';
}

function base64UrlToBytes(input: string): Uint8Array {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  );
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function base64UrlToString(input: string): string {
  const bytes = base64UrlToBytes(input);
  const decoder = new TextDecoder('utf-8');
  return decoder.decode(bytes);
}

export async function verifyAppleIdToken(
  idToken: string,
  expectedBundleId: string,
): Promise<AppleTokenInfo> {
  const parts = idToken.split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed Apple identity token');
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  let header: AppleJwtHeader;
  let payload: AppleJwtPayload;
  try {
    header = JSON.parse(base64UrlToString(headerB64)) as AppleJwtHeader;
    payload = JSON.parse(base64UrlToString(payloadB64)) as AppleJwtPayload;
  } catch {
    throw new Error('Malformed Apple identity token payload');
  }

  if (header.alg !== 'RS256') {
    throw new Error(`Unsupported Apple token algorithm: ${header.alg}`);
  }

  const res = await fetch('https://appleid.apple.com/auth/keys');
  if (!res.ok) {
    throw new Error('Failed to fetch Apple public keys');
  }

  const { keys } = (await res.json()) as AppleKeyResponse;
  const jwk = keys.find((k) => k.kid === header.kid && k.alg === header.alg);
  if (!jwk) {
    throw new Error('Apple signing key not found');
  }

  const cryptoKey = await crypto.subtle.importKey(
    'jwk',
    {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      alg: jwk.alg,
    },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlToBytes(signatureB64);

  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    signature,
    data,
  );
  if (!valid) {
    throw new Error('Apple token signature verification failed');
  }

  if (payload.iss !== 'https://appleid.apple.com') {
    throw new Error('Apple token issuer mismatch');
  }

  if (payload.aud !== expectedBundleId) {
    throw new Error('Apple token audience mismatch');
  }

  const now = Math.floor(Date.now() / 1000);
  if (!payload.exp || payload.exp < now) {
    throw new Error('Apple token expired');
  }

  if (!payload.email) {
    throw new Error('Apple token missing email');
  }

  const emailVerified =
    payload.email_verified === true || payload.email_verified === 'true';

  return {
    sub: payload.sub,
    email: payload.email,
    emailVerified,
  };
}

// ── Sign in with Apple server flow ───────────────────────────────────────────
// Apple's account-deletion rule (App Review 5.1.1(v)) requires revoking the
// user's Apple authorization when their account is deleted. That needs a
// refresh token: the client forwards its one-time authorizationCode at
// sign-in, we exchange it at /auth/token, and we call /auth/revoke on delete.

export interface AppleServiceConfig {
  /** Bundle id for the native app — Apple's `client_id` for /auth/token. */
  clientId: string;
  teamId: string;
  keyId: string;
  /** Contents of the .p8 key (PEM text or bare base64 body). */
  privateKey: string;
}

export function appleServiceConfig(env: {
  APPLE_BUNDLE_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
}): AppleServiceConfig | undefined {
  const clientId = env.APPLE_BUNDLE_ID;
  const { APPLE_TEAM_ID: teamId, APPLE_KEY_ID: keyId, APPLE_PRIVATE_KEY: privateKey } = env;
  if (!clientId || !teamId || !keyId || !privateKey) return undefined;
  return { clientId, teamId, keyId, privateKey };
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function stringToBase64Url(input: string): string {
  return bytesToBase64Url(new TextEncoder().encode(input));
}

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body.replace(/-/g, '+').replace(/_/g, '/'));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/**
 * Apple client_secret: ES256 JWT — iss=team id, sub=client id,
 * aud=appleid.apple.com, ≤6-month expiry, kid=key id, signed with the .p8.
 * https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret
 */
export async function buildAppleClientSecret(
  config: AppleServiceConfig,
  now: Date = new Date(),
): Promise<string> {
  const header = stringToBase64Url(
    JSON.stringify({ alg: 'ES256', kid: config.keyId }),
  );
  const iat = Math.floor(now.getTime() / 1000);
  const payload = stringToBase64Url(
    JSON.stringify({
      iss: config.teamId,
      iat,
      exp: iat + 180 * 24 * 60 * 60,
      aud: 'https://appleid.apple.com',
      sub: config.clientId,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8Bytes(config.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  // ECDSA in WebCrypto emits the raw r||s signature Apple expects.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return `${signingInput}.${bytesToBase64Url(signature)}`;
}

export interface AppleTokenExchangeResult {
  refreshToken: string | null;
}

async function postAppleForm(
  fetchImpl: typeof fetch,
  path: string,
  form: Record<string, string>,
): Promise<Response> {
  return fetchImpl(`https://appleid.apple.com/auth/${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form).toString(),
  });
}

/**
 * Exchange the one-time authorizationCode at Apple's token endpoint.
 * Apple only returns a refresh_token for a fresh authorization grant —
 * a re-auth response without one must not wipe a stored token.
 */
export async function exchangeAppleAuthorizationCode(
  config: AppleServiceConfig,
  code: string,
  fetchImpl: typeof fetch = fetch,
): Promise<AppleTokenExchangeResult> {
  const clientSecret = await buildAppleClientSecret(config);
  const res = await postAppleForm(fetchImpl, 'token', {
    client_id: config.clientId,
    client_secret: clientSecret,
    code,
    grant_type: 'authorization_code',
  });
  if (!res.ok) {
    throw new Error(`Apple token exchange failed (HTTP ${res.status})`);
  }
  const body = (await res.json()) as { refresh_token?: unknown };
  return {
    refreshToken:
      typeof body.refresh_token === 'string' && body.refresh_token.length > 0
        ? body.refresh_token
        : null,
  };
}

/**
 * Revoke a stored refresh token. Apple's endpoint returns 200 both for a
 * successful revocation and for a token that was already invalid — both are
 * treated as terminal: the grant is gone either way.
 */
export async function revokeAppleRefreshToken(
  config: AppleServiceConfig,
  refreshToken: string,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const clientSecret = await buildAppleClientSecret(config);
  const res = await postAppleForm(fetchImpl, 'revoke', {
    client_id: config.clientId,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: 'refresh_token',
  });
  if (!res.ok) {
    throw new Error(`Apple token revocation failed (HTTP ${res.status})`);
  }
}

// ── Credential storage on auth_identities ────────────────────────────────────
// provider_refresh_token lives on the canonical identity row. It is never
// selected into any public response and is deleted with the identity.

interface AppleIdentityRow {
  id: string;
  provider_refresh_token: string | null;
}

type DbLike = Pick<D1Database, 'prepare'>;

/**
 * Revoke the user's Apple grant before account deletion removes the row.
 *
 * - 'none'     — no Apple identity or no stored token (legacy beta accounts
 *                predate authorizationCode capture; nothing to revoke).
 * - 'revoked'  — Apple accepted (or the token was already dead); the identity
 *                row is deleted here so canonical deletion owns the rest.
 * - 'pending'  — Apple was unreachable/errored. The row is anonymized but
 *                kept so retryPendingAppleRevocations can finish the job —
 *                deletion must never be blocked by a transient Apple outage.
 */
export async function revokeAppleCredentialForUser(
  db: DbLike,
  config: AppleServiceConfig | undefined,
  userId: string,
  fetchImpl: typeof fetch = fetch,
): Promise<'none' | 'revoked' | 'pending'> {
  const row = await db
    .prepare(
      "SELECT id, provider_refresh_token FROM auth_identities WHERE user_id = ? AND provider = 'apple'",
    )
    .bind(userId)
    .first<AppleIdentityRow>();
  if (!row?.provider_refresh_token) return 'none';
  if (!config) {
    console.error('[apple] refresh token present but Apple service config missing — keeping credential for retry');
    return 'pending';
  }
  try {
    await revokeAppleRefreshToken(config, row.provider_refresh_token, fetchImpl);
    await db.prepare('DELETE FROM auth_identities WHERE id = ?').bind(row.id).run();
    return 'revoked';
  } catch (err) {
    console.error(
      '[apple] revocation failed — anonymized credential kept for scheduled retry:',
      (err as Error).message,
    );
    // Keep ONLY the refresh token: provider_user_id is nulled so the unique
    // (provider, provider_user_id) index never blocks the same Apple user
    // signing up fresh.
    await db
      .prepare(
        `UPDATE auth_identities
         SET provider_user_id = NULL, email = NULL, email_verified = 0,
             display_name = NULL, avatar_url = NULL
         WHERE id = ?`,
      )
      .bind(row.id)
      .run();
    return 'pending';
  }
}

/** Scheduled retry for revocations that failed during account deletion. */
export async function retryPendingAppleRevocations(
  db: DbLike,
  config: AppleServiceConfig,
  fetchImpl: typeof fetch = fetch,
): Promise<void> {
  const pending = await db
    .prepare(
      "SELECT id, provider_refresh_token FROM auth_identities WHERE provider = 'apple' AND provider_refresh_token IS NOT NULL AND provider_user_id IS NULL",
    )
    .all<AppleIdentityRow>();
  for (const row of pending.results) {
    if (!row.provider_refresh_token) continue;
    try {
      await revokeAppleRefreshToken(config, row.provider_refresh_token, fetchImpl);
      await db.prepare('DELETE FROM auth_identities WHERE id = ?').bind(row.id).run();
    } catch (err) {
      console.error('[apple] revocation retry failed:', (err as Error).message);
    }
  }
}
