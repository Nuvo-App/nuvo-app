"""Load Motion V2 raw-pose-stream fixtures captured from the Teach Nuvo debug
report ("Copy debug report" -> the `rawStreamFixture` key).

Fixture JSON (one movement, 3 demos):

    {
      "movementName": "...",
      "schema": 1,
      "demos": [
        [ {"t": <ms>, "w": <px>, "h": <px>,
           "points": {"leftShoulder": [x, y, z, likelihood], ...}}, ... ],   # demo 1
        [ ... ],                                                              # demo 2
        [ ... ]                                                              # demo 3
      ]
    }

Save fixtures as tools/motion_v2/fixtures/<movement>_<n>.json (either the whole
debug report or just the rawStreamFixture object — both are accepted).
"""
from __future__ import annotations

import glob
import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def _frame_to_nuvo(f: dict) -> dict:
    """fixture frame -> the dict shape adapter.frames_to_h36m expects."""
    pts = {}
    for name, v in f["points"].items():
        x, y = float(v[0]), float(v[1])
        z = float(v[2]) if len(v) > 2 else 0.0
        lk = float(v[3]) if len(v) > 3 else 1.0
        pts[name] = {"x": x, "y": y, "z": z, "likelihood": lk}
    return {"points": pts, "imageWidth": f.get("w", 0.0), "imageHeight": f.get("h", 0.0),
            "t": f.get("t", 0)}


def load_fixture(path: str) -> dict:
    with open(path) as fh:
        d = json.load(fh)
    raw = d.get("rawStreamFixture", d)   # accept full debug report or just the object
    demos = [[_frame_to_nuvo(fr) for fr in demo] for demo in raw["demos"]]
    return {
        "name": raw.get("movementName", os.path.splitext(os.path.basename(path))[0]),
        "demos": demos,
        "path": path,
    }


def load_all(pattern: str = "*.json") -> list[dict]:
    out = []
    for p in sorted(glob.glob(os.path.join(_HERE, pattern))):
        if os.path.basename(p) == "load.py":
            continue
        try:
            out.append(load_fixture(p))
        except (KeyError, json.JSONDecodeError) as e:
            print(f"skip {os.path.basename(p)}: {e}")
    return out


def have_fixtures() -> bool:
    return len(load_all()) > 0


if __name__ == "__main__":
    fx = load_all()
    if not fx:
        print("no fixtures in tools/motion_v2/fixtures/ — capture some via the")
        print("Teach Nuvo debug report (see this file's docstring).")
    for f in fx:
        lens = [len(d) for d in f["demos"]]
        print(f"{f['name']:<24} {len(f['demos'])} demos, frame counts {lens}")
