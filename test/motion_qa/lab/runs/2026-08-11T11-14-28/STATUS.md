# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-11T11:19:51.288213

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 0h 5m 22s |
| Remaining | 7h 54m |
| Budget | 8.0h |
| Throughput | 38.2 exp/s (137516 exp/h) |

## Research Stage

**Current stage:** localRefinement
Experiments since last improvement: 12147
Time since last improvement: 5m
Pending confirmations: 0
Validation confirmations: 1
Final holdout: NOT YET (running)

## Champion

| Metric | Value |
|--------|-------|
| Experiment | EXP-000152 |
| Candidate | temporal_v18 |
| Family | temporal |
| Recall | 0.5625 |
| Precision | 0.6429 |
| F1 | 0.6000 |
| FA clip rate | 0.1111 |
| Exact count | 0.3333 |
| Catastrophic clips | 0 |
| Confirmed runs | 1 |

### Promotion Reason

F1: 0.5294 → 0.6000 (+0.0706), Recall: 0.5625 → 0.5625, Precision: 0.5000 → 0.6429, FA clip rate: 0.222 → 0.111

## Experiment Counts

| Metric | Value |
|--------|-------|
| Total attempted | 12300 |
| Completed | 12300 |
| Failed | 0 |
| Champion changes | 2 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 3724 | 0.6000 | NO | ACTIVE |
| camera | 370 | 0.4348 | NO | ACTIVE |
| signal_quality | 363 | 0.4348 | NO | ACTIVE |
| geometric | 2836 | 0.5294 | NO | ACTIVE |
| confuser_specialist | 337 | 0.5294 | NO | ACTIVE |
| mlp | 358 | 0.4865 | NO | ACTIVE |
| conv1d | 360 | 0.4865 | NO | ACTIVE |
| gru | 359 | 0.4865 | NO | ACTIVE |
| hybrid | 344 | 0.5294 | NO | ACTIVE |
| ensemble | 3249 | 0.5714 | NO | ACTIVE |

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
Generated: 2026-08-11T11:19:51.288650
