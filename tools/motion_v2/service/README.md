# Motion V2 dev inference service

**MVP integration milestone — not production.** Lets Teach Nuvo run the full
`teach → learn → live camera → +1` loop against MotionBERT while on-device export
is a later project. The phone talks to this over your LAN.

## Run

```bash
tools/motion_v2/scripts/setup.sh          # once
source tools/motion_v2/.venv/bin/activate
python tools/motion_v2/service/app.py       # 0.0.0.0:8799
```

Find your Mac's LAN IP (`ipconfig getifaddr en0`), then launch the app pointed
at it:

```bash
flutter run \
  --dart-define=NUVO_MOTION_V2=true \
  --dart-define=NUVO_MOTION_V2_URL=http://<mac-lan-ip>:8799
```

Phone and Mac must be on the same Wi‑Fi.

## What it does

| endpoint | |
|---|---|
| `POST /motion-v2/learn` | 3 demo pose streams → `TaughtMotionV2Spec` |
| `POST /motion-v2/session` | `{spec}` → `{sessionId}` (rolling buffer) |
| `POST /motion-v2/session/<id>/frames` | append frames → `MotionV2RuntimeResult` |
| `POST /motion-v2/session/<id>/reset` · `DELETE /motion-v2/session/<id>` | |
| `GET /motion-v2/health` | encoder info + session count |

Stdlib `http.server` (threaded). No extra deps beyond the base venv. One phone,
one dev machine — that's the design point.

## Test it (no phone)

```bash
python tools/motion_v2/service/test_service.py
```

Learns an *invented* motion from synthetic demos, streams an unseen 4th
performance → `+1`, streams an unrelated motion → `0`.

## Frame wire format

```json
{"t": <ms>, "w": <px>, "h": <px>,
 "points": {"leftShoulder": [x, y, z, likelihood], ...}}
```

`x,y` image-normalized `[0,1]`, matching `NuvoPoseFrame`. The Flutter client
(`lib/features/races/ai/motion_v2/motion_v2_client.dart`) serializes this.
