#!/bin/bash
# Stop and remove the launchd agent. This is the durable kill switch.
set -euo pipefail
LABEL="com.nuvo.orchestrator"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "removed $LABEL — bridge is stopped and will not restart on login"
