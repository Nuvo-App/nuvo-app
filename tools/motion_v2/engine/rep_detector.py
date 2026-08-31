"""RepDetectorV2 — generic repetition counting: split the stream into motion
bursts at embedding-velocity valleys, then run TaughtMotionV2.match() on each
burst and count the passes.

No movement-specific state machine. The only "state" is: are we currently inside
a burst of motion, and does that burst match the taught movement.

    idle A idle A idle A   -> 3
    idle B idle            -> 0
    random flailing        -> 0
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter.nuvo_to_h36m import frames_to_h36m  # noqa: E402
from mb_encoder import encode  # noqa: E402
from experiments.lib_repr import per_frame_embedding  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402
from experiments.lib_repr import _l2n, resample_seq  # noqa: E402

_MIN_BURST = 5          # frames
_MERGE_GAP = 3          # merge excursions separated by <= this many near-rest frames
_PAD = 2


@dataclass
class RepEvent:
    start: int
    end: int
    score: float
    proto_dist: float


@dataclass
class RepDetectorV2:
    motion: TaughtMotionV2
    events: list = field(default_factory=list)

    def _bursts(self, emb: np.ndarray) -> list[tuple[int, int]]:
        """Matched filter: slide the learned canonical trajectory along the
        stream; each local maximum of alignment where the window traverses the
        whole trajectory is one rep. Generic — the template *is* the learned
        movement, no per-movement logic, no rest-pose assumption.
        """
        T = len(emb)
        if T < _MIN_BURST:
            return []
        en = _l2n(emb)
        canon = self.motion.canonical                       # (C, 512) L2n
        C = len(canon)
        # median demo length is the natural window; clamp to the stream.
        W = int(np.clip(np.median(self.motion.demo_lengths) if self.motion.demo_lengths else C,
                        _MIN_BURST, max(_MIN_BURST + 1, T)))
        step = max(1, W // 8)
        scored = []  # (center, score, start, end)
        for start in range(0, max(1, T - W + 1), step):
            end = min(T, start + W)
            win = resample_seq(en[start:end], C)            # (C,512)
            # diagonal-ish alignment score: mean of per-position best cosine in a
            # small forward band (tolerates speed differences)
            S = win @ canon.T                               # (C,C)
            band = np.array([S[i, max(0, i - 2):min(C, i + 3)].max() for i in range(C)])
            scored.append((start + W // 2, float(band.mean()), start, end))
        if not scored:
            return []
        centers = np.array([s[0] for s in scored])
        vals = np.array([s[1] for s in scored])
        thr = max(self.motion.accept_traj_sim if hasattr(self.motion, "accept_traj_sim") else 0.0,
                  np.percentile(vals, 60), 0.75)
        # non-max suppression: peaks above thr, separated by >= W*0.55
        order = np.argsort(-vals)
        picks = []
        for k in order:
            if vals[k] < thr:
                break
            c = centers[k]
            if all(abs(c - centers[p]) >= W * 0.55 for p in picks):
                picks.append(k)
        picks.sort(key=lambda k: centers[k])
        out = []
        for k in picks:
            _, _, s, e = scored[k]
            out.append((max(0, s - _PAD), min(T, e + _PAD)))
        return out

    def run(self, frames: list[dict]) -> int:
        # 1. cheap full encode ONLY for segmentation (rough rest-excursion signal;
        #    transformer context bleed doesn't matter for boundaries).
        emb_full = per_frame_embedding(encode(frames_to_h36m(frames)))

        self.events = []
        for (s, e) in self._bursts(emb_full):
            # 2. RE-ENCODE just this window. A rep sliced out of a pre-encoded
            #    long sequence carries attention context from the other reps and
            #    its descriptor drifts — matching must see the burst in isolation,
            #    exactly as a live sliding window would.
            burst = frames[s:e]
            m = self.motion.match(burst)
            if m.is_same_family:
                self.events.append(RepEvent(s, e, m.score, m.proto_dist))
        return len(self.events)

    @property
    def count(self) -> int:
        return len(self.events)


def count_reps(motion: TaughtMotionV2, frames: list[dict]):
    d = RepDetectorV2(motion=motion)
    d.run(frames)
    return d.count, d.events
