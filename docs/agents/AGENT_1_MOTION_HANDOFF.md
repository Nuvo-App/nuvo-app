# AGENT 1 MOTION HANDOFF — Nuvo Motion Lab

**Date:** 2026-08-11
**From:** Agent 1 (forensic audit + methodology fix)
**To:** Replacement agent
**Git SHA:** d97f0aa8edb02b0acf1ff240d24aaa24f7f74128

---

## 1. WHAT HAPPENED (SUMMARY)

Two overnight runs overwrote the same artifact directory (`test/motion_qa/lab/`). The first run (01:19, 5K experiments, maxExperiments=5000) was a prior session. The second run (01:42–09:42, 308K experiments, 8h budget) was our overnight run. All artifacts reflect Run 2. The `overnight_runner.log` is a leftover from Run 1.

**Champion:** temporal_v42 — dev F1=0.6000, holdout F1=0.2500, overfitting gap=0.3500.

**Key finding:** Holdout was evaluated 1,540 times (every 200 experiments) but holdout metrics never influenced search decisions. However, this was methodologically unsound and inflated `confirmedRuns`.

## 2. WHAT WAS FIXED

### Fix 1: Run-scoped artifact directories
- Each run now creates `test/motion_qa/lab/runs/<timestamp>/`
- `LATEST_RUN.txt` points to the latest run
- No more cross-run overwrites

### Fix 2: Single final holdout evaluation
- Holdout evaluated ONCE after search loop completes
- Not queried every 200 experiments during search

### Fix 3: Validation confirmation runs
- `valGroundTruths` (validation split) is now actually used
- `_runValidationConfirmations()` evaluates champion on validation every 100 experiments
- `confirmedRuns` reflects actual validation confirmations

### Fix 4: Proper protocol
```
SEARCH (dev) → VALIDATION (val) → FINAL HOLDOUT (holdout, once)
```

### Verification
- 18/18 validation checks passed
- Run-scoped directory created: `runs/2026-08-11T10-26-20/`
- Holdout evaluated once (not 1540 times)
- STATUS.md and report show validation confirmations

## 3. FILES MODIFIED

| File | Change |
|------|--------|
| `test/motion_qa/lab/motion_lab.dart` | Run-scoped dirs, single holdout eval, validation confirmations, status/report updates |
| `test/motion_qa/motion_lab_overnight_test.dart` | Clean runs/ dir, updated docs |
| `test/motion_qa/motion_lab_validation_test.dart` | Use run-scoped dir, check validation confirmations, check single holdout |
| `test/motion_qa/lab/search_policy.dart` | (Prior session: removed unused field) |

## 4. FILES PRODUCED

| File | Content |
|------|---------|
| `test/motion_qa/lab/OVERNIGHT_FORENSIC_REPORT.md` | Full forensic analysis |
| `test/motion_qa/lab/METHODOLOGY.md` | Corrected protocol documentation |
| `test/motion_qa/lab/DATA_REQUEST.md` | Request for 18 additional clips |
| `docs/agents/AGENT_1_MOTION_HANDOFF.md` | This document |

## 5. CURRENT STATE

### What works
- Run-scoped artifact directories ✓
- Single final holdout evaluation ✓
- Validation confirmation runs ✓
- Atomic writes ✓
- Hierarchical search ✓
- Conservative champion promotion ✓
- Failure-driven feedback ✓
- Rich STATUS.md and morning report ✓
- Time-based budget termination ✓

### What doesn't work / known limitations
1. **ML families are proxies** — MLP, Conv1D, GRU don't actually train. They use fixed-weight heuristics.
2. **Dataset is tiny** — 31 clips total. Overfitting gap is 0.35.
3. **No cross-validation** — single split, high variance on holdout.
4. **No early stopping on validation** — runs full time budget even if overfitting.
5. **All families plateau quickly** — ~500 experiments to plateau, then 307K more with no improvement.

## 6. HOW TO RUN

### Validation test (2 minutes)
```bash
flutter test test/motion_qa/motion_lab_validation_test.dart --timeout 300s
```

### Overnight run (8 hours)
```bash
MOTION_LAB_CLEAN=1 flutter test test/motion_qa/motion_lab_overnight_test.dart --timeout 36000s
```

### Key configuration
- `budgetHours`: 8.0 (primary termination)
- `maxExperiments`: 2,000,000 (safety ceiling)
- `plateauWindow`: 200 (experiments before plateau detection)
- `productionWrite`: false (never auto-deploy)

## 7. NEXT STEPS FOR REPLACEMENT AGENT

1. **Read the forensic report:** `test/motion_qa/lab/OVERNIGHT_FORENSIC_REPORT.md`
2. **Read the methodology:** `test/motion_qa/lab/METHODOLOGY.md`
3. **Do NOT launch overnight runs** until the data request is fulfilled
4. **Do NOT modify production motion code** (`lib/features/races/ai/`)
5. **Do NOT touch** auth, AI Motion Proof, ML Kit, iOS native files, or backend (see AGENTS.md)
6. **If data is added:** Update `motion_intelligence.dart` clip definitions, run validation test, then overnight run
7. **If implementing real ML:** Replace proxy families with actual TensorFlow Lite models. This is a major undertaking — scope it carefully.
8. **Run `flutter analyze --no-fatal-infos`** after any Dart file change

## 8. IMPORTANT CONSTRAINTS (from AGENTS.md)

- No new features unless explicitly asked
- No backend contract changes
- No auth logic changes
- No AI Motion Proof changes
- Small scoped changes only (≤5 files per task)
- Use Nuvo product language (race, crew, proof, not challenge, event, journey)
- Run `flutter analyze --no-fatal-infos` after changes
