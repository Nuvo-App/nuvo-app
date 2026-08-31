export interface GoogleTokenInfo {
  sub: string;
  email: string;
  email_verified: string;
  name?: string;
  picture?: string;
  aud: string;
  iss: string;
  exp: string;
}

export async function verifyGoogleIdToken(
  idToken: string,
  expectedClientId: string,
): Promise<GoogleTokenInfo> {
  const res = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
  );
  if (!res.ok) {
    throw new Error('Google token verification failed');
  }
  const info = (await res.json()) as GoogleTokenInfo;

  if (info.aud !== expectedClientId) {
    throw new Error('Token audience mismatch');
  }
  if (info.email_verified !== 'true') {
    throw new Error('Google email not verified');
  }
  const expiry = parseInt(info.exp, 10);
  if (isNaN(expiry) || expiry < Math.floor(Date.now() / 1000)) {
    throw new Error('Google token expired');
  }

  return info;
}
