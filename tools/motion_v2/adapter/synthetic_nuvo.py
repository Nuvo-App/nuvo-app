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


def _noise(ov, rng, sd=0.004):
    return {k: (v[0] + rng.normal(0, sd), v[1] + rng.normal(0, sd)) for k, v in ov.items()}


def arm_raise(T=48, seed=4, jitter=1.0) -> list[dict]:
    """Both arms raise forward/up to shoulder height and back down."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)
        ov = {
            "leftWrist": (0.62, 0.56 - 0.26 * ph),
            "rightWrist": (0.38, 0.56 - 0.26 * ph),
            "leftElbow": (0.61, 0.42 - 0.12 * ph),
            "rightElbow": (0.39, 0.42 - 0.12 * ph),
        }
        frames.append(_frame(_noise(ov, rng, 0.004 * jitter)))
    return frames


def lunge(T=48, seed=5) -> list[dict]:
    """Step forward into a lunge (front knee bends, torso drops) and return."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)
        d = 0.14 * ph
        ov = {
            "leftKnee": (0.58 + 0.05 * ph, 0.75 + 0.02 * ph),
            "leftAnkle": (0.60 + 0.10 * ph, 0.93),
            "rightKnee": (0.44, 0.75 + d),
            "leftHip": (0.56, 0.55 + d * 0.6),
            "rightHip": (0.44, 0.55 + d * 0.6),
            "nose": (0.50, 0.16 + d * 0.5),
            "leftShoulder": (0.60, 0.28 + d * 0.5),
            "rightShoulder": (0.40, 0.28 + d * 0.5),
        }
        frames.append(_frame(_noise(ov, rng)))
    return frames


def walk_in_place(T=48, seed=6) -> list[dict]:
    """March in place — alternating knee lifts, small arm swing."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        s = np.sin(2 * np.pi * i / (T / 2))
        ov = {
            "leftKnee": (0.56, 0.75 - 0.10 * max(0, s)),
            "leftAnkle": (0.56, 0.93 - 0.14 * max(0, s)),
            "rightKnee": (0.44, 0.75 - 0.10 * max(0, -s)),
            "rightAnkle": (0.44, 0.93 - 0.14 * max(0, -s)),
            "leftWrist": (0.66, 0.56 - 0.05 * s),
            "rightWrist": (0.34, 0.56 + 0.05 * s),
        }
        frames.append(_frame(_noise(ov, rng, 0.003)))
    return frames


def cross_body_reach(T=52, seed=7, jitter=1.0, speed=1.0) -> list[dict]:
    """An invented 'weird' motion: left arm out to the side, right hand crosses
    to the left shoulder, both arms open wide, return. Distinct from presets."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        p = (i / max(T - 1, 1)) * speed
        p = min(p, 1.0)
        # 0..0.33 left arm out ; 0.33..0.66 right crosses ; 0.66..1 both wide
        if p < 0.34:
            ph = p / 0.34
            ov = {"leftWrist": (0.66 + 0.16 * ph, 0.56 - 0.20 * ph),
                  "leftElbow": (0.64 + 0.08 * ph, 0.42 - 0.06 * ph)}
        elif p < 0.67:
            ph = (p - 0.34) / 0.33
            ov = {"leftWrist": (0.82, 0.36),
                  "rightWrist": (0.34 + 0.26 * ph, 0.56 - 0.28 * ph),
                  "rightElbow": (0.36 + 0.12 * ph, 0.42 - 0.06 * ph)}
        else:
            ph = (p - 0.67) / 0.33
            ov = {"leftWrist": (0.82 + 0.04 * ph, 0.36 - 0.04 * ph),
                  "rightWrist": (0.60 - 0.42 * ph, 0.28 + 0.08 * ph),
                  "rightElbow": (0.48 - 0.12 * ph, 0.36 + 0.02 * ph)}
        frames.append(_frame(_noise(ov, rng, 0.004 * jitter)))
    return frames
