#!/bin/bash
# Install the nuvo-orchestrator as a login-starting launchd agent.
#
# macOS TCC blocks launchd agents from reading ~/Documents, so this copies the
# runtime to ~/.local/share/nuvo-orchestrator/ (outside Documents) and points
# launchd there. The repo remains the source of truth — re-run install.sh
# after editing bridge code or config.
set -euo pipefail

ORCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${NUVO_ORCH_HOME:-$HOME/.local/share/nuvo-orchestrator}"
STATE_DIR="${NUVO_ORCH_STATE_DIR:-$HOME/.local/state/nuvo-orchestrator}"
LABEL="com.nuvo.orchestrator"
PLIST_SRC="$ORCH_DIR/launchd/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents" "$INSTALL_DIR"

rsync -a --delete \
  --exclude '__pycache__' \
  "$ORCH_DIR/bridge/" "$INSTALL_DIR/bridge/"
rsync -a "$ORCH_DIR/config/" "$INSTALL_DIR/config/"

# Prefer a real interpreter: /usr/bin/python3 is an Xcode CLT shim that can be
# missing or differently-sandboxed under launchd.
PYTHON3="$(command -v python3 || true)"
for c in /Library/Developer/CommandLineTools/usr/bin/python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  [ -x "$c" ] && PYTHON3="$c" && break
done

sed -e "s|__ORCH_DIR__|$INSTALL_DIR|g" \
    -e "s|__STATE_DIR__|$STATE_DIR|g" \
    -e "s|__PYTHON__|$PYTHON3|g" \
    "$PLIST_SRC" > "$PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
sleep 2
echo "installed and started $LABEL"
echo "runtime:  $INSTALL_DIR"
echo "state:    $STATE_DIR"
"$ORCH_DIR/bin/status.sh"
