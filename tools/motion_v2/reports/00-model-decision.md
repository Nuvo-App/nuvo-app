# Motion V2 — pretrained encoder decision

Date: 2026-08-31 · Author: engine work, session continuing from git checkpoint reset.

## Requirement

`motion sequence (T joints over time) → generic representation` that supports
**few-shot / custom matching**, not fixed-label action classification. Must run
offline for experiments now; must be exportable to on-device later.

## Candidates

| Model | Representation | Input skeleton | 2D/3D | Params | Speed (CPU, T≈243) | Export | License (code / weights) | Pretrained ckpt | On-device |
|---|---|---|---|---|---|---|---|---|---|
| **MotionBERT-Lite** (DSTformer, `MB_lite`) | `(T, 17, 512)` motion rep from the pretrained backbone before task heads; masked-reconstruction + 2D→3D pretraining on AMASS + H36M-SH | **17-joint H36M**, 2D + confidence, root-relative, res-normalized | 2D in (lifts internally) | ≈16 M (`dim_feat=256, depth=5, dim_rep=512`) | ~tens of ms | TorchScript / ONNX feasible (transformer, no exotic ops) | Apache-2.0 code · weights trained partly on **H36M (non-commercial)** — OK to prototype/evaluate, must re-pretrain on permissive data or swap weights before shipping | **yes** — `walterzhu/MotionBERT` HF, `checkpoint/pretrain/MB_lite/latest_epoch.bin` (64 MB), pinned rev `370a919` | plausible after distill/quantize (~16 M base) |
| MotionBERT (full, `MB_release`) | `(T, 17, 512)`, `dim_feat=512` | same | 2D in | ≈42 M | ~2–3× lite | same | same caveat | same repo, `checkpoint/pretrain/MB_release/` | heavier |
| MotionAGFormer | 3D pose repr; AGFormer blocks (graph + transformer) | 17-joint H36M | 2D→3D | 2.2 M–19 M variants | fast | ONNX ok | Apache-2.0 code · H36M weights | yes (GitHub releases) | good, but it's a **pose-lifting** model — less "generic motion representation," more "accurate 3D." Use as a comparison if MotionBERT rep is weak. |
| PoseFormerV2 / MixSTE | 3D lifting | 17-joint H36M | 2D→3D | 9–34 M | med | ok | research | yes | lifting-focused, same caveat as AGFormer |
| Skeleton MAE / MAMP (self-sup ST-GCN) | skeleton token embeddings | 25-joint NTU | 3D | ~small | fast | ok | research; NTU weights non-commercial | partial | strong self-sup repr but NTU 25-joint + 3D input assumption; adapter is harder |
| Video encoders (V-JEPA 2, VideoMAE) | pixel-space motion repr | n/a (raw frames) | — | 300 M+ | slow on device | hard | mixed | yes | the "understands objects too" path — **Phase D**, not now (distillation is a project) |

## Decision

**Primary prototype: MotionBERT-Lite pretrained backbone.**

Reasons: (1) it is explicitly a *motion representation* model, not a classifier;
(2) the pretrained backbone output `(T,17,512)` is exactly the interface we need;
(3) 2D-keypoint input matches what Nuvo's pose pipeline already produces (no 3D
sensor); (4) code is Apache-2.0 and the full repo + checkpoints are on Hugging
Face at a pinnable revision — deterministic setup, no Google Drive; (5) ~16 M
params → on-device is realistic after distillation.

**Known caveat (tracked, not blocking):** the *weights* were pretrained partly on
Human3.6M, which is non-commercial. Fine for evaluation. Before V2 becomes the
shipping verifier we must either (a) continue-pretrain / retrain the backbone on
permissively-licensed motion data (AMASS subsets, our own flywheel captures), or
(b) swap to a cleanly-licensed backbone. Recorded in `docs/agents/13`.

**Fallback order if MotionBERT-Lite's representation does not separate
same-motion from different-motion in STEP 5:** MotionBERT-full → MotionAGFormer
→ a small self-supervised ST-GCN trained on our fixtures. **Not** a return to V1
threshold tuning.

## Pinned versions

- HF repo: `walterzhu/MotionBERT` @ `370a9196aa3c89198b134c82476143b01c0fb32c`
- Config: `configs/pretrain/MB_lite.yaml` → `maxlen=243, dim_feat=256, mlp_ratio=4,
  depth=5, dim_rep=512, num_heads=8, att_fuse=True, num_joints=17`
- Python 3.12 · torch pinned in `requirements.txt`
