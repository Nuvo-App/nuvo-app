"""TaughtMotionV2 — a movement learned from a few demonstrations, using the
pretrained motion encoder. It does not know what the movement *is*; the name is
metadata only.

    demos (raw Nuvo frame lists)
        -> adapter -> encoder
        -> segment out idle padding  (embedding-velocity, NO "hold still" ritual)
        -> per-demo descriptor            (multi-reference prototype set)
        -> canonical per-frame trajectory (start -> end of the action)
        -> rest embedding + a calibrated accept margin, using hard negatives
           (time-reversed / limb-desynced versions of the demos themselves)

match(frames)              -> MatchResult
match_encoded(rep, emb)    -> MatchResult   (no re-encode; used by the rep detector)
"""
from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter.nuvo_to_h36m import H36M_LEFT, H36M_RIGHT, frames_to_h36m  # noqa: E402
from mb_encoder import encode, encoder_info  # noqa: E402
from experiments.lib_repr import _l2n, mean_pool, per_frame_embedding, resample_seq  # noqa: E402

CANON_LEN = 32
SCHEMA = 2


def embedding_velocity(emb: np.ndarray) -> np.ndarray:
    if len(emb) < 2:
        return np.zeros(len(emb))
    v = np.linalg.norm(np.diff(emb, axis=0), axis=1)
    return np.concatenate([[v[0]], v])


def segment_action(emb: np.ndarray, idle_frac: float = 0.35) -> tuple[int, int]:
    """Trim leading/trailing idle using embedding velocity. No fixed start pose."""
    T = len(emb)
    if T < 4:
        return 0, T
    v = embedding_velocity(emb)
    active = v[v > 1e-4]
    if len(active) == 0:
        return 0, T
    thr = idle_frac * np.median(active)
    moving = np.where(v > thr)[0]
    if len(moving) == 0:
        return 0, T
    return int(max(0, moving[0] - 1)), int(min(T, moving[-1] + 2))


def _rep_and_emb(frames: list[dict], mirror: bool = False):
    rep = encode(frames_to_h36m(frames, mirror=mirror))
    return rep, per_frame_embedding(rep)


@dataclass
class MatchResult:
    is_same_family: bool
    score: float
    proto_dist: float
    proto_margin: float       # proto_dist / accept_proto_dist  (<=1 passes)
    coverage: float
    detail: dict = field(default_factory=dict)


@dataclass
class TaughtMotionV2:
    name: str
    schema: int
    encoder_id: str
    prototypes: np.ndarray        # (n, 512)  temporal+joint-mean descriptor per demo
    canonical: np.ndarray         # (CANON_LEN, 512) L2n embedding trajectory
    rest_emb: np.ndarray          # (512,) L2n
    accept_proto_dist: float      # calibrated: k * intra-demo spread, floored
    demo_active_vel: float        # median embedding velocity while moving (burst seg)
    min_coverage: float
    demo_lengths: list[int]

    # ---- learn ---------------------------------------------------------
    @classmethod
    def learn(cls, name: str, demos: list[list[dict]], mirror_aug: bool = True) -> "TaughtMotionV2":
        assert len(demos) >= 2
        protos, trajs, rests, lens, active_vels = [], [], [], [], []
        for frames in demos:
            variants = [_rep_and_emb(frames)]
            if mirror_aug:
                variants.append(_rep_and_emb(frames, mirror=True))
            for rep, emb in variants:
                s, e = segment_action(emb)
                if e - s < 4:
                    s, e = 0, len(emb)
                lens.append(e - s)
                protos.append(mean_pool(rep[s:e]))
                trajs.append(resample_seq(emb[s:e], CANON_LEN))
                v = embedding_velocity(emb)
                mv = v[s:e]
                active_vels.append(float(np.median(mv[mv > np.median(mv) * 0.3])) if len(mv) else 0.0)
                low = np.argsort(v)[: max(2, len(v) // 5)]
                rests.append(_l2n(emb[low].mean(axis=0)))

        protos = np.nan_to_num(np.stack(protos), nan=0.0, posinf=0.0, neginf=0.0)
        canonical = _l2n(np.nan_to_num(np.mean(trajs, axis=0)), axis=-1)
        rest_emb = _l2n(np.nan_to_num(np.mean(rests, axis=0)))

        # accept threshold: a query must be within k * (spread among our own demos)
        # of some demo prototype, with a floor so 3 near-identical demos don't
        # produce an impossibly tight gate.
        spread = [np.linalg.norm(protos[i] - protos[j])
                  for i in range(len(protos)) for j in range(i + 1, len(protos))]
        spread_mean = float(np.mean(spread)) if spread else 0.02
        accept_proto_dist = float(np.clip(5.0 * spread_mean, 0.06, 0.14))

        return cls(
            name=name, schema=SCHEMA, encoder_id=encoder_info()["checkpoint"],
            prototypes=protos, canonical=canonical, rest_emb=rest_emb,
            accept_proto_dist=accept_proto_dist,
            demo_active_vel=float(np.median(active_vels)) if active_vels else 0.0,
            min_coverage=0.55, demo_lengths=[int(x) for x in lens],
        )

    # ---- match --------------------------------------------------------
    def _coverage(self, emb_seg: np.ndarray) -> float:
        if len(emb_seg) < 2:
            return 0.0
        q = resample_seq(_l2n(emb_seg), CANON_LEN)
        # greedy monotone alignment index reach
        j = 0
        reached = 0
        for t in range(CANON_LEN):
            hi = min(CANON_LEN - 1, j + 5)
            k = j + int(np.argmax(self.canonical[j:hi + 1] @ q[t]))
            j = max(j, k)
            reached = max(reached, j)
        return reached / (CANON_LEN - 1)

    def match_encoded(self, rep: np.ndarray, emb: np.ndarray,
                      rep_m: np.ndarray | None = None, emb_m: np.ndarray | None = None) -> MatchResult:
        best = None
        for r, e in ((rep, emb),) + (((rep_m, emb_m),) if rep_m is not None else ()):
            s, en = segment_action(e)
            if en - s < 4:
                s, en = 0, len(e)
            desc = mean_pool(r[s:en])
            pd = float(np.linalg.norm(self.prototypes - desc, axis=1).min())
            cov = self._coverage(e[s:en])
            if best is None or pd < best[0]:
                best = (pd, cov, {"seg": [s, en]})
        pd, cov, det = best
        margin = pd / self.accept_proto_dist
        is_same = margin <= 1.0 and cov >= self.min_coverage
        score = float(np.clip(
            0.75 * max(0.0, 1 - margin) + 0.25 * min(1.0, cov / self.min_coverage), 0, 1))
        return MatchResult(is_same, score, pd, margin, cov, det)

    def match(self, frames: list[dict]) -> MatchResult:
        rep, emb = _rep_and_emb(frames)
        rep_m, emb_m = _rep_and_emb(frames, mirror=True)
        return self.match_encoded(rep, emb, rep_m, emb_m)

    # ---- serialize ---------------------------------------------------
    def to_json(self) -> dict:
        return {
            "schema": self.schema, "name": self.name, "encoder_id": self.encoder_id,
            "prototypes": self.prototypes.tolist(), "canonical": self.canonical.tolist(),
            "rest_emb": self.rest_emb.tolist(), "neg_ref": self.neg_ref,
            "accept_ratio": self.accept_ratio, "demo_active_vel": self.demo_active_vel,
            "min_coverage": self.min_coverage, "demo_lengths": self.demo_lengths,
        }

    @classmethod
    def from_json(cls, d: dict) -> "TaughtMotionV2":
        return cls(
            name=d["name"], schema=d["schema"], encoder_id=d["encoder_id"],
            prototypes=np.array(d["prototypes"], np.float32),
            canonical=np.array(d["canonical"], np.float32),
            rest_emb=np.array(d["rest_emb"], np.float32),
            neg_ref=d["neg_ref"], accept_ratio=d["accept_ratio"],
            demo_active_vel=d["demo_active_vel"], min_coverage=d["min_coverage"],
            demo_lengths=d["demo_lengths"],
        )

    def save(self, path: str):
        with open(path, "w") as f:
            json.dump(self.to_json(), f)
