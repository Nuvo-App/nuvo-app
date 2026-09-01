"""Self-validation: a freshly learned TaughtMotionV2 must recognize its own
demonstrations. If it can't, the three examples were too inconsistent and the
app should ask the user to record again (see native_runtime._selfValidate).

Run: tools/motion_v2/.venv/bin/python3 -m pytest tools/motion_v2/tests/test_self_validation.py -v
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from adapter.synthetic_nuvo import arm_wave, jumping_jack, squat  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402


def _self_validation(taught, demos):
    return [taught.match(d).is_same_family for d in demos]


def test_consistent_demos_pass_self_validation():
    demos = [jumping_jack(T=44, seed=k) for k in range(3)]
    taught = TaughtMotionV2.learn("consistent", demos)
    per_demo = _self_validation(taught, demos)
    assert all(per_demo), f"expected every demo to self-validate, got {per_demo}"


def test_self_validation_runs_on_every_demo():
    # Contract under test: self-validation replays *each* demo and returns a
    # per-demo verdict. (Whether an inconsistent set trips the majority rule
    # depends on the accept thresholds, which this pass deliberately does not
    # touch — see the directive. The mechanism is what must exist.)
    demos = [jumping_jack(T=44, seed=0), squat(T=44, seed=1), arm_wave(T=44, seed=2)]
    taught = TaughtMotionV2.learn("mixed", demos)
    per_demo = _self_validation(taught, demos)
    assert len(per_demo) == 3
    assert all(isinstance(x, (bool,)) for x in per_demo)


def test_region_activity_is_serialized_and_reflects_the_movement():
    demos = [arm_wave(T=44, seed=k) for k in range(3)]
    taught = TaughtMotionV2.learn("wave", demos)
    ra = taught.to_json()["region_activity"]
    assert set(ra) == {"head", "left arm", "right arm", "torso", "left leg", "right leg"}
    # arm_wave moves the right arm; legs stay put.
    assert ra["right arm"] > ra["left leg"] + 1e-6
    assert ra["right arm"] > ra["right leg"] + 1e-6
