# NUVO MOTION LAB — OVERNIGHT REPORT

Generated: 2026-08-19T00:54:38.523503

---

## EXECUTIVE SUMMARY (30-second read)

Runtime: 0h 0m
Experiments attempted: 1000
Experiments completed: 1000
Experiments failed: 0
Champion changes: 3
Throughput: 23.8 exp/s (85714 exp/h)
Research stage: familySelection
Validation confirmations: 2
Final holdout evaluated: YES

### STARTING CHAMPION
Recall: 0.5625
Precision: 0.5000
F1: 0.5294
False accept rate: 0.2222

### ENDING CHAMPION
Experiment: EXP-000381
Family: temporal
Recall: 0.5625
Precision: 0.6429
F1: 0.6000
False accept rate: 0.1111
Exact count quality: 0.3333
Confirmed runs: 2

### HOLDOUT EVALUATION
Holdout F1: 0.2500
Holdout Recall: 0.2000
Holdout Precision: 0.3333
Holdout FA Clip Rate: 0.200
Overfitting gap (dev - holdout): 0.3500
WARNING: Significant overfitting detected — champion may not generalize

### PROMOTION REASON
F1: 0.5806 → 0.6000 (+0.0194), Recall: 0.5625 → 0.5625, Precision: 0.6000 → 0.6429, FA clip rate: 0.111 → 0.111

### IMPROVEMENT
+0.0706 F1 points

### GATES
75/90: FAIL
85/95: FAIL
90/95: FAIL

### PRODUCTION READY
NO
INSUFFICIENT_DATA_FOR_PRODUCTION_CLAIM

### NEXT BOTTLENECK
MODEL (all families plateaued)

### MOST IMPORTANT DISCOVERY
temporal_v87: F1=0.6000
  Temporal config: airborne=0.05688, hyst=0.0918, gap=13, persist=6

### NEXT HUMAN ACTION
Review failure clusters and consider data expansion or feature engineering

---

## DETAILED ANALYSIS

### Experiment Family Performance

| Family | Experiments | Best F1 | Plateaued | Runtime (ms) |
|--------|-------------|---------|-----------|-------------|
| temporal | 140 | 0.6000 | YES | 5328 |
| camera | 134 | 0.4348 | YES | 5153 |
| signal_quality | 109 | 0.4348 | YES | 4557 |
| geometric | 89 | 0.5294 | YES | 3421 |
| confuser_specialist | 88 | 0.5294 | YES | 3525 |
| mlp | 94 | 0.4865 | YES | 3403 |
| conv1d | 85 | 0.4865 | YES | 3253 |
| gru | 87 | 0.4865 | YES | 3198 |
| hybrid | 77 | 0.5294 | YES | 3357 |
| ensemble | 97 | 0.5714 | YES | 3784 |

### Champion History

1. SEED-000000: temp_adaptive_hyst F1=0.5294
2. EXP-000232: temporal_v30 F1=0.5806
3. EXP-000381: temporal_v59 F1=0.6000

### Learning Curve

| Target Clips | F1 | Recall | Precision |
|-------------|-----|--------|-----------|
| 3 | 0.6000 | 0.5625 | 0.6429 |

### Failure Clusters

- **FALSE_ACCEPT_DEEP_SQUATS**: Champion false-accepts on deep_squats: 1 clips, 3 reps
  - Reason: Deep squat compression pattern resembles jump squat descent phase
  - Proposed: Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout
- **LOW_RECALL_TARGET**: Champion recall is 0.563 — below 0.75 gate
  - Reason: Detector may be too conservative or missing key motion phases
  - Proposed: Try relaxed temporal thresholds or lower airborne confidence

### Plateaued Approaches

- **temporal**: 140 experiments, best F1=0.6000, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.6000, Recent best: 0.6000, Improvement: 0.0000
- **camera**: 134 experiments, best F1=0.4348, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.4348, Recent best: 0.4348, Improvement: 0.0000
- **signal_quality**: 109 experiments, best F1=0.4348, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.4348, Recent best: 0.4348, Improvement: 0.0000
- **geometric**: 89 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **confuser_specialist**: 88 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **mlp**: 94 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **conv1d**: 85 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **gru**: 87 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **hybrid**: 77 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **ensemble**: 97 experiments, best F1=0.5714, reason: No improvement > 0.005 in last 50 experiments. Earlier best: 0.5714, Recent best: 0.5714, Improvement: 0.0000

### Runtime Usage

Total experiment runtime: 39.0s
Total wall clock: 0m

### Production Files Changed

Expected: NONE
Actual: NONE

### Execution Environment

EXECUTION_ENVIRONMENT: local
SAFE_TO_CLOSE_LAPTOP: UNKNOWN
