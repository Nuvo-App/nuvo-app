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
    for ref in spec["references"]:
        ref["proto"] = rd(ref["proto"], 5)
        ref["traj"] = rd(ref["traj"], 5)
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

    # Multi-reference learn + match on the fake reps (schema 4). No encoder, no
    # background bank -> the separation-rescue path is off, decision = 2-of-3.
    from engine.taught_motion import (  # noqa
        DTW_BAND, PROTO_FLOOR, TRAJ_FLOOR, VOTE_K, Reference, embedding_velocity,
        mean_pool as mp,
    )
    refs, rests, lens, vels = [], [], [], []
    for rep in demosA:
        e = emb(rep)
        s, en = segment_action(e)
        if en - s < 4:
            s, en = 0, len(e)
        lens.append(en - s)
        refs.append(Reference(mp(rep[s:en]), resample_seq(_l2n(e[s:en]), CANON_LEN), en - s))
        v = embedding_velocity(e)
        mv = v[s:en]
        vels.append(float(np.median(mv[mv > np.median(mv) * 0.3])) if len(mv) else 0.0)
        low = np.argsort(v)[: max(2, len(v) // 5)]
        rests.append(_l2n(e[low].mean(axis=0)))
    rest_emb = _l2n(np.mean(rests, axis=0))
    pd_pairs = [float(np.linalg.norm(refs[i].proto - refs[j].proto))
                for i in range(len(refs)) for j in range(i + 1, len(refs))]
    td_pairs = [float(dtw_distance(refs[i].traj, refs[j].traj, band=DTW_BAND))
                for i in range(len(refs)) for j in range(i + 1, len(refs))]
    proto_spread = float(np.median(pd_pairs))
    traj_spread = float(np.median(td_pairs))
    ps = max(proto_spread, PROTO_FLOOR)
    ts = max(traj_spread, TRAJ_FLOOR)

    def match(rep):
        e = emb(rep)
        s, en = segment_action(e)
        if en - s < 4:
            s, en = 0, len(e)
        desc = mp(rep[s:en])
        pms, tms = [], []
        for ref in refs:
            pms.append(float(np.linalg.norm(ref.proto - desc)) / ps)
            tms.append(traj_distance(e[s:en], ref.traj, band=DTW_BAND) / ts)
        votes = sum(1 for pm, tm in zip(pms, tms) if pm <= VOTE_K and tm <= VOTE_K)
        return (votes >= 2, round(min(pms), 5), round(min(tms), 5), votes)

    mg["learn"] = {
        "references": [{"proto": rd(r.proto, 6), "traj": rd(r.traj, 6),
                        "length": int(r.length)} for r in refs],
        "rest_emb": rd(rest_emb, 6),
        "proto_spread": round(proto_spread, 6), "traj_spread": round(traj_spread, 6),
        "proto_spread_max": round(float(np.max(pd_pairs)), 6),
        "traj_spread_max": round(float(np.max(td_pairs)), 6),
        "demo_lengths": [int(x) for x in lens],
    }
    okA, pmA, tmA, vA = match(testA)
    okB, pmB, tmB, vB = match(testB)
    mg["match_A"] = {"is_same": okA, "proto_margin": pmA, "traj_margin": tmA, "votes": vA}
    mg["match_B"] = {"is_same": okB, "proto_margin": pmB, "traj_margin": tmB, "votes": vB}
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
