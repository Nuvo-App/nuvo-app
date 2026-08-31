"""Nuvo pose stream  ->  MotionBERT 17-joint H36M skeleton.

Nuvo capture = MediaPipe/BlazePose 33 named landmarks, image-normalized
(x,y in [0,1], y-down) + per-point `likelihood`. See lib/.../ai_motion_models.dart
(NuvoPoseFrame / NuvoPosePoint) and normalized_pose.dart (canonicalPoseLandmarkIds).

Output = (T, 17, 3): H36M joint order, channels (x, y, confidence), coords
sequence-normalized to [-1, 1] via MotionBERT's own `crop_scale` so the encoder
sees its training distribution. Every assumption is explicit here — nothing
downstream re-normalizes.
"""
from __future__ import annotations

import os
import sys
from typing import Iterable

import numpy as np

_VENDOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vendor", "MotionBERT")
if _VENDOR not in sys.path:
    sys.path.insert(0, _VENDOR)
from lib.utils.utils_data import crop_scale  # noqa: E402  (MotionBERT's exact 2D normalizer)

# H36M-17 joint order (from vendor/MotionBERT/lib/data/dataset_action.py coco2h36m):
#  0 root  1 rhip  2 rknee 3 rank  4 lhip  5 lknee 6 lank
#  7 belly 8 neck  9 nose 10 head 11 lsho 12 lelb 13 lwri 14 rsho 15 relb 16 rwri
H36M_NAMES = [
    "root", "rhip", "rknee", "rank", "lhip", "lknee", "lank",
    "belly", "neck", "nose", "head", "lsho", "lelb", "lwri", "rsho", "relb", "rwri",
]
NUM_JOINTS = 17

# Each H36M joint = mean of these Nuvo landmarks (1 = direct copy, 2 = midpoint).
# 'belly' (7) is derived from root+neck afterwards, not from landmarks.
_MAP: dict[int, tuple[str, ...]] = {
    0: ("leftHip", "rightHip"),
    1: ("rightHip",),
    2: ("rightKnee",),
    3: ("rightAnkle",),
    4: ("leftHip",),
    5: ("leftKnee",),
    6: ("leftAnkle",),
    8: ("leftShoulder", "rightShoulder"),
    9: ("nose",),
    10: ("leftEar", "rightEar"),
    11: ("leftShoulder",),
    12: ("leftElbow",),
    13: ("leftWrist",),
    14: ("rightShoulder",),
    15: ("rightElbow",),
    16: ("rightWrist",),
}

# left/right joint indices for horizontal-flip / mirror handling downstream.
H36M_LEFT = [4, 5, 6, 11, 12, 13]
H36M_RIGHT = [1, 2, 3, 14, 15, 16]

MIN_LIKELIHOOD = 0.30


def _pt(points: dict, name: str) -> tuple[float, float, float] | None:
    p = points.get(name)
    if p is None:
        return None
    conf = float(p.get("likelihood", p.get("confidence", 0.0)))
    if conf < MIN_LIKELIHOOD:
        return None
    return float(p["x"]), float(p["y"]), conf


def frame_to_h36m(points: dict) -> np.ndarray:
    """One frame's {name: {x,y,likelihood}} dict -> (17, 3). Missing joints -> conf 0."""
    out = np.zeros((NUM_JOINTS, 3), dtype=np.float32)
    for j, names in _MAP.items():
        got = [_pt(points, n) for n in names]
        got = [g for g in got if g is not None]
        if not got:
            continue
        xs = np.mean([g[0] for g in got])
        ys = np.mean([g[1] for g in got])
        cs = np.min([g[2] for g in got])  # weakest contributor governs confidence
        out[j] = (xs, ys, cs)
    # belly = midpoint(root, neck) when both are present
    if out[0, 2] > 0 and out[8, 2] > 0:
        out[7, :2] = (out[0, :2] + out[8, :2]) * 0.5
        out[7, 2] = min(out[0, 2], out[8, 2])
    # head fallback: if ears missing, extrapolate above the nose along nose->neck
    if out[10, 2] == 0 and out[9, 2] > 0 and out[8, 2] > 0:
        out[10, :2] = out[9, :2] + (out[9, :2] - out[8, :2]) * 0.5
        out[10, 2] = out[9, 2] * 0.5
    return out


def _fill_gaps(seq: np.ndarray) -> np.ndarray:
    """Linearly interpolate short confidence gaps per joint; hold ends. Keeps
    confidence at the interpolated frames low so the encoder de-weights them."""
    T = seq.shape[0]
    out = seq.copy()
    for j in range(NUM_JOINTS):
        conf = seq[:, j, 2]
        valid = np.where(conf > 0)[0]
        if len(valid) == 0:
            continue
        if len(valid) == T:
            continue
        idx = np.arange(T)
        out[:, j, 0] = np.interp(idx, valid, seq[valid, j, 0])
        out[:, j, 1] = np.interp(idx, valid, seq[valid, j, 1])
        # interpolated frames get a damped confidence, real frames keep theirs
        interp_conf = np.interp(idx, valid, conf[valid]) * 0.5
        out[:, j, 2] = np.where(conf > 0, conf, interp_conf)
    return out


def frames_to_h36m(frames: Iterable[dict], *, mirror: bool = False) -> np.ndarray:
    """List of Nuvo frame dicts -> (T, 17, 3), normalized to [-1,1] for MotionBERT.

    frames: each a dict with a "points" key (name -> {x,y,likelihood}) OR the
            points dict directly.
    mirror: horizontally flip (front-camera). x -> -x after normalization, with
            left/right joints swapped. Off by default; the encoder is compared
            against both orientations downstream.
    """
    raw = []
    for f in frames:
        points = f.get("points", f) if isinstance(f, dict) else f
        raw.append(frame_to_h36m(points))
    seq = np.stack(raw, axis=0) if raw else np.zeros((0, NUM_JOINTS, 3), np.float32)
    if seq.shape[0] == 0:
        return seq
    seq = _fill_gaps(seq)
    seq = crop_scale(seq, scale_range=[1, 1])  # MotionBERT's exact 2D normalizer -> [-1,1]
    seq = seq.astype(np.float32)
    if mirror:
        seq[..., 0] *= -1.0
        seq[..., H36M_LEFT + H36M_RIGHT, :] = seq[..., H36M_RIGHT + H36M_LEFT, :]
    return seq


def coverage(seq_h36m: np.ndarray) -> dict:
    """Per-joint fraction of frames with confidence > 0, for diagnostics."""
    if seq_h36m.shape[0] == 0:
        return {n: 0.0 for n in H36M_NAMES}
    frac = (seq_h36m[..., 2] != 0).mean(axis=0)
    return {H36M_NAMES[j]: round(float(frac[j]), 3) for j in range(NUM_JOINTS)}


# H36M skeleton bones, for debug rendering.
H36M_BONES = [
    (0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6),
    (0, 7), (7, 8), (8, 9), (9, 10),
    (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16),
]
