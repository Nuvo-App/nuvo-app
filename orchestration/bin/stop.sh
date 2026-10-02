#!/bin/bash
# Stop the dev-mode bridge (does not touch the launchd install).
set -euo pipefail
STATE_DIR="${NUVO_ORCH_STATE_DIR:-$HOME/.local/state/nuvo-orchestrator}"
LABEL="com.nuvo.orchestrator"
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/$LABEL"
  echo "stopped launchd $LABEL"
elif [ -f "$STATE_DIR/orchestrator.pid" ]; then
  kill "$(cat "$STATE_DIR/orchestrator.pid")" 2>/dev/null || true
  rm -f "$STATE_DIR/orchestrator.pid"
  echo "stopped dev-mode bridge"
else
  pkill -f nuvo_orchestrator.py 2>/dev/null && echo "killed stray bridge" || echo "no bridge running"
fi
