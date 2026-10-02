# Nuvo Orchestration Bridge

Active-dispatch control plane for Nuvo AI workers. The architect (ChatGPT or a
human) POSTs `/dispatch` to this small local service, which launches Devin
worker sessions and tracks the job. **It is not a Notion poller** — nothing
runs unless a caller explicitly dispatches it.

```
ChatGPT / architect
      |  POST /dispatch (shared-secret auth)
      v
nuvo-orchestrator  (this service, localhost:8790, launchd-managed)
      |---> Devin Cloud REST API   api.devin.ai  -> Devin cloud sessions
      |---> devin CLI (local)      `devin -p`    -> local headless sessions
      |---> null_worker            self-test only, never launches real work
      v
Devin workers  --->  branches / PRs  +  Notion Agent Runs / Events / Claims
```

## Layout

- `bridge/nuvo_orchestrator.py` — the service (Python 3 stdlib only, no deps)
- `config/workers.json` — worker registry (id, provider, capabilities)
- `config/bridge.local.json` — real config + generated `bridge_key` (gitignored)
- `launchd/com.nuvo.orchestrator.plist` — auto-start on login
- `bin/install.sh` `uninstall.sh` `start.sh` `stop.sh` `status.sh`

Runtime state lives outside the repo in `~/.local/state/nuvo-orchestrator/`
(`state.json`, `audit.log`, `KILL`). The launchd runtime is copied to
`~/.local/share/nuvo-orchestrator/` because macOS TCC blocks launchd agents
from reading `~/Documents` — re-run `install.sh` after editing bridge code.

## Start / stop

```bash
orchestration/bin/install.sh     # daemon: starts now + on every login
orchestration/bin/uninstall.sh   # remove daemon entirely
orchestration/bin/start.sh       # dev mode (foreground spawn, repo dir)
orchestration/bin/stop.sh        # stop dev mode or launchd instance
orchestration/bin/status.sh      # launchd state + health + recent log
```

Instant kill switch (even if the API is misbehaving):

```bash
touch ~/.local/state/nuvo-orchestrator/KILL   # all /dispatch -> 423
rm    ~/.local/state/nuvo-orchestrator/KILL   # resume
```

## Auth

Every endpoint except `GET /health` requires the shared secret, compared in
constant time:

```
X-Nuvo-Bridge-Key: <bridge_key>        # or Authorization: Bearer <key>
```

The key is generated into `config/bridge.local.json` on first start. There is
**no arbitrary-shell endpoint** — the only side effects are "create a Devin
session with a prompt" and "poll its status", both logged to `audit.log`.

For remote access (e.g. ChatGPT calling from off-machine), put the bridge
behind an authenticated tunnel — e.g. a Cloudflare Tunnel — and keep the
shared secret. Do not bind it to a public interface without TLS.

## Dispatch API

```bash
KEY=$(python3 -c "import json;print(json.load(open('orchestration/config/bridge.local.json'))['bridge_key'])")

curl -X POST http://127.0.0.1:8790/dispatch \
  -H "X-Nuvo-Bridge-Key: $KEY" -H 'Content-Type: application/json' -d '{
    "task_id": "TASK-24",
    "architect": "chatgpt",
    "notion_task_url": "https://app.notion.com/p/<task-page>",
    "instructions": "Read-only recon: report `flutter --version` output as an Agent Event.",
    "workers": [
      {"provider": "devin_cloud", "role": "worker", "scope": "motion verifier"},
      {"provider": "devin_cloud", "role": "worker", "scope": "tests + diagnostics"}
    ]
  }'
```

Response:

```json
{"job_id":"job-…","status":"running",
 "sessions":[{"worker_id":"devin-cloud-1","session_id":"devin-…","session_url":"https://app.devin.ai/sessions/…",…}]}
```

Worker selection — any mix, never hardcoded:

- `{"worker_id": "devin-cloud-2"}` — exact slot
- `{"provider": "devin_cloud", "count": 3}` — 3 least-busy free slots
- `{"capabilities": ["flutter"]}` — any free slot with all listed caps
- `count` with no provider — first N free slots across providers

Other endpoints: `GET /health`, `GET /workers`, `GET /jobs`, `GET /jobs/{id}`,
`POST /jobs/{id}/refresh` (re-poll provider status), `POST /dispatch/dry-run`
(assignment plan, launches nothing), `POST /control {"action":"disable"}`.

## Providers

| provider | launches | requires |
|---|---|---|
| `devin_cloud` | Devin Cloud session via `POST api.devin.ai/v1/sessions` (or v3 when `devin_org_id` set) | `devin_api_key` in `bridge.local.json` or `DEVIN_API_KEY` env — generate at app.devin.ai → Settings → API Keys |
| `local_cli` | `devin -p -- <prompt>` detached on this Mac, cwd = `repo_dir` | one-time `devin auth login`; Devin.app installed |
| `null_worker` | nothing — records a `test-*` session | nothing; plumbing self-test only |

Session status: `POST /jobs/{id}/refresh` re-polls providers and updates the
job (`running`/`completed`/`degraded`). Devin session URLs are returned at
launch so the architect can watch or message a session directly.

## Known limits (MVP)

- `devin_cloud` needs a Devin API key that doesn't exist on this machine yet.
- `local_cli` needs a one-time interactive `devin auth login`; sessions also
  need Desktop-app-equivalent trust for the repo directory.
- The bridge does not write to Notion itself — workers do that per the Devin
  Worker Protocol, and the architect owns task/run bookkeeping.
- `local_cli` session-id binding is best-effort (pid fallback until
  `devin list` exposes the session).
