#!/usr/bin/env python
"""Run the V2 pipeline on REAL device captures (tools/motion_v2/fixtures/*.json).

Capture fixtures via Teach Nuvo (run the app with --dart-define=NUVO_DIAGNOSTICS=
true), teach a movement, open the debug panel, "Copy debug report", save the
JSON as tools/motion_v2/fixtures/<movement>_<n>.json. Need >= 2 movements to
measure cross-rejection; a `<movement>_reps<k>.json` (one demo of k reps) also
runs rep detection.

    python tools/motion_v2/experiments/exp10_real.py
"""
import os
import sys
import time

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from engine.rep_detector import count_reps  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402
from fixtures.load import load_all  # noqa: E402

REPORT = os.path.join(_HERE, "..", "reports", "10-real.md")


def main():
    t0 = time.time()
    fx = load_all()
    reps_fx = [f for f in fx if "reps" in os.path.basename(f["path"]).lower()]
    train_fx = [f for f in fx if f not in reps_fx]
    if len(train_fx) < 1:
        print("no training fixtures found. See this script's docstring.")
        return

    taught = {}
    for f in train_fx:
        demos = f["demos"]
        if len(demos) < 2:
            print(f"skip {f['name']}: only {len(demos)} demos")
            continue
        taught[f["name"]] = (TaughtMotionV2.learn(f["name"], demos), demos)
        m, _ = taught[f["name"]]
        print(f"learned {f['name']}: accept_proto_dist={m.accept_proto_dist:.3f} "
              f"demo_lengths={m.demo_lengths}")

    lines = ["# Motion V2 — STEP 9: real device captures", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M')} · MotionBERT-Lite · "
             f"{len(taught)} movements.", ""]

    # ---- leave-one-out same-family recognition ----
    lines += ["## match() — leave-one-demo-out", "",
              "| taught | held-out demo of | is_same | score | proto_margin | coverage |",
              "|---|---|---|---|---|---|"]
    tp = tn = fp = fn = 0
    for tname, (model, _) in taught.items():
        # own demos, LOO
        for name2, (_, demos2) in taught.items():
            for di, demo in enumerate(demos2):
                # if testing own class, retrain without this demo
                if name2 == tname:
                    if len(demos2) < 3:
                        continue
                    m2 = TaughtMotionV2.learn(tname, [d for k, d in enumerate(demos2) if k != di])
                else:
                    m2 = model
                r = m2.match(demo)
                exp = name2 == tname
                ok = r.is_same_family == exp
                if exp and r.is_same_family:
                    tp += 1
                elif exp:
                    fn += 1
                elif r.is_same_family:
                    fp += 1
                else:
                    tn += 1
                mark = "" if ok else "  ❌"
                lines.append(f"| {tname} | {name2} #{di} | {r.is_same_family} | "
                             f"{r.score:.2f} | {r.proto_margin:.2f} | {r.coverage:.2f}{mark} |")
    lines += ["", f"**match: TP={tp} TN={tn} FP={fp} FN={fn}**  "
              f"(precision {tp/max(tp+fp,1):.2f}, recall {tp/max(tp+fn,1):.2f})", ""]

    # ---- rep detection on *_reps<k>.json ----
    if reps_fx:
        lines += ["## count_reps()", "",
                  "| taught | sequence | expected | detected |", "|---|---|---|---|"]
        for f in reps_fx:
            base = os.path.basename(f["path"]).lower()
            k = int("".join(ch for ch in base.split("reps")[1] if ch.isdigit()) or 0)
            # match the movement name prefix to a taught model
            model = None
            for tname, (m, _) in taught.items():
                if base.startswith(tname.lower().replace(" ", "")):
                    model = m
                    break
            if model is None:
                continue
            for demo in f["demos"]:
                got, _ = count_reps(model, demo)
                lines.append(f"| {model.name} | {base} | {k} | {got}"
                             f"{'' if got == k else '  ⚠'} |")

    lines += ["", f"_(runtime {time.time()-t0:.1f}s)_"]
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("\nwrote", os.path.relpath(REPORT))


if __name__ == "__main__":
    main()
