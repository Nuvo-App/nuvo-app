# Motion V2 — STEP 5: representation separation (synthetic corpus)

Generated 2026-08-31 12:13 · MotionBERT-Lite pretrained backbone · 18 synthetic recordings, 3 classes, nuisance = speed/translation/mirror/noise/dropout.

`separation_sd` = (cross_mean_dist - same_mean_dist) / pooled_sd. > ~0.8 is a usable signal; `loo_3shot_acc` is the money metric (hold one recording out, match to nearest 3-shot prototype).

| strategy | same_dist | cross_dist | sep (sd) | LOO 3-shot acc |
|---|---|---|---|---|
| mean_pool / euclid | 0.0079 | 0.1068 | 3.78 | **1.0** |
| mean_pool / euclid_l2n | 0.0145 | 0.0961 | 2.979 | **1.0** |
| temporal_stats / euclid_l2n | 0.0643 | 0.2773 | 2.618 | **1.0** |
| temporal_stats / euclid | 0.3924 | 1.6664 | 2.579 | **1.0** |
| velocity_energy / euclid | 0.0397 | 0.1193 | 2.43 | **1.0** |
| temporal_stats / cosine | 0.0082 | 0.0389 | 2.247 | **1.0** |
| mean+velocity / euclid_l2n | 0.0551 | 0.2124 | 2.136 | **1.0** |
| mean_pool_joints / euclid_l2n | 0.0544 | 0.2114 | 2.134 | **1.0** |
| mean+velocity / euclid | 0.3349 | 1.2629 | 2.075 | **1.0** |
| mean_pool_joints / euclid | 0.3311 | 1.2572 | 2.073 | **1.0** |
| mean_pool / cosine | 0.0002 | 0.0053 | 2.026 | **1.0** |
| mean+velocity / cosine | 0.0062 | 0.0233 | 1.587 | **1.0** |
| mean_pool_joints / cosine | 0.0061 | 0.0231 | 1.582 | **1.0** |
| velocity_energy / euclid_l2n | 0.31 | 0.7493 | 1.288 | **0.889** |
| per_frame_emb / dtw | 0.0022 | 0.0047 | 0.886 | **0.667** |
| velocity_energy / cosine | 0.1557 | 0.2893 | 0.558 | **0.889** |

**Best:** `mean_pool / euclid` — LOO 3-shot acc 1.0, separation 3.78 sd.

_(runtime 4.6s)_

## Read

Green light for the direction. The pretrained MotionBERT-Lite representation
separates distinct motion classes under speed / translation / mirror / noise /
dropped-joint nuisance without any movement-specific logic — `mean_pool`
(temporal+joint mean of the 512-d rep) with Euclidean distance gives 3.78 sd
separation and 100% leave-one-out 3-shot accuracy on the synthetic corpus.

**Shortlist for STEP 6:** `mean_pool` and `temporal_stats` (mean+std per joint),
Euclidean or cosine. `velocity_energy` alone is weaker; `per_frame_emb / dtw`
underperformed here (0.67) — likely because synthetic motions are too smooth for
temporal alignment to help; re-check on real captures.

**What synthetic does NOT prove:** generalization to *similar* real movements
(squat vs sumo-squat, wave vs arm-raise), or robustness to real phone pose
jitter / foreshortening / partial occlusion. That needs device fixtures (STEP 4
pipe is built). This result means the encoder is not degenerate and the plumbing
is correct — proceed to the 3-shot learner and re-run this harness on real data.
