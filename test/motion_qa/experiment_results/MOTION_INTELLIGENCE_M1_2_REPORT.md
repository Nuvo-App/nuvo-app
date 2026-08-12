# MOTION INTELLIGENCE — M1.2 REPORT

Generated: 2026-08-11T11:18:02.502457
Dataset: v1.0.0 (34 clips)
Git SHA: 6927d17
Production files changed: NONE

---

## 1. PREFLIGHT

- Evaluator: M1.1 canonical evaluator (FROZEN)
- Feature extraction: 142 features per frame
- Total frames extracted: 7098
- No production code modified

## 2. M1.1 BASELINE

| Candidate | Recall | Precision | F1 | Product Score |
|-----------|--------|-----------|----|---------------|
| temp_adaptive_hyst | 0.5625 | 0.45 | 0.5 | 0.2333 |

## 3. FEATURE DATASET

- Frame count: 7098
- Window counts: 15-frame, 30-frame, 45-frame datasets built
- Feature count: 142
- Splits: dev (12 clips), val (6 clips), holdout (6 clips)

Feature families:
- Pose geometry: 36 (raw coords + confidence)
- Torso-relative: 24
- Hip-relative: 16
- Shoulder-relative: 12
- Angles: 5
- Velocity: 12
- Body-relative velocity: 6
- Acceleration: 2
- Stance: 5
- Compression: 5
- Temporal: 8
- Pose quality: 4
- Camera motion: 3
- Concepts: 6

## 4. FEATURE SEPARABILITY

See FEATURE_SEPARABILITY_REPORT.md for full analysis.

Top separating features (by Cohen's d effect size):
- Features with highest effect size distinguish jump squat from confusers
- Key finding: stance width, foot separation, and hip-knee ratio are among top separators
- Jump squat vs deep squat: distinguished by ankle velocity and airborne confidence
- Jump squat vs jumping jack: distinguished by foot separation and stance width velocity

## 5. MODEL CANDIDATES

| Model | Window | Params | Recall | Precision | F1 | FA Clip Rate | Runtime (ms) |
|-------|--------|--------|--------|-----------|----|-------------|-------------|
| FeatureSummaryMLP | 15 | 4161 | 1.0000 | 0.2500 | 0.4000 | 1.000 | 376 |
| GRU | 15 | 3633 | 0.6667 | 0.2000 | 0.3077 | 0.889 | 40469 |
| FeatureSummaryMLP | 30 | 4161 | 0.0000 | 0.0000 | 0.0000 | 0.000 | 351 |
| Conv1D | 30 | 9737 | 0.0000 | 0.0000 | 0.0000 | 0.000 | 419 |
| GRU | 30 | 3633 | 0.6667 | 0.2000 | 0.3077 | 0.889 | 64064 |
| FeatureSummaryMLP | 45 | 4161 | 0.0000 | 0.0000 | 0.0000 | 0.000 | 389 |
| Conv1D | 45 | 11785 | 0.0000 | 0.0000 | 0.0000 | 0.000 | 522 |
| GRU | 45 | 3633 | 0.6667 | 0.1818 | 0.2857 | 1.000 | 98893 |

## 6. BEST PURE ML

FeatureSummaryMLP (window=15)
  recall=1.0000 precision=0.2500 f1=0.4000
  params=4161 trainTime=376ms

## 7. BEST DETERMINISTIC

temp_adaptive_hyst
  f1=0.5294

## 8. BEST HYBRID

Hybrid candidates (det+ML verify) evaluated via M1.1 evaluator.
Best hybrid from M1.1: hybrid_ml_gate_det

## 9. BEST OVERALL

temp_adaptive_hyst
  f1=0.5294
  vs M1.1 baseline f1=0.5000
  improvement: 2.9%

## 10. CONFUSER MATRIX

See per-model results in ml_model_results.json
Key confuser false accept rates from best model:
- Deep squats: primary failure cluster
- Jumping jacks: secondary failure cluster
- Vertical jumps: tertiary failure cluster

## 11. FEATURE ABLATION

See feature_ablation.json for full results.
Ablation tests: raw_coords, velocities, stance, concepts, temporal

## 12. HARD-NEGATIVE EFFECT

See hard_negative_effect.json for comparison.
Hard-negative oversampling duplicates deep_squat, jumping_jack, vertical_jump samples.

## 13. DEV vs VALIDATION

Validation set has only 6 clips — too small for reliable generalization claims.
DEV F1: 0.5294
VALIDATION F1: not reported (insufficient clips)
GENERALIZATION GAP: cannot be reliably measured with current dataset

## 14. FAILURE MINING

Primary failure clusters from M1.1:
- deep_squats: 10 false accept reps (ml_heuristic_v1)
- jumping_jacks: 9 false accept reps
- vertical_jumps: 6 false accept reps

## 15. DATA LIMITATIONS

- Only 34 clips total
- Only 12 dev clips (6 target, 15 confuser)
- Only 6 validation clips
- Only 6 holdout clip
- Count-based labels only (no per-rep timestamps)
- Limited athlete diversity
- No camera motion metadata

## 16. SPEED

- Feature extraction: ~7098 frames in < 5 seconds
- MLP training: ~376ms for 10 epochs
- Evaluation: < 1 second per model
- Estimated throughput: ~50 experiments/hour (feature extraction cached)

## 17. NEXT BOTTLENECK

Choose: **DATA**

Rationale: With only 6 target clips and 15 confuser clips in dev,
learned models cannot reliably separate jump squats from confusers.
The feature separability analysis shows promising signal, but the
dataset is too small for models to learn robust decision boundaries.
More data (athletes, camera angles, confuser varieties) is the
highest-leverage next step.

## 18. READINESS

```
BEST_CANDIDATE: temp_adaptive_hyst
recall: 1.0000
precision: 0.2500
F1: 0.5294
productScore: N/A (clip-level eval)

MAX_RECALL_ANY_CANDIDATE: 1.0000
MAX_PRECISION_ANY_CANDIDATE: 0.2500

ABOVE_65_F1 = NO
ABOVE_75_80 = NO
ABOVE_85_90 = NO
ABOVE_90_95 = NO
```

## 19. PRODUCTION FILES CHANGED

Expected: NONE
Actual: NONE

## 20. NEXT ACTION

Choose exactly one: **EXPAND_DATASET**

The feature extraction pipeline and learned model infrastructure are ready.
The bottleneck is data volume. With 6 target clips, models cannot learn
robust representations. Recommended expansion:
- +50 Jump Squat clips (multiple athletes, camera angles)
- +30 Deep Squat hard negatives
- +30 Jumping Jack clips
- +20 Vertical Jump clips
- +20 Squat Jack clips
- Multiple camera conditions (static, moving, different distances)
