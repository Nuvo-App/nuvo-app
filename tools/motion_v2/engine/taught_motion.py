"""TaughtMotionV2 — a movement learned from 3 demonstrations, using the
pretrained motion encoder. No idea what the movement *is*; the name is metadata.

    demos (raw Nuvo frame lists)
        -> adapter -> encoder
        -> segment out idle padding (no "hold still" assumption)
        -> per-demo descriptor  (multi-reference prototype)
        -> canonical per-frame embedding trajectory (start -> end of the action)
        -> rest embedding (low-motion regions) + accept threshold

Then:
    match(seq)        -> MatchResult(is_same_family, score, ...)
    progress(seq)     -> coverage along the canonical trajectory  [0..1]
"""
from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter.nuvo_to_h36m import frames_to_h36m  # noqa: E402
from mb_encoder import encode  # noqa: E402
from experiments.lib_repr import (  # noqa: E402
    _l2n,
    dtw_distance,
    mean_pool,
    per_frame_embedding,
    resample_seq,
)

CANON_LEN = 32
SCHEMA = 1


def _velocity(emb: np.ndarray) -> np.ndarray:
    """per-frame speed of the (T,512) normalized embedding trajectory."""
    if len(emb) < 2:
        return np.zeros(len(emb))
    v = np.linalg.norm(np.diff(emb, axis=0), axis=1)
    return np.concatenate([[v[0]], v])


def segment_action(emb: np.ndarray, idle_frac: float = 0.35) -> tuple[int, int]:
    """Trim leading/trailing idle using embedding velocity. Returns [start, end).

    idle threshold = idle_frac * median non-trivial speed. No fixed start pose.
    """
    T = len(emb)
    if T < 4:
        return 0, T
    v = _velocity(emb)
    active = v[v > 1e-4]
    if len(active) == 0:
        return 0, T
    thr = idle_frac * np.median(active)
    moving = v > thr
    if not moving.any():
        return 0, T
    idx = np.where(moving)[0]
    start = max(0, idx[0] - 1)
    end = min(T, idx[-1] + 2)
    return int(start), int(end)


@dataclass
class MatchResult:
    is_same_family: bool
    score: float          # 0..1, higher = more like this movement
    proto_dist: float     # descriptor distance to nearest demo prototype
    traj_sim: float       # mean local similarity along the DTW-aligned trajectory
    coverage: float       # fraction of the canonical trajectory traversed
    detail: dict = field(default_factory=dict)


@dataclass
class TaughtMotionV2:
    name: str
    schema: int
    encoder_id: str
    # multi-reference descriptors (one per demo)
    prototypes: np.ndarray            # (n_demos, 512)
    canonical: np.ndarray             # (CANON_LEN, 512) L2-normalized trajectory
    rest_emb: np.ndarray              # (512,) L2-normalized
    accept_proto_dist: float          # threshold on descriptor distance
    accept_traj_sim: float            # threshold on trajectory similarity
    min_coverage: float
    demo_lengths: list[int]

    # ---- fit -------------------------------------------------------------
    @classmethod
    def learn(cls, name: str, demos: list[list[dict]], mirror_aug: bool = True) -> "TaughtMotionV2":
        assert len(demos) >= 2, "need >= 2 demonstrations"
        protos, trajs, rests, lens = [], [], [], []
        for frames in demos:
            reps = []
            h = frames_to_h36m(frames)
            reps.append(encode(h))
            if mirror_aug:
                reps.append(encode(frames_to_h36m(frames, mirror=True)))
            for rep in reps:
                emb = per_frame_embedding(rep)          # (T,512) L2n
                s, e = segment_action(emb)
                if e - s < 4:
                    s, e = 0, len(emb)
                lens.append(e - s)
                trimmed = emb[s:e]
                protos.append(mean_pool(rep[s:e]))
                trajs.append(resample_seq(trimmed, CANON_LEN))
                # rest = mean of the lowest-velocity 20% of frames
                v = _velocity(emb)
                low = np.argsort(v)[: max(2, len(v) // 5)]
                rests.append(_l2n(emb[low].mean(axis=0)))
        protos = np.stack(protos)
        canonical = _l2n(np.mean(trajs, axis=0), axis=-1)
        rest_emb = _l2n(np.mean(rests, axis=0))

        # thresholds from the spread among the demos themselves
        pd = [np.linalg.norm(protos[i] - protos[j])
              for i in range(len(protos)) for j in range(i + 1, len(protos))]
        ts = [1 - dtw_distance(trajs[i], trajs[j])
              for i in range(len(trajs)) for j in range(i + 1, len(trajs))]
        accept_pd = float(np.mean(pd) + 2.5 * np.std(pd)) if pd else 1.0
        accept_ts = float(max(0.3, np.mean(ts) - 2.5 * np.std(ts))) if ts else 0.5

        from mb_encoder import encoder_info
        return cls(
            name=name, schema=SCHEMA, encoder_id=encoder_info()["checkpoint"],
            prototypes=protos, canonical=canonical, rest_emb=rest_emb,
            accept_proto_dist=accept_pd, accept_traj_sim=accept_ts,
            min_coverage=0.75, demo_lengths=[int(x) for x in lens],
        )

    # ---- match --------------------------------------------------------
    def _traj_align(self, emb_norm: np.ndarray) -> tuple[float, float]:
        """DTW-align a normalized embedding trajectory to the canonical one.
        Returns (mean local cosine similarity, coverage)."""
        q = resample_seq(emb_norm, CANON_LEN)
        # local cosine-sim matrix + monotonic DTW path
        S = q @ self.canonical.T                       # (CANON_LEN, CANON_LEN)
        n = CANON_LEN
        D = np.full((n + 1, n + 1), -np.inf)
        D[0, 0] = 0.0
        bt = np.zeros((n + 1, n + 1), dtype=np.int8)
        for i in range(1, n + 1):
            for j in range(1, n + 1):
                cand = (D[i - 1, j - 1], D[i - 1, j], D[i, j - 1])
                k = int(np.argmax(cand))
                D[i, j] = cand[k] + S[i - 1, j - 1]
                bt[i, j] = k
        # backtrack to measure how much of the canonical (j-axis) was covered
        i = j = n
        js = []
        sims = []
        while i > 0 and j > 0:
            sims.append(S[i - 1, j - 1])
            js.append(j - 1)
            k = bt[i, j]
            if k == 0:
                i, j = i - 1, j - 1
            elif k == 1:
                i -= 1
            else:
                j -= 1
        coverage = (max(js) - min(js) + 1) / n if js else 0.0
        return float(np.mean(sims)), float(coverage)

    def match(self, frames: list[dict]) -> MatchResult:
        rep = encode(frames_to_h36m(frames))
        emb = per_frame_embedding(rep)
        s, e = segment_action(emb)
        if e - s < 4:
            s, e = 0, len(emb)
        desc = mean_pool(rep[s:e])
        proto_dist = float(np.linalg.norm(self.prototypes - desc, axis=1).min())
        traj_sim, coverage = self._traj_align(emb[s:e])
        # also try mirrored (front camera)
        repm = encode(frames_to_h36m(frames, mirror=True))
        embm = per_frame_embedding(repm)
        sm, em = segment_action(embm)
        if em - sm < 4:
            sm, em = 0, len(embm)
        pdm = float(np.linalg.norm(self.prototypes - mean_pool(repm[sm:em]), axis=1).min())
        tsm, covm = self._traj_align(embm[sm:em])
        if pdm < proto_dist:
            proto_dist, traj_sim, coverage = pdm, tsm, covm

        score = 0.5 * max(0.0, 1 - proto_dist / (self.accept_proto_dist + 1e-6)) \
            + 0.35 * min(1.0, traj_sim / (self.accept_traj_sim + 1e-6)) \
            + 0.15 * min(1.0, coverage / self.min_coverage)
        is_same = (proto_dist <= self.accept_proto_dist
                   and traj_sim >= self.accept_traj_sim
                   and coverage >= self.min_coverage)
        return MatchResult(is_same, float(np.clip(score, 0, 1)), proto_dist,
                           traj_sim, coverage,
                           detail={"seg": [s, e], "mirrored": pdm < proto_dist})

    # ---- serialize -----------------------------------------------------
    def to_json(self) -> dict:
        return {
            "schema": self.schema, "name": self.name, "encoder_id": self.encoder_id,
            "prototypes": self.prototypes.tolist(),
            "canonical": self.canonical.tolist(),
            "rest_emb": self.rest_emb.tolist(),
            "accept_proto_dist": self.accept_proto_dist,
            "accept_traj_sim": self.accept_traj_sim,
            "min_coverage": self.min_coverage,
            "demo_lengths": self.demo_lengths,
        }

    @classmethod
    def from_json(cls, d: dict) -> "TaughtMotionV2":
        return cls(
            name=d["name"], schema=d["schema"], encoder_id=d["encoder_id"],
            prototypes=np.array(d["prototypes"], np.float32),
            canonical=np.array(d["canonical"], np.float32),
            rest_emb=np.array(d["rest_emb"], np.float32),
            accept_proto_dist=d["accept_proto_dist"],
            accept_traj_sim=d["accept_traj_sim"],
            min_coverage=d["min_coverage"], demo_lengths=d["demo_lengths"],
        )

    def save(self, path: str):
        with open(path, "w") as f:
            json.dump(self.to_json(), f)
