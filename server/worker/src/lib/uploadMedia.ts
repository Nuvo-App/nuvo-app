/**
 * Signed upload-token helpers shared by every R2 write path (profile photos,
 * proof evidence). The token embeds the object key + content type and is
 * signed with JWT_SECRET — the URL itself is the upload credential, so PUT
 * handlers can stay session-free exactly like /profile/photo/upload.
 */

export const UPLOAD_URL_TTL_SECONDS = 600;

export function awsEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (char) =>
    `%${char.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

export function encodeKeyPath(key: string): string {
  return key.split('/').map(awsEncode).join('/');
}

function toHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function b64urlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(
    Math.ceil(value.length / 4) * 4,
    '=',
  );
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

async function hmac(key: string, data: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(key),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
  return crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(data));
}

export function extensionFor(fileName: string, contentType: string): string {
  const cleanName = fileName.toLowerCase();
  const extension = cleanName.match(/\.(jpe?g|png|webp)$/)?.[1];
  if (extension) return extension === 'jpeg' ? 'jpg' : extension;
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/webp') return 'webp';
  return 'jpg';
}

export async function signUploadToken(params: {
  key: string;
  contentType: string;
  jwtSecret: string;
}): Promise<string> {
  const payload = b64url(
    new TextEncoder().encode(JSON.stringify({
      key: params.key,
      contentType: params.contentType,
      exp: Math.floor(Date.now() / 1000) + UPLOAD_URL_TTL_SECONDS,
    })),
  );
  const signature = toHex(await hmac(params.jwtSecret, payload));
  return `${payload}.${signature}`;
}

export async function verifyUploadToken(
  token: string,
  jwtSecret: string,
  allowedKeyPrefixes: string[],
) {
  const [payload, signature] = token.split('.');
  if (!payload || !signature) return null;
  const expected = toHex(await hmac(jwtSecret, payload));
  if (signature !== expected) return null;

  const parsed = JSON.parse(new TextDecoder().decode(b64urlDecode(payload))) as {
    key?: unknown;
    contentType?: unknown;
    exp?: unknown;
  };
  if (typeof parsed.exp !== 'number' || parsed.exp < Math.floor(Date.now() / 1000)) {
    return null;
  }
  const key = parsed.key;
  if (typeof key !== 'string' || !allowedKeyPrefixes.some((p) => key.startsWith(p))) {
    return null;
  }
  if (typeof parsed.contentType !== 'string') return null;
  return { key, contentType: parsed.contentType };
}
