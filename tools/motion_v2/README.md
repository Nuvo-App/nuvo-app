# Nuvo Motion Engine V2

**Goal:** replace V1's hand-engineered pose-feature + similarity + threshold +
state-machine verifier with a **pretrained human-motion encoder** + a thin
few-shot matcher.

```
phone pose stream  →  Nuvo→model skeleton adapter  →  pretrained motion encoder
                                                          │
                        3 demos ─────────────────────────┤→  TaughtMotionV2 (prototype / references)
                                                          │
                        live sequence ───────────────────┴→  generic match progression → rep count → +1
```

V1 (`lib/features/races/ai/custom_pose/`) stays as a **fallback + benchmark
baseline**. Do not tune V1 thresholds. Do not add hand-crafted movement
features. The encoder owns representation; the matcher owns few-shot; a generic
progression detector owns segmentation and counting. No movement-specific logic,
no "hold still" ritual.

## Layout

| dir | what |
|---|---|
| `vendor/` | official upstream model code (downloaded, pinned, gitignored) |
| `checkpoints/` | pretrained weights (downloaded, pinned, gitignored) |
| `adapter/` | Nuvo landmarks → model skeleton (committed, tested) |
| `scripts/` | deterministic setup + smoke tests + experiment runners (committed) |
| `experiments/` | representation / few-shot / rep-detection experiments (committed) |
| `fixtures/` | raw pose-stream captures for offline replay (committed, small) |
| `reports/` | generated experiment results + the model decision matrix (committed) |

## Setup

```bash
cd tools/motion_v2
./scripts/setup.sh            # py3.12 venv + deps + pinned model download
./scripts/smoke_test.py       # loads the encoder, encodes a synthetic sequence
```

`setup.sh` is deterministic: it pins the Python version, the pip requirements,
and the Hugging Face model revision. Nothing large is committed.

## Status

See `reports/00-model-decision.md` for the model choice and
`reports/` for experiment output. Progress is pushed to `main` per checkpoint
(`motion-v2: <what>`).
