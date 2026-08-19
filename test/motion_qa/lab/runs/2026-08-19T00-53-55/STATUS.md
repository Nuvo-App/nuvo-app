# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-19T00:54:38.516550

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 0h 0m 42s |
| Remaining | 0h 1m |
| Budget | 0.03h |
| Throughput | 23.8 exp/s (85714 exp/h) |

## Research Stage

**Current stage:** familySelection
Experiments since last improvement: 618
Time since last improvement: 0m
Pending confirmations: 0
Validation confirmations: 2
Final holdout: EVALUATED

## Champion

| Metric | Value |
|--------|-------|
| Experiment | EXP-000381 |
| Candidate | temporal_v59 |
| Family | temporal |
| Recall | 0.5625 |
| Precision | 0.6429 |
| F1 | 0.6000 |
| FA clip rate | 0.1111 |
| Exact count | 0.3333 |
| Catastrophic clips | 0 |
| Confirmed runs | 2 |
| Holdout F1 | 0.2500 |
| Holdout recall | 0.2000 |
| Holdout precision | 0.3333 |

### Promotion Reason

F1: 0.5806 → 0.6000 (+0.0194), Recall: 0.5625 → 0.5625, Precision: 0.6000 → 0.6429, FA clip rate: 0.111 → 0.111

## Experiment Counts

| Metric | Value |
|--------|-------|
| Total attempted | 1000 |
| Completed | 1000 |
| Failed | 0 |
| Champion changes | 3 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 140 | 0.6000 | YES | PLATEAUED |
| camera | 134 | 0.4348 | YES | PLATEAUED |
| signal_quality | 109 | 0.4348 | YES | PLATEAUED |
| geometric | 89 | 0.5294 | YES | PLATEAUED |
| confuser_specialist | 88 | 0.5294 | YES | PLATEAUED |
| mlp | 94 | 0.4865 | YES | PLATEAUED |
| conv1d | 85 | 0.4865 | YES | PLATEAUED |
| gru | 87 | 0.4865 | YES | PLATEAUED |
| hybrid | 77 | 0.5294 | YES | PLATEAUED |
| ensemble | 97 | 0.5714 | YES | PLATEAUED |

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
Generated: 2026-08-19T00:54:38.516696
