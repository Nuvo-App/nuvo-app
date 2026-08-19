# NUVO MOTION LAB — LIVE STATUS

**STATUS:** RUNNING
**Last update:** 2026-08-19T00:55:13.416002

## Time Budget

| Metric | Value |
|--------|-------|
| Elapsed | 0h 1m 15s |
| Remaining | 7h 58m |
| Budget | 8.0h |
| Throughput | 31.2 exp/s (112320 exp/h) |

## Research Stage

**Current stage:** localRefinement
Experiments since last improvement: 1680
Time since last improvement: 0m
Pending confirmations: 0
Validation confirmations: 2
Final holdout: NOT YET (running)

## Champion

| Metric | Value |
|--------|-------|
| Experiment | EXP-000659 |
| Candidate | temporal_v86 |
| Family | temporal |
| Recall | 0.5625 |
| Precision | 0.6429 |
| F1 | 0.6000 |
| FA clip rate | 0.1111 |
| Exact count | 0.3333 |
| Catastrophic clips | 0 |
| Confirmed runs | 2 |

### Promotion Reason

F1: 0.5806 → 0.6000 (+0.0194), Recall: 0.5625 → 0.5625, Precision: 0.6000 → 0.6429, FA clip rate: 0.111 → 0.111

## Experiment Counts

| Metric | Value |
|--------|-------|
| Total attempted | 2340 |
| Completed | 2340 |
| Failed | 0 |
| Champion changes | 3 |

## Family Status

| Family | Experiments | Best F1 | Plateaued | Status |
|--------|-------------|---------|-----------|--------|
| temporal | 315 | 0.6000 | NO | ACTIVE |
| camera | 269 | 0.4348 | NO | ACTIVE |
| signal_quality | 215 | 0.4348 | NO | ACTIVE |
| geometric | 239 | 0.5294 | NO | ACTIVE |
| confuser_specialist | 201 | 0.5294 | NO | ACTIVE |
| mlp | 209 | 0.4865 | NO | ACTIVE |
| conv1d | 206 | 0.4865 | NO | ACTIVE |
| gru | 210 | 0.4865 | NO | ACTIVE |
| hybrid | 202 | 0.5294 | NO | ACTIVE |
| ensemble | 274 | 0.5714 | NO | ACTIVE |

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
Generated: 2026-08-19T00:55:13.416315
