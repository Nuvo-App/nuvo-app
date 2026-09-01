#!/usr/bin/env python
"""Motion V2 dev inference service — MVP integration milestone, NOT production.

Flutter (Teach Nuvo) talks to this over LAN so the full product loop runs while
on-device export is a later project.

  POST /motion-v2/learn                 {movementName, demos:[[frame,...],...]}  -> {spec}
  POST /motion-v2/session               {spec, fps?}                            -> {sessionId}
  POST /motion-v2/session/<id>/frames   {frames:[frame,...]}                    -> MotionV2RuntimeResult
  POST /motion-v2/session/<id>/reset                                            -> {ok}
  DELETE /motion-v2/session/<id>                                                -> {ok}
  GET  /motion-v2/health                                                        -> {ok, encoder, sessions}

frame = {"t": <ms>, "w": <px>, "h": <px>, "points": {"leftShoulder":[x,y,z,likelihood], ...}}

    python tools/motion_v2/service/app.py            # 0.0.0.0:8799
    MOTION_V2_PORT=9000 python tools/motion_v2/service/app.py
"""
import json
import os
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
from fixtures.load import _frame_to_nuvo  # noqa: E402
from engine.taught_motion import TaughtMotionV2  # noqa: E402
from engine.streaming import StreamingMotionV2  # noqa: E402
from mb_encoder import encoder_info  # noqa: E402

_sessions: dict[str, StreamingMotionV2] = {}
_lock = threading.Lock()


def _learn(body: dict) -> dict:
    name = body.get("movementName", "Custom movement")
    demos = [[_frame_to_nuvo(f) for f in demo] for demo in body["demos"]]
    if len(demos) < 2:
        raise ValueError("need >= 2 demonstrations")
    motion = TaughtMotionV2.learn(name, demos)
    spec = motion.to_json()
    spec["verifier"] = "motion_v2"
    spec["encoder"] = encoder_info()["variant"]
    return {"spec": spec}


def _session_start(body: dict) -> dict:
    spec = body["spec"]
    motion = TaughtMotionV2.from_json(spec)
    sid = uuid.uuid4().hex[:12]
    with _lock:
        _sessions[sid] = StreamingMotionV2(motion, fps_hint=float(body.get("fps", 15)))
    return {"sessionId": sid}


def _session_frames(sid: str, body: dict) -> dict:
    with _lock:
        s = _sessions.get(sid)
    if s is None:
        raise KeyError("unknown session")
    frames = [_frame_to_nuvo(f) for f in body.get("frames", [])]
    return s.push(frames)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code: int, obj: dict):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"{}")

    def log_message(self, *a):  # quieter
        pass

    def do_GET(self):
        if self.path == "/motion-v2/health":
            self._send(200, {"ok": True, "encoder": encoder_info(),
                             "sessions": len(_sessions)})
        else:
            self._send(404, {"error": "not found"})

    def do_DELETE(self):
        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "motion-v2" and parts[1] == "session":
            with _lock:
                _sessions.pop(parts[2], None)
            self._send(200, {"ok": True})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        parts = self.path.strip("/").split("/")
        try:
            if parts == ["motion-v2", "learn"]:
                self._send(200, _learn(self._body()))
            elif parts == ["motion-v2", "session"]:
                self._send(200, _session_start(self._body()))
            elif len(parts) == 4 and parts[:2] == ["motion-v2", "session"] and parts[3] == "frames":
                self._send(200, _session_frames(parts[2], self._body()))
            elif len(parts) == 4 and parts[:2] == ["motion-v2", "session"] and parts[3] == "reset":
                with _lock:
                    s = _sessions.get(parts[2])
                if s:
                    s.reset()
                self._send(200, {"ok": s is not None})
            else:
                self._send(404, {"error": "not found"})
        except (KeyError, ValueError) as e:
            self._send(400, {"error": str(e)})
        except Exception as e:  # noqa: BLE001 — dev service, surface everything
            import traceback
            traceback.print_exc()
            self._send(500, {"error": repr(e)})


def main():
    port = int(os.environ.get("MOTION_V2_PORT", "8799"))
    print("[motion-v2] warming encoder ...")
    encoder_info()  # trigger the lazy model load now, not on first request
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[motion-v2] listening on http://0.0.0.0:{port}  "
          f"(encoder={encoder_info()['variant']}, {encoder_info()['device']})")
    print("[motion-v2] point the app at http://<this-mac-LAN-ip>:%d" % port)
    srv.serve_forever()


if __name__ == "__main__":
    main()
