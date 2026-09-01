"""Motion V2 must be invariant to camera translation/distance, not to real
articulation. Uses the ACTUAL pretrained encoder (not a stand-in) so this is
the authoritative check — the Dart-side test only proves the adapter half.

    embedding(A) ~= embedding(A_shifted) ~= embedding(A_scaled)
    TaughtMotionV2.match(A_shifted) -> True
    TaughtMotionV2.match(A_scaled)  -> True
    TaughtMotionV2.match(different articulation) -> False

Run: tools/motion_v2/.venv/bin/python3 -m pytest tools/motion_v2/tests/test_invariance.py -v
"""
import copy
import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from adapter.nuvo_to_h36m import frames_to_h36m  # noqa: E402
from adapter.synthetic_nuvo import jumping_jack, squat  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402
from mb_encoder import encode  # noqa: E402


def _transform(frames, *, dx=0.0, dy=0.0, scale=1.0):
    """Shift/scale every landmark around the image center — simulates the
    same person standing at a different spot / distance from the camera.
    Real articulation (landmark-to-landmark shape) is untouched."""
    out = []
    for f in frames:
        pts = {}
        for name, p in f["points"].items():
            pts[name] = {
                **p,
                "x": 0.5 + (p["x"] - 0.5) * scale + dx,
                "y": 0.5 + (p["y"] - 0.5) * scale + dy,
            }
        g = copy.deepcopy(f)
        g["points"] = pts
        out.append(g)
    return out


def _cosine(a, b):
    a = a.reshape(-1)
    b = b.reshape(-1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))


@pytest.fixture(scope="module")
def demos():
    return [jumping_jack(T=44, seed=k) for k in range(3)]


@pytest.fixture(scope="module")
def taught(demos):
    return TaughtMotionV2.learn("invariance test move", demos)


def test_embedding_invariant_to_shift_and_scale():
    base = jumping_jack(T=44, seed=9)
    variants = {
        "shifted": _transform(base, dx=0.10, dy=-0.06),
        "closer": _transform(base, scale=1.3),
        "farther": _transform(base, scale=0.75),
        "shift+scale": _transform(base, dx=-0.08, dy=0.05, scale=1.15),
    }
    h_base = frames_to_h36m(base)
    rep_base = encode(h_base)
    emb_base = rep_base.mean(axis=1)  # (T, 512) per-frame embedding (mean over joints)

    for label, frames in variants.items():
        h = frames_to_h36m(frames)
        rep = encode(h)
        emb = rep.mean(axis=1)
        sim = _cosine(emb_base.mean(axis=0), emb.mean(axis=0))
        assert sim > 0.995, f"{label}: mean-embedding cosine similarity too low ({sim:.4f})"


def test_taught_motion_recognizes_shifted_and_scaled_performance(taught):
    base_test = jumping_jack(T=44, seed=42)
    for label, frames in {
        "same position": base_test,
        "shifted right": _transform(base_test, dx=0.12),
        "shifted up": _transform(base_test, dy=-0.08),
        "stepped closer": _transform(base_test, scale=1.3),
        "stepped back": _transform(base_test, scale=0.7),
        "shifted + closer": _transform(base_test, dx=0.06, scale=1.2),
    }.items():
        result = taught.match(frames)
        assert result.is_same_family, (
            f"{label}: expected match, got is_same_family=False "
            f"(proto_margin={result.proto_margin:.3f}, traj_sim={result.traj_sim:.3f})"
        )


def test_taught_motion_rejects_different_articulation_at_same_position(taught):
    different = squat(T=44, seed=5)
    result = taught.match(different)
    assert not result.is_same_family, (
        f"expected reject, got is_same_family=True "
        f"(proto_margin={result.proto_margin:.3f}, traj_sim={result.traj_sim:.3f})"
    )


def test_taught_motion_rejects_different_articulation_even_when_also_shifted(taught):
    different = _transform(squat(T=44, seed=6), dx=0.1, scale=1.2)
    result = taught.match(different)
    assert not result.is_same_family, (
        "camera-distance invariance must not make an unrelated movement match "
        f"(proto_margin={result.proto_margin:.3f}, traj_sim={result.traj_sim:.3f})"
    )
