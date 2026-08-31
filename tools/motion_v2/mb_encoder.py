"""MotionBERT-Lite pretrained motion encoder wrapper.

    seq (T, 17, 3)  ->  representation (T, 17, 512)

Uses the *pretrained backbone* (no task head). Nothing model-specific leaks past
this file — downstream code only sees `encode(seq) -> np.ndarray`.
"""
from __future__ import annotations

import os
import sys
from functools import lru_cache

import numpy as np
import torch

_HERE = os.path.dirname(os.path.abspath(__file__))
_VENDOR = os.path.join(_HERE, "vendor", "MotionBERT")
_CKPT = os.path.join(
    _HERE, "checkpoints", "MotionBERT", "checkpoint", "pretrain", "MB_lite", "latest_epoch.bin"
)
_CONFIG = os.path.join(_VENDOR, "configs", "pretrain", "MB_lite.yaml")

# MotionBERT clip cap (temp_embed length). Longer inputs are chunked.
MAXLEN = 243
NUM_JOINTS = 17
DIM_REP = 512


def _device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


@lru_cache(maxsize=1)
def _load() -> tuple[torch.nn.Module, torch.device]:
    if _VENDOR not in sys.path:
        sys.path.insert(0, _VENDOR)
    from lib.utils.learning import load_backbone, load_pretrained_weights  # noqa: E402
    from lib.utils.tools import get_config  # noqa: E402

    if not os.path.exists(_CKPT):
        raise FileNotFoundError(
            f"missing {_CKPT}\nrun tools/motion_v2/scripts/setup.sh first"
        )
    args = get_config(_CONFIG)
    model = load_backbone(args)
    ckpt = torch.load(_CKPT, map_location="cpu", weights_only=False)
    state = ckpt.get("model_pos", ckpt)
    load_pretrained_weights(model, state)  # strips "module." and matches by name+size
    dev = _device()
    model = model.to(dev).eval()
    return model, dev


@torch.no_grad()
def encode(seq: np.ndarray) -> np.ndarray:
    """seq: (T, 17, 3) float — x,y in roughly [-1,1] root-relative, 3rd = confidence.

    Returns (T, 17, 512) representation (Tanh-bounded).
    """
    seq = np.asarray(seq, dtype=np.float32)
    assert seq.ndim == 3 and seq.shape[1:] == (NUM_JOINTS, 3), f"bad shape {seq.shape}"
    model, dev = _load()
    T = seq.shape[0]

    # Chunk to <= MAXLEN with 50% overlap; average the overlaps back together.
    if T <= MAXLEN:
        x = torch.from_numpy(seq).unsqueeze(0).to(dev)  # (1,T,17,3)
        rep = model(x, return_rep=True)[0]  # (T,17,512)
        return rep.float().cpu().numpy()

    step = MAXLEN // 2
    acc = np.zeros((T, NUM_JOINTS, DIM_REP), dtype=np.float64)
    cnt = np.zeros((T, 1, 1), dtype=np.float64)
    for start in range(0, T, step):
        end = min(start + MAXLEN, T)
        chunk = seq[start:end]
        x = torch.from_numpy(chunk).unsqueeze(0).to(dev)
        rep = model(x, return_rep=True)[0].float().cpu().numpy()
        acc[start:end] += rep
        cnt[start:end] += 1
        if end == T:
            break
    return (acc / np.maximum(cnt, 1)).astype(np.float32)


def encoder_info() -> dict:
    model, dev = _load()
    n = sum(p.numel() for p in model.parameters())
    return {
        "params": n,
        "params_millions": round(n / 1e6, 2),
        "device": str(dev),
        "maxlen": MAXLEN,
        "num_joints": NUM_JOINTS,
        "dim_rep": DIM_REP,
        "checkpoint": os.path.relpath(_CKPT, _HERE),
    }
