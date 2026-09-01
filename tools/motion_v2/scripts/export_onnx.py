#!/usr/bin/env python
"""STEP 1 — export the Motion V2 encoder (MotionBERT release_action backbone,
`return_rep=True`) to ONNX FP32, and verify parity against PyTorch on a real
fixture-shaped input.

Output:
  tools/motion_v2/checkpoints/onnx/motion_v2_encoder_<variant>.onnx
  (also copied to ../../assets/models/ for the Flutter bundle)

    python tools/motion_v2/scripts/export_onnx.py [--variant release_action] [--seqlen 96]
"""
import argparse
import os
import shutil
import sys

import numpy as np
import torch

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, ".."))
import mb_encoder  # noqa: E402
from mb_encoder import NUM_JOINTS, encode  # noqa: E402

OUT_DIR = os.path.join(_HERE, "..", "checkpoints", "onnx")
ASSET_DIR = os.path.join(_HERE, "..", "..", "..", "assets", "models")


class RepWrapper(torch.nn.Module):
    """Fixes return_rep=True so ONNX has a single clean output."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, pose):  # pose: (B, T, 17, 3) -> rep: (B, T, 17, 512)
        return self.backbone(pose, return_rep=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default="release_action")
    ap.add_argument("--seqlen", type=int, default=96, help="dummy T for tracing")
    ap.add_argument("--opset", type=int, default=17)
    args = ap.parse_args()

    mb_encoder.set_variant(args.variant)
    model, _ = mb_encoder._load(args.variant)
    model = model.to("cpu").eval()
    wrapper = RepWrapper(model).eval()

    os.makedirs(OUT_DIR, exist_ok=True)
    onnx_path = os.path.join(OUT_DIR, f"motion_v2_encoder_{args.variant}.onnx")

    dummy = torch.randn(1, args.seqlen, NUM_JOINTS, 3, dtype=torch.float32)
    torch.onnx.export(
        wrapper, (dummy,), onnx_path,
        input_names=["pose"], output_names=["rep"],
        dynamic_axes={"pose": {1: "T"}, "rep": {1: "T"}},
        opset_version=args.opset, do_constant_folding=True,
    )
    print(f"exported {onnx_path}  ({os.path.getsize(onnx_path)/1e6:.1f} MB)")

    # ---- parity: PyTorch vs onnxruntime, on fixture-shaped inputs ----
    import onnxruntime as ort
    sess = ort.InferenceSession(onnx_path, providers=["CPUExecutionProvider"])

    print(f"\nparity (variant={args.variant}):")
    worst_mae = worst_max = 0.0
    worst_cos = 1.0
    for T in (32, 64, 96, 150):
        x = np.random.default_rng(T).standard_normal((1, T, NUM_JOINTS, 3)).astype(np.float32)
        with torch.no_grad():
            pt = wrapper(torch.from_numpy(x)).numpy()
        on = sess.run(["rep"], {"pose": x})[0]
        assert pt.shape == on.shape == (1, T, NUM_JOINTS, 512), (pt.shape, on.shape)
        mae = float(np.abs(pt - on).mean())
        mx = float(np.abs(pt - on).max())
        a, b = pt.reshape(-1), on.reshape(-1)
        cos = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))
        worst_mae = max(worst_mae, mae)
        worst_max = max(worst_max, mx)
        worst_cos = min(worst_cos, cos)
        print(f"  T={T:>3}  MAE={mae:.2e}  max={mx:.2e}  cos={cos:.7f}")

    print(f"\nworst: MAE={worst_mae:.2e}  max={worst_max:.2e}  cos={worst_cos:.7f}")
    ok = worst_mae < 1e-4 and worst_cos > 0.99999
    print("FP32 PARITY OK" if ok else "FP32 PARITY FAIL")
    if not ok:
        sys.exit(1)

    # ---- fp16 weights: fp32 (170 MB) is over GitHub's 100 MB file cap, so the
    #      bundled asset is fp16. Verify fp16 parity too before shipping it. ----
    from onnxconverter_common import float16
    m16 = float16.convert_float_to_float16(
        __import__("onnx").load(onnx_path), keep_io_types=True)
    onnx_fp16 = onnx_path.replace(".onnx", "_fp16.onnx")
    __import__("onnx").save(m16, onnx_fp16)
    sess16 = ort.InferenceSession(onnx_fp16, providers=["CPUExecutionProvider"])
    print(f"\nfp16 ({os.path.getsize(onnx_fp16)/1e6:.1f} MB) parity:")
    w16_mae = w16_cos = None
    for T in (32, 64, 96, 150):
        x = np.random.default_rng(T + 1).standard_normal((1, T, NUM_JOINTS, 3)).astype(np.float32)
        with torch.no_grad():
            pt = wrapper(torch.from_numpy(x)).numpy()
        on = sess16.run(["rep"], {"pose": x})[0]
        mae = float(np.abs(pt - on).mean())
        a, b = pt.reshape(-1), on.reshape(-1)
        cos = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-30))
        w16_mae = mae if w16_mae is None else max(w16_mae, mae)
        w16_cos = cos if w16_cos is None else min(w16_cos, cos)
        print(f"  T={T:>3}  MAE={mae:.2e}  cos={cos:.6f}")
    ok16 = w16_mae < 5e-3 and w16_cos > 0.9999
    print(f"worst fp16: MAE={w16_mae:.2e} cos={w16_cos:.6f}  {'FP16 PARITY OK' if ok16 else 'FP16 PARITY FAIL'}")

    os.makedirs(ASSET_DIR, exist_ok=True)
    asset = os.path.join(ASSET_DIR, "motion_v2_encoder.onnx")
    shutil.copyfile(onnx_fp16, asset)
    print(f"\nbundled -> {os.path.relpath(asset, os.path.join(_HERE, '..', '..', '..'))}"
          f"  ({os.path.getsize(asset)/1e6:.1f} MB, fp16)")
    if not ok16:
        sys.exit(1)


if __name__ == "__main__":
    main()
