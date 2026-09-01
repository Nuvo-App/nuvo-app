"""Integration test for the Motion V2 dev service. Starts it in-process, drives
the full learn -> session -> frames -> +1 loop with a synthetic INVENTED motion
(not one of squat/pushup/jj/wave), then an unrelated motion -> 0.
"""
import os
import sys
import threading
import time
import urllib.request

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
import numpy as np  # noqa: E402
from adapter import synthetic_nuvo as sn  # noqa: E402

PORT = 8791
BASE = f"http://127.0.0.1:{PORT}/motion-v2"


def _post(path, obj):
    req = urllib.request.Request(BASE + path, data=__import__("json").dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return __import__("json").loads(r.read())


def invented_motion(T=44, seed=0):
    """'Test Motion 001' — left elbow out, right hand to left shoulder, arms out,
    return. Not defined anywhere else."""
    rng = np.random.default_rng(seed)
    frames = []
    for i in range(T):
        ph = 0.5 - 0.5 * np.cos(2 * np.pi * i / T)
        ov = {
            "leftElbow": (0.64 + 0.14 * ph, 0.34 - 0.02 * ph),      # elbow out+up
            "rightWrist": (0.52 - 0.18 * ph, 0.30 - 0.02 * ph),     # cross to L shoulder
            "rightElbow": (0.44 - 0.06 * ph, 0.36),
            "leftWrist": (0.70 + 0.12 * ph, 0.40 - 0.10 * ph),
        }
        ov = {k: (v[0] + rng.normal(0, 0.004), v[1] + rng.normal(0, 0.004)) for k, v in ov.items()}
        # build a full frame
        f = sn.idle(T=1, seed=i)[0]
        for k, (x, y) in ov.items():
            f["points"][k] = {"x": x, "y": y, "z": 0.0, "likelihood": 0.95}
        frames.append({"t": i * 66, "w": 720, "h": 1280, "points":
                       {k: [p["x"], p["y"], p["z"], p["likelihood"]] for k, p in f["points"].items()}})
    return frames


def to_wire(frames):
    """synthetic_nuvo dict -> service wire frame."""
    out = []
    for i, f in enumerate(frames):
        pts = f["points"]
        out.append({"t": i * 66, "w": 720, "h": 1280,
                    "points": {k: [v["x"], v["y"], v["z"], v["likelihood"]] for k, v in pts.items()}})
    return out


def main():
    from service.app import ThreadingHTTPServer, Handler
    import service.app as app
    app.encoder_info()
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    time.sleep(0.3)

    # ---- learn an invented motion from 3 demos ----
    demos = [invented_motion(T=int(np.random.default_rng(k).integers(38, 50)), seed=k) for k in range(3)]
    learn = _post("/learn", {"movementName": "Test Motion 001", "demos": demos})
    spec = learn["spec"]
    print("learned:", spec["name"], "verifier=", spec["verifier"], "encoder=", spec["encoder"],
          "accept_pd=%.3f accept_td=%.4f" % (spec["accept_proto_dist"], spec["accept_traj_dist"]))

    # ---- session + stream an UNSEEN 4th performance ----
    sid = _post("/session", {"spec": spec, "fps": 15})["sessionId"]
    unseen = invented_motion(T=46, seed=99)
    reps = 0
    for chunk_start in range(0, len(unseen), 4):
        res = _post(f"/session/{sid}/frames", {"frames": unseen[chunk_start:chunk_start + 4]})
        if res["newRep"]:
            reps += 1
            print(f"  +1 at frame {chunk_start}  conf={res['confidence']} progress={res['progress']} "
                  f"latency={res['latencyMs']}ms")
    print(f"unseen same motion -> {reps} rep(s)   (want >= 1)")
    assert reps >= 1, "MVP FAIL: invented motion not recognized"

    # ---- unrelated motion -> 0 ----
    _post(f"/session/{sid}/reset", {})
    other = to_wire(sn.squat(T=44))
    other_reps = 0
    for c in range(0, len(other), 4):
        res = _post(f"/session/{sid}/frames", {"frames": other[c:c + 4]})
        other_reps += res["newRep"]
    print(f"unrelated motion -> {other_reps} rep(s)   (want 0)")
    assert other_reps == 0, "MVP FAIL: false positive on unrelated motion"

    print("\nSERVICE MVP OK")
    srv.shutdown()


if __name__ == "__main__":
    main()
