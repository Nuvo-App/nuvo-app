// Unambiguous uppercase alphanumeric set — no I, L, O, 0, 1
const MEMBER_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function generateId(): string {
  return crypto.randomUUID();
}

export function generateOtp(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(buf[0] % 1_000_000).padStart(6, '0');
}

export async function hashValue(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function generateRefreshToken(): string {
  const buf = new Uint8Array(48);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function generateMemberId(): string {
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  const suffix = Array.from(buf)
    .map((b) => MEMBER_CHARS[b % MEMBER_CHARS.length])
    .join('');
  return `NUVO-${suffix}`;
}

export function memberIdToSlug(memberId: string): string {
  return memberId.replace('NUVO-', '').toLowerCase();
}
