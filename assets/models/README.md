# Bundled models

`motion_v2_encoder.onnx` — MotionBERT `release_action` backbone (NTU-60
action-finetuned, 42M params), `return_rep` output, **fp16** (~85 MB).

Regenerate: `python tools/motion_v2/scripts/export_onnx.py`
(fp32 is ~170 MB — over GitHub's file cap — so the bundled asset is fp16;
fp16 parity vs fp32: MAE ~1e-4, cosine 1.000000).

Input  `pose` : float32 (1, T, 17, 3)  — H36M-17 joints, (x, y, confidence),
                x,y sequence-normalized to [-1,1] (MotionBERT crop_scale).
Output `rep`  : float32 (1, T, 17, 512) — motion representation.
