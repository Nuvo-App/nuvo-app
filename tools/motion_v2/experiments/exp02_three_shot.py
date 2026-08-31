#!/usr/bin/env python
"""STEP 6 + 8 — the 3-shot learner and generic rep detection.

For each synthetic motion: learn from 3 demos, then check
  - match(): unseen same-motion A4 -> is_same_family True; other motion B -> False
  - count_reps(): idle-A-idle-A-idle-A -> 3 ; idle-B-idle -> 0 ; flailing -> 0

    python tools/motion_v2/experiments/exp02_three_shot.py
"""
import os
import sys
import time

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter import synthetic_nuvo as sn  # noqa: E402
from engine.rep_detector import count_reps  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402

REPORT = os.path.join(_HERE, "..", "reports", "02-three-shot.md")

GENS = {"jumping_jack": sn.jumping_jack, "squat": sn.squat, "arm_wave": sn.arm_wave}


def demos_for(name, n=3):
    gen = GENS[name]
    out = []
    for k in range(n):
        T = int(np.random.default_rng(k).integers(38, 56))
        f = gen(T=T, seed=k, translate=(0.02 * (k % 2))) if gen is sn.jumping_jack else gen(T=T, seed=k)
        out.append(sn.idle(T=5, seed=k) + f + sn.idle(T=4, seed=k + 9))
    return out


def unseen(name, seed=99):
    gen = GENS[name]
    T = int(np.random.default_rng(seed).integers(40, 54))
    f = gen(T=T, seed=seed) if gen is not sn.jumping_jack else gen(T=T, seed=seed, translate=0.03)
    return sn.idle(T=6, seed=seed) + f + sn.idle(T=5, seed=seed + 1)


def reps_sequence(name, k, seed=7):
    """idle (A idle) x k"""
    gen = GENS[name]
    seq = sn.idle(T=8, seed=seed)
    for r in range(k):
        T = int(np.random.default_rng(seed + r).integers(38, 52))
        f = gen(T=T, seed=seed + r) if gen is not sn.jumping_jack else gen(T=T, seed=seed + r, translate=0.02)
        seq = seq + f + sn.idle(T=7, seed=seed + 100 + r)
    return seq


def flailing(T=90, seed=42):
    rng = np.random.default_rng(seed)
    frames = []
    base = sn.idle(T=1)[0]["points"]
    for _ in range(T):
        ov = {n: (base[n]["x"] + rng.normal(0, 0.05), base[n]["y"] + rng.normal(0, 0.05))
              for n in base}
        frames.append(sn.idle(T=1)[0])
        for n, (x, y) in ov.items():
            frames[-1]["points"][n] = {"x": x, "y": y, "z": 0.0, "likelihood": 0.9}
    return frames


def main():
    t0 = time.time()
    np.random.seed(0)
    names = list(GENS)
    taught = {}
    for n in names:
        taught[n] = TaughtMotionV2.learn(n, demos_for(n))
        print(f"learned {n}: accept_proto_dist={taught[n].accept_proto_dist:.3f} "
              f"accept_traj_sim={taught[n].accept_traj_sim:.3f} "
              f"demo_lengths={taught[n].demo_lengths}")

    lines = ["# Motion V2 — STEP 6+8: 3-shot learner + generic rep detection (synthetic)", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M')} · MotionBERT-Lite · 3 demos/movement.", ""]

    # ---- match: same-family vs cross ----
    lines += ["## match() — same-family recognition", "",
              "| taught | query | is_same_family | score | proto_dist | traj_sim | coverage |",
              "|---|---|---|---|---|---|---|"]
    match_tp = match_tn = match_fp = match_fn = 0
    for tn in names:
        for qn in names:
            q = unseen(qn)
            m = taught[tn].match(q)
            exp = tn == qn
            ok = m.is_same_family == exp
            if exp and m.is_same_family:
                match_tp += 1
            elif exp and not m.is_same_family:
                match_fn += 1
            elif not exp and m.is_same_family:
                match_fp += 1
            else:
                match_tn += 1
            mark = "" if ok else "  ❌"
            lines.append(f"| {tn} | {qn} | {m.is_same_family} | {m.score:.2f} | "
                         f"{m.proto_dist:.3f} | {m.traj_sim:.3f} | {m.coverage:.2f}{mark} |")
    lines += ["", f"match: TP={match_tp} TN={match_tn} FP={match_fp} FN={match_fn}", ""]

    # ---- rep counting ----
    lines += ["## count_reps() — generic repetition detection", "",
              "| taught | sequence | expected | detected |",
              "|---|---|---|---|"]
    rep_err = 0
    rep_fp = 0
    for tn in names:
        for k in (1, 3, 5):
            got, _ = count_reps(taught[tn], reps_sequence(tn, k))
            rep_err += abs(got - k)
            mark = "" if got == k else "  ⚠"
            lines.append(f"| {tn} | {k}× {tn} | {k} | {got}{mark} |")
        # cross motion -> 0
        other = [x for x in names if x != tn][0]
        gotc, _ = count_reps(taught[tn], reps_sequence(other, 3))
        rep_fp += gotc
        lines.append(f"| {tn} | 3× {other} (wrong) | 0 | {gotc}{'  ❌' if gotc else ''} |")
        # flailing -> 0
        gotf, _ = count_reps(taught[tn], flailing())
        rep_fp += gotf
        lines.append(f"| {tn} | random flailing | 0 | {gotf}{'  ❌' if gotf else ''} |")

    lines += ["", f"rep counting: total abs error over 9 correct sequences = {rep_err}; "
              f"false positives on wrong-motion + flailing = {rep_fp}", "",
              f"_(runtime {time.time() - t0:.1f}s)_"]

    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote", os.path.relpath(REPORT))


if __name__ == "__main__":
    main()
