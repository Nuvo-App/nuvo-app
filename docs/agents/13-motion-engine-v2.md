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
| 5 representation | ✅ `reports/01`,`03` — action-finetuned backbone (`release_action`, default) beats lite: DTW LOO 0.67→1.0 |
| 6 3-shot `match()` | ✅ synthetic TP 3/3 · TN 6/6 · FP 0 · FN 0, stable across both encoders + threshold schemes. two AND-ed signals: proto_dist + normalized-DTW traj_dist |
| 7 segmentation | ✅ embedding-velocity trim — **no "hold still" ritual** |
| 8 rep detection | ~ isolated reps exact, FP 0; multi-rep undercounts on smooth synthetic (NMS spacing) — needs real inter-rep gaps |
| 4 raw fixture export | ✅ Flutter side + Python loader |
| **MVP wired into the app** | ✅ dev inference service (`tools/motion_v2/service/`) + Flutter `MotionVerifierV2` / `MotionV2ServiceClient` + Teach Nuvo test mode behind `--dart-define=NUVO_MOTION_V2=true`. Learn → session → streamed frames → `newRep` → `NuvoRepPulse` `+1`. `test_service.py`: invented motion recognized, unrelated → 0. |
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

## CURRENT TASK — remove the Mac service, make V2 the default on-device engine

Owner directive: `flutter run --release` must Teach + recognize a new movement
with **no Python process, no dart-define, no LAN IP**. V2 becomes the default
Teach Nuvo engine; V1 drops behind `NUVO_DIAGNOSTICS`. `tools/motion_v2/` stays
as reference/research; the HTTP service stays as a diagnostics/comparison tool
only.

### Runtime decision (research done this session)

- Flutter ONNX plugins on pub: **`onnxruntime` 1.4.1** (android/ios/macos/…,
  mature) and **`flutter_onnxruntime` 1.8.4** (adds web, actively maintained).
- `bukuroo/MotionBERT-3d-ONNX` on HF confirms DSTformer exports to ONNX cleanly
  (they ship 27/81/243-frame pose3d exports). We need our own export of the
  **backbone `return_rep`** output, not the pose3d head.
- **Route: ONNX Runtime Mobile.** Core ML is an iOS-only second export; revisit
  only if ORT latency is unacceptable.

### Checkpoints (push each to main)

1. `motion-v2: export production encoder runtime`
   `tools/motion_v2/scripts/export_onnx.py` — export `release_action` (and
   `lite_pretrain`) backbone with `return_rep=True`, fixed seq len (try 64;
   chunk longer inputs in Dart like `mb_encoder.encode`). Verify
   onnxruntime-CPU output vs PyTorch < 1e-3 abs. int8 dynamic-quantize; record
   size (fp32 ~170MB / int8 ~43MB for 42M; lite int8 ~16MB). Golden fixtures for
   Dart parity.
2. `motion-v2: add native inference bridge`
   Add the ORT plugin to `pubspec.yaml` (owner-directed). `MotionV2OnnxEncoder`
   loads the bundled `.onnx` from `assets/models/`, `encode(seq)->(T,17,512)`.
   Measure load time + per-inference ms on device.
3. `motion-v2: port three-shot learner to app runtime`
   Dart port of the deterministic pipeline (all in
   `lib/features/races/ai/motion_v2/engine/`):
   `nuvo_to_h36m` (joint map + MotionBERT `crop_scale`), `per_frame_embedding`,
   `mean_pool`, `resample_seq`, `dtw_distance`, `segment_action`,
   `traj_distance`, `TaughtMotionV2.learn` / `.match`, `StreamingMotionV2`.
   Parity tests vs Python golden JSON (embeddings, proto/traj distances, match
   decision, learned thresholds).
4. `motion-v2: make V2 default Teach Nuvo engine`
   Drop `kMotionV2Enabled`; `TeachMovementScreen` uses `MotionV2NativeRuntime`
   by default. V1 (`CustomPoseSequenceRuntime`) only when `NUVO_DIAGNOSTICS`.
   Remove dev-only UX (service URL, "Python service" copy, connection errors).
5. `motion-v2: remove local service runtime dependency`
   `MotionV2ServiceClient` kept but only reachable from the diagnostics panel
   (native-vs-Python compare). Release runtime never touches it.
6. `motion-v2: verify release-mode custom motion flow`
   `flutter build ios --release` / `apk --release` succeeds; run the 10-point
   acceptance checklist from the directive. Model-size + latency numbers in
   `reports/`.

### Parity rule

Do NOT swap the working encoder for a weaker approximation to ship. If exact
MotionBERT export fails, prove it with a real failed export/benchmark first.
42M `release_action` is the reference; if it's too heavy on-device, THEN
evaluate int8 → lite variant → distillation — not V1.

### Model packaging

Bundle for now (`assets/models/motion_v2_encoder.onnx`), measure app-size
impact. Move to OTA model delivery later if size is unreasonable.

### Status — checkpoints 1-6 landed

- `3e79940` — native V2 is the default Teach Nuvo engine. No flag, no service.
  `NUVO_FORCE_V1` flips to the legacy geometric verifier for comparison only.
- ONNX Runtime: `onnxruntime` ^1.4.1 pub plugin → `onnxruntime-c` **1.15.1**
  static xcframework, linked straight into the Runner binary (`_OrtGetApiBase`
  present; +~30 MB). No separate framework.
- Model: `assets/models/motion_v2_encoder.onnx` (81 MB fp16) bundles into
  `App.framework/flutter_assets/assets/models/` — verified in the release .app.
- `flutter build ios --release --no-codesign` **succeeds** (Runner.app 182 MB).
- `flutter build apk --release` **fails** on `sign_in_with_apple` 5.0.0
  (`Unresolved reference 'Registrar'` — pre-existing, unrelated to Motion V2;
  needs a plugin bump or the v3-embedding shim).
- Device inference latency: **not yet measured** — needs the physical run.
  The diagnostics panel (`NUVO_DIAGNOSTICS` / debug) prints
  `runtime / encoder / model / frames buffered / last inference ms /
  last protoDist / last trajSim / last match / count` (STEP 8).

### After this: Project A — continuous rep detection.

## Deferred (still valuable, not blocking)

- Real fixtures (`tools/motion_v2/fixtures/README.md`) + `exp10_real.py`.
- STEP 8 NMS tuning on real data.
- STEP 9 V1-vs-V2 benchmark.
