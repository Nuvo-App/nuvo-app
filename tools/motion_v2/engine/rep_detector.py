"""RepDetectorV2 — generic repetition counting against a TaughtMotionV2.

No movement-specific state machine. The only state is *progress along the
learned canonical embedding trajectory* + *returned toward rest*. Works the same
offline (feed a whole sequence) or streaming (feed frames as they arrive) — the
Flutter runtime will mirror this exactly.

    idle A idle A idle A   -> 3
    idle B idle           -> 0   (B doesn't traverse A's trajectory)
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
from experiments.lib_repr import _l2n, per_frame_embedding  # noqa: E402
from engine.taught_motion import CANON_LEN, TaughtMotionV2  # noqa: E402

# generic tuning (NOT per movement) — expressed in encoder-frame units
_FWD_WINDOW = 6          # how far ahead on the canonical index we may jump
_BACK_TOL = 1
_MIN_LOCAL_SIM = 0.55   # a frame must match *some* canonical index this well to count as progress
_RETURN_SIM = 0.80      # similarity to rest_emb that counts as "returned"
_STALL_FRAMES = 24      # abandon an in-progress rep after this many non-advancing frames
_GRACE = 3              # missing/!valid frames tolerated mid-rep


@dataclass
class RepEvent:
    frame: int
    coverage: float
    mean_sim: float


@dataclass
class RepDetectorV2:
    motion: TaughtMotionV2
    # state
    idx: int = 0                    # current canonical progress index
    peak_idx: int = 0
    in_rep: bool = False
    armed: bool = True             # near rest / start, ready to begin a rep
    sims: list = field(default_factory=list)
    stall: int = 0
    count: int = 0
    events: list = field(default_factory=list)
    _canon: np.ndarray = None

    def __post_init__(self):
        self._canon = self.motion.canonical  # (CANON_LEN, 512) L2n

    # ---- per-frame embedding step ------------------------------------
    def step(self, emb_frame: np.ndarray) -> None:
        e = _l2n(np.asarray(emb_frame, np.float32))
        rest_sim = float(e @ self.motion.rest_emb)

        lo = max(0, self.idx - _BACK_TOL)
        hi = min(CANON_LEN - 1, self.idx + _FWD_WINDOW)
        window_sims = self._canon[lo:hi + 1] @ e
        best_local = lo + int(np.argmax(window_sims))
        best_sim = float(window_sims.max())

        advanced = best_local > self.idx and best_sim >= _MIN_LOCAL_SIM

        if not self.in_rep:
            # begin a rep only from an armed (near-rest) state and real forward motion
            if self.armed and advanced and best_local <= _FWD_WINDOW:
                self.in_rep = True
                self.idx = best_local
                self.peak_idx = best_local
                self.sims = [best_sim]
                self.stall = 0
                self.armed = False
            elif rest_sim >= _RETURN_SIM:
                self.armed = True
            return

        # in a rep
        if advanced or (best_sim >= _MIN_LOCAL_SIM and best_local >= self.idx):
            self.idx = max(self.idx, best_local)
            self.peak_idx = max(self.peak_idx, self.idx)
            self.sims.append(best_sim)
            self.stall = 0
        else:
            self.stall += 1

        coverage = self.peak_idx / (CANON_LEN - 1)
        near_end = self.peak_idx >= (CANON_LEN - 1) * self.motion.min_coverage
        returned = rest_sim >= _RETURN_SIM or self.idx <= _BACK_TOL

        if near_end and returned and coverage >= self.motion.min_coverage:
            mean_sim = float(np.mean(self.sims)) if self.sims else 0.0
            if mean_sim >= self.motion.accept_traj_sim * 0.9:
                self.count += 1
                self.events.append(RepEvent(len(self.events), coverage, mean_sim))
            self._reset_rep(armed=True)
            return

        if self.stall >= _STALL_FRAMES:
            self._reset_rep(armed=rest_sim >= _RETURN_SIM * 0.9)

    def _reset_rep(self, armed: bool):
        self.in_rep = False
        self.idx = 0
        self.peak_idx = 0
        self.sims = []
        self.stall = 0
        self.armed = armed

    # ---- offline convenience --------------------------------------
    def run_offline(self, frames: list[dict]) -> int:
        rep = encode(frames_to_h36m(frames))
        emb = per_frame_embedding(rep)  # (T,512) L2n
        for t in range(len(emb)):
            self.step(emb[t])
        return self.count


def count_reps(motion: TaughtMotionV2, frames: list[dict]) -> tuple[int, list[RepEvent]]:
    d = RepDetectorV2(motion=motion)
    d.run_offline(frames)
    return d.count, d.events
