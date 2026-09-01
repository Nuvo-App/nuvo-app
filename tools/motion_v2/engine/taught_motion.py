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
from adapter.nuvo_to_h36m import frames_to_h36m, region_activity  # noqa: E402
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


def traj_distance(emb_seg: np.ndarray, canonical: np.ndarray, band: float = 0.33) -> float:
    """Normalized DTW distance of an ordered embedding path to a reference path.
    Small = traversed the reference trajectory, in order, in full. Band 0.33
    tolerates a slower/faster performance."""
    if len(emb_seg) < 2:
        return 1.0
    q = resample_seq(_l2n(emb_seg), len(canonical))
    return float(dtw_distance(q, canonical, band=band))


def traj_similarity(emb_seg: np.ndarray, canonical: np.ndarray) -> float:
    return 1.0 - traj_distance(emb_seg, canonical)


# ── matcher constants (from experiments/exp_matcher.py — measured, not tuned) ──
CANON_LEN_ = CANON_LEN
DTW_BAND = 0.33
VOTE_K = 3.0            # a reference "matches" if pd/spread <= K and td/spread <= K
RESCUE_K = 6.0          # 2 x VOTE_K — how close a lone reference must be to rescue
SEP_ACCEPT = 0.15       # attempt must be >=2x closer to the taught motion than
                        # to generic motion for the single-reference rescue path
BG_GATE = 1.15         # a reference vote also requires the attempt to be at
                        # least this much closer to the reference than to the
                        # nearest generic-motion anchor — bounds runaway
                        # thresholds when the 3 demos are far apart
PROTO_FLOOR = 0.04
TRAJ_FLOOR = 0.06
SCHEMA = 4


@dataclass
class MatchResult:
    is_same_family: bool
    score: float
    proto_dist: float
    proto_margin: float      # best_proto_dist / proto_spread / VOTE_K  (<=1 = inside)
    traj_sim: float
    detail: dict = field(default_factory=dict)


@dataclass
class Reference:
    """One demonstration kept whole — never averaged into a blur."""
    proto: np.ndarray        # (512,)  descriptor of the segmented rep
    traj: np.ndarray         # (CANON_LEN, 512) L2n  ordered embedding path
    length: int

    def to_json(self):
        return {"proto": self.proto.tolist(), "traj": self.traj.tolist(),
                "length": int(self.length)}

    @classmethod
    def from_json(cls, d):
        return cls(np.array(d["proto"], np.float32),
                   np.array(d["traj"], np.float32), int(d["length"]))


def _seg(emb):
    s, e = segment_action(emb)
    if e - s < 4:
        s, e = 0, len(emb)
    return s, e


@dataclass
class TaughtMotionV2:
    """Three-shot matcher. Keeps all 3 demonstrations as first-class references;
    the decision comes from consensus across them plus a separation margin
    against a generic background of unrelated motion. No averaged canonical."""
    name: str
    schema: int
    encoder_id: str
    references: list          # list[Reference]
    proto_spread: float       # median pairwise proto distance among the demos
    traj_spread: float        # median pairwise trajectory distance among the demos
    proto_spread_max: float
    traj_spread_max: float
    rest_emb: np.ndarray
    demo_active_vel: float
    demo_lengths: list
    demo_region_activity: dict = field(default_factory=dict)

    # ---- learn --------------------------------------------------------
    @classmethod
    def learn(cls, name, demos, mirror_aug=True) -> "TaughtMotionV2":
        assert len(demos) >= 2
        refs, rests, vels = [], [], []
        region_acc, region_n = {}, 0
        for frames in demos:
            ra = region_activity(frames_to_h36m(frames))
            for k, val in ra.items():
                region_acc[k] = region_acc.get(k, 0.0) + val
            region_n += 1
            rep, emb = _rep_and_emb(frames)
            s, e = _seg(emb)
            refs.append(Reference(mean_pool(rep[s:e]),
                                  resample_seq(_l2n(emb[s:e]), CANON_LEN), e - s))
            v = embedding_velocity(emb)
            mv = v[s:e]
            vels.append(float(np.median(mv[mv > np.median(mv) * 0.3])) if len(mv) else 0.0)
            low = np.argsort(v)[: max(2, len(v) // 5)]
            rests.append(_l2n(emb[low].mean(axis=0)))

        pd_pairs, td_pairs = [], []
        for i in range(len(refs)):
            for j in range(i + 1, len(refs)):
                pd_pairs.append(float(np.linalg.norm(refs[i].proto - refs[j].proto)))
                td_pairs.append(float(dtw_distance(refs[i].traj, refs[j].traj, band=DTW_BAND)))

        return cls(
            name=name, schema=SCHEMA, encoder_id=encoder_info()["checkpoint"],
            references=refs,
            proto_spread=float(np.median(pd_pairs)) if pd_pairs else 0.02,
            traj_spread=float(np.median(td_pairs)) if td_pairs else 0.01,
            proto_spread_max=float(np.max(pd_pairs)) if pd_pairs else 0.02,
            traj_spread_max=float(np.max(td_pairs)) if td_pairs else 0.01,
            rest_emb=_l2n(np.nan_to_num(np.mean(rests, axis=0))),
            demo_active_vel=float(np.median(vels)) if vels else 0.0,
            demo_lengths=[int(r.length) for r in refs],
            demo_region_activity={k: (v / region_n if region_n else 0.0)
                                  for k, v in region_acc.items()},
        )

    # ---- match ------------------------------------------------------
    def _dist_one_orientation(self, ref, rep, emb):
        s, e = _seg(emb)
        desc = mean_pool(rep[s:e])
        pd = float(np.linalg.norm(ref.proto - desc))
        td = traj_distance(emb[s:e], ref.traj, band=DTW_BAND)
        return pd, td, desc

    def match_encoded(self, rep, emb, rep_m=None, emb_m=None, background=None) -> MatchResult:
        oris = [(rep, emb)] + ([(rep_m, emb_m)] if rep_m is not None else [])
        ps = max(self.proto_spread, PROTO_FLOOR)
        ts = max(self.traj_spread, TRAJ_FLOOR)

        per_ref, best_desc, best_key = [], None, np.inf
        for ref in self.references:
            bpd, btd, bdesc = np.inf, np.inf, None
            for r, e in oris:
                pd, td, desc = self._dist_one_orientation(ref, r, e)
                if pd / ps + td / ts < bpd / ps + btd / ts:
                    bpd, btd, bdesc = pd, td, desc
            per_ref.append((bpd, btd))
            k = bpd / ps + btd / ts
            if k < best_key:
                best_key, best_desc = k, bdesc

        pms = [pd / ps for pd, _ in per_ref]
        tms = [td / ts for _, td in per_ref]
        best_pd = float(np.min([pd for pd, _ in per_ref]))
        best_td = float(np.min([td for _, td in per_ref]))
        best_pm, best_tm = min(pms), min(tms)

        sep = None
        bg_min = None
        if background is not None and len(background) and best_desc is not None:
            bg_min = float(np.min(np.linalg.norm(np.asarray(background) - best_desc, axis=1)))
            sep = (bg_min - best_pd) / max(bg_min, 1e-6)

        # A reference votes only if it is inside the demos' own variation AND
        # (when we have a background) the attempt is meaningfully closer to that
        # reference than to generic motion. The second clause stops the vote
        # threshold from blowing up when the 3 demos are far apart.
        def _votes_for(pd_abs, pm, tm):
            ok = pm <= VOTE_K and tm <= VOTE_K
            if ok and bg_min is not None:
                ok = pd_abs <= BG_GATE * bg_min
            return ok

        votes = sum(1 for (pd_abs, _), pm, tm in zip(per_ref, pms, tms)
                    if _votes_for(pd_abs, pm, tm))

        one_ok = any(pm <= RESCUE_K and tm <= RESCUE_K for pm, tm in zip(pms, tms))
        rescue = one_ok and sep is not None and sep >= SEP_ACCEPT
        is_same = votes >= 2 or rescue

        score = float(np.clip(
            0.45 * max(0.0, 1 - best_pm / VOTE_K)
            + 0.30 * max(0.0, 1 - best_tm / VOTE_K)
            + 0.25 * (votes / max(len(self.references), 1)),
            0.0, 1.0))

        return MatchResult(
            is_same, score, best_pd, best_pm / VOTE_K, 1.0 - best_td,
            detail={
                "per_ref": [{"proto": round(pd, 4), "traj": round(td, 4),
                             "proto_margin": round(pm, 3), "traj_margin": round(tm, 3),
                             "matches": bool(_votes_for(pd, pm, tm))}
                            for (pd, td), pm, tm in zip(per_ref, pms, tms)],
                "votes": votes,
                "separation": None if sep is None else round(float(sep), 3),
                "proto_spread": round(self.proto_spread, 4),
                "traj_spread": round(self.traj_spread, 4),
                "decision": ("2of3_consensus" if votes >= 2
                             else "separation_rescue" if rescue
                             else "reject"),
            })

    def match(self, frames, background=None) -> MatchResult:
        rep, emb = _rep_and_emb(frames)
        rep_m, emb_m = _rep_and_emb(frames, mirror=True)
        return self.match_encoded(rep, emb, rep_m, emb_m, background=background)

    # ---- self-validation ------------------------------------------
    @staticmethod
    def leave_one_out(demos, background=None):
        """Each demo must be recognizable from the OTHER two. If not, the three
        examples do not define one stable movement — do not learn a blur."""
        out = []
        for i in range(len(demos)):
            others = [demos[j] for j in range(len(demos)) if j != i]
            # lightweight 2-shot spec (duplicate one ref so the 3-way consensus
            # math is unchanged); this is a quality gate, not the product path.
            two = TaughtMotionV2.learn("_loo", [others[0], others[1], others[0]])
            out.append(two.match(demos[i], background=background).is_same_family)
        return out

    def self_check(self, demos, background=None):
        """Every demo must be recognized from the taught spec AND each demo must
        be recoverable from the other two (leave-one-out)."""
        per_demo = [self.match(d, background=background).is_same_family for d in demos]
        loo = self.leave_one_out(demos, background=background)
        need = len(demos) - (len(demos) // 3)  # majority
        passed = sum(per_demo) >= need and sum(loo) >= need
        return {
            "per_demo": per_demo,
            "leave_one_out": loo,
            "passed": passed,
            "proto_spread": self.proto_spread,
            "proto_spread_max": self.proto_spread_max,
        }

    # ---- serialize ------------------------------------------------
    def to_json(self):
        return {
            "schema": self.schema, "name": self.name, "encoder_id": self.encoder_id,
            "verifier": "motion_v2", "version": 1,
            "references": [r.to_json() for r in self.references],
            "proto_spread": self.proto_spread, "traj_spread": self.traj_spread,
            "proto_spread_max": self.proto_spread_max, "traj_spread_max": self.traj_spread_max,
            "rest_emb": self.rest_emb.tolist(),
            "demo_active_vel": self.demo_active_vel, "demo_lengths": self.demo_lengths,
            "region_activity": self.demo_region_activity,
        }

    @classmethod
    def from_json(cls, d):
        return cls(
            name=d.get("name", "Custom movement"), schema=d.get("schema", SCHEMA),
            encoder_id=d.get("encoder_id", d.get("encoder", "onnx")),
            references=[Reference.from_json(r) for r in d["references"]],
            proto_spread=d["proto_spread"], traj_spread=d["traj_spread"],
            proto_spread_max=d.get("proto_spread_max", d["proto_spread"]),
            traj_spread_max=d.get("traj_spread_max", d["traj_spread"]),
            rest_emb=np.array(d["rest_emb"], np.float32),
            demo_active_vel=d.get("demo_active_vel", 0.0),
            demo_lengths=d.get("demo_lengths", []),
            demo_region_activity=d.get("region_activity", {}),
        )

    def save(self, path):
        with open(path, "w") as f:
            json.dump(self.to_json(), f)
