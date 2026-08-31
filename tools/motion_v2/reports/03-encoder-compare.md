# Motion V2 — STEP 5: encoder variant comparison (synthetic)

Generated 2026-08-31 14:22. Same synthetic corpus + nuisance as exp01. `sep` = separation in pooled sd; `acc` = leave-one-out 3-shot accuracy.

## lite_pretrain  (16.0M params)

| strategy | same | cross | sep (sd) | LOO acc |
|---|---|---|---|---|
| mean_pool / euclid | 0.0079 | 0.1068 | 3.78 | **1.0** |
| mean_pool / euclid_l2n | 0.0145 | 0.0962 | 2.979 | **1.0** |
| temporal_stats / euclid_l2n | 0.0643 | 0.2773 | 2.618 | **1.0** |
| temporal_stats / euclid | 0.3924 | 1.6663 | 2.579 | **1.0** |
| velocity_energy / euclid | 0.0397 | 0.1193 | 2.43 | **1.0** |
| temporal_stats / cosine | 0.0082 | 0.0389 | 2.247 | **1.0** |
| mean+velocity / euclid_l2n | 0.0551 | 0.2124 | 2.136 | **1.0** |
| mean_pool_joints / euclid_l2n | 0.0544 | 0.2114 | 2.134 | **1.0** |

best: `mean_pool / euclid` acc 1.0 sep 3.78

## release_action  (42.47M params)

| strategy | same | cross | sep (sd) | LOO acc |
|---|---|---|---|---|
| mean_pool / euclid_l2n | 0.0221 | 0.1448 | 4.009 | **1.0** |
| mean_pool / euclid | 0.1672 | 1.1264 | 3.816 | **1.0** |
| per_frame_emb / dtw | 0.0003 | 0.0063 | 3.126 | **1.0** |
| mean_pool / cosine | 0.0004 | 0.0113 | 2.925 | **1.0** |
| mean_pool_joints / euclid | 2.5171 | 8.704 | 2.644 | **0.889** |
| mean+velocity / euclid | 2.5258 | 8.7171 | 2.64 | **0.889** |
| temporal_stats / euclid | 2.7548 | 9.0941 | 2.532 | **0.889** |
| mean_pool_joints / euclid_l2n | 0.0844 | 0.2832 | 2.508 | **0.889** |

best: `mean_pool / euclid_l2n` acc 1.0 sep 4.009

## Decision

**release_action / mean_pool / euclid_l2n** — LOO acc 1.0, sep 4.009 sd.

_(runtime 14s)_
