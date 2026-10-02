#!/bin/bash
STATE_DIR="${NUVO_ORCH_STATE_DIR:-$HOME/.local/state/nuvo-orchestrator}"
echo "--- launchd ---"
launchctl print "gui/$(id -u)/com.nuvo.orchestrator" 2>/dev/null | grep -E "state|pid" | head -5 || echo "not installed via launchd"
echo "--- health ---"
curl -s --max-time 5 http://127.0.0.1:8790/health || echo "no response on :8790"
echo
echo "--- last log lines ---"
tail -5 "$STATE_DIR/orchestrator.log" 2>/dev/null || true
