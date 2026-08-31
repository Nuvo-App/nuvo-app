# Motion Engine V2 — pretrained encoder + few-shot matcher

**Goal:** "Teach Nuvo" — a user demonstrates a movement 3×, Nuvo learns it, then
recognizes each completed rep live and moves the race board. V1
(`lib/features/races/ai/custom_pose/`, hand-engineered pose features + similarity
+ thresholds + a large state machine) does not generalize; V2 replaces the
*recognition method* with a pretrained motion encoder + a thin few-shot matcher.

V1 stays as a **fallback + benchmark baseline**. Do not tune V1 thresholds or
add hand-crafted movement features as "V2 work".

## Where it lives

```
tools/motion_v2/              (Python — offline research + engine prototype)
  reports/00-model-decision.md    why MotionBERT-Lite
  reports/0N-*.md                 experiment results
  mb_encoder.py                   seq (T,17,3) -> representation (T,17,512)
  adapter/nuvo_to_h36m.py         Nuvo 33 BlazePose landmarks -> 17-joint H36M
  engine/taught_motion.py         TaughtMotionV2.learn(name, demos) / .match(frames)
  engine/rep_detector.py          RepDetectorV2 — generic rep counting
  experiments/                    exp01 representation, exp02 3-shot, exp10 real
  fixtures/                       real device captures (see fixtures/README.md)
  scripts/setup.sh                deterministic env: py3.12 + pinned HF revision
```

The Flutter side that feeds it: **Teach Nuvo** (`/races/teach`,
`teach_movement_screen.dart`). Its debug report ("Copy debug report", behind
`kDebugMode || NUVO_DIAGNOSTICS`) emits `rawStreamFixture` — the raw pose stream
per demo — which `tools/motion_v2/fixtures/load.py` reads.

## Architecture (three tiers)

```
SERVER   big encoder — continually fine-tuned on flywheel data, review queue,
         distillation teacher                     [not built — post-launch]
   |  distill + quantize
ON DEVICE  small motion encoder (MotionBERT-Lite, ~16M) — frozen, OTA-updated
   |  (T,17,512) representation
PER MOVEMENT  TaughtMotionV2 — prototypes + canonical trajectory + rest emb,
              learned from 3 demos. ~KB. name is metadata, never used to verify.
```

## Status (2026-08-31, commits `962b8bb … 9948670`)

| step | state |
|---|---|
| 1 encoder bootstrap | ✅ MotionBERT-Lite loads, `smoke_test.py` passes |
| 2 model decision | ✅ `reports/00` — MotionBERT-Lite, license caveat tracked (H36M non-commercial → re-pretrain before ship) |
| 3 skeleton adapter | ✅ `adapter/`, 11 tests, viz looks right |
| 5 representation | ✅ `reports/01` — encoder separates motion classes, 3.78 sd, `mean_pool` best |
| 6 3-shot `match()` | ✅ synthetic: TP 3/3, FP 0. proto_margin separates same/different ~20× |
| 7 segmentation | ✅ embedding-velocity trim — **no "hold still" ritual** |
| 8 rep detection | ~ works (matched filter + re-encode per burst); jumping_jack exact, others undercount on smooth synthetic; FP low |
| 4 raw fixture export | ✅ Flutter side + Python loader |
| 9 V1 vs V2 benchmark | ⏳ blocked on real fixtures (V1 is Dart) |
| 10 phone | ⏳ after `match()` validates on real fixtures |

## Rules for continuing

- **No hand-crafted movement features. No per-movement branches. Name is
  metadata.** If a change adds movement-specific logic it is V1, not V2.
- The teaching UX stays `Record → move → Stop → Save` ×3. Segmentation /
  start-end inference is the engine's job.
- Experiments are deterministic; commit the report with the result — including
  failures and *why* (see `reports/02` for the pattern). Push each working
  checkpoint to `main` (`motion-v2: <what>`).
- If MotionBERT-Lite's representation fails on real fine-grained movements: try
  MotionBERT-full → MotionAGFormer → a small self-supervised ST-GCN on our
  fixtures. **Not** a return to V1 tuning. Record why each failed.
- Do not commit checkpoint binaries — `scripts/setup.sh` reproduces them from a
  pinned HF revision. See `.gitignore` `tools/motion_v2/` block.
- License: MotionBERT weights are pretrained partly on Human3.6M (non-commercial).
  Fine for evaluation; before V2 is the shipping verifier, re-pretrain the
  backbone on permissive data (AMASS subsets + flywheel captures) or swap it.

## Next concrete steps

1. Capture real fixtures (`tools/motion_v2/fixtures/README.md`) — ≥2 movements,
   include *similar* pairs.
2. `python experiments/exp10_real.py` → `reports/10-real.md`.
3. Tune STEP 8 (NMS spacing, match threshold) on real data.
4. STEP 9 benchmark: a Dart harness runs V1 (`CustomPoseSequenceRuntime`) on the
   same fixtures; compare reps / FP / FN / latency.
5. STEP 10: port `TaughtMotionV2` + `RepDetectorV2` to Dart (or run the encoder
   on-device via LiteRT/ONNX), wire into `ai_motion_proof_screen_io.dart` behind
   a `verifierType == 'motion_v2'` branch, feed `NuvoRepPulse`.
