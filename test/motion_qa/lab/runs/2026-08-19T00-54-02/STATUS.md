# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-19T00:54:09.507634

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 0h 0m 6s |
| Remaining | 0h 2m |
| Budget | 0.05h |
| Throughput | 26.7 exp/s (96000 exp/h) |

## Research Stage

**Current stage:** broadExploration
Experiments since last improvement: 160
Pending confirmations: 0
Validation confirmations: 0
Final holdout: EVALUATED

## Champion

| Metric | Value |
|--------|-------|
| Experiment | SEED-000000 |
| Candidate | temp_adaptive_hyst |
| Family | temporal |
| Recall | 0.5625 |
| Precision | 0.5000 |
| F1 | 0.5294 |
| FA clip rate | 0.2222 |
| Exact count | 0.0000 |
| Catastrophic clips | 0 |
| Confirmed runs | 0 |
| Holdout F1 | 0.2857 |
| Holdout recall | 0.2000 |
| Holdout precision | 0.5000 |

### Promotion Reason

Initial champion (no prior champion to compare)

## Experiment Counts

| Metric | Value |
|--------|-------|
| Total attempted | 160 |
| Completed | 160 |
| Failed | 0 |
| Champion changes | 1 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 19 | 0.5294 | NO | ACTIVE |
| camera | 26 | 0.4167 | NO | ACTIVE |
| signal_quality | 31 | 0.4167 | NO | ACTIVE |
| geometric | 9 | 0.5294 | NO | ACTIVE |
| confuser_specialist | 31 | 0.5294 | NO | ACTIVE |
| mlp | 10 | 0.4865 | NO | ACTIVE |
| conv1d | 5 | 0.4865 | NO | ACTIVE |
| gru | 8 | 0.4865 | NO | ACTIVE |
| hybrid | 19 | 0.5294 | NO | ACTIVE |
| ensemble | 2 | 0.5294 | NO | ACTIVE |

## Failure Analysis

**Primary cluster:** FALSE_ACCEPT_DEEP_SQUATS
- Champion false-accepts on deep_squats: 1 clips, 3 reps
- Reason: Deep squat compression pattern resembles jump squat descent phase
- Proposed: Add explicit knee-angle threshold gate: reject if knee angle < 60° throughout

## Improvement Summary

- Starting F1: 0.5294
- Current F1: 0.5294
- Improvement: +0.0000

---
Generated: 2026-08-19T00:54:09.507760
