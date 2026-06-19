// Web-origin allowlist for CORS pre-flight checks.
// Native mobile apps (Flutter) bypass CORS entirely; this only matters for
// browser-based callers (web dashboard, local dev).
export const ALLOWED_WEB_ORIGINS = [
  'https://getnuvo.net',
  'https://www.getnuvo.net',
] as const;

export const SHARE_BASE_URL = 'https://getnuvo.net';
