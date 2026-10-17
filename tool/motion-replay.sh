#!/usr/bin/env bash
# Usage: tool/motion-replay.sh <session.json[.gz]> [--spec f] [--set key=value] [--out f.html]
set -euo pipefail
cd "$(dirname "$0")/.."
args=()
for a in "$@"; do
  case "$a" in /*) args+=("$a") ;; --*|*=*) args+=("$a") ;; *) args+=("$PWD_ORIG/$a") ;; esac
done
MOTION_REPLAY_ARGS="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1:]))' "$@")" \
  flutter test tool/motion_replay_run_test.dart --reporter expanded 2>&1 | grep -vE "^\s*$|^[0-9:]+ \+[0-9]+: (loading|All tests passed)" 
