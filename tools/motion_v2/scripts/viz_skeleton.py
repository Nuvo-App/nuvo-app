#!/usr/bin/env python
"""Eyeball the Nuvo -> H36M conversion. Renders a strip of frames from a
synthetic (or fixture) sequence to a PNG.

    python tools/motion_v2/scripts/viz_skeleton.py [jumping_jack|squat|arm_wave] [out.png]
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from adapter.nuvo_to_h36m import H36M_BONES, H36M_NAMES, frames_to_h36m  # noqa: E402
from adapter import synthetic_nuvo  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "experiments", "_out")


def render(seq: np.ndarray, title: str, out_path: str, n=8):
    T = seq.shape[0]
    picks = np.linspace(0, T - 1, min(n, T)).astype(int)
    fig, axes = plt.subplots(1, len(picks), figsize=(2.0 * len(picks), 3.2))
    if len(picks) == 1:
        axes = [axes]
    for ax, t in zip(axes, picks):
        f = seq[t]
        for a, b in H36M_BONES:
            if f[a, 2] != 0 and f[b, 2] != 0:
                ax.plot([f[a, 0], f[b, 0]], [f[a, 1], f[b, 1]], "-", lw=2, color="#1264FF")
        vis = f[:, 2] != 0
        ax.scatter(f[vis, 0], f[vis, 1], s=14, color="#07152D", zorder=3)
        ax.set_title(f"t={t}", fontsize=8)
        ax.set_xlim(-1.1, 1.1)
        ax.set_ylim(1.1, -1.1)  # y-down
        ax.set_aspect("equal")
        ax.axis("off")
    fig.suptitle(title, fontsize=11)
    fig.tight_layout()
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    fig.savefig(out_path, dpi=110)
    plt.close(fig)
    print("wrote", os.path.relpath(out_path))


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "jumping_jack"
    gen = {"jumping_jack": synthetic_nuvo.jumping_jack, "squat": synthetic_nuvo.squat,
           "arm_wave": synthetic_nuvo.arm_wave}[which]
    seq = frames_to_h36m(gen(T=48))
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(OUT_DIR, f"skeleton_{which}.png")
    render(seq, f"Nuvo->H36M: {which}  ({', '.join(H36M_NAMES[:4])}...)", out)

    # also a mirrored comparison
    render(frames_to_h36m(gen(T=48), mirror=True), f"{which} (mirrored)",
           os.path.join(OUT_DIR, f"skeleton_{which}_mirror.png"))


if __name__ == "__main__":
    main()
