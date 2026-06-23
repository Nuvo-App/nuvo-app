import { Hono } from 'hono';
import type { AppEnv, UserRow, ProfileRow, EmailCodeRow, SessionRow, AuthIdentityRow } from '../types';
import { requireAuth, signJwt } from '../lib/jwt';
import {
  generateId,
  generateOtp,
  hashValue,
  generateRefreshToken,
  generateMemberId,
  memberIdToSlug,
} from '../lib/crypto';
import { verifyGoogleIdToken } from '../lib/google';
import { sendVerificationCode } from '../lib/resend';
import { normalizeEmail, isValidEmail } from '../lib/validation';

const MAX_OTP_ATTEMPTS = 5;
const OTP_TTL_MS = 10 * 60 * 1000; // 10 minutes
const ACCESS_TOKEN_TTL_S = 15 * 60; // 15 minutes
const REFRESH_TOKEN_TTL_S = 30 * 24 * 60 * 60; // 30 days

export const authRouter = new Hono<AppEnv>();

// ── Helpers ──────────────────────────────────────────────────────────────────

async function ensureProfileAndPass(db: D1Database, userId: string): Promise<void> {
  await db
    .prepare(
      `INSERT INTO profiles (user_id, created_at, updated_at)
       VALUES (?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id) DO NOTHING`,
    )
    .bind(userId)
    .run();

  const existing = await db
    .prepare('SELECT id FROM member_passes WHERE user_id = ?')
    .bind(userId)
    .first<{ id: string }>();

  if (!existing) {
    const memberId = generateMemberId();
    const passSlug = memberIdToSlug(memberId);
    await db
      .prepare(
        `INSERT INTO member_passes (id, user_id, member_id, pass_slug, created_at)
         VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)`,
      )
      .bind(generateId(), userId, memberId, passSlug)
      .run();
  }
}

async function createSession(
  db: D1Database,
  userId: string,
  jwtSecret: string,
  deviceLabel?: string,
): Promise<{ accessToken: string; refreshToken: string }> {
  const refreshToken = generateRefreshToken();
  const refreshTokenHash = await hashValue(refreshToken);
  const sessionId = generateId();
  const expiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_S * 1000).toISOString();

  await db
    .prepare(
      `INSERT INTO sessions (id, user_id, refresh_token_hash, device_label, expires_at, created_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
    )
    .bind(sessionId, userId, refreshTokenHash, deviceLabel ?? null, expiresAt)
    .run();

  const now = Math.floor(Date.now() / 1000);
  const accessToken = await signJwt(
    { sub: userId, iat: now, exp: now + ACCESS_TOKEN_TTL_S },
    jwtSecret,
  );

  return { accessToken, refreshToken };
}

async function buildUserObject(db: D1Database, userId: string, email: string) {
  const profile = await db
    .prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();
  const pass = await db
    .prepare('SELECT id FROM member_passes WHERE user_id = ?')
    .bind(userId)
    .first<{ id: string }>();

  return {
    id: userId,
    email,
    fullName: profile?.full_name ?? null,
    username: profile?.username ?? null,
    profilePhotoUrl: profile?.avatar_url ?? null,
    onboardingComplete: Boolean(profile?.onboarding_complete),
    hasMemberPass: Boolean(pass),
  };
}

async function findOrCreateUser(
  db: D1Database,
  email: string,
): Promise<UserRow> {
  let user = await db
    .prepare('SELECT * FROM users WHERE primary_email = ?')
    .bind(email)
    .first<UserRow>();

  if (!user) {
    const userId = generateId();
    await db
      .prepare(
        `INSERT INTO users (id, primary_email, status, created_at, updated_at, last_login_at)
         VALUES (?, ?, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      )
      .bind(userId, email)
      .run();
    user = await db
      .prepare('SELECT * FROM users WHERE id = ?')
      .bind(userId)
      .first<UserRow>();
  } else {
    await db
      .prepare(
        'UPDATE users SET last_login_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
      )
      .bind(user.id)
      .run();
  }

  if (!user) throw new Error('Failed to find or create user');
  return user;
}

// ── Routes ───────────────────────────────────────────────────────────────────

// POST /auth/email/start
authRouter.post('/email/start', async (c) => {
  let body: { email?: unknown };
  try {
    body = await c.req.json<{ email?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  // Always return the same generic message regardless of email validity
  const GENERIC_OK = {
    ok: true,
    message: 'If that email can receive mail, a code has been sent.',
  } as const;

  const rawEmail = typeof body.email === 'string' ? body.email : '';
  if (!rawEmail || !isValidEmail(rawEmail)) {
    return c.json(GENERIC_OK);
  }

  const email = normalizeEmail(rawEmail);
  const code = generateOtp();
  const codeHash = await hashValue(code);
  const id = generateId();
  const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString();

  await c.env.DB.prepare(
    `INSERT INTO email_codes (id, email, code_hash, attempts, expires_at, created_at)
     VALUES (?, ?, ?, 0, ?, CURRENT_TIMESTAMP)`,
  )
    .bind(id, email, codeHash, expiresAt)
    .run();

  try {
    await sendVerificationCode(email, code, c.env.RESEND_API_KEY, c.env.RESEND_FROM_EMAIL);
  } catch (err) {
    // Log that sending failed but do not expose it to the caller or leak the code
    console.error('[resend] send failed status:', err instanceof Error ? err.message : 'unknown');
  }

  return c.json(GENERIC_OK);
});

// POST /auth/email/verify
authRouter.post('/email/verify', async (c) => {
  let body: { email?: unknown; code?: unknown };
  try {
    body = await c.req.json<{ email?: unknown; code?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const rawEmail = typeof body.email === 'string' ? body.email : '';
  const rawCode = typeof body.code === 'string' ? body.code.trim() : '';

  if (!rawEmail || !rawCode) {
    return c.json({ ok: false, error: 'email and code are required' }, 400);
  }

  const email = normalizeEmail(rawEmail);

  const codeRow = await c.env.DB.prepare(
    `SELECT * FROM email_codes
     WHERE email = ? AND used_at IS NULL AND expires_at > CURRENT_TIMESTAMP
     ORDER BY created_at DESC LIMIT 1`,
  )
    .bind(email)
    .first<EmailCodeRow>();

  // Generic error — never reveal whether the email exists
  const INVALID = { ok: false, error: 'Invalid or expired code' } as const;

  if (!codeRow) return c.json(INVALID, 401);

  if (codeRow.attempts >= MAX_OTP_ATTEMPTS) {
    return c.json({ ok: false, error: 'Too many attempts. Request a new code.' }, 429);
  }

  // Increment attempts before comparing — prevents brute-force timing abuse
  await c.env.DB.prepare('UPDATE email_codes SET attempts = attempts + 1 WHERE id = ?')
    .bind(codeRow.id)
    .run();

  const providedHash = await hashValue(rawCode);
  if (providedHash !== codeRow.code_hash) {
    return c.json(INVALID, 401);
  }

  await c.env.DB.prepare('UPDATE email_codes SET used_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(codeRow.id)
    .run();

  const user = await findOrCreateUser(c.env.DB, email);

  // Ensure email identity row exists
  const existingIdentity = await c.env.DB.prepare(
    "SELECT id FROM auth_identities WHERE user_id = ? AND provider = 'email'",
  )
    .bind(user.id)
    .first<{ id: string }>();

  if (!existingIdentity) {
    await c.env.DB.prepare(
      `INSERT INTO auth_identities (id, user_id, provider, email, email_verified, created_at)
       VALUES (?, ?, 'email', ?, 1, CURRENT_TIMESTAMP)`,
    )
      .bind(generateId(), user.id, email)
      .run();
  }

  await ensureProfileAndPass(c.env.DB, user.id);

  const { accessToken, refreshToken } = await createSession(c.env.DB, user.id, c.env.JWT_SECRET);
  const userObj = await buildUserObject(c.env.DB, user.id, email);

  return c.json({ accessToken, refreshToken, user: userObj });
});

// POST /auth/google
authRouter.post('/google', async (c) => {
  let body: { idToken?: unknown };
  try {
    body = await c.req.json<{ idToken?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const idToken = typeof body.idToken === 'string' ? body.idToken : '';
  if (!idToken) {
    return c.json({ ok: false, error: 'idToken required' }, 400);
  }

  let googleInfo;
  try {
    googleInfo = await verifyGoogleIdToken(idToken, c.env.GOOGLE_IOS_CLIENT_ID);
  } catch {
    // Do not expose verification failure details
    return c.json({ ok: false, error: 'Google sign-in failed' }, 401);
  }

  const email = normalizeEmail(googleInfo.email);
  const user = await findOrCreateUser(c.env.DB, email);

  // Upsert Google identity
  const existingIdentity = await c.env.DB.prepare(
    "SELECT id FROM auth_identities WHERE user_id = ? AND provider = 'google'",
  )
    .bind(user.id)
    .first<AuthIdentityRow>();

  if (!existingIdentity) {
    await c.env.DB.prepare(
      `INSERT INTO auth_identities
         (id, user_id, provider, provider_user_id, email, email_verified, display_name, avatar_url, created_at)
       VALUES (?, ?, 'google', ?, ?, 1, ?, ?, CURRENT_TIMESTAMP)`,
    )
      .bind(generateId(), user.id, googleInfo.sub, email, googleInfo.name ?? null, googleInfo.picture ?? null)
      .run();
  } else {
    await c.env.DB.prepare(
      'UPDATE auth_identities SET display_name = ?, avatar_url = ? WHERE id = ?',
    )
      .bind(googleInfo.name ?? null, googleInfo.picture ?? null, existingIdentity.id)
      .run();
  }

  await ensureProfileAndPass(c.env.DB, user.id);

  const { accessToken, refreshToken } = await createSession(c.env.DB, user.id, c.env.JWT_SECRET);
  const userObj = await buildUserObject(c.env.DB, user.id, email);

  return c.json({ accessToken, refreshToken, user: userObj });
});

// POST /auth/refresh
authRouter.post('/refresh', async (c) => {
  let body: { refreshToken?: unknown };
  try {
    body = await c.req.json<{ refreshToken?: unknown }>();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const rawToken = typeof body.refreshToken === 'string' ? body.refreshToken : '';
  if (!rawToken) {
    return c.json({ ok: false, error: 'refreshToken required' }, 400);
  }

  const tokenHash = await hashValue(rawToken);

  const session = await c.env.DB.prepare(
    `SELECT * FROM sessions
     WHERE refresh_token_hash = ? AND revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP
     LIMIT 1`,
  )
    .bind(tokenHash)
    .first<SessionRow>();

  if (!session) {
    return c.json({ ok: false, error: 'Session expired or invalid' }, 401);
  }

  await c.env.DB.prepare('UPDATE sessions SET last_seen_at = CURRENT_TIMESTAMP WHERE id = ?')
    .bind(session.id)
    .run();

  const now = Math.floor(Date.now() / 1000);
  const accessToken = await signJwt(
    { sub: session.user_id, iat: now, exp: now + ACCESS_TOKEN_TTL_S },
    c.env.JWT_SECRET,
  );

  return c.json({ accessToken });
});

// POST /auth/logout  (requires auth)
authRouter.post('/logout', requireAuth, async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(
    'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE user_id = ? AND revoked_at IS NULL',
  )
    .bind(userId)
    .run();
  return c.json({ ok: true });
});

// GET /auth/me  (requires auth)
authRouter.get('/me', requireAuth, async (c) => {
  const userId = c.get('userId');
  const user = await c.env.DB.prepare('SELECT * FROM users WHERE id = ?')
    .bind(userId)
    .first<UserRow>();
  if (!user || user.status === 'deleted') {
    return c.json({ ok: false, error: 'User not found' }, 404);
  }
  const userObj = await buildUserObject(c.env.DB, userId, user.primary_email ?? '');
  return c.json({ user: userObj });
});

// DELETE /auth/account  (requires auth — soft delete)
authRouter.delete('/account', requireAuth, async (c) => {
  const userId = c.get('userId');

  await c.env.DB.batch([
    c.env.DB.prepare(
      "UPDATE users SET status = 'deleted', updated_at = CURRENT_TIMESTAMP WHERE id = ?",
    ).bind(userId),
    c.env.DB.prepare(
      'UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP WHERE user_id = ? AND revoked_at IS NULL',
    ).bind(userId),
  ]);

  return c.json({ ok: true });
});
