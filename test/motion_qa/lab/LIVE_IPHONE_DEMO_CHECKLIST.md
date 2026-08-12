# Live iPhone Demo Checklist

**Goal:** Find out if the current app can count reps reliably enough to demo.
**Time:** 30-40 minutes for Jumping Jacks, 30-40 minutes for Sumo Squats.

---

## Setup (do once)

- Build the app on your iPhone in **debug mode** (not release). Debug mode enables console logging.
- Connect your iPhone to your Mac and open **Xcode → Window → Devices and Simulators → your iPhone → Open Console**. Filter for `NuvoVerify`. You will see live validator state every 15 frames.
- Mount iPhone on a tripod, **6 feet away**, waist height.
- Use the **front-facing (selfie) camera**.
- Face a plain wall. Bright light behind the phone, not behind you.
- Wear fitted clothing that contrasts with the wall.
- Stand so your full body is in frame with margin above your head and below your feet.

---

# PART A: Jumping Jacks (best 100-action demo candidate)

## Stage 1: Jumping Jacks — 10 reps (3 trials)

Run 3 times. Reset between each trial.

1. Open AI Motion Proof. Select **Jumping Jacks**. Set target to **10**.
2. Stand still for 3 seconds.
3. Do 10 slow, deliberate jumping jacks. Arms fully overhead, feet fully apart each rep. ~1 rep per 2 seconds.
4. Note the final count.

**Pass:** at least 2 of 3 trials count **8 or more**.
**Fail:** fewer than 2 trials count 8+.

## Stage 2: Jumping Jacks — 25 reps (3 trials, only if Stage 1 passed)

Same setup. 25 reps at the same slow tempo. Run 3 times.

**Pass:** at least 2 of 3 trials count **22 or more**.
**Fail:** fewer than 2 trials count 22+.

## Stage 3: Jumping Jacks — 100 reps (at least 1 trial, only if Stage 2 passed)

Same setup. 100 reps.

**Pass:** app counts **90 or more**, no freeze, no obvious count jumps.
**Fail:** app counts 89 or fewer, or freezes, or jumps erratically.

## Stage 4: Jumping Jacks — 250 reps (optional internal stress test)

Only after Stage 3 passes. **Not the default live demo.**

**Pass:** app counts **225 or more**, no freeze.
**Fail:** app counts 224 or fewer, or freezes.

---

# PART B: Sumo Squats (first new action to stabilize)

## Confirmed live production path

```
AI Motion Proof screen
  → PoseDetectorService (ML Kit Pose Detection, iOS)
  → NuvoPoseFrame (12 landmarks: shoulders, elbows, wrists, hips, knees, ankles)
  → PresetPoseVerifierRuntime.update()
  → NuvoVerifyEngine.update()
  → ConfigurableRepValidator(definition: sumoSquatRepDefinition)
  → RepCounterStateMachine
  → count displayed on screen
```

## Sumo Squat detection rules (current production)

| Phase | Condition | Threshold |
|-------|-----------|-----------|
| START (standing) | hipToKneeRatio > 0.86 AND ankleWidthToBodyWidth > 1.5 | Must stand tall with wide stance |
| ACTIVE (squat) | hipToKneeRatio < 0.58 AND ankleWidthToBodyWidth > 1.5 | Must squat deep with wide stance |
| stableFrames | 3 consecutive frames | Both START and ACTIVE must hold 3 frames |
| Required landmarks | shoulders, hips, knees, ankles (8 total) | All must be visible |

**Key risk:** the `hipToKneeRatio > 0.86` standing threshold is the same threshold that gave regular squats 0% recall on real video. Real people don't stand fully upright between reps. This is the most likely failure point.

**Second risk:** `ankleWidthToBodyWidth > 1.5` requires a very wide stance. If your stance is not wide enough, neither START nor ACTIVE will ever match, and the count stays at 0.

## What the console log shows (every 15 frames)

```
[NuvoVerify] validatorState=start:stable movement=sumoSquats count=0
  confidence=0.00 failedRule=none
  debug={framesAnalyzed: 15, validPoseFrames: 15, visibility: 0.95,
         hipToKneeRatio: 0.92, ankleWidthToBodyWidth: 1.6, phase: 1.0}
```

- **validatorState:** `phase:state` — phase is `unknown`, `start`, or `active`. state is the rep counter state.
- **hipToKneeRatio:** must be > 0.86 for START, < 0.58 for ACTIVE.
- **ankleWidthToBodyWidth:** must be > 1.5 for both START and ACTIVE.
- **failedRuleReason:** `none` if all landmarks visible, `low_landmark_confidence` if not.
- **phase index:** 0=unknown, 1=start, 2=active.

**What is NOT logged:** stable frame count (how many consecutive frames the current phase has held). This is internal to `RepCounterStateMachine` and not exposed in `debugValues`.

## On-screen debug overlay

There is **no on-screen debug overlay for preset movements**. An overlay exists only for custom movements. For preset movements like Sumo Squats, you must watch the Xcode console.

**If you want an on-screen overlay** showing hipToKneeRatio, ankleWidthToBodyWidth, phase, and failedRuleReason live on the camera preview, I can add a small temporary one gated by `kDebugMode` (so it never appears in release builds). This requires touching `ai_motion_proof_screen_io.dart`, which is in the AI Motion Proof no-touch zone. **I need your explicit approval before making this change.**

## Stage 1: Sumo Squats — 10 reps (3 trials)

1. Open AI Motion Proof. Select **Sumo Squats**. Set target to **10**.
2. Stand still for 3 seconds. Stand with feet wider than shoulder-width apart (wide stance is required for detection).
3. Do 10 slow sumo squats. Squat deep (thighs parallel or below), then stand tall between each rep. Keep feet wide throughout. ~1 rep per 3 seconds.
4. Note the final count. Watch the console for hipToKneeRatio and ankleWidthToBodyWidth values.

**Pass:** at least 2 of 3 trials count **9 or more**.
**Fail:** fewer than 2 trials count 9+.

## Stage 2: Sumo Squats — 25 reps (3 trials, only if Stage 1 passed)

Same setup. 25 reps at the same slow tempo. Run 3 times.

**Pass:** at least 2 of 3 trials count **23 or more**.
**Fail:** fewer than 2 trials count 23+.

## Stage 3: Sumo Squats — 50 reps (2 trials, only if Stage 2 passed)

Same setup. 50 reps. Run 2 times.

**Pass:** both trials count **45 or more**.
**Fail:** either trial counts 44 or fewer.

## Stage 4: Sumo Squats — 100 reps (optional stress test, only if Stage 3 passed)

Only if Stage 3 is clean. **Not a live demo target yet.**

**Pass:** app counts **90 or more**, no freeze, no count jumps.
**Fail:** app counts 89 or fewer, or freezes, or jumps erratically.

---

## Record after each trial (both Jumping Jacks and Sumo Squats)

For every trial, write down:

1. Movement (Jumping Jacks / Sumo Squats)
2. Stage (1 / 2 / 3 / 4)
3. Trial number
4. Target reps
5. App count
6. Did the app crash or freeze? (yes/no)
7. Did you see "Position your full body in frame" when you were fully in frame? (yes/no)
8. Did the count update smoothly or jump in batches?
9. Did the count stop early (hit target before you finished)?
10. **For Sumo Squats only:** from the console, what was your hipToKneeRatio when standing? What was your ankleWidthToBodyWidth? (This tells us if the thresholds match your body.)
11. Any other weird behavior?

---

## What the results mean

### Jumping Jacks

- **Stage 1 + 2 + 3 all pass:** Demo 100 jumping jacks live. Rehearse once more.
- **Stage 1 + 2 pass, Stage 3 fails:** Demo 25 jumping jacks. Do not attempt 100.
- **Stage 1 passes, Stage 2 fails:** Demo 10 jumping jacks only. Say "motion verification is in development."
- **Stage 1 fails:** Do not demo live.

### Sumo Squats

- **Stage 1 + 2 + 3 all pass:** Sumo Squats are stable through 50. Can demo 50.
- **Stage 1 + 2 pass, Stage 3 fails:** Stable through 25. Can demo 25.
- **Stage 1 passes, Stage 2 fails:** Stable through 10 only.
- **Stage 1 fails:** Sumo Squats not ready. Diagnose using the section below.

---

## If Sumo Squats Stage 1 fails: diagnose before fixing

Do not assume the cause. Check the console log and observe which of these is failing:

### 1. Is ankleWidthToBodyWidth above 1.5?

Look at the console. If `ankleWidthToBodyWidth` is below 1.5 even when your feet are wide, the threshold is too high for your body proportions or camera distance.

**Fix candidate:** lower `ankleWidthToBodyWidth` threshold from 1.5 to 1.3 or 1.35 in `sumoSquatRepDefinition`.

### 2. Is hipToKneeRatio above 0.86 when standing?

If the console shows `hipToKneeRatio` stuck below 0.86 even when you stand tall between reps, the standing threshold is too strict. This is the same failure that gave regular squats 0% recall on real video.

**Fix candidate:** lower `hipToKneeRatio` standing threshold from 0.86 to 0.78 or 0.80 in `sumoSquatRepDefinition`.

### 3. Is hipToKneeRatio dropping below 0.58 when you squat?

If `hipToKneeRatio` stays above 0.58 even at the bottom of your squat, you're not squatting deep enough for the detector, or the threshold is too low. Try squatting deeper first. If you are already at full depth and it still doesn't trigger, the active threshold may need to rise.

### 4. Is phase stuck at "unknown"?

If `phase` is always 0 (unknown), neither START nor ACTIVE conditions are matching. Check both hipToKneeRatio and ankleWidthToBodyWidth against their thresholds in the console.

### 5. Is failedRuleReason showing "low_landmark_confidence"?

If yes, landmarks are being lost. This is a camera/lighting/distance problem, not a threshold problem. Fix the setup before changing code.

### 6. Is the count lagging or missing reps despite correct phase transitions?

If `phase` is cycling between `start` and `active` correctly but the count isn't incrementing, `stableFrames: 3` may be too many for your tempo. Each phase must hold 3 consecutive frames. At 30fps that's 100ms. If you move faster than that, the validator resets before counting.

**Fix candidate:** lower `stableFrames` from 3 to 2 in `sumoSquatRepDefinition`.

### 7. Is the count double-counting on single reps?

If one squat produces 2 counts, there's no cooldown between reps. The rep counter state machine may be re-triggering immediately.

**Fix candidate:** add a cooldown (e.g. 2-3 frames) to the rep counter. Only do this if double-counting is actually observed.

---

## Likely first fix candidates (depending on live failure)

These are the smallest reversible changes, in order of likelihood. **Do not apply any until you have run Stage 1 and told me which diagnostic above matched your failure.**

| Fix | File | Change | When to apply |
|-----|------|--------|---------------|
| Lower ankle width threshold | `motion_validators.dart` line 1632-1634, 1640-1642 | `1.5 → 1.3` or `1.35` | ankleWidthToBodyWidth stays below 1.5 even with wide stance |
| Lower standing threshold | `motion_validators.dart` line 1630 | `0.86 → 0.78` or `0.80` | hipToKneeRatio stays below 0.86 when standing tall |
| Lower stableFrames | `motion_validators.dart` line 1645 | `3 → 2` | phase cycles correctly but count doesn't increment |
| Add cooldown | `RepCounterStateMachine` (if needed) | 2-3 frame cooldown | double-counting on single reps |

All changes are in `lib/features/races/ai/motion_validators.dart` (the `sumoSquatRepDefinition` constant). Each is a one-line threshold change. All are reversible. None change backend contracts, auth, or the camera pipeline.

**Do not touch airborne actions (Jump Squats, Lunge Jumps) in this phase.**

---

## What to ignore

- Any lab F1 score, champion name, or experiment count. None of it predicts your iPhone.
- The overnight report. Historical.
- The data request. Matters for research, not for this demo.
- Lab holdout metrics. Not relevant to live device testing.
