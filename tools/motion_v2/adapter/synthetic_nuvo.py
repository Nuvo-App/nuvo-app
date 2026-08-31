"""Synthetic Nuvo pose frames (33 BlazePose landmarks) for tests + experiments,
until real device fixtures land. Image-normalized coords (x,y in [0,1], y-down),
`likelihood` per point.
"""
from __future__ import annotations

import numpy as np

# 33 BlazePose landmark names (Nuvo camelCase convention).
NUVO_NAMES = [
    "nose", "leftEyeInner", "leftEye", "leftEyeOuter", "rightEyeInner", "rightEye",
    "rightEyeOuter", "leftEar", "rightEar", "leftMouth", "rightMouth",
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist",
    "leftPinky", "rightPinky", "leftIndex", "rightIndex", "leftThumb", "rightThumb",
    "leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle",
    "leftHeel", "rightHeel", "leftFootIndex", "rightFootIndex",
]

# rest pose in image coords, standing centred, y-down.
_REST = {
    "nose": (0.50, 0.16), "leftEye": (0.52, 0.15), "rightEye": (0.48, 0.15),
    "leftEar": (0.54, 0.16), "rightEar": (0.46, 0.16),
    "leftMouth": (0.51, 0.18), "rightMouth": (0.49, 0.18),
    "leftShoulder": (0.60, 0.28), "rightShoulder": (0.40, 0.28),
    "leftElbow": (0.64, 0.42), "rightElbow": (0.36, 0.42),
    "leftWrist": (0.66, 0.56), "rightWrist": (0.34, 0.56),
    "leftHip": (0.56, 0.55), "rightHip": (0.44, 0.55),
    "leftKnee": (0.56, 0.75), "rightKnee": (0.44, 0.75),
    "leftAnkle": (0.56, 0.93), "rightAnkle": (0.44, 0.93),
    "leftHeel": (0.55, 0.95), "rightHeel": (0.45, 0.95),
    "leftFootIndex": (0.58, 0.96), "rightFootIndex": (0.42, 0.96),
}
for _n in ("leftEyeInner", "leftEyeOuter", "rightEyeInner", "rightEyeOuter"):
    _REST[_n] = _REST["leftEye"] if _n.startswith("left") else _REST["rightEye"]
for _n in ("leftPinky", "leftIndex", "leftThumb"):
    _REST[_n] = _REST["leftWrist"]
for _n in ("rightPinky", "rightIndex", "rightThumb"):
    _REST[_n] = _REST["rightWrist"]


def _frame(overrides: dict, conf=0.95, drop: set[str] | None = None) -> dict:
    drop = drop or set()
    pts = {}
    for n in NUVO_NAMES:
        x, y = overrides.get(n, _REST[n])
        pts[n] = {"x": float(x), "y": float(y), "z": 0.0,
                  "likelihood": 0.0 if n in drop else float(conf)}
    return {"points": pts, "imageWidth": 720.0, "imageHeight": 1280.0}


def jumping_jack(T=48, seed=0, translate=0.0, drop_face=False) -> list[dict]:
    """Arms up + legs out on the beat, back to rest. One full cycle per ~T/1."""
    rng = np.random.default_rng(seed)
    frames = []
    drop = {"leftEar", "rightEar", "leftMouth", "rightMouth"} if drop_face else set()
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)  # 0..1..0
        ov = {}
        # arms sweep up to overhead
        ov["leftWrist"] = (0.66 - 0.18 * ph, 0.56 - 0.44 * ph)
        ov["rightWrist"] = (0.34 + 0.18 * ph, 0.56 - 0.44 * ph)
        ov["leftElbow"] = (0.64 - 0.10 * ph, 0.42 - 0.20 * ph)
        ov["rightElbow"] = (0.36 + 0.10 * ph, 0.42 - 0.20 * ph)
        # legs out
        ov["leftAnkle"] = (0.56 + 0.10 * ph, 0.93)
        ov["rightAnkle"] = (0.44 - 0.10 * ph, 0.93)
        ov["leftKnee"] = (0.56 + 0.06 * ph, 0.75)
        ov["rightKnee"] = (0.44 - 0.06 * ph, 0.75)
        tx = translate * np.sin(2 * np.pi * i / max(T, 1))
        ov = {k: (v[0] + tx + rng.normal(0, 0.004), v[1] + rng.normal(0, 0.004))
              for k, v in ov.items()}
        frames.append(_frame(ov, drop=drop))
    return frames


def squat(T=48, seed=1) -> list[dict]:
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)
        d = 0.16 * ph  # hips/knees drop
        ov = {
            "leftHip": (0.56, 0.55 + d), "rightHip": (0.44, 0.55 + d),
            "leftKnee": (0.58, 0.75 + 0.02 * ph), "rightKnee": (0.42, 0.75 + 0.02 * ph),
            "leftShoulder": (0.60, 0.28 + d), "rightShoulder": (0.40, 0.28 + d),
            "leftWrist": (0.56, 0.40 + d), "rightWrist": (0.44, 0.40 + d),
            "leftElbow": (0.58, 0.34 + d), "rightElbow": (0.42, 0.34 + d),
            "nose": (0.50, 0.16 + d),
        }
        ov = {k: (v[0] + rng.normal(0, 0.004), v[1] + rng.normal(0, 0.004)) for k, v in ov.items()}
        frames.append(_frame(ov))
    return frames


def arm_wave(T=48, seed=2) -> list[dict]:
    """Right arm waves side to side; rest of body still."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        s = np.sin(2 * np.pi * i / T)
        ov = {
            "rightWrist": (0.34 + 0.10 * s, 0.30 + 0.04 * abs(s)),
            "rightElbow": (0.36 + 0.05 * s, 0.38),
        }
        ov = {k: (v[0] + rng.normal(0, 0.003), v[1] + rng.normal(0, 0.003)) for k, v in ov.items()}
        frames.append(_frame(ov))
    return frames


def idle(T=20, seed=3) -> list[dict]:
    rng = np.random.default_rng(seed)
    return [_frame({n: (_REST[n][0] + rng.normal(0, 0.003), _REST[n][1] + rng.normal(0, 0.003))
                    for n in _REST}) for _ in range(T)]
