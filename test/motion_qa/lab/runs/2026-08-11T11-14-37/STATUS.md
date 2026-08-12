# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-11T11:14:38.253992

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 0h 0m 0s |
| Remaining | 0h 2m |
| Budget | 0.05h |
| Throughput | 15.0 exp/s (54000 exp/h) |

## Research Stage

**Current stage:** broadExploration
Experiments since last improvement: 15
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
| Total attempted | 15 |
| Completed | 15 |
| Failed | 0 |
| Champion changes | 1 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 1 | 0.5143 | NO | ACTIVE |
| camera | 5 | 0.4167 | NO | ACTIVE |
| signal_quality | 0 | 0.0000 | NO | ACTIVE |
| geometric | 2 | 0.5143 | NO | ACTIVE |
| confuser_specialist | 1 | 0.5294 | NO | ACTIVE |
| mlp | 3 | 0.4615 | NO | ACTIVE |
| conv1d | 0 | 0.0000 | NO | ACTIVE |
| gru | 0 | 0.0000 | NO | ACTIVE |
| hybrid | 3 | 0.5294 | NO | ACTIVE |
| ensemble | 0 | 0.0000 | NO | ACTIVE |

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
Generated: 2026-08-11T11:14:38.254214
