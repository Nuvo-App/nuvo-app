/**
 * Invite tokens — the one share primitive behind race links, crew links, QR
 * codes and (later) squad links. See docs/agents/19-social-platform-contract.md.
 *
 * TOKEN DESIGN (documented decision):
 *   A high-entropy RANDOM LOOKUP token, not a signed blob. 32 bytes from
 *   crypto.getRandomValues, base64url — 256 bits of entropy, non-guessable,
 *   not derived from any internal id, so it leaks nothing. It is a row key in
 *   `invites`, which is exactly what we want: revocation (revoked_at),
 *   expiry (expires_at) and usage limits (max_uses / use_count) are all
 *   first-class columns, and every acceptance is audited in `invite_uses`.
 *   A signed/stateless token would trade all of that away for avoiding one
 *   indexed lookup — a bad trade here.
 */

export const INVITE_KINDS = ['race_join', 'crew_connect', 'squad_join'] as const;
export type InviteKind = (typeof INVITE_KINDS)[number];

export function targetTypeForKind(kind: InviteKind): 'race' | 'user' | 'squad' {
  switch (kind) {
    case 'race_join':
      return 'race';
    case 'crew_connect':
      return 'user';
    case 'squad_join':
      return 'squad';
  }
}

export interface InviteRow {
  id: string;
  token: string;
  kind: string;
  actor_user_id: string;
  target_type: string;
  target_id: string;
  max_uses: number | null;
  use_count: number;
  expires_at: string | null;
  revoked_at: string | null;
  metadata: string | null;
  created_at: string;
}

export type InviteAvailability =
  | 'active'
  | 'expired'
  | 'revoked'
  | 'used' // usage cap reached
  | 'not_found';

/**
 * Pure availability check — no I/O, unit-tested. `now` is an ISO string or Date.
 */
export function inviteAvailability(
  row: Pick<InviteRow, 'expires_at' | 'revoked_at' | 'max_uses' | 'use_count'> | null | undefined,
  now: Date = new Date(),
): InviteAvailability {
  if (!row) return 'not_found';
  if (row.revoked_at) return 'revoked';
  if (row.expires_at && new Date(row.expires_at).getTime() <= now.getTime()) {
    return 'expired';
  }
  if (row.max_uses != null && row.use_count >= row.max_uses) return 'used';
  return 'active';
}

/** HTTP status for an availability that is not `active`. */
export function statusForAvailability(a: Exclude<InviteAvailability, 'active'>): 404 | 410 {
  return a === 'not_found' ? 404 : 410;
}

const B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** 43 url-safe chars, one per random byte — ~258 bits of entropy. */
export function generateInviteToken(): string {
  const buf = new Uint8Array(43);
  crypto.getRandomValues(buf);
  let out = '';
  for (const b of buf) out += B64URL[b % 64];
  return out;
}

/** Loosely validate a token before hitting the DB (cheap enumeration guard). */
export function looksLikeInviteToken(raw: string): boolean {
  return typeof raw === 'string' && raw.length >= 24 && raw.length <= 64 && /^[A-Za-z0-9_-]+$/.test(raw);
}

/**
 * The canonical shareable URL for a token. `origin` is the Worker's own origin
 * (derived from the request) — a prettier custom domain (e.g. get.nuvo.app) is
 * a DNS-only swap that does not change this shape.
 */
export function shareUrl(origin: string, token: string): string {
  return `${origin.replace(/\/$/, '')}/j/${token}`;
}

/** Default expiry per kind, in seconds. null = no expiry. */
export function defaultExpirySeconds(kind: InviteKind): number | null {
  switch (kind) {
    case 'race_join':
      return null; // open-ended; creator can revoke / regenerate
    case 'crew_connect':
      return null; // "connect with me" is reusable, like handing out a member id
    case 'squad_join':
      return 7 * 24 * 3600;
  }
}
