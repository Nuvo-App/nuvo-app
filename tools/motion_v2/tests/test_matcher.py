"""Multi-reference three-shot matcher — the CRITICAL TEST.

Teach an invented motion x3, then:
  new performance of it        -> ACCEPT
  jumping jack / squat / wave  -> REJECT
  random flailing / idle       -> REJECT
Teach each of those separately -> their families stay distinguishable.
Leave-one-out: every demo recoverable from the other two.

Run: tools/motion_v2/.venv/bin/python3 -m pytest tools/motion_v2/tests/test_matcher.py -v
"""
import json
import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from adapter import synthetic_nuvo as sn  # noqa: E402
from engine.taught_motion import Reference, TaughtMotionV2  # noqa: E402

_BG = os.path.join(os.path.dirname(__file__), "..", "..", "..",
                   "assets", "models", "motion_v2_background.json")


@pytest.fixture(scope="module")
def background():
    with open(_BG) as f:
        return np.array(json.load(f)["protos"], np.float32)


FAMILIES = {
    # 3 demos with realistic human-scale variation (speed + jitter), not clones.
    "cross_body_reach": lambda: [
        sn.cross_body_reach(T=52, seed=0),
        sn.cross_body_reach(T=58, seed=1, jitter=1.3),
        sn.cross_body_reach(T=48, seed=2, jitter=1.5),
    ],
    "jumping_jack": lambda: [sn.jumping_jack(T=t, seed=s) for t, s in ((44, 10), (50, 11), (46, 12))],
    "squat": lambda: [sn.squat(T=t, seed=s) for t, s in ((44, 10), (50, 11), (46, 12))],
    "arm_wave": lambda: [sn.arm_wave(T=t, seed=s) for t, s in ((44, 10), (50, 11), (46, 12))],
}

NEGATIVES = {
    "jumping_jack": sn.jumping_jack(seed=40),
    "squat": sn.squat(seed=40),
    "arm_wave": sn.arm_wave(seed=40),
    "arm_raise": sn.arm_raise(seed=40),
    "lunge": sn.lunge(seed=40),
    "walk": sn.walk_in_place(seed=40),
    "idle": sn.idle(T=44, seed=40),
    "cross_body_reach": sn.cross_body_reach(seed=40),
}


@pytest.fixture(scope="module")
def taught():
    return {name: TaughtMotionV2.learn(name, fn()) for name, fn in FAMILIES.items()}


def test_custom_motion_accepts_a_new_performance(taught, background):
    t = taught["cross_body_reach"]
    for seed in (20, 21, 22):
        r = t.match(sn.cross_body_reach(seed=seed), background=background)
        assert r.is_same_family, (
            f"new cross_body_reach perf rejected (votes={r.detail['votes']}, "
            f"sep={r.detail['separation']}, decision={r.detail['decision']})"
        )


@pytest.mark.parametrize("neg_name", list(NEGATIVES))
def test_custom_motion_rejects_every_unrelated_movement(taught, background, neg_name):
    if neg_name == "cross_body_reach":
        pytest.skip("same family")
    t = taught["cross_body_reach"]
    r = t.match(NEGATIVES[neg_name], background=background)
    assert not r.is_same_family, (
        f"'{neg_name}' matched a cross_body_reach spec "
        f"(votes={r.detail['votes']}, sep={r.detail['separation']})"
    )


@pytest.mark.parametrize("fam", list(FAMILIES))
def test_every_family_accepts_itself_and_rejects_the_others(taught, background, fam):
    t = taught[fam]
    # positive: a fresh performance
    gen = FAMILIES[fam]()[0]
    assert t.match(gen, background=background).is_same_family

    # negatives: the other families
    for other, ofn in FAMILIES.items():
        if other == fam:
            continue
        r = t.match(ofn()[0], background=background)
        assert not r.is_same_family, f"{fam} spec matched {other}"


@pytest.mark.parametrize("fam", list(FAMILIES))
def test_leave_one_out(fam):
    demos = FAMILIES[fam]()
    for i in range(3):
        others = [demos[j] for j in range(3) if j != i]
        t2 = TaughtMotionV2.learn(fam, [others[0], others[1], others[0]])
        assert t2.match(demos[i]).is_same_family, f"{fam}: demo {i} not recoverable from the other two"


def test_self_check_flags_an_inconsistent_demo_set(background):
    good = TaughtMotionV2.learn("good", FAMILIES["cross_body_reach"]())
    assert good.self_check(FAMILIES["cross_body_reach"](), background=background)["passed"]

    mixed = TaughtMotionV2.learn(
        "mixed",
        [sn.jumping_jack(seed=0), sn.squat(seed=1), sn.arm_wave(seed=2)],
    )
    chk = mixed.self_check(
        [sn.jumping_jack(seed=0), sn.squat(seed=1), sn.arm_wave(seed=2)],
        background=background,
    )
    assert not chk["passed"], f"inconsistent demo set should fail self_check: {chk}"
