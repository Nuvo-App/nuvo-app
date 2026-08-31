"""TaughtMotionV2 — a movement learned from a few demonstrations, on top of the
pretrained motion encoder. It has no idea what the movement *is*; the name is
metadata only, never used to verify.

    demos (raw Nuvo frame lists)
        -> adapter -> encoder
        -> segment out idle padding  (embedding velocity — NO "hold still")
        -> per-demo descriptor            : temporal+joint mean of the rep
        -> canonical embedding trajectory : ordered per-frame path, start->end
        -> rest embedding + calibrated accept thresholds

Two independent signals decide a match:
  proto_dist : distance to the nearest demo descriptor   (which movement)
  traj_sim   : DTW similarity of the ordered embedding path to the canonical
               trajectory                                (done in order / fully)
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
from mb_encoder import encode, encoder_info  # noqa: E402
from experiments.lib_repr import (  # noqa: E402
    _l2n, dtw_distance, mean_pool, per_frame_embedding, resample_seq,
)

CANON_LEN = 32
SCHEMA = 3


def embedding_velocity(emb: np.ndarray) -> np.ndarray:
    if len(emb) < 2:
        return np.zeros(len(emb))
    v = np.linalg.norm(np.diff(emb, axis=0), axis=1)
    return np.concatenate([[v[0]], v])


def segment_action(emb: np.ndarray, idle_frac: float = 0.30) -> tuple[int, int]:
    """Trim leading/trailing idle by embedding velocity. No fixed start pose."""
    T = len(emb)
    if T < 4:
        return 0, T
    v = embedding_velocity(emb)
    active = v[v > 1e-5]
    if len(active) == 0:
        return 0, T
    thr = idle_frac * np.median(active)
    moving = np.where(v > thr)[0]
    if len(moving) == 0:
        return 0, T
    return int(max(0, moving[0] - 1)), int(min(T, moving[-1] + 2))


def _rep_and_emb(frames, mirror=False):
    rep = encode(frames_to_h36m(frames, mirror=mirror))
    return rep, per_frame_embedding(rep)


def traj_distance(emb_seg: np.ndarray, canonical: np.ndarray) -> float:
    """Normalized DTW distance of the ordered embedding path to the canonical
    path. Small = traversed the learned trajectory, in order, in full."""
    if len(emb_seg) < 2:
        return 1.0
    q = resample_seq(_l2n(emb_seg), len(canonical))
    return float(dtw_distance(q, canonical))


def traj_similarity(emb_seg: np.ndarray, canonical: np.ndarray) -> float:
    return 1.0 - traj_distance(emb_seg, canonical)


@dataclass
class MatchResult:
    is_same_family: bool
    score: float
    proto_dist: float
    proto_margin: float      # proto_dist / accept_proto_dist   (<=1 passes)
    traj_sim: float
    detail: dict = field(default_factory=dict)


@dataclass
class TaughtMotionV2:
    name: str
    schema: int
    encoder_id: str
    prototypes: np.ndarray        # (n, 512)
    canonical: np.ndarray         # (CANON_LEN, 512) L2n
    rest_emb: np.ndarray          # (512,) L2n
    accept_proto_dist: float
    accept_traj_dist: float
    demo_active_vel: float
    demo_lengths: list[int]

    # ---- learn --------------------------------------------------------
    @classmethod
    def learn(cls, name, demos, mirror_aug=True) -> "TaughtMotionV2":
        assert len(demos) >= 2
        protos, trajs, rests, lens, vels = [], [], [], [], []
        for frames in demos:
            variants = [_rep_and_emb(frames)] + ([_rep_and_emb(frames, mirror=True)] if mirror_aug else [])
            for rep, emb in variants:
                s, e = segment_action(emb)
                if e - s < 4:
                    s, e = 0, len(emb)
                lens.append(e - s)
                protos.append(mean_pool(rep[s:e]))
                trajs.append(resample_seq(_l2n(emb[s:e]), CANON_LEN))
                v = embedding_velocity(emb)
                mv = v[s:e]
                vels.append(float(np.median(mv[mv > np.median(mv) * 0.3])) if len(mv) else 0.0)
                low = np.argsort(v)[: max(2, len(v) // 5)]
                rests.append(_l2n(emb[low].mean(axis=0)))

        protos = np.nan_to_num(np.stack(protos))
        canonical = _l2n(np.nan_to_num(np.mean(trajs, axis=0)), axis=-1)
        rest_emb = _l2n(np.nan_to_num(np.mean(rests, axis=0)))

        # Both thresholds: k x (spread among our OWN demos), floor + cap relative
        # to the signal's own scale so it works across encoder variants.
        pd_spread = [np.linalg.norm(protos[i] - protos[j])
                     for i in range(len(protos)) for j in range(i + 1, len(protos))]
        mag = float(np.median(np.linalg.norm(protos, axis=1)))
        accept_proto_dist = float(np.clip(
            4.0 * (np.mean(pd_spread) if pd_spread else 0.02), 0.04 * mag, 0.15 * mag))

        td_own = [traj_distance(trajs[i], canonical) for i in range(len(trajs))]
        td_ref = float(np.median(td_own)) if td_own else 0.01
        accept_traj_dist = float(np.clip(td_ref * 3.0 + 5e-4, 1e-3, 0.05))

        return cls(
            name=name, schema=SCHEMA, encoder_id=encoder_info()["checkpoint"],
            prototypes=protos, canonical=canonical, rest_emb=rest_emb,
            accept_proto_dist=accept_proto_dist, accept_traj_dist=accept_traj_dist,
            demo_active_vel=float(np.median(vels)) if vels else 0.0,
            demo_lengths=[int(x) for x in lens],
        )

    # ---- match ------------------------------------------------------
    def match_encoded(self, rep, emb, rep_m=None, emb_m=None) -> MatchResult:
        best = None
        for r, e in ((rep, emb),) + (((rep_m, emb_m),) if rep_m is not None else ()):
            s, en = segment_action(e)
            if en - s < 4:
                s, en = 0, len(e)
            pd = float(np.linalg.norm(self.prototypes - mean_pool(r[s:en]), axis=1).min())
            td = traj_distance(e[s:en], self.canonical)
            key = pd / self.accept_proto_dist + td / self.accept_traj_dist
            if best is None or key < best[0]:
                best = (key, pd, td, {"seg": [s, en]})
        _, pd, td, det = best
        pm = pd / self.accept_proto_dist
        tm = td / self.accept_traj_dist
        is_same = pm <= 1.0 and tm <= 1.0
        score = float(np.clip(0.55 * max(0.0, 1 - pm) + 0.45 * max(0.0, 1 - tm), 0, 1))
        return MatchResult(is_same, score, pd, pm, 1.0 - td, det)

    def match(self, frames) -> MatchResult:
        rep, emb = _rep_and_emb(frames)
        rep_m, emb_m = _rep_and_emb(frames, mirror=True)
        return self.match_encoded(rep, emb, rep_m, emb_m)

    # ---- serialize ------------------------------------------------
    def to_json(self):
        return {
            "schema": self.schema, "name": self.name, "encoder_id": self.encoder_id,
            "prototypes": self.prototypes.tolist(), "canonical": self.canonical.tolist(),
            "rest_emb": self.rest_emb.tolist(),
            "accept_proto_dist": self.accept_proto_dist, "accept_traj_dist": self.accept_traj_dist,
            "demo_active_vel": self.demo_active_vel, "demo_lengths": self.demo_lengths,
        }

    @classmethod
    def from_json(cls, d):
        return cls(
            name=d["name"], schema=d["schema"], encoder_id=d["encoder_id"],
            prototypes=np.array(d["prototypes"], np.float32),
            canonical=np.array(d["canonical"], np.float32),
            rest_emb=np.array(d["rest_emb"], np.float32),
            accept_proto_dist=d["accept_proto_dist"], accept_traj_dist=d["accept_traj_dist"],
            demo_active_vel=d["demo_active_vel"], demo_lengths=d["demo_lengths"],
        )

    def save(self, path):
        with open(path, "w") as f:
            json.dump(self.to_json(), f)
