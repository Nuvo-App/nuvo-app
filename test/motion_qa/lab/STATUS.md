# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-11T09:42:28.016585

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 8h 0m 0s |
| Remaining | 0h 0m |
| Budget | 8.0h |
| Throughput | 10.7 exp/s (38508 exp/h) |

## Research Stage

**Current stage:** localRefinement
Experiments since last improvement: 307763
Time since last improvement: 479m
Pending confirmations: 2
Holdout evaluations: 1540

## Champion

| Metric | Value |
|--------|-------|
| Experiment | EXP-000297 |
| Candidate | temporal_v42 |
| Family | temporal |
| Recall | 0.5625 |
| Precision | 0.6429 |
| F1 | 0.6000 |
| FA clip rate | 0.1111 |
| Exact count | 0.3333 |
| Catastrophic clips | 0 |
| Confirmed runs | 1539 |
| Holdout F1 | 0.2500 |
| Holdout recall | 0.2000 |
| Holdout precision | 0.3333 |

### Promotion Reason

F1: 0.5625 → 0.6000 (+0.0375), Recall: 0.5625 → 0.5625, Precision: 0.5625 → 0.6429, FA clip rate: 0.111 → 0.111

## Experiment Counts

| Metric | Value |
|--------|-------|
| Total attempted | 308061 |
| Completed | 308061 |
| Failed | 0 |
| Champion changes | 3 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 165346 | 0.6000 | YES | PLATEAUED |
| camera | 3427 | 0.4348 | YES | PLATEAUED |
| signal_quality | 3274 | 0.4348 | YES | PLATEAUED |
| geometric | 55173 | 0.5294 | YES | PLATEAUED |
| confuser_specialist | 3258 | 0.5294 | YES | PLATEAUED |
| mlp | 3191 | 0.4865 | YES | PLATEAUED |
| conv1d | 3287 | 0.4865 | YES | PLATEAUED |
| gru | 3161 | 0.4865 | YES | PLATEAUED |
| hybrid | 3399 | 0.5294 | YES | PLATEAUED |
| ensemble | 64545 | 0.5714 | YES | PLATEAUED |

## Failure Analysis

**Primary cluster:** FALSE_ACCEPT_DEEP_SQUATS
- Champion false-accepts on deep_squats: 1 clips, 3 reps
- Reason: Deep squat compression pattern resembles jump squat descent phase
- Proposed: Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout

## Improvement Summary

- Starting F1: 0.5294
- Current F1: 0.6000
- Improvement: +0.0706

---
Generated: 2026-08-11T09:42:28.029756
