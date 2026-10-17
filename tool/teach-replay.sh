#!/usr/bin/env bash
# Usage: tool/teach-replay.sh <session.json[.gz] | directory> [--no-v2] [--target N] [--demos]
# Replays teach artifacts (nuvo-motion.mjs teach-get) through both matchers.
# V2 needs the ONNX shared lib on Linux:
#   LD_LIBRARY_PATH=/home/server1/ort/onnxruntime-linux-x64-1.15.1/lib tool/teach-replay.sh s.json.gz
# Self-test (no session needed): TEACH_REPLAY_SELFTEST=1 tool/teach-replay.sh --no-v2
set -euo pipefail
cd "$(dirname "$0")/.."
MOTION_V2_LD="${LD_LIBRARY_PATH:-}"
TEACH_REPLAY_ARGS="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1:]))' "$@")" \
  LD_LIBRARY_PATH="$MOTION_V2_LD" \
  flutter test tool/teach_replay_run_test.dart --reporter expanded 2>&1 \
  | grep -vE "^\s*$|^[0-9:]+ \+[0-9]+: (loading|All tests passed)"
