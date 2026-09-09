import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { AppEnv, ProfileRow } from './types';
import { authRouter } from './routes/auth';
import { profileRouter } from './routes/profile';
import { passRouter } from './routes/pass';
import { racesRouter } from './routes/races';
import { RACE_ACTIVITY_CATALOG } from './domain/raceActivities';
import { arenaRouter } from './routes/arena';
import { motionRouter, motionSessionsRouter } from './routes/motion';
import { internalRouter } from './routes/internal';
import { usersRouter } from './routes/users';
import { crewRouter } from './routes/crew';
import { reportsRouter } from './routes/reports';
import { invitesRouter } from './routes/invites';
import { notificationsRouter } from './routes/notifications';
import { devicesRouter } from './routes/devices';
import { requireAuth } from './lib/jwt';
import { ALLOWED_WEB_ORIGINS } from './lib/response';
import {
  androidAssetLinks,
  appleAppSiteAssociation,
  inviteFallbackHtml,
} from './lib/wellKnown';
import { inviteAvailability, looksLikeInviteToken } from './lib/invites';

const app = new Hono<AppEnv>();

// ── CORS ─────────────────────────────────────────────────────────────────────
// Native apps (Flutter) do not send an Origin header, so they bypass CORS
// entirely. This only applies to browser callers (web dashboard, local dev).
app.use(
  '*',
  cors({
    origin: (origin) => {
      if (!origin) return '*'; // native app — no origin header
      if (origin.startsWith('http://localhost') || origin.startsWith('http://127.0.0.1')) {
        return origin; // local dev
      }
      // GitHub Codespaces forwarded-port preview URLs:
      // https://{name}-8080.preview.app.github.dev
      // https://{name}-8080.app.github.dev
      // https://{name}-8080.githubpreview.dev
      if (origin.endsWith('.app.github.dev') || origin.endsWith('.githubpreview.dev')) {
        return origin;
      }
      return (ALLOWED_WEB_ORIGINS as readonly string[]).includes(origin)
        ? origin
        : ALLOWED_WEB_ORIGINS[0];
    },
    allowMethods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization'],
    maxAge: 86400,
    credentials: false,
  }),
);

// ── Health ────────────────────────────────────────────────────────────────────
app.get('/health', (c) => c.json({ ok: true, service: 'nuvo-api', ts: Date.now() }));

// ── Universal-link / App-Link association + invite web fallback ────────────────
// Public, unauthenticated, cacheable. The invite link host is this Worker's
// origin; a prettier domain is a DNS-only swap (see docs/agents/19).
app.get('/.well-known/apple-app-site-association', (c) => {
  c.header('Cache-Control', 'public, max-age=3600');
  return c.json(appleAppSiteAssociation());
});
app.get('/apple-app-site-association', (c) => {
  c.header('Cache-Control', 'public, max-age=3600');
  return c.json(appleAppSiteAssociation());
});
app.get('/.well-known/assetlinks.json', (c) => {
  c.header('Cache-Control', 'public, max-age=3600');
  return c.json(androidAssetLinks());
});

// The shared invite URL. A device with the app installed never reaches this
// (the OS routes the universal link straight into Nuvo); everyone else gets a
// branded page with a preview and store links.
app.get('/j/:token', async (c) => {
  const token = c.req.param('token');
  const origin = new URL(c.req.url).origin;
  let status = 'not_found';
  let preview: { headline: string; sub: string } | null = null;

  if (looksLikeInviteToken(token)) {
    const row = await c.env.DB.prepare(
      'SELECT kind, target_id, expires_at, revoked_at, max_uses, use_count FROM invites WHERE token = ?',
    )
      .bind(token)
      .first<{
        kind: string;
        target_id: string;
        expires_at: string | null;
        revoked_at: string | null;
        max_uses: number | null;
        use_count: number;
      }>();
    status = inviteAvailability(row);
    if (status === 'active' && row) {
      if (row.kind === 'race_join') {
        const race = await c.env.DB.prepare(
          "SELECT title FROM races WHERE id = ? AND deleted_at IS NULL",
        )
          .bind(row.target_id)
          .first<{ title: string }>();
        if (race) preview = { headline: `Join “${race.title}” on Nuvo`, sub: 'Open the link on your phone to join the race.' };
      } else if (row.kind === 'crew_connect') {
        const p = await c.env.DB.prepare(
          'SELECT full_name, username FROM profiles WHERE user_id = ?',
        )
          .bind(row.target_id)
          .first<{ full_name: string | null; username: string | null }>();
        const name = p?.full_name || (p?.username ? `@${p.username}` : 'a Nuvo member');
        preview = { headline: `Connect with ${name} on Nuvo`, sub: 'Open the link on your phone to add them to your crew.' };
      }
    }
  }

  c.header('Cache-Control', 'no-store');
  return c.html(inviteFallbackHtml({ token, origin, preview, status }));
});

// ── Public race-activity catalog ──────────────────────────────────────────────
// Unauthenticated on purpose: it's static, non-sensitive reference data, and
// exposing it makes "is the deployed Worker's activity allowlist current?"
// verifiable without creating a race. The `supported` list is the exact set a
// preset race can be created with — if a client offers a preset that is not
// here, `POST /races` will reject it with "Choose a supported activity".
// Registered before `app.route('/races', ...)` so it bypasses that router's
// auth middleware.
app.get('/races/activities', (c) =>
  c.json({
    ok: true,
    count: RACE_ACTIVITY_CATALOG.length,
    supported: RACE_ACTIVITY_CATALOG.filter((a) => a.availability === 'supported').map(
      (a) => a.id,
    ),
    activities: RACE_ACTIVITY_CATALOG,
  }),
);

// ── Auth routes ───────────────────────────────────────────────────────────────
app.route('/auth', authRouter);

// ── Profile routes ────────────────────────────────────────────────────────────
app.route('/profile', profileRouter);

// ── Pass routes ───────────────────────────────────────────────────────────────
app.route('/pass', passRouter);

// ── Social routes ─────────────────────────────────────────────────────────────
app.route('/users', usersRouter);
app.route('/crew', crewRouter);
app.route('/invites', invitesRouter);
app.route('/notifications', notificationsRouter);
app.route('/devices', devicesRouter);

// ── Reporting and safety routes ───────────────────────────────────────────────
app.route('/reports', reportsRouter);

// ── Race routes ───────────────────────────────────────────────────────────────
app.route('/races', racesRouter);

// ── Arena snapshot route ──────────────────────────────────────────────────────
app.route('/arena', arenaRouter);

// ── Motion analysis and training-data routes ────────────────────────────────
app.route('/motion', motionRouter);

// ── Motion Session telemetry ingest (authed) + internal lookup (X-Internal-Key)
app.route('/motion-sessions', motionSessionsRouter);
app.route('/internal', internalRouter);

// ── Onboarding complete ───────────────────────────────────────────────────────
app.post('/onboarding/complete', requireAuth, async (c) => {
  const userId = c.get('userId');
  await c.env.DB.prepare(
    'UPDATE profiles SET onboarding_complete = 1, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?',
  )
    .bind(userId)
    .run();

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE user_id = ?')
    .bind(userId)
    .first<ProfileRow>();

  return c.json({
    ok: true,
    onboardingComplete: Boolean(profile?.onboarding_complete),
  });
});

// ── Error handlers ────────────────────────────────────────────────────────────
app.onError((err, c) => {
  // Never expose internal error details in production
  console.error('[worker] unhandled error:', err.message);
  return c.json({ ok: false, error: 'Internal server error' }, 500);
});

app.notFound((c) => c.json({ ok: false, error: 'Not found' }, 404));

export default app;
