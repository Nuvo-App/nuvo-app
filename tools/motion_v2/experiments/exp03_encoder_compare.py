#!/usr/bin/env python
"""STEP 5 cont. — compare pretrained-encoder variants for representation quality.

  lite_pretrain  : MB_lite backbone, pretrained (2D->3D + masked reconstruction)
  release_action : full MB_release backbone, fine-tuned on NTU-60 action
                   recognition (its rep is optimized to separate *actions*)

Runs the exp01 separation harness (synthetic corpus, 3 classes, speed/mirror/
noise/dropout nuisance) on each, all strategies. Winner = highest LOO 3-shot
accuracy then separation.

    python tools/motion_v2/experiments/exp03_encoder_compare.py
"""
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
import mb_encoder  # noqa: E402
from experiments.exp01_representation import build_corpus, evaluate  # noqa: E402

REPORT = os.path.join(_HERE, "..", "reports", "03-encoder-compare.md")
VARIANTS = ["lite_pretrain", "release_action"]


def main():
    t0 = time.time()
    lines = ["# Motion V2 — STEP 5: encoder variant comparison (synthetic)", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M')}. Same synthetic corpus + "
             "nuisance as exp01. `sep` = separation in pooled sd; `acc` = leave-one-out "
             "3-shot accuracy.", ""]
    best_overall = None
    for v in VARIANTS:
        mb_encoder.set_variant(v)
        info = mb_encoder.encoder_info()
        import numpy as np
        np.random.seed(0)
        corpus = build_corpus()
        rows = evaluate(corpus)
        top = max(rows, key=lambda r: (r["loo_3shot_acc"], r["separation_sd"]))
        lines += [f"## {v}  ({info['params_millions']}M params)", "",
                  "| strategy | same | cross | sep (sd) | LOO acc |",
                  "|---|---|---|---|---|"]
        for r in rows[:8]:
            lines.append(f"| {r['strategy']} | {r['same_mean']} | {r['cross_mean']} | "
                         f"{r['separation_sd']} | **{r['loo_3shot_acc']}** |")
        lines += ["", f"best: `{top['strategy']}` acc {top['loo_3shot_acc']} sep {top['separation_sd']}", ""]
        cand = (top["loo_3shot_acc"], top["separation_sd"], v, top["strategy"])
        if best_overall is None or cand > best_overall:
            best_overall = cand
        print(f"{v}: best {top['strategy']} acc={top['loo_3shot_acc']} sep={top['separation_sd']}")

    lines += ["## Decision", "",
              f"**{best_overall[2]} / {best_overall[3]}** — LOO acc {best_overall[0]}, "
              f"sep {best_overall[1]} sd.", "",
              f"_(runtime {time.time()-t0:.0f}s)_"]
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\nwrote", os.path.relpath(REPORT))


if __name__ == "__main__":
    main()
