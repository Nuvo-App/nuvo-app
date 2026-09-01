"""StreamingMotionV2 — incremental recognition for the live test camera.

Maintains a rolling frame buffer. On each `push()` it segments the recent motion
and runs `TaughtMotionV2.match()`. A rep is emitted when the buffer transitions
into a confident match after having been *away* from a match (so holding the end
pose can't re-fire, and idle can't fire).

Generic: the only state is match / not-match + a return-to-neutral gate. No
per-movement logic.
"""
from __future__ import annotations

import time
from dataclasses import dataclass, field

import numpy as np

from adapter.nuvo_to_h36m import frames_to_h36m
from mb_encoder import encode
from experiments.lib_repr import _l2n, per_frame_embedding
from engine.taught_motion import TaughtMotionV2, segment_action

BUFFER_SECONDS = 5.0
MIN_FRAMES_TO_MATCH = 8
REEVAL_EVERY = 3          # frames — don't re-encode on literally every frame
NEUTRAL_DROP = 0.55      # match score must fall below this before another rep


@dataclass
class StreamState:
    count: int = 0
    armed: bool = True            # ready to fire (has been away from a match)
    in_match: bool = False
    frames_seen: int = 0
    _since_eval: int = 0
    last: dict = field(default_factory=dict)


class StreamingMotionV2:
    def __init__(self, motion: TaughtMotionV2, fps_hint: float = 15.0):
        self.motion = motion
        self.buf: list[dict] = []
        self.buf_cap = max(30, int(BUFFER_SECONDS * fps_hint))
        self.s = StreamState()

    def reset(self):
        self.buf.clear()
        self.s = StreamState()

    def push(self, frames: list[dict]) -> dict:
        t0 = time.time()
        self.buf.extend(frames)
        if len(self.buf) > self.buf_cap:
            self.buf = self.buf[-self.buf_cap:]
        self.s.frames_seen += len(frames)
        self.s._since_eval += len(frames)

        new_rep = False
        if self.s.frames_seen < MIN_FRAMES_TO_MATCH:
            return self._result(new_rep, 0.0, 0.0, "warming_up", t0)

        if self.s._since_eval < REEVAL_EVERY and self.s.last:
            r = self.s.last
            return self._result(False, r["confidence"], r["progress"], r["state"], t0,
                                cached=True)
        self.s._since_eval = 0

        rep = encode(frames_to_h36m(self.buf))
        emb = per_frame_embedding(rep)
        repm = encode(frames_to_h36m(self.buf, mirror=True))
        embm = per_frame_embedding(repm)
        m = self.motion.match_encoded(rep, emb, repm, embm)

        # progress = how far the active segment traversed the canonical path
        s, e = segment_action(emb)
        prog = self._progress(emb[s:e] if e - s >= 4 else emb)

        if m.is_same_family and m.score >= self.motion.accept_traj_dist * 0 + 0.5:
            if self.s.armed and not self.s.in_match:
                self.s.count += 1
                new_rep = True
                self.s.armed = False
            self.s.in_match = True
        else:
            self.s.in_match = False
            if m.score < NEUTRAL_DROP:
                self.s.armed = True
            # trim the buffer once a rep is done + we've left the match, so the
            # next rep starts from a clean window
            if not self.s.armed is False and self.s.count > 0 and len(self.buf) > MIN_FRAMES_TO_MATCH:
                self.buf = self.buf[-MIN_FRAMES_TO_MATCH:]

        state = "matched" if self.s.in_match else ("neutral" if self.s.armed else "returning")
        self.s.last = {"confidence": m.score, "progress": prog, "state": state,
                       "proto_dist": m.proto_dist, "proto_margin": m.proto_margin,
                       "traj_sim": m.traj_sim}
        return self._result(new_rep, m.score, prog, state, t0,
                            proto_dist=m.proto_dist, proto_margin=m.proto_margin,
                            traj_sim=m.traj_sim)

    def _progress(self, emb_seg: np.ndarray) -> float:
        if len(emb_seg) < 2:
            return 0.0
        from experiments.lib_repr import resample_seq
        q = resample_seq(_l2n(emb_seg), len(self.motion.canonical))
        j = 0
        C = len(self.motion.canonical)
        for t in range(C):
            hi = min(C - 1, j + 5)
            j = max(j, j + int(np.argmax(self.motion.canonical[j:hi + 1] @ q[t])))
        return j / (C - 1)

    def _result(self, new_rep, conf, prog, state, t0, cached=False, **extra):
        return {
            "matched": state == "matched",
            "newRep": new_rep,
            "count": self.s.count,
            "confidence": round(float(conf), 3),
            "progress": round(float(prog), 3),
            "state": state,
            "bufferFrames": len(self.buf),
            "latencyMs": round((time.time() - t0) * 1000, 1),
            "cached": cached,
            **{k: round(float(v), 4) for k, v in extra.items()},
        }
