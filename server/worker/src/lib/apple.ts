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
