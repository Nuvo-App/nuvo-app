import { Hono } from 'hono';
import { cors } from 'hono/cors';
import type { AppEnv, ProfileRow } from './types';
import { purgeExpiredMotionData } from './lib/motion_privacy';
import { appleServiceConfig, retryPendingAppleRevocations } from './lib/apple';
import { purgeExpiredAuthData } from './lib/dataRetention';
import { sweepRaceLifecycle } from './domain/raceFinalize';
import { notifyLifecycleTransitions, runNotificationJob } from './domain/notificationPolicy';
import { claimDueJobs } from './domain/notificationJobs';
import { authRouter } from './routes/auth';
import { profileRouter } from './routes/profile';
import { passRouter } from './routes/pass';
import { racesRouter } from './routes/races';
import { RACE_ACTIVITY_CATALOG } from './domain/raceActivities';
import { readMotionCatalog, readMotionRelease } from './domain/motionRegistry';
import { declaredPackageAssets, packageAssetContentType, packageAssetKey } from './domain/motionAssets';
import { arenaRouter } from './routes/arena';
import { motionRouter, motionSessionsRouter } from './routes/motion';
import { verificationSessionsRouter } from './routes/verificationSessions';
import { internalRouter } from './routes/internal';
import { usersRouter } from './routes/users';
import { progressionRouter } from './routes/progression';
import { crewRouter } from './routes/crew';
import { reportsRouter } from './routes/reports';
import { invitesRouter } from './routes/invites';
import { notificationsRouter } from './routes/notifications';
import { reactionsRouter } from './routes/reactions';
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

/// Bounded string-list extraction from registry `metadata_json` — returns
/// null when the value isn't a clean list so callers keep their fallback.
function metadataStringList(value: unknown, max: number): string[] | null {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) return null;
  const entries = value.filter(
    (entry): entry is string =>
      typeof entry === 'string' && entry.trim().length > 0 && entry.length <= 140,
  );
  return entries.length === value.length ? entries.map((e) => e.trim()) : null;
}

// ── Public race-activity catalog ──────────────────────────────────────────────
// Unauthenticated on purpose: it's static, non-sensitive reference data, and
// exposing it makes "is the deployed Worker's activity allowlist current?"
// verifiable without creating a race. The `supported` list is the exact set a
// preset race can be created with — if a client offers a preset that is not
// here, `POST /races` will reject it with "Choose a supported activity".
// Registered before `app.route('/races', ...)` so it bypasses that router's
// auth middleware.
app.get('/races/activities', async (c) => {
  try {
    const catalog = await readMotionCatalog(c.env.DB);
    const activities = catalog.activities.map((entry) => ({
      ...(entry.legacy ?? {
        id: entry.id,
        displayName: entry.displayName,
        aliases: [],
        supportedMetrics: [entry.metric],
        defaultMetric: entry.metric,
        validatorKey: 'registry_release',
        verificationMethod: 'camera_pose',
        cameraOrientation: 'front',
        sessionBehavior: entry.measurementType === 'duration' ? 'validated_timer' : 'count_reps',
        suggestedTargets: entry.suggestedTargets,
        supportedFormats: entry.supportedFormats,
        availability: entry.availability,
        instructions: [],
      }),
      // Registry columns are authoritative. The legacy object only supplies
      // compatibility fields such as aliases and camera orientation.
      id: entry.id,
      displayName: entry.displayName,
      supportedMetrics: [entry.metric],
      defaultMetric: entry.metric,
      suggestedTargets: entry.suggestedTargets,
      supportedFormats: entry.supportedFormats,
      availability: entry.availability,
      featured: entry.featured,
      sortPriority: entry.sortPriority,
      // A pointed-but-non-stable release (draft/validated/disabled/etc.) is
      // advertised as nothing: session creation refuses it, so presenting it
      // here would make the catalog claim support the verifier can't honor.
      // The channel pointer itself is unchanged — operators still see the
      // full pointer+status on the internal catalog route.
      currentReleaseId: entry.releaseStatus === 'stable' ? entry.releaseId : null,
      currentReleaseChecksum: entry.releaseStatus === 'stable' ? entry.releaseChecksum : null,
      engineType: entry.releaseStatus === 'stable' ? entry.engineType : null,
      requiredCapabilities: entry.releaseStatus === 'stable' ? entry.requiredCapabilities : [],
      minimumAppBuild: entry.releaseStatus === 'stable' ? entry.minimumAppBuild : null,
      // Decorative pre-verify preview animation only — never consumed by the
      // camera verifier. Absent/invalid on the client falls back to the
      // bundled compiled sequence, so this is safe to leave unset.
      previewSequence: entry.metadata?.previewSequence ?? null,
      // Registry-published display metadata. Lets a motion this build never
      // compiled for present real instructions and camera framing instead of
      // generic fallbacks. Bounded on the client; absent → generic guidance.
      instructions: metadataStringList(entry.metadata?.instructions, 6) ??
        entry.legacy?.instructions ?? [],
      cameraOrientation: typeof entry.metadata?.cameraOrientation === 'string'
        ? entry.metadata.cameraOrientation
        : entry.legacy?.cameraOrientation ?? 'front',
      aliases: metadataStringList(entry.metadata?.aliases, 8) ??
        entry.legacy?.aliases ?? [],
    }));
    const etag = `\"${catalog.catalogVersion}:${activities.length}\"`;
    c.header('ETag', etag);
    if (c.req.header('If-None-Match') === etag) return c.body(null, 304);
    return c.json({
      ok: true,
      catalogVersion: catalog.catalogVersion,
      etag,
      count: activities.length,
      supported: activities.filter((a) => a.availability === 'supported').map((a) => a.id),
      activities,
    });
  } catch (error) {
    // Deploy the Worker before applying D1 0015 without breaking old clients.
    console.error('[motion-registry] registry read unavailable; using legacy catalog:', error);
    return c.json({
      ok: true,
      etag: 'legacy-catalog',
      count: RACE_ACTIVITY_CATALOG.length,
      supported: RACE_ACTIVITY_CATALOG.filter((a) => a.availability === 'supported').map((a) => a.id),
      activities: RACE_ACTIVITY_CATALOG,
      registryFallback: true,
    });
  }
});

// Immutable release download endpoint. The catalog intentionally contains
// only stable metadata and release identity; the spec is fetched and cached
// separately so a changed database pointer downloads exactly one new release.
app.get('/motion/releases/:releaseId', async (c) => {
  const releaseId = c.req.param('releaseId');
  const release = await readMotionRelease(c.env.DB, releaseId);
  if (!release) return c.json({ ok: false, error: 'Verifier release not found.' }, 404);
  const etag = `"${release.id}:${release.checksum}"`;
  c.header('ETag', etag);
  c.header('Cache-Control', 'public, max-age=300');
  if (c.req.header('If-None-Match') === etag) return c.body(null, 304);
  return c.json({
    ok: true,
    release: {
      id: release.id,
      activityId: release.activityId,
      engineType: release.engineType,
      specSchemaVersion: release.specSchemaVersion,
      spec: release.spec,
      checksum: release.checksum,
      requiredCapabilities: release.requiredCapabilities,
      minimumAppBuild: release.minimumAppBuild,
    },
  });
});

// Package asset download — public like the release itself (bytes are
// checksum-verified by the client against the immutable manifest, so there
// is nothing to hide), but scoped hard: the URL's assetId only ever selects
// among assets the release's spec actually declares. No path traversal, no
// arbitrary R2 keys — `packageAssetKey` is the single key shape.
app.get('/motion/releases/:releaseId/assets/:assetId', async (c) => {
  const releaseId = c.req.param('releaseId');
  const assetId = c.req.param('assetId');
  const release = await readMotionRelease(c.env.DB, releaseId);
  if (!release) return c.json({ ok: false, error: 'Verifier release not found.' }, 404);
  const declared = declaredPackageAssets(release).find((a) => a.id === assetId);
  if (!declared) {
    return c.json({ ok: false, error: 'Asset not declared by this release.' }, 404);
  }
  const object = await c.env.PROFILE_PHOTOS.get(packageAssetKey(releaseId, assetId));
  if (!object) return c.json({ ok: false, error: 'Package asset is unavailable.' }, 503);
  // The stored object must still be the bytes the manifest promises — a
  // bucket object that drifted from its declared checksum is never served.
  const storedSha = object.customMetadata?.sha256;
  if (storedSha !== declared.sha256) {
    return c.json({ ok: false, error: 'Package asset failed integrity.' }, 503);
  }
  const etag = `"${declared.sha256}"`;
  c.header('ETag', etag);
  c.header('X-Asset-SHA256', declared.sha256);
  c.header('Cache-Control', 'public, max-age=31536000, immutable');
  if (c.req.header('If-None-Match') === etag) return c.body(null, 304);
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('Content-Type', packageAssetContentType(declared.type));
  headers.set('ETag', etag);
  headers.set('X-Asset-SHA256', declared.sha256);
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  return new Response(object.body, { headers });
});

// ── Auth routes ───────────────────────────────────────────────────────────────
app.route('/auth', authRouter);

// ── Profile routes ────────────────────────────────────────────────────────────
app.route('/profile', profileRouter);

// ── Pass routes ───────────────────────────────────────────────────────────────
app.route('/pass', passRouter);

// ── Progression (Nuvo Levels) ─────────────────────────────────────────────────
app.route('/progression', progressionRouter);

// ── Social routes ─────────────────────────────────────────────────────────────
app.route('/users', usersRouter);
app.route('/crew', crewRouter);
app.route('/invites', invitesRouter);
app.route('/notifications', notificationsRouter);
app.route('/reactions', reactionsRouter);
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
app.route('/', verificationSessionsRouter);
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

// Keep the Hono request surface intact for local tests while exposing the
// Cloudflare scheduled handler used for the 90-day motion-data purge and the
// race lifecycle sweep (start lines crossed + deadline finalization). Race
// correctness never depends on this cadence — the same transitions run
// lazily on reads — but notifications for races nobody is looking at do.
const worker = Object.assign(app, {
  scheduled: async (
    controller: ScheduledController,
    env: AppEnv['Bindings'],
    ctx: ExecutionContext,
  ) => {
    ctx.waitUntil(
      (async () => {
        // The 90-day purge runs on the daily trigger only — the minute
        // trigger exists for lifecycle edges + notification reminders.
        if (controller.cron === '0 3 * * *') {
          try {
            await purgeExpiredMotionData(env.DB, env.PROFILE_PHOTOS);
          } catch (err) {
            console.error('[cron] motion purge failed:', (err as Error).message);
          }
          try {
            await purgeExpiredAuthData(env.DB);
          } catch (err) {
            console.error('[cron] auth-data purge failed:', (err as Error).message);
          }
        }
        try {
          const transitions = await sweepRaceLifecycle(env.DB);
          await notifyLifecycleTransitions(env, (p) => ctx.waitUntil(p), transitions);
        } catch (err) {
          console.error('[cron] race lifecycle sweep failed:', (err as Error).message);
        }
        try {
          const jobs = await claimDueJobs(env.DB);
          for (const job of jobs) {
            await runNotificationJob(env, (p) => ctx.waitUntil(p), job);
          }
        } catch (err) {
          console.error('[cron] notification jobs failed:', (err as Error).message);
        }
        // Apple revocation retries: a grant that couldn't be revoked during
        // account deletion keeps an anonymized credential row; finish it here
        // so the Apple authorization doesn't outlive the Nuvo account.
        const appleConfig = appleServiceConfig(env);
        if (appleConfig) {
          try {
            await retryPendingAppleRevocations(env.DB, appleConfig);
          } catch (err) {
            console.error('[cron] apple revocation retry failed:', (err as Error).message);
          }
        }
      })(),
    );
  },
});

export default worker;
