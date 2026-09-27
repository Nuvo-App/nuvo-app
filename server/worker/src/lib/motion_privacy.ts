const ENVELOPE_VERSION = 'nuvo-motion-v1';
const IV_BYTES = 12;
const DATA_KEY_BYTES = 32;

function encodeBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function importAesKey(raw: Uint8Array, usages: Array<'encrypt' | 'decrypt'>): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, usages);
}

async function masterKey(masterSecret: string): Promise<CryptoKey> {
  if (!masterSecret.trim()) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(masterSecret));
  return importAesKey(new Uint8Array(digest), ['encrypt', 'decrypt']);
}

export async function motionAccountRef(masterSecret: string, userId: string): Promise<string> {
  if (!masterSecret.trim()) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(masterSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return encodeBase64(new Uint8Array(
    await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(userId)),
  ));
}

async function encryptWithKey(key: CryptoKey, plaintext: Uint8Array): Promise<Uint8Array> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, plaintext);
  return new TextEncoder().encode(JSON.stringify({
    version: ENVELOPE_VERSION,
    iv: encodeBase64(iv),
    ciphertext: encodeBase64(new Uint8Array(ciphertext)),
  }));
}

async function decryptWithKey(key: CryptoKey, envelopeBytes: Uint8Array): Promise<Uint8Array> {
  const envelope = JSON.parse(new TextDecoder().decode(envelopeBytes)) as {
    version?: unknown;
    iv?: unknown;
    ciphertext?: unknown;
  };
  if (
    envelope.version !== ENVELOPE_VERSION ||
    typeof envelope.iv !== 'string' ||
    typeof envelope.ciphertext !== 'string'
  ) throw new Error('Unsupported motion encryption envelope.');
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: decodeBase64(envelope.iv) },
    key,
    decodeBase64(envelope.ciphertext),
  );
  return new Uint8Array(plaintext);
}

export function isMotionEncryptionEnvelope(bytes: Uint8Array): boolean {
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes)) as { version?: unknown };
    return value.version === ENVELOPE_VERSION;
  } catch {
    return false;
  }
}

export async function getOrCreateMotionDataKey(
  db: D1Database,
  masterSecret: string | undefined,
  userId: string,
): Promise<Uint8Array> {
  if (!masterSecret) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  const existing = await getMotionDataKey(db, masterSecret, userId);
  if (existing) return existing;

  const accountRef = await motionAccountRef(masterSecret, userId);
  const rawKey = crypto.getRandomValues(new Uint8Array(DATA_KEY_BYTES));
  const wrapped = await encryptWithKey(await masterKey(masterSecret), rawKey);
  await db.prepare(
    `INSERT INTO motion_account_keys (account_ref, wrapped_key, created_at, revoked_at)
     VALUES (?, ?, CURRENT_TIMESTAMP, NULL)
     ON CONFLICT(account_ref) DO NOTHING`,
  ).bind(accountRef, new TextDecoder().decode(wrapped)).run();
  return (await getMotionDataKey(db, masterSecret, userId)) ?? rawKey;
}

export async function getMotionDataKey(
  db: D1Database,
  masterSecret: string | undefined,
  userId: string,
): Promise<Uint8Array | null> {
  if (!masterSecret) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  return getMotionDataKeyByRef(db, masterSecret, await motionAccountRef(masterSecret, userId));
}

export async function getMotionDataKeyByRef(
  db: D1Database,
  masterSecret: string | undefined,
  accountRef: string,
): Promise<Uint8Array | null> {
  if (!masterSecret) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  const existing = await db.prepare(
    'SELECT wrapped_key FROM motion_account_keys WHERE account_ref = ? AND revoked_at IS NULL LIMIT 1',
  ).bind(accountRef).first<{ wrapped_key: string }>();
  if (!existing?.wrapped_key) return null;
  return decryptWithKey(
    await masterKey(masterSecret),
    new TextEncoder().encode(existing.wrapped_key),
  );
}

export async function encryptMotionBytes(key: Uint8Array, bytes: Uint8Array): Promise<Uint8Array> {
  return encryptWithKey(await importAesKey(key, ['encrypt']), bytes);
}

export async function decryptMotionBytes(key: Uint8Array, envelope: Uint8Array): Promise<Uint8Array> {
  return decryptWithKey(await importAesKey(key, ['decrypt']), envelope);
}

export async function encryptMotionText(key: Uint8Array, value: string): Promise<string> {
  const encrypted = await encryptMotionBytes(key, new TextEncoder().encode(value));
  return new TextDecoder().decode(encrypted);
}

export async function decryptMotionText(key: Uint8Array, value: string): Promise<string> {
  const decrypted = await decryptMotionBytes(key, new TextEncoder().encode(value));
  return new TextDecoder().decode(decrypted);
}

export async function revokeMotionDataKey(
  db: D1Database,
  masterSecret: string | undefined,
  userId: string,
): Promise<void> {
  if (!masterSecret) throw new Error('MOTION_DATA_MASTER_KEY is not configured.');
  const accountRef = await motionAccountRef(masterSecret, userId);
  await db.prepare('DELETE FROM motion_account_keys WHERE account_ref = ?').bind(accountRef).run();
}

export async function purgeExpiredMotionData(
  db: D1Database,
  r2: R2Bucket,
): Promise<{ sessions: number; trainingExamples: number }> {
  const sessions = await db.prepare(
    `SELECT session_id, object_key FROM motion_sessions
     WHERE created_at < datetime('now', '-90 days')`,
  ).all<{ session_id: string; object_key: string }>();
  const trainingExamples = await db.prepare(
    `SELECT id, object_key FROM motion_training_examples
     WHERE created_at < datetime('now', '-90 days')`,
  ).all<{ id: string; object_key: string | null }>();

  for (const row of [...sessions.results, ...trainingExamples.results]) {
    if (row.object_key) {
      try { await r2.delete(row.object_key); } catch { /* retried next run */ }
    }
  }
  for (const row of sessions.results) {
    await db.prepare('DELETE FROM motion_feedback_labels WHERE motion_session_id = ?').bind(row.session_id).run();
    await db.prepare('DELETE FROM motion_sessions WHERE session_id = ?').bind(row.session_id).run();
  }
  for (const row of trainingExamples.results) {
    await db.prepare('DELETE FROM motion_training_examples WHERE id = ?').bind(row.id).run();
  }
  return { sessions: sessions.results.length, trainingExamples: trainingExamples.results.length };
}

export async function deleteUserMotionData(
  db: D1Database,
  r2: R2Bucket,
  masterSecret: string | undefined,
  userId: string,
): Promise<void> {
  // Account deletion must never depend on the motion pipeline being enabled.
  // The account ref (needed to locate ref-keyed rows + revoke the wrapped data
  // key) is only derivable when the master secret is configured — but the
  // plaintext object_key in each row is enough to delete the R2 artifacts, so
  // cleanup still runs against every row keyed by the raw user id either way.
  const accountRef = masterSecret?.trim()
    ? await motionAccountRef(masterSecret, userId)
    : null;
  const sessions = await db.prepare(
    'SELECT session_id, object_key FROM motion_sessions WHERE user_id IN (?, ?)',
  ).bind(userId, accountRef ?? userId).all<{ session_id: string; object_key: string }>();
  const trainingExamples = await db.prepare(
    'SELECT id, object_key FROM motion_training_examples WHERE user_id IN (?, ?)',
  ).bind(userId, accountRef ?? userId).all<{ id: string; object_key: string | null }>();

  for (const row of [...sessions.results, ...trainingExamples.results]) {
    if (row.object_key) {
      try { await r2.delete(row.object_key); } catch { /* account deletion is idempotent */ }
    }
  }
  await db.prepare('DELETE FROM motion_feedback_labels WHERE user_id IN (?, ?)').bind(userId, accountRef ?? userId).run();
  await db.prepare('DELETE FROM motion_sessions WHERE user_id IN (?, ?)').bind(userId, accountRef ?? userId).run();
  await db.prepare('DELETE FROM motion_training_examples WHERE user_id IN (?, ?)').bind(userId, accountRef ?? userId).run();
  await db.prepare('DELETE FROM motion_analysis_jobs WHERE user_id = ?').bind(userId).run();
  if (accountRef) {
    await db.prepare('DELETE FROM motion_account_keys WHERE account_ref = ?').bind(accountRef).run();
  }
}
