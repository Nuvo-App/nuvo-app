"""Representation reductions + distances over MotionBERT reps (T, 17, 512).

Everything here is generic. No movement-specific logic.
"""
from __future__ import annotations

import numpy as np


def _l2n(v: np.ndarray, axis=-1, eps=1e-8) -> np.ndarray:
    v = np.nan_to_num(np.asarray(v, np.float64))
    return (v / (np.linalg.norm(v, axis=axis, keepdims=True) + eps)).astype(np.float32)


# ---- reductions: (T,17,512) -> fixed-size descriptor -------------------------

def mean_pool(rep: np.ndarray) -> np.ndarray:
    """mean over time and joints -> (512,)"""
    return rep.mean(axis=(0, 1))


def mean_pool_joints(rep: np.ndarray) -> np.ndarray:
    """mean over time, keep joints -> (17*512,)"""
    return rep.mean(axis=0).reshape(-1)


def temporal_stats(rep: np.ndarray) -> np.ndarray:
    """[mean, std] over time, per joint -> (17*1024,)"""
    m = rep.mean(axis=0)
    s = rep.std(axis=0)
    return np.concatenate([m, s], axis=-1).reshape(-1)


def velocity_energy(rep: np.ndarray) -> np.ndarray:
    """mean absolute frame-to-frame change per joint-channel -> (17*512,)"""
    if rep.shape[0] < 2:
        return np.zeros(rep.shape[1] * rep.shape[2])
    return np.abs(np.diff(rep, axis=0)).mean(axis=0).reshape(-1)


def mean_plus_velocity(rep: np.ndarray) -> np.ndarray:
    return np.concatenate([mean_pool_joints(rep), velocity_energy(rep)])


REDUCERS = {
    "mean_pool": mean_pool,
    "mean_pool_joints": mean_pool_joints,
    "temporal_stats": temporal_stats,
    "velocity_energy": velocity_energy,
    "mean+velocity": mean_plus_velocity,
}


# ---- distances between descriptors ------------------------------------------

def cosine_dist(a: np.ndarray, b: np.ndarray) -> float:
    a, b = _l2n(a), _l2n(b)
    return float(1.0 - a @ b)


def euclid_dist(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def euclid_dist_norm(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(_l2n(a) - _l2n(b)))


DISTANCES = {
    "cosine": cosine_dist,
    "euclid": euclid_dist,
    "euclid_l2n": euclid_dist_norm,
}


# ---- sequence-level: resample + DTW over pooled-per-frame embeddings --------

def per_frame_embedding(rep: np.ndarray, l2n=True) -> np.ndarray:
    """(T,17,512) -> (T, 512) : mean over joints per frame."""
    e = rep.mean(axis=1)
    return _l2n(e, axis=-1) if l2n else e


def resample_seq(seq: np.ndarray, target: int) -> np.ndarray:
    T = seq.shape[0]
    if T == target:
        return seq
    idx = np.linspace(0, T - 1, target)
    lo = np.floor(idx).astype(int)
    hi = np.minimum(lo + 1, T - 1)
    w = (idx - lo)[:, None]
    return seq[lo] * (1 - w) + seq[hi] * w


def dtw_distance(a: np.ndarray, b: np.ndarray, band: float = 0.2) -> float:
    """DTW with a Sakoe-Chiba band. a,b: (Ta,D),(Tb,D). Cosine local cost."""
    Ta, Tb = len(a), len(b)
    an, bn = _l2n(a), _l2n(b)
    w = max(int(band * max(Ta, Tb)), abs(Ta - Tb) + 1)
    D = np.full((Ta + 1, Tb + 1), np.inf)
    D[0, 0] = 0.0
    for i in range(1, Ta + 1):
        jlo = max(1, i - w)
        jhi = min(Tb, i + w)
        for j in range(jlo, jhi + 1):
            c = 1.0 - float(an[i - 1] @ bn[j - 1])
            D[i, j] = c + min(D[i - 1, j], D[i, j - 1], D[i - 1, j - 1])
    return float(D[Ta, Tb] / (Ta + Tb))


def seq_dtw_dist(rep_a: np.ndarray, rep_b: np.ndarray, target=48) -> float:
    ea = resample_seq(per_frame_embedding(rep_a), target)
    eb = resample_seq(per_frame_embedding(rep_b), target)
    return dtw_distance(ea, eb)
