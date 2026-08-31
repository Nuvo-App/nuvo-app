"""MotionBERT motion encoder wrapper.

    seq (T, 17, 3)  ->  representation (T, 17, C)   [C = 512]

Uses the *backbone* only (no task head), via `forward(return_rep=True)` — the
(T,17,dim_rep) motion representation the authors' own action heads consume
(model_action.py: temporal-mean then flatten joints).

Two variants (pick with `set_variant()` / `MOTION_V2_ENCODER` env):
  - "lite_pretrain"  : MB_lite backbone, pretrained (2D->3D + masked recon).
  - "release_action" : full MB_release backbone, fine-tuned on NTU60 action
                       recognition — its rep is optimized to make *actions*
                       separable, which is what we want. ~42M params.
"""
from __future__ import annotations

import os
import sys
from functools import lru_cache

import numpy as np
import torch

_HERE = os.path.dirname(os.path.abspath(__file__))
_VENDOR = os.path.join(_HERE, "vendor", "MotionBERT")
_CKPT_ROOT = os.path.join(_HERE, "checkpoints", "MotionBERT", "checkpoint")

MAXLEN = 243
NUM_JOINTS = 17
DIM_REP = 512

_VARIANTS = {
    "lite_pretrain": {
        "config": "configs/pretrain/MB_lite.yaml",
        "ckpt": os.path.join(_CKPT_ROOT, "pretrain", "MB_lite", "latest_epoch.bin"),
        "state_key": "model_pos",
        "strip": "",
    },
    "release_action": {
        "config": "configs/action/MB_ft_NTU60_xsub.yaml",
        "ckpt": os.path.join(_CKPT_ROOT, "action", "FT_MB_release_MB_ft_NTU60_xsub", "best_epoch.bin"),
        "state_key": "model",
        "strip": "backbone.",   # applied AFTER the leading "module." is removed
    },
}

_variant = os.environ.get("MOTION_V2_ENCODER", "release_action")


def set_variant(name: str) -> None:
    global _variant
    assert name in _VARIANTS, name
    _variant = name
    _load.cache_clear()


def current_variant() -> str:
    return _variant


def _device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


@lru_cache(maxsize=2)
def _load(variant: str | None = None):
    variant = variant or _variant
    spec = _VARIANTS[variant]
    if _VENDOR not in sys.path:
        sys.path.insert(0, _VENDOR)
    from lib.model.DSTformer import DSTformer  # noqa: E402
    from lib.utils.tools import get_config  # noqa: E402

    if not os.path.exists(spec["ckpt"]):
        raise FileNotFoundError(f"missing {spec['ckpt']}\nrun tools/motion_v2/scripts/setup.sh")

    args = get_config(os.path.join(_VENDOR, spec["config"]))
    model = DSTformer(
        dim_in=3, dim_out=3, dim_feat=args.dim_feat, dim_rep=args.dim_rep,
        depth=args.depth, num_heads=args.num_heads, mlp_ratio=args.mlp_ratio,
        num_joints=args.num_joints, maxlen=args.maxlen,
        att_fuse=getattr(args, "att_fuse", True),
    )
    raw = torch.load(spec["ckpt"], map_location="cpu", weights_only=False)
    state = raw[spec["state_key"]]
    strip = spec["strip"]
    md = model.state_dict()
    new = {}
    matched = 0
    for k, v in state.items():
        kk = k[7:] if k.startswith("module.") else k
        if strip and kk.startswith(strip):
            kk = kk[len(strip):]
        elif strip:
            continue  # head / non-backbone weights
        if kk in md and md[kk].shape == v.shape:
            new[kk] = v
            matched += 1
    md.update(new)
    model.load_state_dict(md, strict=True)
    dev = _device()
    model = model.to(dev).eval()
    print(f"[mb_encoder] variant={variant} matched {matched}/{len(md)} backbone weights")
    return model, dev


@torch.no_grad()
def encode(seq: np.ndarray) -> np.ndarray:
    """seq: (T,17,3) — x,y ~[-1,1] root-relative, ch2 = confidence. -> (T,17,512)."""
    seq = np.asarray(seq, dtype=np.float32)
    assert seq.ndim == 3 and seq.shape[1:] == (NUM_JOINTS, 3), f"bad shape {seq.shape}"
    model, dev = _load(_variant)
    T = seq.shape[0]
    if T <= MAXLEN:
        x = torch.from_numpy(seq).unsqueeze(0).to(dev)
        return model(x, return_rep=True)[0].float().cpu().numpy()
    step = MAXLEN // 2
    acc = np.zeros((T, NUM_JOINTS, DIM_REP), np.float64)
    cnt = np.zeros((T, 1, 1), np.float64)
    for start in range(0, T, step):
        end = min(start + MAXLEN, T)
        r = model(torch.from_numpy(seq[start:end]).unsqueeze(0).to(dev), return_rep=True)[0]
        acc[start:end] += r.float().cpu().numpy()
        cnt[start:end] += 1
        if end == T:
            break
    return (acc / np.maximum(cnt, 1)).astype(np.float32)


def encoder_info() -> dict:
    model, dev = _load(_variant)
    n = sum(p.numel() for p in model.parameters())
    return {
        "variant": _variant, "params": n, "params_millions": round(n / 1e6, 2),
        "device": str(dev), "maxlen": MAXLEN, "num_joints": NUM_JOINTS, "dim_rep": DIM_REP,
        "checkpoint": os.path.relpath(_VARIANTS[_variant]["ckpt"], _HERE),
    }
