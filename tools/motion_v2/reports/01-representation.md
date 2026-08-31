# Motion V2 — STEP 5: representation separation (synthetic corpus)

Generated 2026-08-31 14:23 · MotionBERT-Lite pretrained backbone · 18 synthetic recordings, 3 classes, nuisance = speed/translation/mirror/noise/dropout.

`separation_sd` = (cross_mean_dist - same_mean_dist) / pooled_sd. > ~0.8 is a usable signal; `loo_3shot_acc` is the money metric (hold one recording out, match to nearest 3-shot prototype).

| strategy | same_dist | cross_dist | sep (sd) | LOO 3-shot acc |
|---|---|---|---|---|
| mean_pool / euclid_l2n | 0.0221 | 0.1448 | 4.009 | **1.0** |
| mean_pool / euclid | 0.1672 | 1.1264 | 3.816 | **1.0** |
| per_frame_emb / dtw | 0.0003 | 0.0063 | 3.126 | **1.0** |
| mean_pool / cosine | 0.0004 | 0.0113 | 2.925 | **1.0** |
| mean_pool_joints / euclid | 2.5171 | 8.704 | 2.644 | **0.889** |
| mean+velocity / euclid | 2.5258 | 8.7171 | 2.64 | **0.889** |
| temporal_stats / euclid | 2.7548 | 9.0941 | 2.532 | **0.889** |
| mean_pool_joints / euclid_l2n | 0.0844 | 0.2832 | 2.508 | **0.889** |
| mean+velocity / euclid_l2n | 0.0847 | 0.2836 | 2.504 | **0.889** |
| temporal_stats / euclid_l2n | 0.0919 | 0.2946 | 2.399 | **0.889** |
| mean_pool_joints / cosine | 0.0087 | 0.0413 | 2.096 | **0.889** |
| mean+velocity / cosine | 0.0087 | 0.0414 | 2.091 | **0.889** |
| temporal_stats / cosine | 0.0101 | 0.0447 | 1.969 | **0.889** |
| velocity_energy / euclid | 0.204 | 0.4754 | 1.631 | **0.889** |
| velocity_energy / euclid_l2n | 0.3084 | 0.627 | 1.206 | **0.889** |
| velocity_energy / cosine | 0.1047 | 0.2091 | 0.66 | **0.889** |

**Best:** `mean_pool / euclid_l2n` — LOO 3-shot acc 1.0, separation 4.009 sd.

_(runtime 4.7s)_
