#!/usr/bin/env python3
"""
Serves build/web/ as static files and proxies /api/* to the Workers API.
Solves Codespaces CSP blocking of cross-origin fetch requests.
"""
import http.server
import urllib.request
import urllib.error
import os

STATIC_DIR = os.path.join(os.path.dirname(__file__), 'build', 'web')
API_ORIGIN = 'https://nuvo-api.getnuvoapp.workers.dev'
API_PREFIX = '/api'

_SKIP_HEADERS = {'transfer-encoding', 'connection', 'keep-alive'}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC_DIR, **kwargs)

    def log_message(self, fmt, *args):
        print(f'[proxy] {self.address_string()} {fmt % args}')

    # ── Dispatch ──────────────────────────────────────────────────────────────

    def do_GET(self):
        if self.path.startswith(API_PREFIX):
            self._proxy()
        else:
            self._static()

    def do_POST(self):
        if self.path.startswith(API_PREFIX):
            self._proxy()
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        if self.path.startswith(API_PREFIX):
            self._proxy()
        else:
            self.send_error(404)

    def do_PATCH(self):
        if self.path.startswith(API_PREFIX):
            self._proxy()
        else:
            self.send_error(404)

    def do_DELETE(self):
        if self.path.startswith(API_PREFIX):
            self._proxy()
        else:
            self.send_error(404)

    # ── Static files (SPA fallback) ───────────────────────────────────────────

    def _static(self):
        # For paths that don't correspond to a real file, serve index.html
        # so the Flutter router can handle them client-side.
        rel = self.path.split('?')[0].lstrip('/')
        full = os.path.join(STATIC_DIR, rel)
        if rel and not os.path.exists(full):
            self.path = '/index.html'
        super().do_GET()

    # ── API proxy ─────────────────────────────────────────────────────────────

    def _proxy(self):
        api_path = self.path[len(API_PREFIX):]  # strip /api prefix
        url = API_ORIGIN + api_path

        # Forward request body
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length > 0 else None

        # Forward safe headers (including User-Agent so Cloudflare doesn't block)
        fwd = {}
        for h in ('Content-Type', 'Authorization', 'User-Agent'):
            if h in self.headers:
                fwd[h] = self.headers[h]
        if 'User-Agent' not in fwd:
            fwd['User-Agent'] = (
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/125.0.0.0 Safari/537.36'
            )

        req = urllib.request.Request(
            url, data=body, headers=fwd, method=self.command
        )

        try:
            with urllib.request.urlopen(req) as resp:
                self._relay(resp.status, resp.headers, resp.read())
        except urllib.error.HTTPError as e:
            self._relay(e.code, e.headers, e.read())

    def _relay(self, status, headers, body):
        self.send_response(status)
        for k, v in headers.items():
            if k.lower() not in _SKIP_HEADERS:
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)


if __name__ == '__main__':
    port = 8080
    server = http.server.ThreadingHTTPServer(('0.0.0.0', port), Handler)
    print(f'Nuvo proxy running on http://0.0.0.0:{port}')
    print(f'  Static: {STATIC_DIR}')
    print(f'  API:    /api/* → {API_ORIGIN}/*')
    server.serve_forever()
