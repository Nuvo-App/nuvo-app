#!/usr/bin/env python3
"""
nuvo-orchestrator — authenticated dispatch bridge for Nuvo AI workers.

The architect (ChatGPT or a human) calls this service to explicitly dispatch
Devin worker sessions. It is NOT a Notion poller: nothing happens unless a
caller POSTs /dispatch.

Endpoints
  GET  /health            unauthenticated liveness + provider readiness
  GET  /workers           worker registry + live availability
  GET  /jobs              list dispatch jobs
  GET  /jobs/{id}         job detail
  POST /jobs/{id}/refresh re-poll provider status for a job's sessions
  POST /dispatch          launch worker sessions (see README for schema)
  POST /dispatch/dry-run  validate + show the assignment plan, launch nothing
  POST /control           {"action": "enable"|"disable"} kill switch

Auth: every endpoint except /health requires the shared secret in either
  X-Nuvo-Bridge-Key: <secret>        or
  Authorization: Bearer <secret>
compared in constant time. There is no arbitrary-shell endpoint anywhere.
"""

import hashlib
import hmac
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "0.1.0"

ORCH_DIR = Path(__file__).resolve().parent.parent
CONFIG_PATH = ORCH_DIR / "config" / "bridge.local.json"
EXAMPLE_CONFIG_PATH = ORCH_DIR / "config" / "bridge.example.json"
WORKERS_PATH = ORCH_DIR / "config" / "workers.json"
STATE_DIR = Path(
    os.environ.get("NUVO_ORCH_STATE_DIR", Path.home() / ".local/state/nuvo-orchestrator")
)
STATE_PATH = STATE_DIR / "state.json"
AUDIT_PATH = STATE_DIR / "audit.log"
KILLFILE = STATE_DIR / "KILL"
LOG_PATH = STATE_DIR / "orchestrator.log"

MAX_BODY = 32 * 1024
MAX_WORKERS_PER_DISPATCH = 20
MAX_PROMPT_LEN = 16 * 1024

DEVIN_API_BASE = "https://api.devin.ai"
DEFAULT_DEVIN_BIN = (
    "/Applications/Devin.app/Contents/Resources/app/extensions/"
    "windsurf/devin/bin/devin"
)

PROMPT_TEMPLATE = """You are a Nuvo Devin worker dispatched by the nuvo-orchestrator.

Follow the Nuvo HQ "Devin Worker Protocol" end to end:
READ -> CHECK -> CLAIM -> PLAN -> IMPLEMENT -> TEST -> REVIEW -> PUBLISH -> PR -> RELEASE CLAIM.

Nuvo HQ: https://app.notion.com/p/3eda4b4316b281f0a606f58879b3a59c
Worker protocol: https://app.notion.com/p/3eda4b4316b281cdb4b3c68fc4766037
AI Operating Protocol: https://app.notion.com/p/3eda4b4316b2811bad82d97bdeac9874

Assignment
- Task: {task_ref}
- Worker: {worker_id} ({provider})
- Scope: {scope}

Instructions
{instructions}

Before editing, create an Agent Run and an active Claim in Nuvo HQ covering
your expected file scope, and post a Plan event. When finished, post an
Implemented or Handoff event and release the Claim. Branch convention:
agent/{task_ref}-short-description.
"""

_state_lock = threading.Lock()


def utcnow():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def log_line(msg):
    line = f"{utcnow()} {msg}"
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_PATH, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass
    print(line, flush=True)


def audit(entry):
    entry = dict(entry)
    entry["ts"] = utcnow()
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with open(AUDIT_PATH, "a") as f:
            f.write(json.dumps(entry, sort_keys=True) + "\n")
    except OSError:
        pass


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


def load_state():
    with _state_lock:
        return load_json(STATE_PATH, {"jobs": {}, "sessions": {}})


def save_state(state):
    with _state_lock:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix="state.", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(state, f, indent=2, sort_keys=True)
        os.replace(tmp, STATE_PATH)


def mutate_state(fn):
    state = load_state()
    result = fn(state)
    save_state(state)
    return result


def load_config():
    cfg = load_json(CONFIG_PATH, None)
    if cfg is None:
        cfg = load_json(EXAMPLE_CONFIG_PATH, {})
    cfg.setdefault("host", "127.0.0.1")
    cfg.setdefault("port", 8790)
    cfg.setdefault("repo_dir", str(ORCH_DIR.parent))
    cfg.setdefault("devin_bin", DEFAULT_DEVIN_BIN)
    if not cfg.get("devin_api_key"):
        cfg["devin_api_key"] = os.environ.get("DEVIN_API_KEY", "")
    if not cfg.get("bridge_key"):
        cfg["bridge_key"] = os.environ.get("NUVO_BRIDGE_KEY", "")
    # A placeholder copied verbatim from bridge.example.json is not a secret.
    if str(cfg.get("bridge_key", "")).startswith("REPLACE_"):
        cfg["bridge_key"] = ""
    return cfg


def load_workers():
    data = load_json(WORKERS_PATH, {"workers": []})
    return data.get("workers", [])


# --------------------------------------------------------------------------
# Providers
# --------------------------------------------------------------------------


class ProviderError(Exception):
    pass


def _http_json(method, url, headers=None, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:500]
        raise ProviderError(f"HTTP {e.code} from {url}: {detail}")
    except urllib.error.URLError as e:
        raise ProviderError(f"network error calling {url}: {e.reason}")


class DevinCloudProvider:
    """Launches Devin sessions through the official api.devin.ai REST API.

    Uses v1 endpoints (POST /v1/sessions). If a devin_org_id is configured the
    v3 org-scoped endpoints are used instead.
    """

    name = "devin_cloud"

    def __init__(self, cfg):
        self.api_key = cfg.get("devin_api_key") or ""
        self.org_id = cfg.get("devin_org_id") or ""
        self.base = cfg.get("devin_api_base", DEVIN_API_BASE)

    @property
    def configured(self):
        return bool(self.api_key)

    def _headers(self):
        return {"Authorization": f"Bearer {self.api_key}"}

    def launch(self, prompt, title=None, worker=None):
        if not self.configured:
            raise ProviderError(
                "devin_cloud not configured: set devin_api_key in "
                "config/bridge.local.json or DEVIN_API_KEY env"
            )
        tags = ["nuvo-orchestrator"]
        if worker:
            tags.append(f"worker:{worker}")
        if self.org_id:
            url = f"{self.base}/v3/organizations/{self.org_id}/sessions"
            body = {"prompt": prompt, "tags": tags}
            if title:
                body["title"] = title
        else:
            url = f"{self.base}/v1/sessions"
            body = {"prompt": prompt, "idempotent": True, "tags": tags}
            if title:
                body["title"] = title
        _, data = _http_json("POST", url, self._headers(), body)
        session_id = data.get("session_id") or data.get("devin_id") or data.get("id")
        if not session_id:
            raise ProviderError(f"session created but no id in response: {data}")
        return {
            "session_id": session_id,
            "session_url": data.get("url") or data.get("session_url"),
            "provider": self.name,
            "raw": data,
        }

    def status(self, session_id):
        if self.org_id:
            url = f"{self.base}/v3/organizations/{self.org_id}/sessions/{session_id}"
        else:
            url = f"{self.base}/v1/sessions/{session_id}"
        _, data = _http_json("GET", url, self._headers())
        status = data.get("status_enum") or data.get("status") or "unknown"
        return {
            "status": status,
            "detail": data.get("structured_output") or data.get("title") or "",
            "raw": data,
        }


class LocalCliProvider:
    """Launches a local headless Devin session: `devin -p -- <prompt>`.

    Requires `devin auth login` to have been completed once on this machine.
    The spawned process is detached so the session survives this service.
    """

    name = "local_cli"

    def __init__(self, cfg):
        self.devin_bin = cfg.get("devin_bin", DEFAULT_DEVIN_BIN)
        self.repo_dir = cfg.get("repo_dir", str(ORCH_DIR.parent))

    @property
    def configured(self):
        return Path(self.devin_bin).exists()

    def _list_sessions(self):
        try:
            out = subprocess.run(
                [self.devin_bin, "list", "--format", "json"],
                cwd=self.repo_dir, capture_output=True, text=True, timeout=30,
            )
            return json.loads(out.stdout or "[]")
        except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
            return []

    def launch(self, prompt, title=None, worker=None):
        if not self.configured:
            raise ProviderError(f"devin binary not found at {self.devin_bin}")
        before = {s.get("id") for s in self._list_sessions()}
        log_path = STATE_DIR / "local-cli-sessions.log"
        log_f = open(log_path, "a")
        proc = subprocess.Popen(
            [self.devin_bin, "-p", "--", prompt],
            cwd=self.repo_dir, stdout=log_f, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        session_id = None
        deadline = time.time() + 15
        while time.time() < deadline:
            time.sleep(1)
            now = {s.get("id"): s for s in self._list_sessions()}
            new_ids = [sid for sid in now if sid not in before]
            if new_ids:
                session_id = new_ids[0]
                break
            if proc.poll() is not None:
                break
        return {
            "session_id": session_id or f"local-pid-{proc.pid}",
            "session_url": None,
            "provider": self.name,
            "pid": proc.pid,
            "raw": {"pid": proc.pid, "note": "prompt delivered via devin -p"},
        }

    def status(self, session_id):
        if session_id and session_id.startswith("local-pid-"):
            pid = int(session_id.rsplit("-", 1)[1])
            try:
                os.kill(pid, 0)
                return {"status": "running", "detail": f"pid {pid} alive"}
            except OSError:
                return {"status": "exited", "detail": f"pid {pid} gone; see {STATE_DIR}/local-cli-sessions.log"}
        for s in self._list_sessions():
            if s.get("id") == session_id:
                return {"status": "present", "detail": s.get("title", ""), "raw": s}
        return {"status": "unknown", "detail": "session id not in devin list"}


class NullWorkerProvider:
    """Bridge-plumbing self-test provider. Does NOT launch a Devin session.

    Used only to verify auth/registry/state/audit machinery end to end when
    no real provider credentials exist yet. Sessions are prefixed `test-` so
    they can never be confused with real work.
    """

    name = "null_worker"

    def __init__(self, cfg):
        pass

    @property
    def configured(self):
        return True

    def launch(self, prompt, title=None, worker=None):
        sid = "test-" + secrets.token_hex(6)
        return {
            "session_id": sid,
            "session_url": None,
            "provider": self.name,
            "raw": {"note": "TEST PROVIDER — no Devin session was launched"},
        }

    def status(self, session_id):
        return {"status": "test", "detail": "null_worker — nothing real was launched"}


def providers_for(cfg):
    return {
        "devin_cloud": DevinCloudProvider(cfg),
        "local_cli": LocalCliProvider(cfg),
        "null_worker": NullWorkerProvider(cfg),
    }


# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------

TASK_REF_RE = re.compile(r"^[A-Za-z0-9_.:/-]{1,200}$")


def build_prompt(cfg, task_ref, worker, scope, instructions):
    tmpl = cfg.get("prompt_template", PROMPT_TEMPLATE)
    return tmpl.format(
        task_ref=task_ref or "ad-hoc",
        worker_id=worker.get("worker_id", "?"),
        provider=worker.get("provider", "?"),
        scope=scope or "see instructions",
        instructions=instructions or "",
    )


def pick_workers(registry, request_workers, providers, state):
    """Resolve the caller's worker selection to registry entries.

    request_workers entries may carry:
      - worker_id          exact registry slot
      - provider           any free slot of that provider
      - capabilities [...] slot must include all listed capabilities
      - count N + provider pick the N least-busy free slots
    """
    active = set()
    for job in state.get("jobs", {}).values():
        if job.get("status") == "running":
            for s in job.get("sessions", []):
                if s.get("launch") == "ok":
                    active.add(s.get("worker_id"))

    resolved = []
    errors = []
    used = set()
    for req in request_workers:
        cand = None
        if req.get("worker_id"):
            cand = [w for w in registry if w["worker_id"] == req["worker_id"]]
            if not cand:
                errors.append(f"unknown worker_id {req['worker_id']}")
                continue
        else:
            provider = req.get("provider")
            caps = set(req.get("capabilities") or [])
            cand = [
                w for w in registry
                if w.get("enabled", True)
                and (not provider or w["provider"] == provider)
                and caps.issubset(set(w.get("capabilities", [])))
                and w["worker_id"] not in active
                and w["worker_id"] not in used
            ]
            count = int(req.get("count", 1))
            cand = cand[:count]
            if not cand:
                errors.append(
                    f"no free worker for provider={provider} caps={sorted(caps)}"
                )
                continue
        for w in cand:
            used.add(w["worker_id"])
            resolved.append((w, req))
    return resolved, errors


def do_dispatch(cfg, providers, body, dry_run=False):
    task_ref = body.get("task_id") or body.get("task") or "ad-hoc"
    if task_ref != "ad-hoc" and not TASK_REF_RE.match(str(task_ref)):
        return 400, {"error": "task_id contains disallowed characters"}

    instructions = body.get("instructions") or ""
    title = body.get("title") or f"nuvo-{task_ref}"
    request_workers = body.get("workers")
    if not request_workers:
        request_workers = [{"provider": "devin_cloud", "count": int(body.get("count", 1))}]
    if len(request_workers) > MAX_WORKERS_PER_DISPATCH:
        return 400, {"error": f"too many workers requested (max {MAX_WORKERS_PER_DISPATCH})"}

    state = load_state()
    registry = load_workers()
    resolved, errors = pick_workers(registry, request_workers, providers, state)
    if not resolved:
        return 409, {"error": "no workers could be assigned", "detail": errors}

    job_id = "job-" + secrets.token_hex(6)
    plan = []
    for w, req in resolved:
        scope = req.get("scope") or body.get("scope") or ""
        instr = req.get("instructions") or instructions
        prompt = req.get("prompt") or build_prompt(
            cfg, task_ref, w, scope, instr
        )
        if len(prompt) > MAX_PROMPT_LEN:
            return 400, {"error": "prompt exceeds max length"}
        plan.append({
            "worker_id": w["worker_id"],
            "provider": w["provider"],
            "role": req.get("role") or w.get("role") or "worker",
            "scope": scope,
            "prompt_preview": prompt[:400],
            "prompt": prompt,
        })

    if dry_run:
        return 200, {
            "dry_run": True, "job_id": None, "task_id": task_ref,
            "assignments": [{k: v for k, v in p.items() if k != "prompt"} for p in plan],
            "warnings": errors,
        }

    sessions = []
    for p in plan:
        provider = providers[p["provider"]]
        try:
            result = provider.launch(p["prompt"], title=title, worker=p["worker_id"])
            sessions.append({**p, "launch": "ok", **{k: result.get(k) for k in
                             ("session_id", "session_url", "pid")}})
        except ProviderError as e:
            sessions.append({**p, "launch": "failed", "error": str(e)})

    job = {
        "job_id": job_id,
        "task_id": task_ref,
        "title": title,
        "architect": body.get("architect", "unknown"),
        "created_at": utcnow(),
        "status": "running" if any(s["launch"] == "ok" for s in sessions) else "failed",
        "sessions": [{k: v for k, v in s.items() if k != "prompt"} for s in sessions],
        "notion_task_url": body.get("notion_task_url"),
        "errors": errors,
    }

    def _save(st):
        st["jobs"][job_id] = job
        for s in sessions:
            if s.get("session_id"):
                st["sessions"][s["session_id"]] = {
                    "job_id": job_id, "worker_id": s["worker_id"],
                    "provider": s["provider"], "created_at": job["created_at"],
                }
    mutate_state(_save)
    return 200, {"job_id": job_id, "status": job["status"], "sessions": job["sessions"], "warnings": errors}


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = f"nuvo-orchestrator/{VERSION}"
    cfg = None
    providers = None
    disabled = False

    def log_message(self, fmt, *args):
        log_line("http " + (fmt % args))

    # -- helpers -------------------------------------------------------------

    def _send(self, code, obj):
        body = json.dumps(obj, indent=2, sort_keys=True).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise ValueError("body too large")
        raw = self.rfile.read(n) if n else b"{}"
        try:
            return json.loads(raw or b"{}")
        except json.JSONDecodeError:
            raise ValueError("invalid JSON body")

    def _authed(self):
        key = self.cfg.get("bridge_key") or ""
        if not key:
            return False  # no key configured -> refuse all authed endpoints
        supplied = self.headers.get("X-Nuvo-Bridge-Key")
        if not supplied:
            auth = self.headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                supplied = auth[7:]
        return bool(supplied) and hmac.compare_digest(supplied, key)

    def _kill_switched(self):
        return Handler.disabled or KILLFILE.exists()

    def _guard(self):
        """Return an error response tuple, or None if the request may proceed."""
        if not self._authed():
            audit({"ep": self.path, "ok": False, "why": "unauthorized",
                   "remote": self.client_address[0]})
            return (401, {"error": "unauthorized"})
        return None

    # -- routes --------------------------------------------------------------

    def do_GET(self):
        try:
            if self.path == "/health":
                prov = {name: {"configured": p.configured}
                        for name, p in self.providers.items()}
                return self._send(200, {
                    "ok": True, "version": VERSION,
                    "dispatch_enabled": not self._kill_switched(),
                    "providers": prov,
                    "workers": len(load_workers()),
                })
            if self.path.startswith("/jobs"):
                err = self._guard()
                if err:
                    return self._send(*err)
                state = load_state()
                if self.path == "/jobs":
                    return self._send(200, {"jobs": list(state["jobs"].values())})
                jid = self.path.split("/")[-1]
                job = state["jobs"].get(jid)
                return self._send(200, job) if job else self._send(404, {"error": "unknown job"})
            if self.path == "/workers":
                err = self._guard()
                if err:
                    return self._send(*err)
                return self._send(200, {"workers": load_workers()})
            if self.path == "/audit":
                err = self._guard()
                if err:
                    return self._send(*err)
                lines = []
                try:
                    lines = AUDIT_PATH.read_text().strip().split("\n")[-100:]
                except OSError:
                    pass
                return self._send(200, {"audit": [json.loads(l) for l in lines if l]})
            self._send(404, {"error": "not found"})
        except Exception as e:  # never leak a stack to callers
            log_line(f"handler error: {e!r}")
            self._send(500, {"error": "internal"})

    def do_POST(self):
        try:
            if self.path.startswith("/dispatch") or self.path.startswith("/jobs") or self.path == "/control":
                err = self._guard()
                if err:
                    return self._send(*err)
            else:
                return self._send(404, {"error": "not found"})

            body = self._body()

            if self.path == "/dispatch/dry-run":
                audit({"ep": "dispatch/dry-run", "ok": True,
                       "task": body.get("task_id"),
                       "n_workers": len(body.get("workers") or [])})
                code, resp = do_dispatch(self.cfg, self.providers, body, dry_run=True)
                return self._send(code, resp)

            if self.path == "/dispatch":
                if self._kill_switched():
                    audit({"ep": "dispatch", "ok": False, "why": "disabled"})
                    return self._send(423, {"error": "dispatch disabled (kill switch)"})
                audit({"ep": "dispatch", "ok": True, "task": body.get("task_id"),
                       "n_workers": len(body.get("workers") or []),
                       "architect": body.get("architect")})
                code, resp = do_dispatch(self.cfg, self.providers, body)
                return self._send(code, resp)

            if self.path == "/control":
                action = body.get("action")
                if action not in ("enable", "disable"):
                    return self._send(400, {"error": "action must be enable|disable"})
                Handler.disabled = (action == "disable")
                audit({"ep": "control", "ok": True, "action": action})
                return self._send(200, {"dispatch_enabled": not self._kill_switched()})

            if self.path.startswith("/jobs/") and self.path.endswith("/refresh"):
                jid = self.path.split("/")[2]
                return self._refresh(jid)

            self._send(404, {"error": "not found"})
        except ValueError as e:
            self._send(400, {"error": str(e)})
        except Exception as e:
            log_line(f"handler error: {e!r}")
            self._send(500, {"error": "internal"})

    def _refresh(self, jid):
        state = load_state()
        job = state["jobs"].get(jid)
        if not job:
            return self._send(404, {"error": "unknown job"})
        updates = []
        for s in job["sessions"]:
            sid = s.get("session_id")
            if not sid or s.get("launch") != "ok":
                continue
            provider = self.providers.get(s["provider"])
            if not provider:
                continue
            try:
                st = provider.status(sid)
                s["last_status"] = st["status"]
                s["status_detail"] = str(st.get("detail", ""))[:300]
                s["status_at"] = utcnow()
            except ProviderError as e:
                s["last_status"] = "poll_error"
                s["status_detail"] = str(e)[:300]
            updates.append({"session_id": sid, "status": s["last_status"]})
        statuses = {s.get("last_status") for s in job["sessions"] if s.get("last_status")}
        if statuses and statuses.issubset({"finished", "exited", "blocked", "test", "expired"}):
            job["status"] = "completed"
        elif any(s.get("last_status") == "poll_error" for s in job["sessions"]):
            job["status"] = "degraded"
        job["updated_at"] = utcnow()
        save_state(state)
        audit({"ep": "refresh", "ok": True, "job": jid})
        return self._send(200, {"job_id": jid, "job_status": job["status"], "updates": updates})


def main():
    cfg = load_config()
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    if not cfg.get("bridge_key"):
        cfg["bridge_key"] = secrets.token_urlsafe(32)
        local_cfg = load_json(CONFIG_PATH, None) or dict(cfg)
        local_cfg.pop("comment", None)
        local_cfg["bridge_key"] = cfg["bridge_key"]
        with open(CONFIG_PATH, "w") as f:
            json.dump(local_cfg, f, indent=2)
        log_line(f"generated new bridge_key in {CONFIG_PATH}")

    Handler.cfg = cfg
    Handler.providers = providers_for(cfg)

    host, port = cfg["host"], int(cfg["port"])
    server = ThreadingHTTPServer((host, port), Handler)

    def _shutdown(*_):
        log_line("shutting down")
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    configured = [n for n, p in Handler.providers.items() if p.configured]
    log_line(f"nuvo-orchestrator {VERSION} listening on http://{host}:{port} "
             f"providers_configured={configured} pid={os.getpid()}")
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
