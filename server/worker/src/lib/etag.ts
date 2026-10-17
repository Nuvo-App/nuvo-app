import type { Context } from 'hono';
import type { AppEnv } from '../types';

/**
 * Conditional-GET helpers for the authenticated read routes.
 *
 * Responses here are per-user, so they are `private, no-cache`: a client may
 * keep the body but must revalidate, and a matching `If-None-Match` costs a
 * 304 with no body. Older app builds never send `If-None-Match`, so they keep
 * getting full 200s — adding validators never changes a response body.
 *
 * A validator MUST change whenever the response could. Where a payload field
 * is not covered by a precise signal (profile names, invites, ...), fold in
 * {@link stalenessBucket} so the worst-case staleness is bounded.
 */

/** Weak ETag over arbitrary parts: `W/"a:b:c"`. Null/undefined become ''. */
export function weakEtag(...parts: ReadonlyArray<string | number | null | undefined>): string {
  return `W/"${parts.map((p) => String(p ?? '')).join(':')}"`;
}

/** Wall-clock bucket that caps how long an uncovered change can stay hidden. */
export function stalenessBucket(nowMs: number = Date.now(), bucketMs = 5 * 60_000): number {
  return Math.floor(nowMs / bucketMs);
}

function opaque(tag: string): string {
  return tag.trim().replace(/^W\//, '');
}

/** Whether an `If-None-Match` header value matches [etag] (weak comparison). */
export function etagMatches(header: string | undefined | null, etag: string): boolean {
  if (!header) return false;
  if (header.trim() === '*') return true;
  const want = opaque(etag);
  return header.split(',').some((t) => opaque(t) === want);
}

/**
 * Stamp validators on the response and short-circuit with a 304 when the
 * client already holds this version. Returns the 304 to `return` from the
 * handler, or null when the handler should build the full response (the
 * validators are already set on it).
 *
 * Call it AFTER any lazy lifecycle writes the handler performs, so a 304 can
 * never hide a state transition, and BEFORE the expensive response build.
 */
export function conditional(c: Context<AppEnv>, etag: string): Response | null {
  c.header('ETag', etag);
  c.header('Cache-Control', 'private, no-cache');
  c.header('Vary', 'Authorization');
  if (etagMatches(c.req.header('If-None-Match'), etag)) return c.body(null, 304);
  return null;
}
