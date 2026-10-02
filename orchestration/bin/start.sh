#!/bin/bash
# Start the bridge in the foreground-of-nothing fashion without launchd
# (useful for dev). For the daemon version use bin/install.sh.
set -euo pipefail
ORCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${NUVO_ORCH_STATE_DIR:-$HOME/.local/state/nuvo-orchestrator}"
mkdir -p "$STATE_DIR"
nohup /usr/bin/python3 "$ORCH_DIR/bridge/nuvo_orchestrator.py" \
  >> "$STATE_DIR/orchestrator.log" 2>&1 &
echo $! > "$STATE_DIR/orchestrator.pid"
echo "started pid $(cat "$STATE_DIR/orchestrator.pid")"
sleep 1
curl -s http://127.0.0.1:8790/health || echo "health check failed — see $STATE_DIR/orchestrator.log"
