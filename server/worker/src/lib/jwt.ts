import type { MiddlewareHandler } from 'hono';
import type { AppEnv } from '../types';

const enc = new TextEncoder();
const dec = new TextDecoder();

export interface JwtPayload {
  sub: string;
  iat: number;
  exp: number;
}

async function importKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

function b64url(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function b64urlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

export async function signJwt(payload: JwtPayload, secret: string): Promise<string> {
  const header = b64url(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const message = `${header}.${body}`;
  const key = await importKey(secret);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return `${message}.${b64url(sig)}`;
}

export async function verifyJwt(token: string, secret: string): Promise<JwtPayload> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('malformed token');
  const [header, body, sigPart] = parts;
  const message = `${header}.${body}`;
  const key = await importKey(secret);
  const valid = await crypto.subtle.verify(
    'HMAC',
    key,
    b64urlDecode(sigPart).buffer as ArrayBuffer,
    enc.encode(message).buffer as ArrayBuffer,
  );
  if (!valid) throw new Error('invalid signature');
  const payload = JSON.parse(dec.decode(b64urlDecode(body))) as JwtPayload;
  if (payload.exp < Math.floor(Date.now() / 1000)) throw new Error('token expired');
  return payload;
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ ok: false, error: 'Unauthorized' }, 401);
  }
  try {
    const payload = await verifyJwt(authHeader.slice(7), c.env.JWT_SECRET);
    c.set('userId', payload.sub);
    await next();
    return;
  } catch {
    return c.json({ ok: false, error: 'Unauthorized' }, 401);
  }
};
