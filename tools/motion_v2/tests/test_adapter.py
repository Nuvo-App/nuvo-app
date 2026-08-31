import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from adapter.nuvo_to_h36m import (  # noqa: E402
    H36M_LEFT,
    H36M_RIGHT,
    NUM_JOINTS,
    coverage,
    frames_to_h36m,
)
from adapter.synthetic_nuvo import arm_wave, idle, jumping_jack, squat  # noqa: E402


def test_shape_and_range():
    seq = frames_to_h36m(jumping_jack(T=40))
    assert seq.shape == (40, NUM_JOINTS, 3)
    assert np.isfinite(seq).all()
    # x,y normalized to [-1, 1]
    assert seq[..., :2].min() >= -1.0001 and seq[..., :2].max() <= 1.0001


def test_all_core_joints_covered_for_clean_input():
    cov = coverage(frames_to_h36m(squat(T=30)))
    for name in ("root", "lsho", "rsho", "lhip", "rhip", "lknee", "lwri", "neck"):
        assert cov[name] == 1.0, (name, cov)


def test_missing_face_landmarks_do_not_break_body():
    seq = frames_to_h36m(jumping_jack(T=30, drop_face=True))
    cov = coverage(seq)
    # ears dropped -> head may fall back to nose-extrapolation, still present
    assert cov["nose"] == 1.0
    assert cov["lwri"] == 1.0 and cov["rwri"] == 1.0
    assert np.isfinite(seq).all()


def test_translation_invariance():
    """Same movement centred vs drifting across frame -> nearly identical after
    sequence-level crop_scale (bbox is over the whole clip, so a slow global
    drift changes it, but a small oscillation should barely matter)."""
    a = frames_to_h36m(jumping_jack(T=40, seed=7, translate=0.0))
    b = frames_to_h36m(jumping_jack(T=40, seed=7, translate=0.03))
    # joints that actually move (wrists/ankles) will differ; torso should be close
    torso = [0, 7, 8, 11, 14]  # root, belly, neck, lsho, rsho
    d = np.abs(a[:, torso, :2] - b[:, torso, :2]).mean()
    assert d < 0.05, d


def test_mirror_swaps_left_right():
    seq = frames_to_h36m(arm_wave(T=24))
    mir = frames_to_h36m(arm_wave(T=24), mirror=True)
    # mirrored right-wrist x ≈ -1 * original left-wrist x (roles swapped)
    assert np.allclose(mir[:, H36M_LEFT, 0], -seq[:, H36M_RIGHT, 0], atol=1e-4)
    assert np.allclose(mir[:, H36M_RIGHT, 0], -seq[:, H36M_LEFT, 0], atol=1e-4)


def test_confidence_gap_interpolation():
    frames = jumping_jack(T=20)
    # knock out the left wrist for 3 middle frames
    for i in (9, 10, 11):
        frames[i]["points"]["leftWrist"]["likelihood"] = 0.0
    seq = frames_to_h36m(frames)
    assert np.isfinite(seq).all()
    assert coverage(seq)["lwri"] == 1.0  # gap filled


def test_empty_input():
    assert frames_to_h36m([]).shape == (0, NUM_JOINTS, 3)


@pytest.mark.parametrize("gen", [jumping_jack, squat, arm_wave, idle])
def test_all_generators_produce_valid_sequences(gen):
    seq = frames_to_h36m(gen(T=24))
    assert seq.shape[0] == 24 and np.isfinite(seq).all()
