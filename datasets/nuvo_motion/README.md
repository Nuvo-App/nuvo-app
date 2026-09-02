# datasets/nuvo_motion

Evaluation / training fixtures derived from real `NuvoMotionDiagnosticSession`s
(schema 1). Produced by:

    tools/motion_v2/.venv/bin/python3 tools/motion_v2/replay_session.py \
        <session>.json.gz --to-fixture datasets/nuvo_motion/<name>

Each `<name>/fixture.json`:

    {
      "sourceSession": "MV2-...",
      "movementName": "...",
      "supports":        [ [wire frames]  x3 ],   # the 3 teaching demos
      "heldOutPositive": [ wire frames ],         # the failed / successful 4th attempt
      "meta": { ... }                             # engine versions at capture time
    }

Internal labels (`movementName`, positive/negative role) are used ONLY for
offline evaluation and metric-head training. The production Teach Nuvo runtime
never sees a movement label — it always works from the user's 3 examples.

Negatives for a fixture are drawn from OTHER fixtures' supports + the synthetic
bank (`tools/motion_v2/adapter/synthetic_nuvo.py`).

Do not commit RGB video here — pose/skeleton sequences only.
