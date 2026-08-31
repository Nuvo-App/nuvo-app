#!/usr/bin/env python
"""STEP 5 — does the pretrained encoder's representation separate same-motion
from different-motion?

Builds a small synthetic corpus: several motion classes, each recorded multiple
times with realistic nuisance variation (speed, translation, mirror, noise,
dropped joints). For every (reducer x distance) strategy and the sequence-DTW
strategy, reports:

  - same-motion mean distance   (lower = better)
  - cross-motion mean distance
  - separation  = cross_mean - same_mean   (normalized by pooled std)
  - LOO 3-shot accuracy: hold one recording out, match to the nearest
    per-class prototype (mean of the other recordings of each class).

Synthetic is a plumbing + shortlist check. Real device fixtures (STEP 4) are the
real eval and reuse this exact harness.

    python tools/motion_v2/experiments/exp01_representation.py
"""
import json
import os
import sys
import time

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter.nuvo_to_h36m import frames_to_h36m  # noqa: E402
from adapter import synthetic_nuvo as sn  # noqa: E402
from mb_encoder import encode  # noqa: E402
from experiments.lib_repr import DISTANCES, REDUCERS, seq_dtw_dist  # noqa: E402

REPORT = os.path.join(_HERE, "..", "reports", "01-representation.md")


def build_corpus(recordings_per_class=6):
    """class -> list of MotionBERT reps (T,17,512)."""
    gens = {"jumping_jack": sn.jumping_jack, "squat": sn.squat, "arm_wave": sn.arm_wave}
    corpus = {}
    for name, gen in gens.items():
        reps = []
        for k in range(recordings_per_class):
            T = int(np.random.default_rng(100 + k).integers(36, 60))   # speed variation
            translate = [0.0, 0.02, 0.04, 0.0, 0.03, 0.0][k % 6]
            mirror = k % 3 == 2                                         # some front-camera
            drop_face = k % 4 == 3
            frames = gen(T=T, seed=k, translate=translate) if gen is sn.jumping_jack \
                else gen(T=T, seed=k)
            # simulate idle padding before/after (no "hold still" assumption)
            frames = sn.idle(T=6, seed=k) + frames + sn.idle(T=5, seed=k + 1)
            h = frames_to_h36m(frames, mirror=mirror)
            reps.append(encode(h))
        corpus[name] = reps
    return corpus


def evaluate(corpus):
    classes = list(corpus)
    results = []

    # ---- descriptor strategies -------------------------------------------
    for rname, reducer in REDUCERS.items():
        desc = {c: [reducer(r) for r in reps] for c, reps in corpus.items()}
        for dname, dist in DISTANCES.items():
            same, cross = [], []
            for c in classes:
                v = desc[c]
                for i in range(len(v)):
                    for j in range(i + 1, len(v)):
                        same.append(dist(v[i], v[j]))
                for c2 in classes:
                    if c2 == c:
                        continue
                    for a in desc[c]:
                        for b in desc[c2]:
                            cross.append(dist(a, b))
            acc = loo_accuracy(desc, dist)
            results.append(_row(f"{rname} / {dname}", same, cross, acc))

    # ---- sequence DTW strategy -----------------------------------------
    same, cross = [], []
    for c in classes:
        reps = corpus[c]
        for i in range(len(reps)):
            for j in range(i + 1, len(reps)):
                same.append(seq_dtw_dist(reps[i], reps[j]))
        for c2 in classes:
            if c2 == c:
                continue
            for a in corpus[c]:
                for b in corpus[c2]:
                    cross.append(seq_dtw_dist(a, b))
    acc = loo_accuracy_seq(corpus)
    results.append(_row("per_frame_emb / dtw", same, cross, acc))

    results.sort(key=lambda r: -r["separation_sd"])
    return results


def _row(name, same, cross, acc):
    same, cross = np.array(same), np.array(cross)
    pooled_sd = np.sqrt(0.5 * (same.var() + cross.var())) + 1e-9
    return {
        "strategy": name,
        "same_mean": round(float(same.mean()), 4),
        "cross_mean": round(float(cross.mean()), 4),
        "separation": round(float(cross.mean() - same.mean()), 4),
        "separation_sd": round(float((cross.mean() - same.mean()) / pooled_sd), 3),
        "loo_3shot_acc": round(acc, 3),
    }


def loo_accuracy(desc, dist):
    classes = list(desc)
    correct = total = 0
    for c in classes:
        n = len(desc[c])
        for held in range(n):
            protos = {}
            for cc in classes:
                pool = [desc[cc][k] for k in range(len(desc[cc])) if not (cc == c and k == held)]
                if cc == c:
                    pool = [desc[c][k] for k in range(n) if k != held]
                protos[cc] = np.mean(pool, axis=0)
            q = desc[c][held]
            pred = min(protos, key=lambda k: dist(q, protos[k]))
            correct += pred == c
            total += 1
    return correct / total


def loo_accuracy_seq(corpus):
    classes = list(corpus)
    correct = total = 0
    for c in classes:
        n = len(corpus[c])
        for held in range(n):
            refs = {cc: [corpus[cc][k] for k in range(len(corpus[cc]))
                         if not (cc == c and k == held)] for cc in classes}
            q = corpus[c][held]
            # nearest by mean DTW to that class's references (multi-reference match)
            pred = min(classes, key=lambda cc: np.mean([seq_dtw_dist(q, r) for r in refs[cc]]))
            correct += pred == c
            total += 1
    return correct / total


def main():
    t0 = time.time()
    np.random.seed(0)
    print("encoding synthetic corpus ...")
    corpus = build_corpus()
    n = sum(len(v) for v in corpus.values())
    print(f"  {len(corpus)} classes x ~{n // len(corpus)} recordings = {n} reps")
    rows = evaluate(corpus)

    lines = [
        "# Motion V2 — STEP 5: representation separation (synthetic corpus)",
        "",
        f"Generated {time.strftime('%Y-%m-%d %H:%M')} · MotionBERT-Lite pretrained backbone · "
        f"{n} synthetic recordings, {len(corpus)} classes, nuisance = speed/translation/mirror/noise/dropout.",
        "",
        "`separation_sd` = (cross_mean_dist - same_mean_dist) / pooled_sd. "
        "> ~0.8 is a usable signal; `loo_3shot_acc` is the money metric "
        "(hold one recording out, match to nearest 3-shot prototype).",
        "",
        "| strategy | same_dist | cross_dist | sep (sd) | LOO 3-shot acc |",
        "|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append(
            f"| {r['strategy']} | {r['same_mean']} | {r['cross_mean']} | "
            f"{r['separation_sd']} | **{r['loo_3shot_acc']}** |"
        )
    best = max(rows, key=lambda r: (r["loo_3shot_acc"], r["separation_sd"]))
    lines += [
        "",
        f"**Best:** `{best['strategy']}` — LOO 3-shot acc {best['loo_3shot_acc']}, "
        f"separation {best['separation_sd']} sd.",
        "",
        f"_(runtime {time.time() - t0:.1f}s)_",
    ]
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote", os.path.relpath(REPORT))
    # machine-readable
    with open(REPORT.replace(".md", ".json"), "w") as f:
        json.dump(rows, f, indent=2)


if __name__ == "__main__":
    main()
