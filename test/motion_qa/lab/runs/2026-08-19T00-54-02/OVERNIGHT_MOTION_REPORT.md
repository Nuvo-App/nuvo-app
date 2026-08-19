# NUVO MOTION LAB — OVERNIGHT REPORT

Generated: 2026-08-19T00:54:09.514928

---

## EXECUTIVE SUMMARY (30-second read)

Runtime: 0h 0m
Experiments attempted: 160
Experiments completed: 160
Experiments failed: 0
Champion changes: 1
Throughput: 26.7 exp/s (96000 exp/h)
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
hybrid_high_recall_temporal_confuser_gate_v17: F1=0.5294
  Hybrid: high_recall_temporal proposes → confuser_gate verifies. Config: {detector: high_recall_temporal, verifier: confuser_gate, verifierWindow: 15, verifierThreshold: 0.3, targetConfuser: deep_squats}

### NEXT HUMAN ACTION
Review failure clusters and consider data expansion or feature engineering

---

## DETAILED ANALYSIS

### Experiment Family Performance

| Family | Experiments | Best F1 | Plateaued | Runtime (ms) |
|--------|-------------|---------|-----------|-------------|
| temporal | 19 | 0.5294 | NO | 689 |
| camera | 26 | 0.4167 | NO | 1030 |
| signal_quality | 31 | 0.4167 | NO | 1228 |
| geometric | 9 | 0.5294 | NO | 353 |
| confuser_specialist | 31 | 0.5294 | NO | 1111 |
| mlp | 10 | 0.4865 | NO | 384 |
| conv1d | 5 | 0.4865 | NO | 192 |
| gru | 8 | 0.4865 | NO | 329 |
| hybrid | 19 | 0.5294 | NO | 773 |
| ensemble | 2 | 0.5294 | NO | 77 |

### Champion History

1. SEED-000000: temp_adaptive_hyst F1=0.5294

### Learning Curve

| Target Clips | F1 | Recall | Precision |
|-------------|-----|--------|-----------|
| 3 | 0.5294 | 0.5625 | 0.5000 |

### Failure Clusters

- **FALSE_ACCEPT_DEEP_SQUATS**: Champion false-accepts on deep_squats: 1 clips, 3 reps
  - Reason: Deep squat compression pattern resembles jump squat descent phase
  - Proposed: Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout
- **FALSE_ACCEPT_SQUAT_JACKS**: Champion false-accepts on squat_jacks: 1 clips, 1 reps
  - Reason: Squat jack combines squat + jump, closely resembling jump squat
  - Proposed: Add temporal ordering gate: require compression before airborne phase
- **LOW_RECALL_TARGET**: Champion recall is 0.563 — below 0.75 gate
  - Reason: Detector may be too conservative or missing key motion phases
  - Proposed: Try relaxed temporal thresholds or lower airborne confidence

### Plateaued Approaches

No families plateaued

### Runtime Usage

Total experiment runtime: 6.2s
Total wall clock: 0m

### Production Files Changed

Expected: NONE
Actual: NONE

### Execution Environment

EXECUTION_ENVIRONMENT: local
SAFE_TO_CLOSE_LAPTOP: UNKNOWN
