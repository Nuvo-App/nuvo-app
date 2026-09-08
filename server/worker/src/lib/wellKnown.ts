/**
 * Universal-link / App-Link association files + the web fallback page for a
 * shared invite URL (https://<host>/j/<token>).
 *
 * The link host is currently the Worker's own origin
 * (nuvo-api.getnuvoapp.workers.dev). A prettier host (get.nuvo.app) is a
 * DNS + wrangler-route change that does not touch any of this.
 */

const IOS_APP_ID = 'W62869AF7L.net.getnuvo.app'; // <TeamID>.<bundleId>
const IOS_BUNDLE_ID = 'net.getnuvo.app';
const APP_STORE_URL = 'https://apps.apple.com/app/nuvo/id0000000000'; // TODO: real App Store id
const ANDROID_PACKAGE = 'net.getnuvo.app';

/** GET /.well-known/apple-app-site-association */
export function appleAppSiteAssociation() {
  return {
    applinks: {
      apps: [],
      details: [
        {
          appID: IOS_APP_ID,
          paths: ['/j/*'],
          components: [{ '/': '/j/*', comment: 'Nuvo invite links' }],
        },
      ],
    },
    webcredentials: { apps: [IOS_APP_ID] },
  };
}

/**
 * GET /.well-known/assetlinks.json
 * The SHA-256 signing-cert fingerprint of the release keystore must be filled
 * in before Android App Links verify. Left empty on purpose — documented as the
 * one remaining Android step in docs/agents/19.
 */
export function androidAssetLinks() {
  return [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: {
        namespace: 'android_app',
        package_name: ANDROID_PACKAGE,
        sha256_cert_fingerprints: [] as string[],
      },
    },
  ];
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

interface FallbackPreview {
  headline: string;
  sub: string;
}

/** The web page shown when /j/<token> is opened without the app. */
export function inviteFallbackHtml(opts: {
  token: string;
  origin: string;
  preview: FallbackPreview | null;
  status: string;
}): string {
  const deepLink = `nuvo://j/${escapeHtml(opts.token)}`;
  const headline = opts.preview
    ? escapeHtml(opts.preview.headline)
    : opts.status === 'active'
      ? 'You’ve been invited to Nuvo'
      : 'This invite is no longer available';
  const sub = opts.preview
    ? escapeHtml(opts.preview.sub)
    : opts.status === 'active'
      ? 'Open the link on your phone to join.'
      : 'Ask whoever shared it for a new one.';
  const showButtons = opts.status === 'active';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-itunes-app" content="app-id=0000000000">
<title>Nuvo</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background:#0E1116; color:#F4F1EA; padding:24px; }
  .card { width:100%; max-width:380px; text-align:center; }
  .logo { font-weight:800; letter-spacing:.08em; font-size:14px; color:#8AA0FF; margin-bottom:28px; }
  h1 { font-size:24px; line-height:1.25; margin:0 0 10px; }
  p { margin:0 0 28px; opacity:.72; }
  a.btn { display:block; padding:15px 18px; border-radius:14px; font-weight:700; text-decoration:none; margin:10px 0; }
  a.primary { background:#3B6BFF; color:#fff; }
  a.secondary { background:rgba(255,255,255,.08); color:#F4F1EA; }
</style>
</head>
<body>
  <div class="card">
    <div class="logo">NUVO</div>
    <h1>${headline}</h1>
    <p>${sub}</p>
    ${
      showButtons
        ? `<a class="btn primary" href="${deepLink}">Open in Nuvo</a>
    <a class="btn secondary" href="${escapeHtml(APP_STORE_URL)}">Get Nuvo on the App Store</a>`
        : ''
    }
  </div>
  <script>
    // If the app is installed, the universal link handler intercepts before
    // this runs. Otherwise, try the custom scheme once on load.
    ${showButtons ? `setTimeout(function(){ window.location = ${JSON.stringify(deepLink)}; }, 350);` : ''}
  </script>
</body>
</html>`;
}

export { IOS_BUNDLE_ID, ANDROID_PACKAGE, APP_STORE_URL };
