# NUVO MOTION LAB — OVERNIGHT REPORT

Generated: 2026-08-11T11:14:28.630862

---

## EXECUTIVE SUMMARY (30-second read)

Runtime: 0h 0m
Experiments attempted: 3
Experiments completed: 3
Experiments failed: 0
Champion changes: 1
Throughput: 3.0 exp/s (10800 exp/h)
Research stage: broadExploration
Validation confirmations: 0
Final holdout evaluated: YES

### STARTING CHAMPION
Recall: 0.5625
Precision: 0.5000
F1: 0.5294
False accept rate: 0.2222

### ENDING CHAMPION
Experiment: SEED-000000
Family: temporal
Recall: 0.5625
Precision: 0.5000
F1: 0.5294
False accept rate: 0.2222
Exact count quality: 0.0000
Confirmed runs: 0

### HOLDOUT EVALUATION
Holdout F1: 0.2857
Holdout Recall: 0.2000
Holdout Precision: 0.5000
Holdout FA Clip Rate: 0.200
Overfitting gap (dev - holdout): 0.2437
WARNING: Significant overfitting detected — champion may not generalize

### PROMOTION REASON
Initial champion (no prior champion to compare)

### IMPROVEMENT
+0.0000 F1 points

### GATES
75/90: FAIL
85/95: FAIL
90/95: FAIL

### PRODUCTION READY
NO
INSUFFICIENT_DATA_FOR_PRODUCTION_CLAIM

### NEXT BOTTLENECK
See family analysis below

### MOST IMPORTANT DISCOVERY
mlp_w15_h16_l2_v1: F1=0.4615
  MLP: window=15, hidden=16, layers=2, lr=0.01, epochs=10, thresh=0.5

### NEXT HUMAN ACTION
Review failure clusters and consider data expansion or feature engineering

---

## DETAILED ANALYSIS

### Experiment Family Performance

| Family | Experiments | Best F1 | Plateaued | Runtime (ms) |
|--------|-------------|---------|-----------|-------------|
| temporal | 0 | 0.0000 | NO | 0 |
| camera | 1 | 0.4167 | NO | 82 |
| signal_quality | 0 | 0.0000 | NO | 0 |
| geometric | 0 | 0.0000 | NO | 0 |
| confuser_specialist | 0 | 0.0000 | NO | 0 |
| mlp | 2 | 0.4615 | NO | 73 |
| conv1d | 0 | 0.0000 | NO | 0 |
| gru | 0 | 0.0000 | NO | 0 |
| hybrid | 0 | 0.0000 | NO | 0 |
| ensemble | 0 | 0.0000 | NO | 0 |

### Champion History

1. SEED-000000: temp_adaptive_hyst F1=0.5294

### Learning Curve

| Target Clips | F1 | Recall | Precision |
|-------------|-----|--------|-----------|
| 3 | 0.5294 | 0.5625 | 0.5000 |

### Failure Clusters

- **FALSE_ACCEPT_NORMAL_SQUATS**: Champion false-accepts on normal_squats: 1 clips, 2 reps
  - Reason: Normal squat has compression but no flight phase
  - Proposed: Investigate specific feature differences between normal_squats and jump_squats
- **FALSE_ACCEPT_DEEP_SQUATS**: Champion false-accepts on deep_squats: 1 clips, 3 reps
  - Reason: Deep squat compression pattern resembles jump squat descent phase
  - Proposed: Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout
- **FALSE_ACCEPT_JUMPING_JACKS**: Champion false-accepts on jumping_jacks: 1 clips, 1 reps
  - Reason: Jumping jack airborne phase and vertical motion triggers flight detection
  - Proposed: Add stance-width velocity gate: reject if foot separation oscillates without net compression
- **FALSE_ACCEPT_SQUAT_JACKS**: Champion false-accepts on squat_jacks: 1 clips, 2 reps
  - Reason: Squat jack combines squat + jump, closely resembling jump squat
  - Proposed: Add temporal ordering gate: require compression before airborne phase
- **LOW_RECALL_TARGET**: Champion recall is 0.563 — below 0.75 gate
  - Reason: Detector may be too conservative or missing key motion phases
  - Proposed: Try relaxed temporal thresholds or lower airborne confidence

### Plateaued Approaches

No families plateaued

### Runtime Usage

Total experiment runtime: 0.2s
Total wall clock: 0m

### Production Files Changed

Expected: NONE
Actual: NONE

### Execution Environment

EXECUTION_ENVIRONMENT: local
SAFE_TO_CLOSE_LAPTOP: UNKNOWN
