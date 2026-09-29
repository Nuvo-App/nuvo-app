// Expiry comparisons must compare like with like. The Worker writes expiry
// columns via Date.prototype.toISOString() — 'YYYY-MM-DDTHH:MM:SS.sssZ'.
// SQLite CURRENT_TIMESTAMP/datetime() produce 'YYYY-MM-DD HH:MM:SS' (space
// separator, no zone), which lexically sorts before any same-day ISO value,
// so `expires_at > CURRENT_TIMESTAMP` treated every ISO row as unexpired
// until the date rolled over. ISO-written columns compare against ISO now;
// columns written via CURRENT_TIMESTAMP keep comparing against datetime().

/** SQL expression: current UTC instant in ISO-8601 (matches toISOString()). */
export const SQLITE_NOW_ISO = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";

/** SQL expression: UTC instant `offset` ago, in ISO-8601. */
export function sqliteIsoOffset(offset: string): string {
  return `strftime('%Y-%m-%dT%H:%M:%fZ','now','${offset}')`;
}
