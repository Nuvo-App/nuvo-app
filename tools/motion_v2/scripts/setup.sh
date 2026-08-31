#!/usr/bin/env bash
# Deterministic Motion V2 dev setup. Idempotent.
#   - Python 3.12 venv at tools/motion_v2/.venv
#   - pinned requirements
#   - pinned Hugging Face snapshot of MotionBERT (code + MB_lite pretrained ckpt)
# Nothing large is committed; this reproduces it.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PY="${MOTION_V2_PYTHON:-python3.12}"
HF_REPO="walterzhu/MotionBERT"
HF_REV="370a9196aa3c89198b134c82476143b01c0fb32c"

command -v "$PY" >/dev/null || { echo "need $PY (brew install python@3.12)"; exit 1; }

echo "== venv =="
if [ ! -d .venv ]; then "$PY" -m venv .venv; fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -q --upgrade pip
python -m pip install -q -r requirements.txt

echo "== download MotionBERT ($HF_REPO @ ${HF_REV:0:8}) =="
python - <<PYEOF
from huggingface_hub import snapshot_download
import os
root = os.environ["ROOT"] if "ROOT" in os.environ else "."
# Code + configs into vendor/, checkpoints into checkpoints/.
snapshot_download(
    "$HF_REPO", revision="$HF_REV",
    local_dir="vendor/MotionBERT",
    allow_patterns=["lib/**", "configs/**", "params/**", "*.py", "requirements.txt", "LICENSE"],
)
snapshot_download(
    "$HF_REPO", revision="$HF_REV",
    local_dir="checkpoints/MotionBERT",
    allow_patterns=[
        "checkpoint/pretrain/MB_lite/**",                       # lite_pretrain variant
        "checkpoint/action/FT_MB_release_MB_ft_NTU60_xsub/**",  # release_action variant (default)
    ],
)
print("ok")
PYEOF

echo
echo "done. next:  source tools/motion_v2/.venv/bin/activate && python tools/motion_v2/scripts/smoke_test.py"
