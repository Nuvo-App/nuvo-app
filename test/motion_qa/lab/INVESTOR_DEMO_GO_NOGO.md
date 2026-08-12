# INVESTOR DEMO RELIABILITY — GO / NO-GO REPORT

**Date:** 2026-08-11
**Question:** Can Nuvo reliably verify a controlled demo of 100 to 250 actions?
**Answer:** **NO-GO** for 100-250 actions. Conditional GO for 10-20 actions with jumping jacks under a tightly controlled protocol.

---

## 1. VERDICT

| Target | Verdict | Reason |
|--------|---------|--------|
| 250 actions | **NO-GO** | Best movement recall is 35.5%. 250 actions → ~89 counted, ~161 missed. Not reliable. |
| 100 actions | **NO-GO** | 100 actions → ~36 counted, ~64 missed. Not reliable. |
| 10-20 actions | **CONDITIONAL GO** | Jumping jacks under controlled conditions. ~4-7 counted at 35.5% recall. Demonstrates the concept but not accuracy. Requires rehearsal. |

**No movement in the production codebase can reliably count 100-250 actions on real video.**

---

## 2. EVIDENCE: REAL VIDEO TEST RESULTS

Ran `test/motion_qa_real_video_test.dart` — 35/35 tests pass. The test replays real YouTube video pose fixtures (MediaPipe extraction) through production validators.

### Per-movement detection on real video

| Movement | Clips | Expected Reps | Detected Reps | Recall | Clips with >0 |
|----------|-------|---------------|---------------|--------|---------------|
| **jumping_jacks** | 4 | 31 | 11 | **35.5%** | 2/4 |
| lunges | 3 | 14 | 3 | 21.4% | 2/3 |
| jump_squats | 6 | 29 | 4 | 13.8% | 2/6 |
| normal_squats | 5 | 23 | 0 | 0.0% | 0/5 |
| deep_squats | 3 | 9 | 0 | 0.0% | 0/3 |
| vertical_jumps | 4 | 12 | 0 | 0.0% | 0/4 |
| squat_jacks | 2 | 10 | 0 | 0.0% | 0/2 |
| lunge_jumps | 3 | 10 | 0 | 0.0% | 0/3 |

**Source:** `test/motion_qa_real_video_test.dart` per-movement summary, run 2026-08-11.

### What this means for 100-250 actions

| Movement | Recall | 100 actions → counted | 250 actions → counted | Missed |
|----------|--------|-----------------------|-----------------------|--------|
| jumping_jacks | 35.5% | ~36 | ~89 | ~64-161 |
| lunges | 21.4% | ~21 | ~54 | ~79-196 |
| jump_squats | 13.8% | ~14 | ~35 | ~86-215 |

Even the best movement misses the majority of reps. An investor watching 100 jumping jacks and seeing "36" on screen would immediately question the product.

### Overcounting problem (jumping jacks)

Jumping jacks also overcount on some clips:
- `yt_jumping_jack_003`: expected 5 reps, detected **9** (80% overcount)
- `yt_jumping_jack_002`: expected 10 reps, detected **2** (80% undercount)

The validator is inconsistent — sometimes overcounts, sometimes undercounts. This is worse than a consistent undercount because the investor cannot predict which direction the error will go.

---

## 3. WHY PRODUCTION FAILS ON REAL VIDEO

### Root cause 1: Athletic stance threshold too high

Production validators require `hipToKneeRatio > 0.86` for the STANDING/START phase. Real athletes stay in an athletic stance (ratio ~0.60-0.85) between reps. They rarely stand fully erect.

- **Squats:** `startCondition: hipToKneeRatio > 0.86` → 0% recall on real video
- **Jump squats:** lowered to 0.60 (tuned) → 13.8% recall. Still fails because airborne detection fails.
- **Jumping jacks:** uses arm position + ankle width, not hipToKneeRatio → 35.5% recall. Best signal.

### Root cause 2: Airborne detection fails on real video

The `AirborneStateTracker` requires both ankles to rise above a torso-relative threshold from a stable baseline. On real video:
- Camera sway causes false ankle shifts → baseline can't establish
- Small jumps don't produce enough ankle rise → airborne never detected
- Missing ankle landmarks during fast motion → fail-safe (no state change)
- Video starting mid-exercise → baseline never establishes

This kills jump squats (13.8%) and lunge jumps (0%) entirely.

### Root cause 3: stableFrames too high for real tempo

Production validators require 3 consecutive stable frames to confirm a phase. Real exercise at 30fps is fast — a squat dip may last only 1-2 frames. The validator resets before it can count.

### Root cause 4: Synthetic tests don't represent reality

All synthetic tests pass (14/14 proof, 30/30 configurable, 35/35 real video QA). But synthetic fixtures use idealized poses with:
- Perfect standing posture (ratio > 0.86)
- 3+ frame phase holds
- No camera sway
- No missing landmarks
- No pose noise outliers

**Synthetic pass rate: 100%. Real video recall: 0-35%.** The gap is the entire problem.

---

## 4. LAB CHAMPION vs PRODUCTION

The Motion Lab champion (`temporal_v42`) is NOT in production. It is a research candidate.

| | Lab Champion (temporal_v42) | Production Validator |
|---|---|---|
| Architecture | TemporalHysteresis | MultiPhaseSequenceValidator |
| Dev F1 | 0.6000 | not measured (lower) |
| Dev Recall | 0.5625 | ~0.138 (real video) |
| Holdout F1 | 0.2500 | not measured |
| Holdout Recall | 0.2000 | not measured |
| In production? | **NO** | YES |
| Overfitting gap | 0.3500 | unknown |

Even if the lab champion were deployed, 56% recall on 100 actions → ~56 counted, ~44 missed. Still not reliable for a demo.

---

## 5. GAP: LAB vs LIVE PIPELINE

| Factor | Lab (test fixtures) | Live demo (production app) |
|--------|---------------------|---------------------------|
| Pose model | MediaPipe PoseLandmarker (lite) | ML Kit Pose Detection (iOS) |
| Frame source | Pre-recorded JSON fixtures | Live camera stream |
| Camera | Static YouTube clips | iPhone camera (handheld or mounted) |
| Lighting | Whatever the video had | Demo room lighting |
| Pose noise | Fixed in fixture | Real-time, variable |
| Frame rate | Fixed (extracted at 30fps) | Variable (camera + processing latency) |

**No data exists on ML Kit performance.** The lab only tests MediaPipe fixtures. ML Kit may be better or worse — we don't know. This is an unmeasured risk.

---

## 6. SAFEST MOVEMENT FOR DEMO: JUMPING JACKS

### Why jumping jacks are safest

1. **Highest recall:** 35.5% vs 0-21% for all other movements
2. **No airborne detection:** Uses arm position (wrists above shoulders) and ankle width (feet wide). No flight threshold, no baseline establishment, no ankle tracking.
3. **Robust signals:** Arm raises and feet spreading are large, unambiguous movements visible from multiple camera angles.
4. **No hipToKneeRatio dependency:** Not affected by athletic stance threshold issues.
5. **No ankle baseline needed:** The main failure mode (baseline_not_established) doesn't apply.

### Why not jump squats (the research target)

- 13.8% recall on real video (production)
- Requires airborne detection (both feet leaving ground) — the most fragile signal
- Sensitive to camera angle, distance, jump height, and ankle landmark visibility
- The lab champion (56% recall) is not in production and has a 0.35 overfitting gap

### Why not squats, lunges, pushups, etc.

- Squats: 0% recall (hipToKneeRatio > 0.86 threshold too high for real athletes)
- Lunges: 21.4% recall (better than squats but still low, uses knee angle which is camera-sensitive)
- Pushups, arm raises, high knees, plank: no real video data at all — completely untested on real video

---

## 7. CONTROLLED DEMO PROTOCOL (if demo must proceed)

### Setup

| Parameter | Specification | Reason |
|-----------|--------------|--------|
| **Movement** | Jumping jacks | Highest recall (35.5%), no airborne detection |
| **Target reps** | 10 (not 100-250) | At 35.5% recall, 10 reps → ~4 counted. Demonstrates concept without exposing the recall gap. |
| **Camera** | iPhone on tripod, front-facing (selfie camera) | Front camera has higher resolution for pose detection on iOS |
| **Camera position** | 6-8 feet from subject, waist height | Full body in frame with margin. Too close cuts off feet/arms. Too far reduces pose landmark accuracy. |
| **Framing** | Full body visible with 10% margin on all sides | Arms overhead must stay in frame. Feet spread must stay in frame. |
| **Lighting** | Bright, even, frontal lighting. No backlight. | ML Kit needs clear body silhouette. Backlight destroys pose detection. |
| **Background** | Plain, uncluttered, high contrast with subject | Reduces pose noise. Patterned backgrounds cause false landmarks. |
| **Subject attire** | Fitted clothing, contrasting color from background | Loose clothing hides joint position. Same-color-as-background destroys detection. |
| **Floor** | Non-reflective, visible contrast with feet | Reflective floors confuse ankle detection. |

### Execution

| Step | Action |
|------|--------|
| 1 | Mount iPhone on tripod, 6-8 feet away, waist height |
| 2 | Open Nuvo, navigate to AI Motion Proof, select Jumping Jacks |
| 3 | Set target to 10 |
| 4 | Subject stands still for 3 seconds (lets pose detector lock on) |
| 5 | Subject performs 10 slow, deliberate jumping jacks with full range of motion |
| 6 | Each rep: arms fully overhead, feet fully spread, then return to start |
| 7 | Tempo: ~1 rep per 2 seconds (slow, deliberate) |
| 8 | After completion, show the count on screen |

### Expected outcome

- At 35.5% recall: ~4 of 10 reps counted
- With controlled conditions (good lighting, slow tempo, full ROM): possibly 5-7 of 10
- **Do not claim the count is accurate. Frame it as "live motion verification in development."**

### What NOT to do

- **Do not demo 100 or 250 reps.** The count will be visibly wrong (36/100 or 89/250).
- **Do not demo jump squats.** 13.8% recall + airborne detection failures = high chance of 0 reps counted.
- **Do not demo without rehearsal.** Camera position and lighting matter enormously.
- **Do not demo on a new device without testing first.** ML Kit behavior varies by device.
- **Do not let the subject go fast.** Fast tempo reduces stableFrames matching.
- **Do not use a handheld camera.** Camera sway destroys airborne detection and introduces pose noise.

---

## 8. PROPOSED TESTS (not yet run — require device or approval)

### Test A: Live device rehearsal (requires iPhone + build)

**Purpose:** Measure real recall on the actual device with the actual demo setup.

1. Build the app on the demo iPhone
2. Set up the tripod, lighting, and background per protocol above
3. Perform 10 jumping jacks, record the count
4. Repeat 5 times
5. Record: counted reps, missed reps, overcounts, app crashes, latency, UX issues

**Pass criteria:** ≥7/10 reps counted in at least 3 of 5 trials.

### Test B: Extended count stress (requires iPhone + build)

**Purpose:** Measure degradation over 100 reps.

1. Same setup as Test A
2. Perform 100 jumping jacks continuously
3. Record count at 10, 25, 50, 75, 100
4. Record: final count, app stability, frame rate, memory usage

**Pass criteria:** No crash, count within ±20% of 100 (80-120).

### Test C: False accept test (requires iPhone + build)

**Purpose:** Verify the jumping jack validator doesn't count non-jumping-jack movements.

1. Same setup
2. Perform 10 squats, 10 arm raises, 10 high knees
3. Record: jumping jack count for each

**Pass criteria:** 0 false counts for all non-jumping-jack movements.

### Test D: Latency and UX (requires iPhone + build)

**Purpose:** Measure real-time feedback latency and UX failure modes.

1. Same setup
2. Perform 10 jumping jacks
3. Record: time from movement to on-screen count update, any UI freezes, any "position your full body" false prompts, any camera issues

**Pass criteria:** Count update < 500ms, no UI freezes, no false prompts during full-body visibility.

---

## 9. CRITICAL RISKS

| Risk | Severity | Mitigation |
|------|----------|------------|
| ML Kit performs worse than MediaPipe | HIGH | Run Test A before demo. No data currently exists. |
| Count is visibly wrong in front of investors | HIGH | Demo 10 reps, not 100-250. Frame as "in development." |
| App crashes during demo | MEDIUM | Rehearse 3+ times. Kill other apps. Ensure battery > 50%. |
| Camera/pose detection fails to start | MEDIUM | Rehearse. Have a backup screen to show. |
| Investor asks "why didn't it count all 10?" | MEDIUM | Scripted answer: "We're tuning the detection thresholds. The lab is running autonomous parameter search to close this gap." |
| Investor asks to try 100 reps | HIGH | Decline. Say "the model isn't trained for high-rep counts yet. We're collecting data to get there." |
| Subject fatigue affects form | LOW (10 reps) | 10 jumping jacks is trivial. Not a risk at this target. |

---

## 10. PATH TO RELIABLE 100-250 ACTIONS

This is NOT achievable today. The path requires:

1. **Data:** Collect 18+ real-world clips per `DATA_REQUEST.md` (8 jump squat, 4 deep squat, 7 confuser variety). Current dataset: 31 clips, all families plateaued.
2. **ML Kit evaluation:** Run the lab harness on ML Kit pose output, not just MediaPipe. The production pipeline uses ML Kit — we have zero data on it.
3. **Threshold tuning for controlled conditions:** The current thresholds are tuned for synthetic fixtures. A controlled demo (fixed camera, good lighting, known subject) could use different thresholds. This requires a production code change (off-limits without explicit approval).
4. **Real ML models:** The ML families (MLP, Conv1D, GRU) are proxy-only with fixed weights. Real trained models could improve recall significantly.
5. **Early stopping + cross-validation:** The lab runs 8 hours and plateaus at 500 experiments. Better methodology could find better champions faster.
6. **Estimated timeline to 90%+ recall on 100-250 actions:** Unknown. The dataset bottleneck is the primary blocker. No amount of parameter search overcomes insufficient data.

---

## 11. SUMMARY

```
CAN NUVO RELIABLY VERIFY 100-250 ACTIONS?  NO

Best movement:     Jumping jacks (35.5% recall on real video)
Best safe target:  10 reps (demonstrates concept, hides recall gap)
Production code:   Unchanged — no modifications made
Lab champion:      Not deployed (temporal_v42, F1=0.60, holdout F1=0.25)
Data gap:          31 clips, all families plateaued, 18 more needed
ML Kit gap:        Zero data on production pose model performance
Demo risk:         HIGH if 100-250 attempted, MEDIUM if 10 with rehearsal

RECOMMENDATION:    Demo 10 jumping jacks under controlled protocol.
                   Do not attempt 100-250.
                   Rehearse 3+ times on the actual demo device.
                   Run Test A (live rehearsal) before the demo.
```

---

## APPENDIX: TEST RUN EVIDENCE

### Tests run 2026-08-11

| Test | Result | What it proves |
|------|--------|----------------|
| `test/jump_squat_lunge_jump_proof_test.dart` | 14/14 pass | Synthetic jump squat/lunge jump sequences work perfectly |
| `test/configurable_rep_validator_test.dart` | 30/30 pass | Synthetic squat/jumping jack/lunge sequences work perfectly |
| `test/motion_qa_real_video_test.dart` | 35/35 pass | Real video recall is 0-35.5% across all movements |

### Key files referenced (read-only, no modifications)

- `lib/features/races/ai/motion_validators.dart` — production validator dispatch
- `lib/features/races/ai/preset_motion/multi_phase_definitions.dart` — jump squat phase definition
- `lib/features/races/ai/airborne_state_tracker.dart` — flight detection primitive
- `test/motion_qa/motion_intelligence.dart` — lab harness, clip definitions, dataset manifest
- `test/motion_qa/lab/CHAMPION.json` — lab champion (temporal_v42, not deployed)
- `test/motion_qa/lab/STATUS.md` — overnight run status (stale, pre-fix)
- `test/motion_qa/REAL_VIDEO_QA_REPORT.md` — real video QA findings
- `test/motion_qa/TOLERANCE_EXPERIMENT_REPORT.md` — tolerance tuning experiment

### Production code status

**No production files were modified.** This report is analysis only. All motion lab files are untracked (new). The only tracked changes are `test/motion_qa/fixtures/manifest.json` and `test/motion_qa/fixtures/qa_report.md` from prior sessions.
