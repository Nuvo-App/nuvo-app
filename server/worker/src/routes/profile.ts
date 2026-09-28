import { Hono } from 'hono';
import type { AppEnv, MediaObjectRow, ProfileRow } from '../types';
import { generateId } from '../lib/crypto';
import { requireAuth } from '../lib/jwt';
import { normalizeUsername, isValidUsername } from '../lib/validation';
import { hasAcceptedTerms } from '../lib/terms';
import {
  awsEncode,
  encodeKeyPath,
  extensionFor,
  signUploadToken,
  verifyUploadToken,
} from '../lib/uploadMedia';

export const profileRouter = new Hono<AppEnv>();

const PROFILE_IMAGE_KEY_PREFIXES = ['profile-photos/', 'profile-avatars/'];

profileRouter.put('/photo/upload', async (c) => {
  const token = c.req.query('token');
  if (!token) return c.json({ ok: false, error: 'Missing upload token' }, 401);

  const upload = await verifyUploadToken(
    token,
    c.env.JWT_SECRET,
    PROFILE_IMAGE_KEY_PREFIXES,
  );
  if (!upload) return c.json({ ok: false, error: 'Invalid upload token' }, 401);

  await c.env.PROFILE_PHOTOS.put(upload.key, c.req.raw.body, {
    httpMetadata: { contentType: upload.contentType },
  });

  // Track the object in media_objects and link it to the user's profile.
  // The userId is encoded in the path: profile-avatars/{userId}/{timestamp}.{ext}
  const userIdMatch = upload.key.match(/^profile-(?:avatars|photos)\/([^/]+)/);
  const userId = userIdMatch?.[1];
  const baseUrl = new URL(c.req.url).origin;
  const publicUrl = `${baseUrl}/profile/photo/object/${encodeKeyPath(upload.key)}`;

  if (userId) {
    const existing = await c.env.DB.prepare('SELECT id FROM media_objects WHERE object_key = ?')
      .bind(upload.key)
      .first<MediaObjectRow>();
    if (existing) {
      await c.env.DB.prepare(
        "UPDATE media_objects SET public_url = ?, status = 'active', deleted_at = NULL WHERE id = ?"
      ).bind(publicUrl, existing.id).run();
    } else {
      await c.env.DB.prepare(
        `INSERT INTO media_objects (id, owner_user_id, bucket, object_key, public_url, media_type, purpose, status, created_at)
         VALUES (?, ?, 'nuvor2', ?, ?, 'image', 'profile_avatar', 'active', CURRENT_TIMESTAMP)`
      ).bind(generateId(), userId, upload.key, publicUrl).run();
    }
    await c.env.DB.prepare(
      'UPDATE profiles SET avatar_object_key = ?, avatar_url = ? WHERE user_id = ?'
    ).bind(upload.key, publicUrl, userId).run();
  }

  return c.json({ ok: true, key: upload.key, publicUrl });
});

profileRouter.get('/photo/object/*', async (c) => {
  const key = c.req.path.replace('/profile/photo/object/', '');
  if (!key.startsWith('profile-photos/') && !key.startsWith('profile-avatars/')) {
    return c.json({ ok: false, error: 'Not found' }, 404);
  }

  const object = await c.env.PROFILE_PHOTOS.get(key);
  if (!object) return c.json({ ok: false, error: 'Not found' }, 404);

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return new Response(object.body, { headers });
});

// All routes below require a valid access token.
profileRouter.use('*', requireAuth);

// GET /profile/me
profileRouter.get('/me', async (c) => {
  const userId = c.get('userId');
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();

  if (!profile) {
    return c.json({ ok: false, error: 'Profile not found' }, 404);
  }

  return c.json({
    fullName: profile.full_name,
    username: profile.username,
    profilePhotoUrl: profile.avatar_url,
    avatarUrl: profile.avatar_url,
    privateProfile: Boolean(profile.private_profile),
    onboardingComplete: Boolean(profile.onboarding_complete),
  });
});

// POST /profile/photo/upload-url
async function deleteR2Object(r2: R2Bucket, objectKey: string) {
  try { await r2.delete(objectKey); } catch { /* ignore R2 errors */ }
}

/** The R2 key of an avatar object owned by `userId`, or null. Requires a
 *  media_objects row owned by the user AND the user's own key prefix. */
async function ownedAvatarKey(
  db: D1Database,
  userId: string,
  match: { publicUrl: string } | { objectKey: string },
): Promise<string | null> {
  const [column, value] = 'publicUrl' in match
    ? ['public_url', match.publicUrl]
    : ['object_key', match.objectKey];
  const row = await db
    .prepare(`SELECT object_key FROM media_objects WHERE ${column} = ? AND owner_user_id = ? LIMIT 1`)
    .bind(value, userId)
    .first<{ object_key: string }>();
  const key = row?.object_key ?? null;
  const ownPrefix = PROFILE_IMAGE_KEY_PREFIXES.some((p) => key?.startsWith(`${p}${userId}/`));
  return key && ownPrefix ? key : null;
}

profileRouter.post('/photo/upload-url', async (c) => {
  console.log('PROFILE_UPLOAD_URL_ROUTE_HIT');
  const userId = c.get('userId');

  if (!(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before uploading a profile photo' }, 403);
  }

  let body: { fileName?: unknown; contentType?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const fileName = typeof body.fileName === 'string' && body.fileName.trim()
    ? body.fileName.trim()
    : 'profile-photo.jpg';
  const contentType = typeof body.contentType === 'string' && body.contentType.trim()
    ? body.contentType.trim().toLowerCase()
    : 'image/jpeg';

  if (!['image/jpeg', 'image/png', 'image/webp'].includes(contentType)) {
    return c.json({ ok: false, error: 'Unsupported image type' }, 400);
  }

  const extension = extensionFor(fileName, contentType);
  const key = `profile-avatars/${userId}/${Date.now()}.${extension}`;
  const baseUrl = new URL(c.req.url).origin;
  const publicUrl = `${baseUrl}/profile/photo/object/${encodeKeyPath(key)}`;
  const token = await signUploadToken({
    key,
    contentType,
    jwtSecret: c.env.JWT_SECRET,
  });
  const uploadUrl = `${baseUrl}/profile/photo/upload?token=${awsEncode(token)}`;

  // Upsert a media_objects row so the upload is tracked in D1 even before it happens.
  const existing = await c.env.DB.prepare('SELECT id FROM media_objects WHERE object_key = ?')
    .bind(key)
    .first<MediaObjectRow>();
  if (existing) {
    await c.env.DB.prepare(
      "UPDATE media_objects SET public_url = ?, status = 'active', deleted_at = NULL WHERE id = ?"
    ).bind(publicUrl, existing.id).run();
  } else {
    await c.env.DB.prepare(
      `INSERT INTO media_objects (id, owner_user_id, bucket, object_key, public_url, media_type, purpose, status, created_at)
       VALUES (?, ?, 'nuvor2', ?, ?, 'image', 'profile_avatar', 'active', CURRENT_TIMESTAMP)`
    ).bind(generateId(), userId, key, publicUrl).run();
  }

  console.log(`PROFILE_UPLOAD_URL_PUBLIC_URL: ${publicUrl}`);
  return c.json({ uploadUrl, publicUrl, key });
});

// POST /profile
profileRouter.post('/', async (c) => {
  const userId = c.get('userId');

  let body: {
    fullName?: unknown;
    username?: unknown;
    privateProfile?: unknown;
    profilePhotoUrl?: unknown;
    avatarUrl?: unknown;
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const isPersonalUpdate =
    typeof body.fullName === 'string' ||
    typeof body.username === 'string' ||
    typeof body.privateProfile === 'boolean' ||
    body.profilePhotoUrl !== undefined ||
    body.avatarUrl !== undefined;

  if (isPersonalUpdate && !(await hasAcceptedTerms(c.env.DB, userId))) {
    return c.json({ ok: false, error: 'You must accept the Terms of Service before creating a profile' }, 403);
  }

  // Build update fields dynamically to avoid clobbering untouched columns
  const fields: string[] = ['updated_at = CURRENT_TIMESTAMP'];
  const bindings: unknown[] = [];

  if (typeof body.fullName === 'string') {
    const name = body.fullName.trim();
    if (name.length > 100) {
      return c.json({ ok: false, error: 'Full name too long (max 100 chars)' }, 400);
    }
    fields.push('full_name = ?');
    bindings.push(name);
  }

  if (typeof body.username === 'string') {
    const username = normalizeUsername(body.username);
    if (!isValidUsername(username)) {
      return c.json(
        { ok: false, error: 'Username must be 3-20 characters using only letters, numbers, or underscore' },
        400,
      );
    }
    const taken = await c.env.DB.prepare(
      'SELECT user_id FROM profiles WHERE username = ? AND user_id != ?',
    )
      .bind(username, userId)
      .first<{ user_id: string }>();
    if (taken) {
      return c.json({ ok: false, error: 'Username already taken' }, 409);
    }
    fields.push('username = ?');
    bindings.push(username);
  }

  if (typeof body.privateProfile === 'boolean') {
    fields.push('private_profile = ?');
    bindings.push(body.privateProfile ? 1 : 0);
  }

  if (
    body.profilePhotoUrl === null ||
    body.avatarUrl === null ||
    typeof body.profilePhotoUrl === 'string' ||
    typeof body.avatarUrl === 'string'
  ) {
    const photoUrl = (body.profilePhotoUrl ?? body.avatarUrl) as string | null;

    // Ownership is only ever established by a media_objects row this user
    // owns (created by their own signed upload). A URL alone — including
    // another member's public avatar URL — never becomes an owned R2 key.
    const newKey = photoUrl ? await ownedAvatarKey(c.env.DB, userId, { publicUrl: photoUrl }) : null;

    // Delete the previous R2 object when the avatar changes — but only an
    // object this user owns. A stale/foreign key is unlinked, never deleted.
    const oldProfile = await c.env.DB.prepare('SELECT avatar_object_key FROM profiles WHERE user_id = ?')
      .bind(userId)
      .first<{ avatar_object_key: string | null }>();
    const oldKey = oldProfile?.avatar_object_key;
    if (oldKey && oldKey !== newKey && (await ownedAvatarKey(c.env.DB, userId, { objectKey: oldKey }))) {
      await deleteR2Object(c.env.PROFILE_PHOTOS, oldKey);
      await c.env.DB.prepare('UPDATE media_objects SET status = \'deleted\', deleted_at = CURRENT_TIMESTAMP WHERE object_key = ? AND owner_user_id = ?')
        .bind(oldKey, userId).run();
    }

    fields.push('avatar_url = ?');
    bindings.push(photoUrl);
    fields.push('avatar_object_key = ?');
    bindings.push(newKey);
  }

  if (fields.length === 1) {
    // Only the timestamp update — nothing else to change
    return c.json({ ok: false, error: 'No updatable fields provided' }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE profiles SET ${fields.join(', ')} WHERE user_id = ?`,
  )
    .bind(...bindings, userId)
    .run();

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();

  return c.json({
    fullName: profile?.full_name ?? null,
    username: profile?.username ?? null,
    profilePhotoUrl: profile?.avatar_url ?? null,
    avatarUrl: profile?.avatar_url ?? null,
    privateProfile: Boolean(profile?.private_profile),
    onboardingComplete: Boolean(profile?.onboarding_complete),
  });
});

// POST /profile/username/check
profileRouter.post('/username/check', async (c) => {
  let body: { username?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ ok: false, error: 'Invalid request body' }, 400);
  }

  const rawUsername = typeof body.username === 'string' ? body.username : '';
  if (!rawUsername) {
    return c.json({ ok: false, error: 'username required' }, 400);
  }

  const username = normalizeUsername(rawUsername);
  if (!isValidUsername(username)) {
    return c.json({ available: false, reason: 'invalid_format' });
  }

  const existing = await c.env.DB.prepare(
    'SELECT user_id FROM profiles WHERE username = ?',
  )
    .bind(username)
    .first<{ user_id: string }>();

  return c.json({ available: !existing });
});
