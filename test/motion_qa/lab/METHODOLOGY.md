# MOTION LAB METHODOLOGY — Corrected Protocol

**Version:** 2.0 (post-forensic-audit)
**Date:** 2026-08-11

---

## PROTOCOL: SEARCH → VALIDATION → FINAL HOLDOUT

### Layer 1: SEARCH (dev split)
- **Purpose:** Optimize detector parameters, explore experiment families, promote champions
- **Data:** `dev` split clips only
- **Frequency:** Every experiment iteration
- **Rules:**
  - All experiment evaluation uses dev ground truths
  - Champion promotion uses dev F1, recall, precision, FA rate
  - Family weighting uses dev performance
  - Failure mining uses dev false-accept patterns
  - Search policy stages (broad → select → refine → confirm) operate on dev metrics

### Layer 2: VALIDATION (validation split)
- **Purpose:** Confirm that a promoted champion generalizes beyond the dev split
- **Data:** `validation` split clips only
- **Frequency:** Every 100 experiments (only if pending confirmations exist)
- **Rules:**
  - Only the current champion is evaluated on validation
  - Validation results do NOT influence search, promotion, or family weighting
  - Validation gap > 0.10 triggers a warning (champion may be overfit)
  - `confirmedRuns` counter increments only from validation confirmations
  - Validation results are logged but do not stop or redirect search

### Layer 3: FINAL HOLDOUT (holdout split)
- **Purpose:** One-time, final evaluation of the champion after search completes
- **Data:** `holdout` split clips only
- **Frequency:** **ONCE** — after the search loop terminates
- **Rules:**
  - Holdout is NEVER queried during search
  - Holdout metrics do NOT influence any search decision
  - Holdout F1 is the authoritative generalization measure
  - Overfitting gap (dev F1 - holdout F1) is reported in the morning report
  - If overfitting gap > 0.05, a warning is emitted

### Data Split Summary

| Split | Purpose | Clip Count | Queried During Search? |
|-------|---------|------------|------------------------|
| dev | Search & optimization | ~16 | YES (every experiment) |
| validation | Champion confirmation | ~8 | YES (every 100 experiments, read-only) |
| holdout | Final evaluation | ~6 | NO (only once, after search ends) |

---

## RUN-SCOPED ARTIFACT DIRECTORIES

Each run creates a timestamped subdirectory:
```
test/motion_qa/lab/
  LATEST_RUN.txt          → points to latest run directory
  runs/
    2026-08-11T01-42-28/  → Run 1 artifacts
      EXPERIMENTS.jsonl
      CHAMPION.json
      STATUS.md
      OVERNIGHT_MOTION_REPORT.md
      HOLDOUT_RESULTS.md
      ...
    2026-08-12T01-00-00/  → Run 2 artifacts
      ...
```

This prevents simultaneous or previous runs from overwriting each other's artifacts.

---

## CRASH SAFETY

- All artifact writes use atomic write (write to `.tmp` file, then rename)
- State is persisted every 10 experiments (family state, failure clusters)
- Champion is saved immediately on promotion
- On crash, the latest `.tmp` file may be stale but the renamed file is consistent

---

## CHAMPION PROMOTION CRITERIA

A challenger becomes champion only if ALL of:
1. F1 improvement ≥ 0.005 over current champion
2. Recall does not drop by more than 0.10 (absolute)
3. False-accept clip rate does not increase by more than 0.05 (absolute)
4. Promotion reason is documented in `CHAMPION.json`

---

## TERMINATION CONDITIONS

1. **Primary:** Time budget exhausted (default: 8 hours)
2. **Safety ceiling:** maxExperiments reached (default: 2,000,000)
3. **No stop on plateau:** Global plateau resets all family plateaus and continues exploration
4. **No stop on data ceiling:** Data ceiling generates `DATA_REQUEST.md` but does not stop search

---

## KNOWN LIMITATIONS

1. **ML families are proxies:** MLP, Conv1D, GRU families use fixed-weight heuristics, not actual trained models. Their plateau reflects the proxy ceiling, not a learned model ceiling.
2. **Tiny dataset:** 31 total clips (16 dev, 8 validation, 6 holdout). Results have high variance and significant overfitting risk.
3. **No cross-validation:** Single split, no k-fold. Holdout F1 on 6 clips is noisy.
4. **No early stopping on validation:** Lab runs full time budget even if validation shows overfitting.
