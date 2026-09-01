#!/usr/bin/env python
"""Golden parity data for the Dart port. Small enough to commit.

  test/fixtures/motion_v2_golden.json
    demos/test/other  : wire frames (input)
    h36m_*            : framesToH36m(...) -> adapter parity target (T x 51, 4dp)
    spec             : the learned TaughtMotionV2Spec Dart must reproduce from
                       the same encoder reps
    match_test/other : the decisions Dart must reproduce

  test/fixtures/motion_v2_math_golden.json
    tiny hand-made reps + expected meanPool / dtw / resample / learn / match
    outputs — isolates the Dart math from the (separately-proven) encoder.
"""
import json
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
import mb_encoder  # noqa: E402
from adapter.nuvo_to_h36m import frames_to_h36m  # noqa: E402
from adapter import synthetic_nuvo as sn  # noqa: E402
from engine.taught_motion import (  # noqa: E402
    CANON_LEN, TaughtMotionV2, segment_action, traj_distance,
)
from experiments.lib_repr import (  # noqa: E402
    _l2n, dtw_distance, mean_pool, per_frame_embedding, resample_seq,
)
from fixtures.load import _frame_to_nuvo  # noqa: E402

OUT = os.path.join(_HERE, "..", "..", "..", "test", "fixtures", "motion_v2_golden.json")
OUT_MATH = os.path.join(_HERE, "..", "..", "..", "test", "fixtures", "motion_v2_math_golden.json")


def invented(T, seed):
    rng = np.random.default_rng(seed)
    out = []
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)
        ov = {
            "leftElbow": (0.64 + 0.16 * ph, 0.36 - 0.03 * ph),
            "leftWrist": (0.72 + 0.14 * ph, 0.42 - 0.14 * ph),
            "rightWrist": (0.52 - 0.20 * ph, 0.30 - 0.02 * ph),
            "rightElbow": (0.44 - 0.07 * ph, 0.37 - 0.01 * ph),
        }
        f = sn.idle(T=1, seed=i)[0]
        for k, (x, y) in ov.items():
            f["points"][k] = {"x": x + rng.normal(0, 0.003), "y": y + rng.normal(0, 0.003),
                              "z": 0.0, "likelihood": 0.95}
        out.append({"t": i * 66, "w": 720.0, "h": 1280.0,
                    "points": {k: [p["x"], p["y"], p["z"], p["likelihood"]]
                               for k, p in f["points"].items()}})
    return out


def wire(frames):
    return [{"t": 0, "w": 720.0, "h": 1280.0,
             "points": {k: [v["x"], v["y"], v["z"], v["likelihood"]] for k, v in f["points"].items()}}
            for f in frames]


def rd(a, dp=4):
    return np.asarray(a, np.float64).round(dp).tolist()


def adapter_golden():
    mb_encoder.set_variant("release_action")
    np.random.seed(0)
    demos_wire = [invented(int(np.random.default_rng(k).integers(40, 52)), k) for k in range(3)]
    test_wire = invented(46, 99)
    other_wire = wire(sn.squat(T=44))

    demos = [[_frame_to_nuvo(f) for f in d] for d in demos_wire]
    test = [_frame_to_nuvo(f) for f in test_wire]
    other = [_frame_to_nuvo(f) for f in other_wire]

    motion = TaughtMotionV2.learn("Golden Motion", demos)
    mt, mo = motion.match(test), motion.match(other)
    spec = motion.to_json()
    # round the big arrays to keep the file small
    spec["prototypes"] = rd(spec["prototypes"], 5)
    spec["canonical"] = rd(spec["canonical"], 5)
    spec["rest_emb"] = rd(spec["rest_emb"], 5)

    g = {
        "demos": demos_wire, "test": test_wire, "other": other_wire,
        "h36m_demo0": rd(frames_to_h36m(demos[0]).reshape(len(demos[0]), -1)),
        "h36m_demo0_mirror": rd(frames_to_h36m(demos[0], mirror=True).reshape(len(demos[0]), -1)),
        "h36m_test": rd(frames_to_h36m(test).reshape(len(test), -1)),
        "spec": spec,
        "match_test": {"is_same": mt.is_same_family, "proto_margin": round(mt.proto_margin, 4),
                       "traj_sim": round(mt.traj_sim, 4)},
        "match_other": {"is_same": mo.is_same_family, "proto_margin": round(mo.proto_margin, 4),
                        "traj_sim": round(mo.traj_sim, 4)},
    }
    with open(OUT, "w") as f:
        json.dump(g, f)
    print(f"{os.path.relpath(OUT)}  {os.path.getsize(OUT)/1024:.0f} KB")
    print("  match_test", g["match_test"], "\n  match_other", g["match_other"])
    assert mt.is_same_family and not mo.is_same_family


def math_golden():
    """Tiny hand-made reps -> exact math outputs, so the Dart port of meanPool /
    per_frame_embedding / resample / dtw / segment / traj_distance / learn /
    match can be asserted without an encoder."""
    # tiny dims — the math is dimension-agnostic; this is a Python<->Dart
    # parity check, not a semantic one.
    rng = np.random.default_rng(7)
    D = 8
    J = 4

    def fake_rep(T, drift, jit):
        base = rng.standard_normal((J, D)) * 0.2
        seq = np.zeros((T, J, D), np.float32)
        for t in range(T):
            ph = t / max(T - 1, 1)
            seq[t] = base + drift * ph + rng.standard_normal((J, D)) * jit
        return seq

    driftA = rng.standard_normal((J, D)) * 0.3
    driftB = rng.standard_normal((J, D)) * 0.3
    demosA = [fake_rep(T, driftA, 0.002) for T in (12, 14, 13)]
    testA = fake_rep(13, driftA, 0.002)
    testB = fake_rep(13, driftB, 0.002)

    def emb(rep):
        return per_frame_embedding(rep)

    # simple math op checks
    r0 = demosA[0]
    mg = {
        "meanPool_in_shape": list(r0.shape),
        "meanPool": rd(mean_pool(r0), 6),
        "perFrameEmbedding_0": rd(emb(r0)[0], 6),
        "resample_len": CANON_LEN,
        "resample_first": rd(resample_seq(_l2n(emb(r0)), CANON_LEN)[0], 6),
        "dtw_self": round(float(dtw_distance(_l2n(emb(r0))[:16], _l2n(emb(r0))[:16])), 6),
        "dtw_cross": round(float(dtw_distance(_l2n(emb(demosA[0]))[:16], _l2n(emb(testB))[:16])), 6),
        "segment_full": list(segment_action(emb(r0))),
    }

    # learn + match on the fake reps (mirror aug OFF so it's deterministic w/o encoder)
    from engine.taught_motion import mean_pool as mp  # noqa
    protos, trajs, rests, lens, vels = [], [], [], [], []
    from engine.taught_motion import embedding_velocity
    for rep in demosA:
        e = emb(rep)
        s, en = segment_action(e)
        if en - s < 4:
            s, en = 0, len(e)
        lens.append(en - s)
        protos.append(mp(rep[s:en]))
        trajs.append(resample_seq(_l2n(e[s:en]), CANON_LEN))
        v = embedding_velocity(e)
        mv = v[s:en]
        vels.append(float(np.median(mv[mv > np.median(mv) * 0.3])) if len(mv) else 0.0)
        low = np.argsort(v)[: max(2, len(v) // 5)]
        rests.append(_l2n(e[low].mean(axis=0)))
    protos = np.stack(protos)
    canonical = _l2n(np.mean(trajs, axis=0), axis=-1)
    rest_emb = _l2n(np.mean(rests, axis=0))
    pd_spread = [np.linalg.norm(protos[i] - protos[j])
                 for i in range(len(protos)) for j in range(i + 1, len(protos))]
    mag = float(np.median(np.linalg.norm(protos, axis=1)))
    apd = float(np.clip(4.0 * (np.mean(pd_spread) if pd_spread else 0.02), 0.04 * mag, 0.15 * mag))
    td_own = [traj_distance(trajs[i], canonical) for i in range(len(trajs))]
    atd = float(np.clip(float(np.median(td_own)) * 3.0 + 5e-4, 1e-3, 0.05))

    def match(rep):
        e = emb(rep)
        s, en = segment_action(e)
        if en - s < 4:
            s, en = 0, len(e)
        pdist = float(np.linalg.norm(protos - mp(rep[s:en]), axis=1).min())
        td = traj_distance(e[s:en], canonical)
        return (pdist / apd <= 1.0 and td / atd <= 1.0, round(pdist / apd, 5), round(td / atd, 5))

    mg["learn"] = {
        "prototypes": rd(protos, 6), "canonical": rd(canonical, 6),
        "rest_emb": rd(rest_emb, 6),
        "accept_proto_dist": round(apd, 6), "accept_traj_dist": round(atd, 6),
        "demo_lengths": [int(x) for x in lens],
    }
    okA, pmA, tmA = match(testA)
    okB, pmB, tmB = match(testB)
    mg["match_A"] = {"is_same": okA, "proto_margin": pmA, "traj_margin": tmA}
    mg["match_B"] = {"is_same": okB, "proto_margin": pmB, "traj_margin": tmB}
    mg["demosA_reps"] = [rd(r, 6) for r in demosA]
    mg["testA_rep"] = rd(testA, 6)
    mg["testB_rep"] = rd(testB, 6)

    with open(OUT_MATH, "w") as f:
        json.dump(mg, f)
    print(f"{os.path.relpath(OUT_MATH)}  {os.path.getsize(OUT_MATH)/1024:.0f} KB")
    print("  match_A", mg["match_A"], "match_B", mg["match_B"])
    _ = (okA, okB)  # parity data only, not a semantic assertion


def main():
    adapter_golden()
    math_golden()
    print("GOLDEN OK")


if __name__ == "__main__":
    main()
