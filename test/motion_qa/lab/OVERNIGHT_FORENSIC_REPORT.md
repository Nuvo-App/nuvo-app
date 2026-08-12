# OVERNIGHT FORENSIC REPORT — Nuvo Motion Lab

**Investigation date:** 2026-08-11 10:30 EDT
**Investigator:** Agent 1 (automated)
**Git SHA at investigation:** d97f0aa8edb02b0acf1ff240d24aaa24f7f74128

---

## 1. THE CONTRADICTION

Two sources reported different results for the overnight run:

| Source | Experiments | Champion | F1 | Termination |
|--------|-------------|----------|----|-------------|
| STATUS.md (current artifacts) | 308,061 | temporal_v42 | 0.6000 | BUDGET HOURS EXHAUSTED |
| overnight_runner.log | 5,000 | ensemble_subtract_confuser_v22 | 0.5517 | MAX EXPERIMENTS REACHED |

## 2. ROOT CAUSE: TWO SEPARATE RUNS OVERWROTE THE SAME ARTIFACT DIRECTORY

### Run 1 (overnight_runner.log)
- **Timestamp:** Aug 11 01:19:53 2026 (file mtime)
- **Config:** `maxExperiments: 5000`, `budgetHours: 8.0`
- **Seeded champion F1:** 0.5000
- **Termination:** MAX EXPERIMENTS REACHED at 5,000 experiments
- **Champion:** ensemble_subtract_confuser_v22 (F1=0.5517)
- **Status:** This was a **prior run** (likely from an earlier session or test). It wrote artifacts to `test/motion_qa/lab/` directly.

### Run 2 (overnight_output.log) — THE AUTHORITATIVE RUN
- **Timestamp:** Aug 11 01:42:28 to 09:42:28 2026 (8 hours)
- **Config:** `maxExperiments: 2,000,000`, `budgetHours: 8.0`
- **Seeded champion F1:** 0.5294 (different from Run 1 — different dataset splits)
- **Termination:** BUDGET HOURS EXHAUSTED at 308,061 experiments
- **Champion:** temporal_v42 (F1=0.6000 on dev, F1=0.2500 on holdout)
- **Status:** This was **our run**, launched at 01:42 via tmux + caffeinate. It overwrote all Run 1 artifacts.

### Evidence
1. `overnight_runner.log` mtime: Aug 11 01:19 — predates our run (01:42)
2. `overnight_output.log` mtime: Aug 11 09:42 — matches our 8-hour run completion
3. Different `maxExperiments` configs: 5,000 vs 2,000,000
4. Different seeded champion F1: 0.5000 vs 0.5294 (different dataset splits)
5. `EXPERIMENTS.jsonl` has 308,061 lines — matches Run 2, not Run 1
6. First experiment timestamp: `2026-08-11T01:42:28` — matches Run 2 launch
7. `overnight_runner.log` was NOT overwritten because it has a different filename

### Conclusion
**Run 2 is authoritative.** Run 1 was a prior session's run that wrote to the same directory. Run 2 overwrote all shared artifact files. The `overnight_runner.log` is a leftover from Run 1 and does not reflect the overnight results.

## 3. HOLDOUT CONTAMINATION AUDIT

### Was holdout actually untouched during search?
**Yes — holdout data was never used for search, promotion, or family weighting.**

Evidence from code audit:
- Main experiment loop uses `devGroundTruths` only (line 697)
- `tryPromote()` uses only dev F1/recall/precision/FA rate (lines 399-412)
- `SearchPolicy` has no reference to holdout data
- `FailureMiner` has no reference to holdout data
- Experiment families have no reference to holdout data
- `holdoutMetrics` is only read for display/reporting (lines 1137, 1285)

### Did holdout metrics influence any decision?
**No.** Holdout metrics were written to `champ.holdoutMetrics` and `HOLDOUT_RESULTS.md` but never read back into any search, promotion, weighting, or stopping decision.

### Why were there ~1,540 holdout evaluations?
**This was a methodology bug.** The code evaluated the champion on holdout every 200 experiments (`registry.completedCount % 200 == 0`). Over 308,061 experiments, this triggered 1,540 times. While this didn't influence search decisions, it:
1. Repeatedly queried the holdout set, which is methodologically unsound
2. Inflated `confirmedRuns` to 1,539 (incremented each holdout evaluation)
3. Created a false impression of "confirmation" when no actual confirmation logic existed

**FIX APPLIED:** Holdout is now evaluated **once** at the end of the run, after the search loop terminates. Validation confirmations use the validation split (not holdout) during search.

## 4. OVERFITTING ANALYSIS

### Is the F1=0.6000 champion legitimately better?
**The champion is legitimately better than the seed on the dev split** (+0.0706 F1 improvement). However, it is **primarily overfit to the dev split.**

### Why is holdout F1 only 0.2500?
- **Dev split:** 16 clips (9 target + 7 confuser) — champion tuned to these specific clips
- **Holdout split:** 6 clips (1 target + 5 confuser) — champion has never seen these
- **Overfitting gap:** 0.3500 (dev F1 0.6000 - holdout F1 0.2500)
- The champion's temporal thresholds (airborne=0.0588, hysteresis=0.0825) are tuned to the specific jump squat clips in the dev split
- On holdout, recall drops from 0.5625 to 0.2000 and precision from 0.6429 to 0.3333

### Root cause of overfitting
1. **Tiny dataset:** Only 31 total fixture clips, 6 in holdout
2. **Repeated evaluation:** 1,540 holdout evaluations on 6 clips — even without direct optimization, the researcher (code author) could have indirectly tuned to holdout patterns
3. **No regularization:** Temporal family has no mechanism to prevent overfitting to specific clips

## 5. SCIENTIFIC CONCLUSIONS FROM LAST NIGHT

1. **Temporal hysteresis is the best family** for jump squat detection on the dev split (F1=0.6000)
2. **All 10 experiment families plateaued** within the first ~500 experiments — the remaining 307,561 experiments explored random variations around the same parameter ranges without improvement
3. **The dataset is too small to produce a generalizable model** — 0.3500 overfitting gap confirms this
4. **The primary confuser is deep squats** — the champion false-accepts deep squat reps as jump squats
5. **No family reached the 75/90 production gate** (75% recall, 90% precision)
6. **ML families (MLP, Conv1D, GRU) are proxy-only** — they don't actually train; they use fixed-weight heuristics that mimic ML behavior. Their plateau at F1=0.4865 reflects the proxy's ceiling, not a learned model's ceiling.

## 6. METHODOLOGY FIXES APPLIED

### Fix 1: Run-scoped artifact directories
Each run now creates a timestamped subdirectory: `test/motion_qa/lab/runs/YYYY-MM-DDTHH-MM-SS/`
- Prevents cross-run artifact overwrites
- `LATEST_RUN.txt` pointer in base labDir for convenience
- **Verified:** 18/18 validation checks passed

### Fix 2: Single final holdout evaluation
- Holdout is evaluated **once** after the search loop completes
- Not queried every 200 experiments during search
- **Verified:** HOLDOUT_RESULTS.md contains a single evaluation, not 1,540

### Fix 3: Validation confirmation runs
- `valGroundTruths` (validation split) is now actually used
- `_runValidationConfirmations()` evaluates champion on validation set every 100 experiments
- `confirmedRuns` now reflects actual validation confirmations, not holdout evaluations
- **Verified:** STATUS.md shows "Validation confirmations" count

### Fix 4: Proper SEARCH → VALIDATION → HOLDOUT protocol
```
SEARCH (dev split)     → optimize parameters, promote champions
  ↓ every 100 experiments
VALIDATION (val split) → confirm champion generalizes beyond dev
  ↓ at end of run (ONCE)
HOLDOUT (holdout split) → final, untouched evaluation
```

## 7. REMAINING LIMITATIONS

1. **ML families are still proxies** — they don't actually train neural networks. This is documented but not yet fixed.
2. **Dataset is still tiny** — 31 clips total, 6 in holdout. No amount of search can overcome this.
3. **No cross-validation** — with only 6 holdout clips, the holdout F1 has high variance.
4. **No early stopping based on validation** — the lab runs for the full time budget even if validation shows overfitting.
