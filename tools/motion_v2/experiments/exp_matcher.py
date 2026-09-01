"""Three-shot matcher benchmark.

Keeps all 3 demonstrations as first-class references (no early averaging into a
blurry canonical) and measures several consensus rules against a positive set
and a negative bank, plus leave-one-out teaching validation.

Run: tools/motion_v2/.venv/bin/python3 experiments/exp_matcher.py
"""
from __future__ import annotations

import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from adapter import synthetic_nuvo as sn  # noqa: E402
from adapter.nuvo_to_h36m import frames_to_h36m, region_activity  # noqa: E402
from engine.taught_motion import embedding_velocity, segment_action  # noqa: E402
from experiments.lib_repr import (  # noqa: E402
    _l2n, dtw_distance, mean_pool, per_frame_embedding, resample_seq,
)
from mb_encoder import encode  # noqa: E402

CANON = 32


# ── one reference (a single demonstration) ──────────────────────────────────

def _rep_emb(frames, mirror=False):
    rep = encode(frames_to_h36m(frames, mirror=mirror))
    return rep, per_frame_embedding(rep)


def _encode_orientations(frames):
    return [_rep_emb(frames, mirror=False), _rep_emb(frames, mirror=True)]


def _segment(emb):
    s, e = segment_action(emb)
    if e - s < 4:
        s, e = 0, len(emb)
    return s, e


class Reference:
    def __init__(self, frames):
        rep, emb = _rep_emb(frames)
        s, e = _segment(emb)
        self.proto = mean_pool(rep[s:e])
        self.traj = resample_seq(_l2n(emb[s:e]), CANON)
        self.length = e - s
        self.region = region_activity(frames_to_h36m(frames))

    def dist_from(self, rep_pairs):
        """(proto_dist, traj_dist) given pre-encoded (rep,emb) for each
        orientation — take the better orientation for identity. Wider DTW band
        (0.33) so a slower/faster performance still aligns."""
        best_pd, best_td = np.inf, np.inf
        for rep, emb in rep_pairs:
            s, e = _segment(emb)
            pd = float(np.linalg.norm(self.proto - mean_pool(rep[s:e])))
            td = float(dtw_distance(resample_seq(_l2n(emb[s:e]), CANON), self.traj,
                                    band=0.33))
            if pd + td < best_pd + best_td:
                best_pd, best_td = pd, td
        return best_pd, best_td

    def dist(self, frames):
        return self.dist_from(_encode_orientations(frames))


class MultiRefTaught:
    """Three references kept whole + the geometry between them."""

    def __init__(self, demos):
        assert len(demos) == 3
        self.refs = [Reference(d) for d in demos]
        pd_pairs, td_pairs, len_pairs = [], [], []
        for i in range(3):
            for j in range(i + 1, 3):
                pd, td = self.refs[i].dist_ref(self.refs[j]) \
                    if hasattr(self.refs[i], "dist_ref") else self._pair(i, j)
                pd_pairs.append(pd)
                td_pairs.append(td)
                len_pairs.append(abs(self.refs[i].length - self.refs[j].length))
        self.proto_spread = float(np.median(pd_pairs))
        self.proto_spread_max = float(np.max(pd_pairs))
        self.traj_spread = float(np.median(td_pairs))
        self.traj_spread_max = float(np.max(td_pairs))
        self.len_mean = float(np.mean([r.length for r in self.refs]))
        self.len_spread = float(np.max(len_pairs)) + 2

    def _pair(self, i, j):
        pd = float(np.linalg.norm(self.refs[i].proto - self.refs[j].proto))
        td = float(dtw_distance(self.refs[i].traj, self.refs[j].traj))
        return pd, td

    def per_ref(self, frames):
        oris = _encode_orientations(frames)
        return [r.dist_from(oris) for r in self.refs]

    def set_background(self, bank_frames):
        """A generic negative bank (unrelated motions). We measure how much
        closer an attempt is to the taught refs than to this background —
        the separation margin."""
        oris_list = [_encode_orientations(f) for f in bank_frames]
        self._bg = []
        for oris in oris_list:
            best = min(
                (min(np.linalg.norm(r.proto - mean_pool(rep[slice(*_segment(emb))]))
                     for r in self.refs) for rep, emb in oris)
            )
            self._bg.append(best)
        self._bg_proto_min = float(np.min(self._bg)) if self._bg else np.inf

    def margin(self, frames):
        oris = _encode_orientations(frames)
        pd = min(min(np.linalg.norm(r.proto - mean_pool(rep[slice(*_segment(emb))]))
                     for r in self.refs) for rep, emb in oris)
        return self._bg_proto_min - pd

    def separation(self, frames):
        """(bg_min - pd) / bg_min. >= 0.5  =>  the attempt sits at least twice
        as close to the taught motion as generic motion does. A principled
        confidence signal — not a tuned constant."""
        oris = _encode_orientations(frames)
        pd = min(min(np.linalg.norm(r.proto - mean_pool(rep[slice(*_segment(emb))]))
                     for r in self.refs) for rep, emb in oris)
        return (self._bg_proto_min - pd) / max(self._bg_proto_min, 1e-6)


# ── consensus decision strategies ──────────────────────────────────────────

def _norm(dists, taught):
    """[(pd,td), ...] -> [(pd/spread, td/spread), ...] with a small floor so a
    zero-spread demo set can't divide by ~0."""
    ps = max(taught.proto_spread, 1e-3)
    ts = max(taught.traj_spread, 1e-4)
    return [(pd / ps, td / ts) for pd, td in dists]


def strat_nearest(dists, taught, kp=3.0, kt=3.0):
    n = _norm(dists, taught)
    key = min(pd / kp + td / kt for pd, td in n)
    return key <= 1.0, key


def strat_median(dists, taught, kp=3.0, kt=3.0):
    n = _norm(dists, taught)
    pdm = float(np.median([p for p, _ in n]))
    tdm = float(np.median([t for _, t in n]))
    return (pdm <= kp and tdm <= kt), max(pdm / kp, tdm / kt)


def strat_two_of_three(dists, taught, kp=3.0, kt=3.0):
    n = _norm(dists, taught)
    votes = sum(1 for pd, td in n if pd <= kp and td <= kt)
    # tie-break score: 2nd-best combined key
    keys = sorted(pd / kp + td / kt for pd, td in n)
    return votes >= 2, keys[1]


def strat_envelope(dists, taught, k=3.0):
    """Attempt's best (min) proto & traj distance must fall inside k x the
    max pairwise spread among the demos — the movement's own variation."""
    pd = min(p for p, _ in dists)
    td = min(t for _, t in dists)
    okp = pd <= k * max(taught.proto_spread_max, 1e-3)
    okt = td <= k * max(taught.traj_spread_max, 1e-4)
    score = max(pd / (k * max(taught.proto_spread_max, 1e-3)),
               td / (k * max(taught.traj_spread_max, 1e-4)))
    return (okp and okt), score


def strat_hybrid(dists, taught, kp=3.0, kt=3.0, sep=None):
    """2-of-3 reference consensus, OR one reference is a decent match AND the
    attempt is at least twice as close to the taught motion as generic motion
    (separation >= 0.5). The second path rescues correct performances when the
    3 demos happened to be very consistent (tight spread)."""
    two, s2 = strat_two_of_three(dists, taught, kp, kt)
    n = _norm(dists, taught)
    one_ok = any(pd <= 2.0 * kp and td <= 2.0 * kt for pd, td in n)
    rescue = one_ok and (sep is not None and sep >= 0.5)
    return (two or rescue), s2


STRATS = {
    "nearest": strat_nearest,
    "median": strat_median,
    "2of3": strat_two_of_three,
    "envelope": strat_envelope,
    "hybrid": strat_hybrid,
}


# ── families ───────────────────────────────────────────────────────────────

def family(fn, seeds, **kw):
    return [fn(seed=s, **kw) for s in seeds]


FAMILIES = {
    "cross_body_reach": lambda: family(sn.cross_body_reach, [0, 1, 2]),
    "jumping_jack": lambda: family(sn.jumping_jack, [10, 11, 12]),
    "squat": lambda: family(sn.squat, [10, 11, 12]),
    "arm_wave": lambda: family(sn.arm_wave, [10, 11, 12]),
    "arm_raise": lambda: family(sn.arm_raise, [10, 11, 12]),
    "lunge": lambda: family(sn.lunge, [10, 11, 12]),
}

POSITIVES = {
    "cross_body_reach": [sn.cross_body_reach(seed=20),
                         sn.cross_body_reach(seed=21, jitter=1.6),
                         sn.cross_body_reach(T=60, seed=22)],  # slower, full motion
    "jumping_jack": [sn.jumping_jack(seed=20), sn.jumping_jack(seed=21, translate=0.03)],
    "squat": [sn.squat(seed=20), sn.squat(seed=21)],
    "arm_wave": [sn.arm_wave(seed=20), sn.arm_wave(seed=21)],
    "arm_raise": [sn.arm_raise(seed=20), sn.arm_raise(seed=21, jitter=1.5)],
    "lunge": [sn.lunge(seed=20), sn.lunge(seed=21)],
}

NEG_BANK = {
    "jumping_jack": sn.jumping_jack(seed=30),
    "squat": sn.squat(seed=30),
    "arm_wave": sn.arm_wave(seed=30),
    "arm_raise": sn.arm_raise(seed=30),
    "lunge": sn.lunge(seed=30),
    "walk": sn.walk_in_place(seed=30),
    "idle": sn.idle(T=44, seed=30),
    "cross_body_reach": sn.cross_body_reach(seed=30),
}


def loo(demos):
    """Leave-one-out: each demo must be recognized from the other two."""
    out = []
    for i in range(3):
        others = [demos[j] for j in range(3) if j != i]
        # lightweight 2-shot taught: duplicate one so MultiRefTaught keeps 3
        t2 = MultiRefTaught([others[0], others[1], others[0]])
        d = t2.per_ref(demos[i])
        ok, _ = strat_two_of_three(d, t2)
        out.append(ok)
    return out


def main():
    print("building families + references (real MotionBERT encoder)…\n")
    taught = {}
    for name, fn in FAMILIES.items():
        t = MultiRefTaught(fn())
        bank = [clip for k, clip in NEG_BANK.items() if k != name]
        t.set_background(bank)
        taught[name] = t

    for strat_name, strat in STRATS.items():
        print(f"══════ strategy: {strat_name} ══════")
        tp = fp = tn = fn_ = 0
        for fam, t in taught.items():
            for k, clip in enumerate(POSITIVES[fam]):
                d = t.per_ref(clip)
                sp = t.separation(clip)
                ok, score = (strat(d, t, sep=sp) if strat is strat_hybrid
                             else strat(d, t))
                tp += ok
                fn_ += (not ok)
                print(f"  {fam:>18}  positive[{k}]  -> {'ACCEPT' if ok else 'reject':6}  "
                      f"score={score:.2f}  sep={sp:+.2f}")
            for nn, clip in NEG_BANK.items():
                if nn == fam:
                    continue
                d = t.per_ref(clip)
                sp = t.separation(clip)
                ok, score = (strat(d, t, sep=sp) if strat is strat_hybrid
                             else strat(d, t))
                fp += ok
                tn += (not ok)
                tag = "ACCEPT (FALSE POSITIVE!)" if ok else "reject"
                print(f"  {fam:>18}  NEG {nn:<16} -> {tag:24}  "
                      f"score={score:.2f}  sep={sp:+.2f}")
        prec = tp / (tp + fp) if tp + fp else 0
        rec = tp / (tp + fn_) if tp + fn_ else 0
        print(f"  → TP={tp} FP={fp} TN={tn} FN={fn_}   precision={prec:.2f} recall={rec:.2f}\n")

    print("══════ leave-one-out teaching validation ══════")
    for name, fn in FAMILIES.items():
        res = loo(fn())
        print(f"  {name:>18}  LOO {sum(res)}/3   {res}")


if __name__ == "__main__":
    main()
