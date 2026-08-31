#!/usr/bin/env python
"""Milestone 1: the pretrained MotionBERT-Lite backbone loads and produces a
representation from a valid synthetic skeleton sequence.

    python tools/motion_v2/scripts/smoke_test.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from mb_encoder import DIM_REP, NUM_JOINTS, encode, encoder_info  # noqa: E402


def synthetic_sequence(T=64, seed=0) -> np.ndarray:
    """A moving skeleton: 17 joints on a unit-ish body, arms swinging over time."""
    rng = np.random.default_rng(seed)
    # rough root-relative H36M layout (x right, y up) at rest
    base = np.array(
        [
            [0.00, 0.00],   # 0 hip (root)
            [0.12, -0.02],  # 1 r hip
            [0.14, -0.45],  # 2 r knee
            [0.15, -0.90],  # 3 r ankle
            [-0.12, -0.02], # 4 l hip
            [-0.14, -0.45], # 5 l knee
            [-0.15, -0.90], # 6 l ankle
            [0.00, 0.22],   # 7 spine
            [0.00, 0.45],   # 8 thorax
            [0.00, 0.58],   # 9 neck/nose
            [0.00, 0.70],   # 10 head top
            [-0.18, 0.42],  # 11 l shoulder
            [-0.30, 0.20],  # 12 l elbow
            [-0.38, -0.02], # 13 l wrist
            [0.18, 0.42],   # 14 r shoulder
            [0.30, 0.20],   # 15 r elbow
            [0.38, -0.02],  # 16 r wrist
        ],
        dtype=np.float32,
    )
    seq = np.repeat(base[None], T, axis=0).copy()
    t = np.linspace(0, 2 * np.pi, T, dtype=np.float32)
    swing = 0.25 * np.sin(t)
    # elbows/wrists move on both arms
    for j in (12, 13, 15, 16):
        seq[:, j, 1] += swing
        seq[:, j, 0] += 0.15 * np.sin(t) * (1 if j in (15, 16) else -1)
    seq += rng.normal(0, 0.005, seq.shape).astype(np.float32)  # tiny jitter
    conf = np.full((T, NUM_JOINTS, 1), 0.95, dtype=np.float32)
    return np.concatenate([seq, conf], axis=-1)  # (T,17,3)


def main() -> int:
    info = encoder_info()
    print("encoder:", info)

    for T in (32, 64, 300):  # 300 exercises the >MAXLEN chunking path
        seq = synthetic_sequence(T=T)
        rep = encode(seq)
        assert rep.shape == (T, NUM_JOINTS, DIM_REP), rep.shape
        finite = np.isfinite(rep).all()
        # two runs must be identical (deterministic eval)
        rep2 = encode(seq)
        deterministic = np.allclose(rep, rep2)
        print(
            f"T={T:>3}  rep {rep.shape}  finite={finite}  deterministic={deterministic}  "
            f"mean={rep.mean():+.4f}  std={rep.std():.4f}  |max|={np.abs(rep).max():.3f}"
        )
        assert finite and deterministic

    # sanity: a still sequence and a moving sequence should differ in their
    # temporal-mean representation.
    still = np.concatenate(
        [np.repeat(synthetic_sequence(T=64)[0:1, :, :2], 64, axis=0),
         np.full((64, NUM_JOINTS, 1), 0.95, np.float32)],
        axis=-1,
    )
    moving = synthetic_sequence(T=64)
    d = np.linalg.norm(encode(still).mean(0) - encode(moving).mean(0))
    print(f"still vs moving mean-rep L2 = {d:.3f}  (expect > 0)")
    assert d > 0.1

    print("\nSMOKE OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
