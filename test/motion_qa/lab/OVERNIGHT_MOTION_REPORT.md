# NUVO MOTION LAB — OVERNIGHT REPORT

Generated: 2026-08-11T09:42:28.310607

---

## EXECUTIVE SUMMARY (30-second read)

Runtime: 8h 0m
Experiments attempted: 308061
Experiments completed: 308061
Experiments failed: 0
Champion changes: 3
Throughput: 10.7 exp/s (38508 exp/h)
Research stage: localRefinement
Holdout evaluations: 1540

### STARTING CHAMPION
Recall: 0.5625
Precision: 0.5000
F1: 0.5294
False accept rate: 0.2222

### ENDING CHAMPION
Experiment: EXP-000297
Family: temporal
Recall: 0.5625
Precision: 0.6429
F1: 0.6000
False accept rate: 0.1111
Exact count quality: 0.3333
Confirmed runs: 1539

### HOLDOUT EVALUATION
Holdout F1: 0.2500
Holdout Recall: 0.2000
Holdout Precision: 0.3333
Holdout FA Clip Rate: 0.200
Overfitting gap (dev - holdout): 0.3500
WARNING: Significant overfitting detected — champion may not generalize

### PROMOTION REASON
F1: 0.5625 → 0.6000 (+0.0375), Recall: 0.5625 → 0.5625, Precision: 0.5625 → 0.6429, FA clip rate: 0.111 → 0.111

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
temporal_v147586: F1=0.6000
  Temporal config: airborne=0.06480000000000001, hyst=0.0924, gap=14, persist=3

### NEXT HUMAN ACTION
Review failure clusters and consider data expansion or feature engineering

---

## DETAILED ANALYSIS

### Experiment Family Performance

| Family | Experiments | Best F1 | Plateaued | Runtime (ms) |
|--------|-------------|---------|-----------|-------------|
| temporal | 165346 | 0.6000 | YES | 2887353 |
| camera | 3427 | 0.4348 | YES | 61113 |
| signal_quality | 3274 | 0.4348 | YES | 63065 |
| geometric | 55173 | 0.5294 | YES | 974182 |
| confuser_specialist | 3258 | 0.5294 | YES | 56291 |
| mlp | 3191 | 0.4865 | YES | 55378 |
| conv1d | 3287 | 0.4865 | YES | 57104 |
| gru | 3161 | 0.4865 | YES | 54650 |
| hybrid | 3399 | 0.5294 | YES | 60219 |
| ensemble | 64545 | 0.5714 | YES | 1172372 |

### Champion History

1. SEED-000000: temp_adaptive_hyst F1=0.5294
2. EXP-000122: temporal_v16 F1=0.5625
3. EXP-000297: temporal_v42 F1=0.6000

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

- **temporal**: 165346 experiments, best F1=0.6000, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.6000, Recent best: 0.6000, Improvement: 0.0000
- **camera**: 3427 experiments, best F1=0.4348, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.4348, Recent best: 0.4348, Improvement: 0.0000
- **signal_quality**: 3274 experiments, best F1=0.4348, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.4348, Recent best: 0.4348, Improvement: 0.0000
- **geometric**: 55173 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **confuser_specialist**: 3258 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **mlp**: 3191 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **conv1d**: 3287 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **gru**: 3161 experiments, best F1=0.4865, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.4865, Recent best: 0.4865, Improvement: 0.0000
- **hybrid**: 3399 experiments, best F1=0.5294, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.5294, Recent best: 0.5294, Improvement: 0.0000
- **ensemble**: 64545 experiments, best F1=0.5714, reason: No improvement > 0.005 in last 200 experiments. Earlier best: 0.5714, Recent best: 0.5714, Improvement: 0.0000

### Runtime Usage

Total experiment runtime: 5441.7s
Total wall clock: 480m

### Production Files Changed

Expected: NONE
Actual: NONE

### Execution Environment

EXECUTION_ENVIRONMENT: local
SAFE_TO_CLOSE_LAPTOP: UNKNOWN
