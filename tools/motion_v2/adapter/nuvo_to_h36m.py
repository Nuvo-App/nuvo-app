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


def root_scale_normalize(seq: np.ndarray) -> tuple[np.ndarray, dict]:
    """Body-relative, camera-distance-invariant 2D normalize.

    1) Subtract the per-frame hip-center root (H36M joint 0) from every joint —
       removes translation from walking, camera drift, or the phone moving.
    2) Divide by a robust anatomical scale: the MEDIAN hip-center -> shoulder-
       center ("torso length") across the sequence — removes camera-distance
       changes (stepping closer/farther) without touching real articulation.
       Median (not per-frame) so a single noisy frame can't rescale the rest.

    Whole-body camera translation/scale drift is discarded here, on purpose —
    it is not part of the taught motion. Real relative articulation (a joint
    moving relative to the torso) survives untouched. Returns diagnostics
    (root drift, scale spread) so a bad camera setup can be flagged without
    ever teaching the drift as the movement.
    """
    root = seq[:, 0, :2]
    root_conf = seq[:, 0, 2]
    neck = seq[:, 8, :2]
    neck_conf = seq[:, 8, 2]

    valid_both = (root_conf > 0) & (neck_conf > 0)
    torso_lengths = np.linalg.norm(neck[valid_both] - root[valid_both], axis=-1)
    torso_lengths = torso_lengths[torso_lengths > 1e-6]
    scale = float(np.median(torso_lengths)) if torso_lengths.size else 1.0
    if scale < 1e-6:
        scale = 1.0

    out = seq.copy()
    have_root = root_conf > 0
    for j in range(NUM_JOINTS):
        m = have_root & (out[:, j, 2] > 0)
        out[m, j, 0] = (out[m, j, 0] - root[m, 0]) / scale
        out[m, j, 1] = (out[m, j, 1] - root[m, 1]) / scale

    valid_root = root[have_root]
    root_drift = (
        float(np.max(np.linalg.norm(valid_root - valid_root[0], axis=-1)))
        if valid_root.shape[0] >= 2 else 0.0
    )
    scale_spread = (
        float((torso_lengths.max() - torso_lengths.min()) / scale)
        if torso_lengths.size >= 2 else 0.0
    )
    diagnostics = {
        "root_translation_magnitude": round(root_drift, 5),
        "scale_change_fraction": round(scale_spread, 5),
        "anatomical_scale": round(scale, 5),
    }
    return out, diagnostics


# A user recording can hold far more frames than MotionBERT needs; a bounded
# sequence keeps encoder cost flat. Must match Dart `kEncodeMaxFrames`.
MAX_FRAMES = 96


def _resample_seq(seq: np.ndarray, target: int) -> np.ndarray:
    """Linear temporal resample of (T, 17, 3) -> (target, 17, 3). Bit-identical
    to Dart `resampleSeq` (linspace + floor/ceil lerp)."""
    T = seq.shape[0]
    if T == target:
        return seq
    idx = np.linspace(0, T - 1, target)
    lo = np.floor(idx).astype(int)
    hi = np.minimum(lo + 1, T - 1)
    w = (idx - lo)[:, None, None]
    return (seq[lo] * (1 - w) + seq[hi] * w).astype(np.float32)


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


def frames_to_h36m(
    frames: Iterable[dict], *, mirror: bool = False, diagnostics: dict | None = None
) -> np.ndarray:
    """List of Nuvo frame dicts -> (T, 17, 3), normalized to [-1,1] for MotionBERT.

    frames: each a dict with a "points" key (name -> {x,y,likelihood}) OR the
            points dict directly.
    mirror: horizontally flip (front-camera). x -> -x after normalization, with
            left/right joints swapped. Off by default; the encoder is compared
            against both orientations downstream.
    diagnostics: if a dict is passed, `root_scale_normalize`'s diagnostics
            (root drift, scale spread) are written into it. Never affects the
            returned array — for camera-quality diagnostics only.

    Pipeline: adapt -> fill short confidence gaps -> subtract per-frame
    hip-center root + divide by the sequence's anatomical scale (camera/body-
    translation and camera-distance invariant) -> MotionBERT's `crop_scale`
    fit into [-1,1]. The encoder sees relative articulated motion, not where
    the person stood in the frame or how close they were to the camera.
    """
    raw = []
    for f in frames:
        points = f.get("points", f) if isinstance(f, dict) else f
        raw.append(frame_to_h36m(points))
    seq = np.stack(raw, axis=0) if raw else np.zeros((0, NUM_JOINTS, 3), np.float32)
    if seq.shape[0] == 0:
        return seq
    seq = _fill_gaps(seq)
    seq, diag = root_scale_normalize(seq)
    if diagnostics is not None:
        diagnostics.update(diag)
    seq = crop_scale(seq, scale_range=[1, 1])  # fit into MotionBERT's [-1,1] envelope
    seq = seq.astype(np.float32)
    if MAX_FRAMES > 0 and seq.shape[0] > MAX_FRAMES:
        seq = _resample_seq(seq, MAX_FRAMES)
    if mirror:
        seq[..., 0] *= -1.0
        seq[..., H36M_LEFT + H36M_RIGHT, :] = seq[..., H36M_RIGHT + H36M_LEFT, :]
    return seq


# h36m joint indices per understandable body region.
H36M_REGIONS = {
    "head": [9, 10],
    "left arm": [11, 12, 13],
    "right arm": [14, 15, 16],
    "torso": [0, 7, 8],
    "left leg": [4, 5, 6],
    "right leg": [1, 2, 3],
}


def region_activity(seq_h36m: np.ndarray) -> dict:
    """Per-region mean frame-to-frame joint travel over an h36m sequence.
    Diagnostics only — tells the failure explainer which region *should* have
    moved. Generic; no per-exercise rules. 1:1 with Dart `regionActivity`."""
    out = {}
    for region, joints in H36M_REGIONS.items():
        total, count = 0.0, 0
        for j in joints:
            prev = None
            for t in range(seq_h36m.shape[0]):
                x, y, c = seq_h36m[t, j]
                if c == 0:
                    continue
                if prev is not None:
                    total += float(np.hypot(x - prev[0], y - prev[1]))
                    count += 1
                prev = (x, y)
        out[region] = (total / count) if count else 0.0
    return out


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
