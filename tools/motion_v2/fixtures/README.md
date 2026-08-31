# Motion V2 fixtures — real device captures

The V2 experiments (`exp10_real.py`) run on real Teach Nuvo captures, not
synthetic. Add fixtures here.

## Capture one

1. Run the app with `--dart-define=NUVO_DIAGNOSTICS=true` (or a debug build).
2. Compete → Start a race → **"Don't see your movement?"** → Teach Nuvo.
3. Teach a movement: Record → do it → Stop → Save, ×3.
4. On the summary screen, open the debug panel → **Copy debug report**.
5. Save the JSON as `tools/motion_v2/fixtures/<movement>_1.json`.
   The whole debug report is fine — the loader pulls the `rawStreamFixture` key.

## Naming

| file | used for |
|---|---|
| `<movement>_1.json`, `<movement>_2.json` … | training + leave-one-out `match()` eval |
| `<movement>_reps<k>.json` | one demo containing **k** reps → rep-detection eval |

Capture **≥ 2 different movements** so cross-rejection can be measured, and
capture a couple that are *similar* (squat vs sumo-squat, wave vs arm-raise) —
those are the hard cases synthetic data can't test.

## Then

```bash
source tools/motion_v2/.venv/bin/activate
python tools/motion_v2/experiments/exp10_real.py     # -> reports/10-real.md
python tools/motion_v2/experiments/exp01_representation.py   # (still synthetic)
```

Fixtures are small (pose landmarks only, no video) and **are committed** — they
are the seed of the eval set and eventually the learned-encoder training set.
