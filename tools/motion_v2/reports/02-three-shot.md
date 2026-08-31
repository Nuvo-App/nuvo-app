# Motion V2 — STEP 6+8: 3-shot learner + generic rep detection (synthetic)

Generated 2026-08-31 14:23 · MotionBERT-Lite · 3 demos/movement.

## match() — same-family recognition

| taught | query | is_same_family | score | proto_dist | margin | traj_sim |
|---|---|---|---|---|---|---|
| jumping_jack | jumping_jack | True | 0.82 | 0.075 | 0.26 | 1.00 |
| jumping_jack | squat | False | 0.00 | 1.182 | 4.15 | 0.99 |
| jumping_jack | arm_wave | False | 0.00 | 0.498 | 1.75 | 1.00 |
| squat | jumping_jack | False | 0.00 | 1.196 | 3.53 | 0.99 |
| squat | squat | True | 0.89 | 0.052 | 0.15 | 1.00 |
| squat | arm_wave | False | 0.00 | 1.308 | 3.86 | 0.99 |
| arm_wave | jumping_jack | False | 0.30 | 0.461 | 0.45 | 1.00 |
| arm_wave | squat | False | 0.00 | 1.302 | 1.27 | 0.99 |
| arm_wave | arm_wave | True | 0.89 | 0.042 | 0.04 | 1.00 |

match: TP=3 TN=6 FP=0 FN=0

## count_reps() — generic repetition detection

| taught | sequence | expected | detected |
|---|---|---|---|
| jumping_jack | 1× jumping_jack | 1 | 1 |
| jumping_jack | 3× jumping_jack | 3 | 1  ⚠ |
| jumping_jack | 5× jumping_jack | 5 | 2  ⚠ |
| jumping_jack | 3× squat (wrong) | 0 | 0 |
| jumping_jack | random flailing | 0 | 0 |
| squat | 1× squat | 1 | 1 |
| squat | 3× squat | 3 | 1  ⚠ |
| squat | 5× squat | 5 | 4  ⚠ |
| squat | 3× jumping_jack (wrong) | 0 | 0 |
| squat | random flailing | 0 | 0 |
| arm_wave | 1× arm_wave | 1 | 1 |
| arm_wave | 3× arm_wave | 3 | 1  ⚠ |
| arm_wave | 5× arm_wave | 5 | 3  ⚠ |
| arm_wave | 3× jumping_jack (wrong) | 0 | 0 |
| arm_wave | random flailing | 0 | 0 |

rep counting: total abs error over 9 correct sequences = 12; false positives on wrong-motion + flailing = 0

_(runtime 23.4s)_
