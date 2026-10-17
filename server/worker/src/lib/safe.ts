// Small guards shared by the social routes so a bad request or a failed
// side effect answers with clean JSON instead of a 500.

/** Parses a JSON object body. Returns null for bad JSON, null, arrays and scalars. */
export async function readJsonObject(c: {
  req: { json: <T = unknown>() => Promise<T> };
}): Promise<Record<string, unknown> | null> {
  try {
    const body = await c.req.json<unknown>();
    return body && typeof body === 'object' && !Array.isArray(body)
      ? (body as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

/**
 * Runs a side effect that must not undo or fail the primary action (a
 * notification, a feed event, a push). Failures are logged once as
 * structured JSON and swallowed. Returns the value, or undefined on failure.
 */
export async function bestEffort<T>(label: string, fn: () => Promise<T> | T): Promise<T | undefined> {
  try {
    return await fn();
  } catch (err) {
    console.error(
      JSON.stringify({
        evt: 'side_effect_failed',
        label,
        message: (err instanceof Error ? err.message : String(err)).slice(0, 300),
      }),
    );
    return undefined;
  }
}

/** Query-string integer clamped to [min, max]; NaN or junk falls back. */
export function clampedInt(raw: string | undefined | null, fallback: number, min: number, max: number): number {
  const n = Number(raw ?? fallback);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(Math.trunc(n), min), max);
}
