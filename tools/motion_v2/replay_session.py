"""Replay a NuvoMotionDiagnosticSession offline — the "no more blind tuning" loop.

    tools/motion_v2/.venv/bin/python3 tools/motion_v2/replay_session.py \
        ~/Downloads/MV2-20260902-8F3K2.json.gz

Loads the session, re-learns from the 3 teaching demos with the CURRENT engine,
then replays:
  - the whole live pose stream + a windowed match trace (this engine vs the phone)
  - the whole final attempt -> does it ACCEPT / REJECT now, and why

`--to-fixture datasets/nuvo_motion/<name>` writes the session as an eval fixture
(support x3 + held-out positive). The production runtime never sees labels.
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
from engine.taught_motion import TaughtMotionV2  # noqa: E402
from fixtures.load import _frame_to_nuvo  # noqa: E402


def load_session(path: str) -> dict:
    raw = open(path, "rb").read()
    if path.endswith(".gz"):
        raw = gzip.decompress(raw)
    return json.loads(raw)


def _to_wire(diag_frames: list[dict], key: str) -> list[dict]:
    """session frame ({name: [x,y,z,conf]}) -> fixture/wire frame."""
    out = []
    for f in diag_frames:
        pts = f.get(key) or f.get("raw") or {}
        out.append({"t": f.get("t", 0), "w": 720.0, "h": 1280.0, "points": pts})
    return out


def _nuvo(wire: list[dict]) -> list[dict]:
    return [_frame_to_nuvo(f) for f in wire]


def _background():
    p = os.path.join(_HERE, "..", "..", "assets", "models", "motion_v2_background.json")
    return np.array(json.load(open(p))["protos"], np.float32) if os.path.exists(p) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session")
    ap.add_argument("--to-fixture", default=None)
    ap.add_argument("--window", type=int, default=45)
    args = ap.parse_args()

    s = load_session(args.session)
    print(f"session {s['sessionId']}  diag-schema {s.get('schema')}")
    print(f"meta: {json.dumps(s.get('meta', {}), separators=(',', ':'))}")

    demos_wire = [_to_wire(d["frames"], "smoothed") for d in s["teaching"]]
    for i, d in enumerate(s["teaching"]):
        print(f"  demo {i+1}: {d['rawFrameCount']} raw -> {len(demos_wire[i])} frames  "
              f"{d['rawDurationMs']}ms  ~{d['estFps']:.0f}fps  seg={d.get('segmentation')}")

    bg = _background()
    name = s.get("meta", {}).get("movementName", "replay")
    taught = TaughtMotionV2.learn(name, [_nuvo(w) for w in demos_wire])
    print(f"\nlearned: proto_spread={taught.proto_spread:.4f}  "
          f"traj_spread={taught.traj_spread:.4f}  "
          f"proto_spread_max={taught.proto_spread_max:.4f}")
    print("self-check:", taught.self_check([_nuvo(w) for w in demos_wire], background=bg))

    live = s.get("liveTest")
    if not live:
        print("\n(no live test in this session)")
        return

    lf = _nuvo(_to_wire(live["frames"], "smoothed"))
    print(f"\nlive test: {len(lf)} frames  phone finalCount={live.get('finalCount')}")

    W = args.window
    if len(lf) >= W:
        print("\nwindowed match trace (this engine):")
        for end in range(W, len(lf) + 1, max(3, W // 8)):
            r = taught.match(lf[end - W:end], background=bg)
            pr = r.detail["per_ref"]
            print(f"  end={end:3d}  votes={r.detail['votes']}/3  "
                  f"sep={r.detail.get('separation')}  {r.detail['decision']:18s}  "
                  f"proto={[round(x['proto'],3) for x in pr]}  "
                  f"traj={[round(x['traj'],3) for x in pr]}")

    r = taught.match(lf, background=bg)
    print(f"\nWHOLE ATTEMPT -> is_same_family={r.is_same_family}  "
          f"votes={r.detail['votes']}/3  sep={r.detail.get('separation')}  "
          f"decision={r.detail['decision']}")
    print("phone said:",
          json.dumps(live.get("finalAttempt", {}), separators=(',', ':'))[:500])

    if args.to_fixture:
        os.makedirs(args.to_fixture, exist_ok=True)
        json.dump(
            {"sourceSession": s["sessionId"], "movementName": name,
             "supports": demos_wire,
             "heldOutPositive": _to_wire(live["frames"], "smoothed"),
             "meta": s.get("meta", {})},
            open(os.path.join(args.to_fixture, "fixture.json"), "w"))
        print(f"\nwrote {args.to_fixture}/fixture.json")


if __name__ == "__main__":
    main()
